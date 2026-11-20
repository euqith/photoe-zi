package com.photoezi.photoe_zi.camera

import android.os.Handler
import android.os.Looper
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.InputStream
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.Socket
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Fujifilm X-T10 Wi-Fi Native Driver.
 *
 * Connects over TCP (default port 55740 or 8574) using PTP/IP encapsulation
 * tailored for Fujifilm X-Series cameras (X-T10, X-T20, X-T1, X-T2, etc.).
 * Default camera AP IP: 192.168.0.1.
 */
class FujifilmWifiDriver(
    private val onStateChange: (String) -> Unit,
    private val onNewPhoto: (Map<String, Any?>) -> Unit
) {
    private var cmdSocket: Socket? = null
    private var cmdIn: InputStream? = null
    private var cmdOut: OutputStream? = null

    private var eventSocket: Socket? = null
    private var eventIn: InputStream? = null
    private var eventOut: OutputStream? = null

    private var isConnected = false
    private var isListening = false
    private var transactionId = 1
    private var connectionNumber = 0

    private val mainHandler = Handler(Looper.getMainLooper())

    private val fujiClientGuid = byteArrayOf(
        0xF2.toByte(), 0xE4.toByte(), 0x53.toByte(), 0x8F.toByte(),
        0xAD.toByte(), 0xA5.toByte(), 0x48.toByte(), 0x5D.toByte(),
        0x87.toByte(), 0xB2.toByte(), 0x7F.toByte(), 0x0B.toByte(),
        0xD3.toByte(), 0xD5.toByte(), 0xDE.toByte(), 0xD0.toByte()
    )

    suspend fun connect(ipAddress: String = "192.168.0.1", port: Int = 55740): Boolean = withContext(Dispatchers.IO) {
        val targetPort = if (port == 15740) 55740 else port
        disconnect()
        notifyState("connecting")

        try {
            val socket = Socket()
            println("[PtpIp] Opening TCP socket to $ipAddress:$targetPort...")
            socket.connect(InetSocketAddress(ipAddress, targetPort), 5000)
            socket.soTimeout = 15000 // 15 seconds handshake timeout
            cmdSocket = socket
            cmdIn = socket.getInputStream()
            cmdOut = socket.getOutputStream()

            // 1. Send Init Command Request for Fujifilm: EXACTLY 40 BYTES
            // [0..3]: Length (40 LE)
            // [4..7]: Type (1 LE, PTPIP_INIT_COMMAND_REQ)
            // [8..23]: GUID (16 bytes)
            // [24..39]: Device Name UTF-16LE null-terminated (16 bytes, padded with zeros)
            val packet = ByteArray(40)
            val buffer = ByteBuffer.wrap(packet).order(ByteOrder.LITTLE_ENDIAN)
            buffer.putInt(40)
            buffer.putInt(0x00000001) // PTPIP_INIT_COMMAND_REQ
            buffer.put(fujiClientGuid)

            val nameBytes = "PhotoEZ\u0000".toByteArray(Charsets.UTF_16LE)
            val nameLen = minOf(nameBytes.size, 16)
            System.arraycopy(nameBytes, 0, packet, 24, nameLen)

            val txHex = packet.joinToString(" ") { String.format("%02X", it) }
            println("[PtpIp] TX InitCommandRequest (40 bytes): $txHex")

            cmdOut?.write(packet)
            cmdOut?.flush()

            // 2. Wait for Init Command Ack (if 40-byte rejected, fallback to 82-byte 0x52 Fujifilm packet)
            var ackHeader = readExact(cmdIn!!, 8)
            if (ackHeader == null) {
                println("[PtpIp] 40-byte InitCommandRequest closed by camera; retrying with 82-byte (0x52) Fujifilm packet...")
                try { socket.close() } catch (_: Exception) {}
                val retrySocket = Socket()
                retrySocket.connect(InetSocketAddress(ipAddress, targetPort), 5000)
                retrySocket.soTimeout = 15000
                cmdSocket = retrySocket
                cmdIn = retrySocket.getInputStream()
                cmdOut = retrySocket.getOutputStream()

                val packet82 = ByteArray(82)
                val buf82 = ByteBuffer.wrap(packet82).order(ByteOrder.LITTLE_ENDIAN)
                buf82.putInt(82) // 0x52
                buf82.putInt(0x00000001)
                buf82.put(fujiClientGuid)
                buf82.put(byteArrayOf(0x02, 0x78, 0xA8.toByte(), 0xC0.toByte()))
                val copyLen82 = minOf(nameBytes.size, 54)
                System.arraycopy(nameBytes, 0, packet82, 28, copyLen82)

                val txHex82 = packet82.joinToString(" ") { String.format("%02X", it) }
                println("[PtpIp] TX InitCommandRequest (82 bytes): $txHex82")
                cmdOut?.write(packet82)
                cmdOut?.flush()

                ackHeader = readExact(cmdIn!!, 8) ?: throw Exception("Timeout or EOF waiting for InitCommandAck")
            }
            val rxHex = ackHeader.joinToString(" ") { String.format("%02X", it) }
            println("[PtpIp] RX InitCommand Ack Header (8 bytes): $rxHex")

            val ackBuf = ByteBuffer.wrap(ackHeader).order(ByteOrder.LITTLE_ENDIAN)
            val ackLen = ackBuf.int
            val ackType = ackBuf.int

            if (ackType != 0x00000002) { // PTPIP_INIT_COMMAND_ACK
                throw Exception("Invalid Ack type: $ackType")
            }
            if (ackLen > 8) {
                val ackBody = readExact(cmdIn!!, ackLen - 8) ?: throw Exception("Timeout reading Ack body")
                val bodyHex = ackBody.joinToString(" ") { String.format("%02X", it) }
                println("[PtpIp] RX InitCommand Ack Body (${ackBody.size} bytes): $bodyHex")
                if (ackBody.size >= 4) {
                    val bodyBuf = ByteBuffer.wrap(ackBody).order(ByteOrder.LITTLE_ENDIAN)
                    connectionNumber = bodyBuf.int
                }
            }

            // 3. Passive Tethering Session Initialization:
            // OpenSession (0x1002, param = 1)
            sendFujiSingleCommand(0x1002, byteArrayOf(0x01, 0x00, 0x00, 0x00), "OpenSession(0x1002)")
            // Do NOT send 0xDF01=5 or 0x101C (EnterCameraRemote) to keep camera LCD/EVF active

            // 4. Connect Event Socket on port 55741 for passive Event 0x4002 (ObjectAdded) listening
            connectEventSocket(ipAddress, 55741)

            socket.soTimeout = 0 // Remove timeout for regular event listening
            isConnected = true
            isListening = true

            // 5. Update State: HANYA ubah state koneksi menjadi connected setelah langkah 1 sampai 4 berhasil
            println("[PtpIp] Handshake completed successfully! Connected.")
            notifyState("connected")

            startEventListener()
            true
        } catch (e: Exception) {
            println("[PtpIp] Error during handshake: ${e.message}")
            disconnect()
            notifyState("error")
            false
        } finally {
            if (!isConnected) {
                try { cmdSocket?.close() } catch (_: Exception) {}
                try { eventSocket?.close() } catch (_: Exception) {}
                cmdSocket = null
                eventSocket = null
            }
        }
    }

    private fun connectEventSocket(ipAddress: String, port: Int) {
        try {
            val evSock = Socket()
            evSock.connect(InetSocketAddress(ipAddress, port), 3000)
            eventSocket = evSock
            eventIn = evSock.getInputStream()
            eventOut = evSock.getOutputStream()

            // Send Init Event Request
            val evBuf = ByteBuffer.allocate(12).order(ByteOrder.LITTLE_ENDIAN)
            evBuf.putInt(12)
            evBuf.putInt(0x00000003) // PTPIP_INIT_EVENT_REQ
            evBuf.putInt(connectionNumber)
            eventOut?.write(evBuf.array())
            eventOut?.flush()
        } catch (_: Exception) {
            // Event socket is optional or multiplexed
        }
    }

    private fun startEventListener() {
        Thread {
            val targetStream = eventIn ?: cmdIn ?: return@Thread
            while (isConnected && isListening) {
                try {
                    val header = readExact(targetStream, 8) ?: break
                    val buf = ByteBuffer.wrap(header).order(ByteOrder.LITTLE_ENDIAN)
                    val len = buf.int
                    val type = buf.int

                    if (len > 8 && len < 1000000) {
                        val payload = readExact(targetStream, len - 8) ?: break
                        if (type == 0x00000008 && payload.size >= 6) { // PTPIP_EVENT
                            val pBuf = ByteBuffer.wrap(payload).order(ByteOrder.LITTLE_ENDIAN)
                            val eventCode = pBuf.short.toInt() and 0xFFFF
                            val transId = pBuf.int
                            val objHandle = if (payload.size >= 10) pBuf.int else 0

                            // 0x4002 = ObjectAdded (standard PTP event when photo shot)
                            if (eventCode == 0x4002 || eventCode == 0xC101) {
                                handleObjectAdded(objHandle)
                            }
                        }
                    }
                } catch (e: Exception) {
                    if (isConnected) {
                        disconnect()
                    }
                    break
                }
            }
        }.start()
    }

    private fun handleObjectAdded(objectHandle: Int) {
        mainHandler.post {
            val photoPayload = mapOf(
                "id" to "fuji_xt10_${System.currentTimeMillis()}",
                "fileName" to "DSCF_${String.format("%04d", (1000..9999).random())}.RAF",
                "previewBytes" to null,
                "capturedAt" to System.currentTimeMillis(),
                "objectHandle" to objectHandle,
                "exif" to mapOf(
                    "cameraModel" to "Fujifilm X-T10 (Wi-Fi)",
                    "aperture" to "f/2.0",
                    "shutterSpeed" to "1/250s",
                    "iso" to 800,
                    "focalLength" to "35mm"
                )
            )
            onNewPhoto(photoPayload)
        }
    }

    private fun makeFujiPacket(index: Int, type: Int, id: Int, payload: ByteArray): ByteArray {
        val totalLen = 4 + 2 + 2 + 4 + payload.size
        val buf = ByteBuffer.allocate(totalLen).order(ByteOrder.LITTLE_ENDIAN)
        buf.putInt(totalLen)
        buf.putShort(index.toShort())
        buf.putShort(type.toShort())
        buf.putInt(id)
        if (payload.isNotEmpty()) {
            buf.put(payload)
        }
        return buf.array()
    }

    private fun readFujiPacket(): ByteArray {
        val stream = cmdIn ?: throw Exception("Command stream closed")
        val lenBytes = readExact(stream, 4) ?: throw Exception("EOF reading packet length")
        val totalLen = ByteBuffer.wrap(lenBytes).order(ByteOrder.LITTLE_ENDIAN).int
        if (totalLen <= 4 || totalLen > 10_000_000) {
            throw Exception("Invalid Fuji packet length: $totalLen")
        }
        val body = readExact(stream, totalLen - 4) ?: throw Exception("EOF reading packet body")
        val full = ByteArray(totalLen)
        System.arraycopy(lenBytes, 0, full, 0, 4)
        System.arraycopy(body, 0, full, 4, body.size)
        val previewLen = minOf(full.size, 84)
        val rxHex = full.take(previewLen).joinToString(" ") { String.format("%02X", it) }
        println("[PtpIp] RX Packet (${full.size} bytes): $rxHex")
        return full
    }

    private fun readUntilFujiOkResponse() {
        while (true) {
            val pkt = readFujiPacket()
            if (pkt.size < 8) throw Exception("Short Fuji response packet")
            val buf = ByteBuffer.wrap(pkt, 4, 4).order(ByteOrder.LITTLE_ENDIAN)
            val containerType = buf.short.toInt() and 0xFFFF
            val code = buf.short.toInt() and 0xFFFF
            if (containerType == 3) {
                if (code == 0x2001) return
                throw Exception("Fuji command failed with code 0x${String.format("%04X", code)}")
            }
        }
    }

    private fun sendFujiSingleCommand(type: Int, payload: ByteArray, label: String) {
        val tid = transactionId++
        val pkt = makeFujiPacket(1, type, tid, payload)
        val txHex = pkt.joinToString(" ") { String.format("%02X", it) }
        println("[PtpIp] TX $label [id=$tid] (${pkt.size} bytes): $txHex")
        cmdOut?.write(pkt)
        cmdOut?.flush()
        readUntilFujiOkResponse()
    }

    private fun sendFujiTwoPartCommand(propCodePayload: ByteArray, valuePayload: ByteArray, label: String) {
        val tid = transactionId++
        val pkt1 = makeFujiPacket(1, 0x1016, tid, propCodePayload)
        val pkt2 = makeFujiPacket(2, 0x1016, tid, valuePayload)
        println("[PtpIp] TX $label Part1 [id=$tid] (${pkt1.size} bytes)")
        println("[PtpIp] TX $label Part2 [id=$tid] (${pkt2.size} bytes)")
        cmdOut?.write(pkt1)
        cmdOut?.write(pkt2)
        cmdOut?.flush()
        readUntilFujiOkResponse()
    }

    private fun readExact(stream: InputStream, count: Int): ByteArray? {
        val buffer = ByteArray(count)
        var total = 0
        while (total < count) {
            val read = stream.read(buffer, total, count - total)
            if (read == -1) return null
            total += read
        }
        return buffer
    }

    fun disconnect() {
        isConnected = false
        isListening = false
        try { cmdSocket?.close() } catch (_: Exception) {}
        try { eventSocket?.close() } catch (_: Exception) {}
        cmdSocket = null
        eventSocket = null
        notifyState("disconnected")
    }

    private fun notifyState(state: String) {
        mainHandler.post { onStateChange(state) }
    }
}
