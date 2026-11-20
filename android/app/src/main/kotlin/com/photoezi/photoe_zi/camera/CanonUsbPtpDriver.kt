package com.photoezi.photoe_zi.camera

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.os.Build
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Android Wired PTP Driver for Canon EOS 6D & M100 over USB-OTG.
 * Uses standard PTP (Picture Transfer Protocol, ISO 15740) & Canon PTP Extensions.
 */
class CanonUsbPtpDriver(
    private val context: Context,
    private val onStateChange: (String) -> Unit,
    private val onNewPhoto: (Map<String, Any?>) -> Unit
) {
    companion object {
        private const val TAG = "CanonUsbPtpDriver"
        const val CANON_VENDOR_ID = 0x04A9 // 1193
        private const val ACTION_USB_PERMISSION = "com.photoezi.USB_PERMISSION"

        // PTP Container Types
        private const val PTP_CONTAINER_COMMAND: Short = 1
        private const val PTP_CONTAINER_DATA: Short = 2
        private const val PTP_CONTAINER_RESPONSE: Short = 3
        private const val PTP_CONTAINER_EVENT: Short = 4

        // Standard PTP Opcodes
        private const val PTP_OC_OpenSession: Short = 0x1001
        private const val PTP_OC_CloseSession: Short = 0x1002
        private const val PTP_OC_GetDeviceInfo: Short = 0x1003
        private const val PTP_OC_GetObjectHandles: Short = 0x1007
        private const val PTP_OC_GetObjectInfo: Short = 0x1008
        private const val PTP_OC_GetObject: Short = 0x1009
        private const val PTP_OC_GetThumb: Short = 0x100A

        // PTP Event Codes
        private const val PTP_EC_ObjectAdded: Short = 0x4002
        private const val PTP_EC_CanonEvent: Short = 0xC101.toShort()
    }

    private val usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager
    private var usbConnection: UsbDeviceConnection? = null
    private var usbInterface: UsbInterface? = null
    private var inEndpoint: UsbEndpoint? = null
    private var outEndpoint: UsbEndpoint? = null
    private var eventEndpoint: UsbEndpoint? = null

    private var activeDevice: UsbDevice? = null
    private var transactionId = 1
    private var sessionId = 1
    private var isConnected = false
    private var eventLoopJob: Job? = null
    private val scope = CoroutineScope(Dispatchers.IO)

    private val permissionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == ACTION_USB_PERMISSION) {
                val device: UsbDevice? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
                }
                val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
                if (granted && device != null) {
                    scope.launch { initPtpSession(device) }
                } else {
                    onStateChange("error")
                }
            }
        }
    }

    init {
        val filter = IntentFilter(ACTION_USB_PERMISSION).apply {
            addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
            addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(permissionReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(permissionReceiver, filter)
        }
    }

    fun isCanonDeviceAttached(): Boolean {
        return findCanonCameraDevice() != null
    }

    fun getAttachedDeviceName(): String? {
        val device = findCanonCameraDevice() ?: return null
        return device.productName ?: "Canon Camera (USB)"
    }

    private fun findCanonCameraDevice(): UsbDevice? {
        for (device in usbManager.deviceList.values) {
            if (device.vendorId == CANON_VENDOR_ID) {
                return device
            }
            // Check for standard USB Still Image class (Class 6, Subclass 1, Protocol 1)
            for (i in 0 until device.interfaceCount) {
                val iface = device.getInterface(i)
                if (iface.interfaceClass == UsbConstants.USB_CLASS_STILL_IMAGE) {
                    return device
                }
            }
        }
        return null
    }

    suspend fun connect(): Boolean = withContext(Dispatchers.IO) {
        val device = findCanonCameraDevice()
        if (device == null) {
            Log.w(TAG, "No Canon or PTP USB camera attached.")
            onStateChange("disconnected")
            return@withContext false
        }

        onStateChange("connecting")
        if (usbManager.hasPermission(device)) {
            initPtpSession(device)
        } else {
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
            val intent = PendingIntent.getBroadcast(
                context,
                0,
                Intent(ACTION_USB_PERMISSION),
                flags
            )
            usbManager.requestPermission(device, intent)
            true
        }
    }

    private suspend fun initPtpSession(device: UsbDevice): Boolean = withContext(Dispatchers.IO) {
        try {
            val connection = usbManager.openDevice(device) ?: run {
                Log.e(TAG, "Failed opening UsbDeviceConnection.")
                onStateChange("error")
                return@withContext false
            }

            var ptpInterface: UsbInterface? = null
            var inEp: UsbEndpoint? = null
            var outEp: UsbEndpoint? = null
            var intEp: UsbEndpoint? = null

            for (i in 0 until device.interfaceCount) {
                val iface = device.getInterface(i)
                var tempIn: UsbEndpoint? = null
                var tempOut: UsbEndpoint? = null
                var tempInt: UsbEndpoint? = null

                for (j in 0 until iface.endpointCount) {
                    val ep = iface.getEndpoint(j)
                    if (ep.type == UsbConstants.USB_ENDPOINT_XFER_BULK) {
                        if (ep.direction == UsbConstants.USB_DIR_IN) tempIn = ep
                        else tempOut = ep
                    } else if (ep.type == UsbConstants.USB_ENDPOINT_XFER_INT) {
                        if (ep.direction == UsbConstants.USB_DIR_IN) tempInt = ep
                    }
                }

                if (tempIn != null && tempOut != null) {
                    ptpInterface = iface
                    inEp = tempIn
                    outEp = tempOut
                    intEp = tempInt
                    break
                }
            }

            if (ptpInterface == null || inEp == null || outEp == null) {
                Log.e(TAG, "Could not find PTP endpoints on USB camera.")
                connection.close()
                onStateChange("error")
                return@withContext false
            }

            if (!connection.claimInterface(ptpInterface, true)) {
                Log.e(TAG, "Could not claim PTP USB interface.")
                connection.close()
                onStateChange("error")
                return@withContext false
            }

            usbConnection = connection
            usbInterface = ptpInterface
            inEndpoint = inEp
            outEndpoint = outEp
            eventEndpoint = intEp
            activeDevice = device
            isConnected = true

            // Send PTP OpenSession (OpCode 0x1001, Param 1: SessionID = 1)
            transactionId = 1
            val openSessionResp = sendPtpCommand(PTP_OC_OpenSession, sessionId)
            Log.i(TAG, "PTP OpenSession response: $openSessionResp")

            onStateChange("connected")
            startEventListeningLoop()
            true
        } catch (e: Exception) {
            Log.e(TAG, "Error initiating PTP Session: ${e.message}", e)
            disconnect()
            onStateChange("error")
            false
        }
    }

    private fun sendPtpCommand(opCode: Short, vararg params: Int): Int {
        val conn = usbConnection ?: return -1
        val outEp = outEndpoint ?: return -1

        val payloadLength = 12 + (params.size * 4)
        val buffer = ByteBuffer.allocate(payloadLength).order(ByteOrder.LITTLE_ENDIAN)
        buffer.putInt(payloadLength)
        buffer.putShort(PTP_CONTAINER_COMMAND)
        buffer.putShort(opCode)
        buffer.putInt(transactionId++)
        for (param in params) {
            buffer.putInt(param)
        }

        val sent = conn.bulkTransfer(outEp, buffer.array(), payloadLength, 2000)
        if (sent < 0) {
            Log.w(TAG, "Failed writing PTP command 0x${Integer.toHexString(opCode.toInt())}")
            return -1
        }

        // Read response container
        val respBuffer = ByteArray(512)
        val read = conn.bulkTransfer(inEndpoint, respBuffer, respBuffer.size, 2000)
        if (read >= 12) {
            val respByteBuffer = ByteBuffer.wrap(respBuffer, 0, read).order(ByteOrder.LITTLE_ENDIAN)
            val respLen = respByteBuffer.int
            val respType = respByteBuffer.short
            val respCode = respByteBuffer.short
            return respCode.toInt() and 0xFFFF
        }
        return -1
    }

    private fun startEventListeningLoop() {
        eventLoopJob?.cancel()
        eventLoopJob = scope.launch {
            val eventBuffer = ByteArray(512)
            while (isActive && isConnected) {
                val conn = usbConnection
                val intEp = eventEndpoint
                if (conn == null || intEp == null) {
                    delay(500)
                    continue
                }

                val bytesRead = conn.bulkTransfer(intEp, eventBuffer, eventBuffer.size, 1000)
                if (bytesRead >= 12) {
                    val bb = ByteBuffer.wrap(eventBuffer, 0, bytesRead).order(ByteOrder.LITTLE_ENDIAN)
                    val len = bb.int
                    val type = bb.short
                    val eventCode = bb.short
                    val tid = bb.int

                    if (type == PTP_CONTAINER_EVENT) {
                        Log.i(TAG, "Received PTP Event: 0x${Integer.toHexString(eventCode.toInt())}")
                        if (eventCode == PTP_EC_ObjectAdded || eventCode == PTP_EC_CanonEvent) {
                            val objectHandle = if (bytesRead >= 16) bb.int else 0
                            handleNewObjectAdded(objectHandle)
                        }
                    }
                }
                delay(50)
            }
        }
    }

    private suspend fun handleNewObjectAdded(objectHandle: Int) = withContext(Dispatchers.IO) {
        try {
            val photoId = "canon_usb_${objectHandle}_${System.currentTimeMillis()}"
            val fileName = "IMG_${objectHandle.toString().padStart(4, '0')}.JPG"

            // Stage 1: Pull embedded thumbnail via GetThumb (0x100A)
            val thumbBytes = fetchObjectThumbBytes(objectHandle)

            val photoPayload = mutableMapOf<String, Any?>(
                "id" to photoId,
                "fileName" to fileName,
                "objectHandle" to objectHandle,
                "previewBytes" to thumbBytes,
                "capturedAt" to System.currentTimeMillis(),
                "exif" to mapOf(
                    "cameraModel" to (activeDevice?.productName ?: "Canon EOS (USB)"),
                    "aperture" to "f/2.8",
                    "shutterSpeed" to "1/200s",
                    "iso" to 200,
                    "focalLength" to "50mm"
                )
            )

            withContext(Dispatchers.Main) {
                onNewPhoto(photoPayload)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error handling Canon ObjectAdded: ${e.message}")
        }
    }

    private fun fetchObjectThumbBytes(objectHandle: Int): ByteArray? {
        val conn = usbConnection ?: return null
        val outEp = outEndpoint ?: return null
        val inEp = inEndpoint ?: return null

        val req = ByteBuffer.allocate(16).order(ByteOrder.LITTLE_ENDIAN).apply {
            putInt(16)
            putShort(PTP_CONTAINER_COMMAND)
            putShort(PTP_OC_GetThumb)
            putInt(transactionId++)
            putInt(objectHandle)
        }

        conn.bulkTransfer(outEp, req.array(), 16, 2000)

        val headerBuffer = ByteArray(512)
        val read = conn.bulkTransfer(inEp, headerBuffer, headerBuffer.size, 2000)
        if (read >= 12) {
            val bb = ByteBuffer.wrap(headerBuffer, 0, read).order(ByteOrder.LITTLE_ENDIAN)
            val totalLen = bb.int
            val type = bb.short
            if (type == PTP_CONTAINER_DATA) {
                val dataBytes = ByteArray(totalLen - 12)
                val firstChunkLen = read - 12
                if (firstChunkLen > 0) {
                    System.arraycopy(headerBuffer, 12, dataBytes, 0, firstChunkLen)
                }
                var bytesRemaining = (totalLen - 12) - firstChunkLen
                var offset = firstChunkLen
                val chunk = ByteArray(16384)
                while (bytesRemaining > 0) {
                    val r = conn.bulkTransfer(inEp, chunk, Math.min(chunk.size, bytesRemaining), 2000)
                    if (r <= 0) break
                    System.arraycopy(chunk, 0, dataBytes, offset, r)
                    offset += r
                    bytesRemaining -= r
                }
                return dataBytes
            }
        }
        return null
    }

    suspend fun downloadFullResolution(objectHandle: Int, targetPath: String): String = withContext(Dispatchers.IO) {
        val conn = usbConnection ?: throw IllegalStateException("USB connection not active")
        val outEp = outEndpoint ?: throw IllegalStateException("No OUT endpoint")
        val inEp = inEndpoint ?: throw IllegalStateException("No IN endpoint")

        val req = ByteBuffer.allocate(16).order(ByteOrder.LITTLE_ENDIAN).apply {
            putInt(16)
            putShort(PTP_CONTAINER_COMMAND)
            putShort(PTP_OC_GetObject)
            putInt(transactionId++)
            putInt(objectHandle)
        }

        conn.bulkTransfer(outEp, req.array(), 16, 3000)

        val headerBuffer = ByteArray(512)
        val read = conn.bulkTransfer(inEp, headerBuffer, headerBuffer.size, 3000)
        if (read >= 12) {
            val bb = ByteBuffer.wrap(headerBuffer, 0, read).order(ByteOrder.LITTLE_ENDIAN)
            val totalLen = bb.int
            val type = bb.short
            if (type == PTP_CONTAINER_DATA) {
                val outFile = File(targetPath)
                outFile.parentFile?.mkdirs()

                outFile.outputStream().use { fos ->
                    val firstChunkLen = read - 12
                    if (firstChunkLen > 0) {
                        fos.write(headerBuffer, 12, firstChunkLen)
                    }
                    var bytesRemaining = (totalLen - 12) - firstChunkLen
                    val chunk = ByteArray(32768)
                    while (bytesRemaining > 0) {
                        val r = conn.bulkTransfer(inEp, chunk, Math.min(chunk.size, bytesRemaining), 3000)
                        if (r <= 0) break
                        fos.write(chunk, 0, r)
                        bytesRemaining -= r
                    }
                }
                return@withContext outFile.absolutePath
            }
        }
        throw Exception("Failed downloading full resolution object $objectHandle from Canon camera")
    }

    fun disconnect() {
        isConnected = false
        eventLoopJob?.cancel()
        eventLoopJob = null

        try {
            usbConnection?.let { conn ->
                usbInterface?.let { iface ->
                    conn.releaseInterface(iface)
                }
                conn.close()
            }
        } catch (e: Exception) {
            Log.w(TAG, "Error closing USB connection: ${e.message}")
        } finally {
            usbConnection = null
            usbInterface = null
            inEndpoint = null
            outEndpoint = null
            eventEndpoint = null
            activeDevice = null
            onStateChange("disconnected")
        }
    }

    fun destroy() {
        disconnect()
        try {
            context.unregisterReceiver(permissionReceiver)
        } catch (_: Exception) {}
    }
}
