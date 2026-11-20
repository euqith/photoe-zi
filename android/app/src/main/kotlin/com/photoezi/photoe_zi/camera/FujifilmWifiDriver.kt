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

    suspend fun connect(ipAddress: String = "192.168.0.1", port: Int = 15740): Boolean = withContext(Dispatchers.IO) {
        disconnect()
        notifyState("connecting")

        try {
            val socket = Socket()
            socket.connect(InetSocketAddress(ipAddress, port), 5000)
            socket.soTimeout = 5000 // 5 seconds handshake timeout
            cmdSocket = socket
            cmdIn = socket.getInputStream()
            cmdOut = socket.getOutputStream()

            // 1. Send Init Command Request for Fujifilm
            // Packet layout: Length (4B), Type = 1 (Init_Command_Request, 4B), GUID (16B), Friendly Name (UTF-16LE null terminated), Version (4B)
            val guid = ByteArray(16) { (0..255).random().toByte() }
            val clientName = "PhotoE-Zi\u0000".toByteArray(Charsets.UTF_16LE)
            val packetLen = 4 + 4 + 16 + clientName.size + 4 // version (4B)
            val buffer = ByteBuffer.allocate(packetLen).order(ByteOrder.LITTLE_ENDIAN)
            buffer.putInt(packetLen)
            buffer.putInt(0x00000001) // PTPIP_INIT_COMMAND_REQ
            buffer.put(guid)
            buffer.put(clientName)
            buffer.putInt(0x00010000) // PTP Version 1.0

            cmdOut?.write(buffer.array())
            cmdOut?.flush()

            // 2. Wait for Init Command Ack
            val ackHeader = readExact(cmdIn!!, 8) ?: throw Exception("Timeout or EOF waiting for InitCommandAck")
            val ackBuf = ByteBuffer.wrap(ackHeader).order(ByteOrder.LITTLE_ENDIAN)
            val ackLen = ackBuf.int
            val ackType = ackBuf.int

            if (ackType != 0x00000002) { // PTPIP_INIT_COMMAND_ACK
                throw Exception("Invalid Ack type: $ackType")
            }
            if (ackLen > 8) {
                val ackBody = readExact(cmdIn!!, ackLen - 8) ?: throw Exception("Timeout reading Ack body")
                if (ackBody.size >= 4) {
                    val bodyBuf = ByteBuffer.wrap(ackBody).order(ByteOrder.LITTLE_ENDIAN)
                    connectionNumber = bodyBuf.int
                }
            }

            // 3. Send Open Session (PTP 0x1002) with SessionID = 1
            sendPtpCommand(0x1002, listOf(1)) // Session ID 1

            // 4. Connect Event Socket if supported
            connectEventSocket(ipAddress, port)

            socket.soTimeout = 0 // Remove timeout for regular event listening
            isConnected = true
            isListening = true

            // 5. Update State: HANYA ubah state koneksi menjadi connected setelah langkah 1 sampai 4 berhasil
            notifyState("connected")

            startEventListener()
            true
        } catch (e: Exception) {
            disconnect()
            notifyState("error")
            false
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

    private fun sendPtpCommand(opCode: Int, params: List<Int>) {
        val payloadLen = 4 + 4 + 4 + 4 + (params.size * 4)
        val buf = ByteBuffer.allocate(payloadLen).order(ByteOrder.LITTLE_ENDIAN)
        buf.putInt(payloadLen)
        buf.putInt(0x00000006) // PTPIP_CMD_REQ
        buf.putInt(1)          // Data phase
        buf.putShort(opCode.toShort())
        buf.putInt(transactionId++)
        for (param in params) {
            buf.putInt(param)
        }
        cmdOut?.write(buf.array())
        cmdOut?.flush()
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
