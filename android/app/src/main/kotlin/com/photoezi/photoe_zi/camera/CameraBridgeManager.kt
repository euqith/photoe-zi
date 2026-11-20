package com.photoezi.photoe_zi.camera

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class CameraBridgeManager(
    private val context: Context,
    messenger: BinaryMessenger
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        const val METHOD_CHANNEL = "com.photoezi/camera_control"
        const val EVENT_CHANNEL = "com.photoezi/camera_events"
    }

    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val scope = CoroutineScope(Dispatchers.Main)

    private val usbDriver = CanonUsbPtpDriver(
        context = context,
        onStateChange = { state -> sendEvent("connectionStateChanged", state) },
        onNewPhoto = { photo -> sendEvent("photoAdded", photo) }
    )

    private val wifiDriver = CanonWifiPtpIpDriver(
        onStateChange = { state -> sendEvent("connectionStateChanged", state) },
        onNewPhoto = { photo -> sendEvent("photoAdded", photo) }
    )

    private val fujiWifiDriver = FujifilmWifiDriver(
        onStateChange = { state -> sendEvent("connectionStateChanged", state) },
        onNewPhoto = { photo -> sendEvent("photoAdded", photo) }
    )

    private val dualNetworkManager = DualNetworkManager(
        context = context,
        onNetworkStatusChanged = { status -> sendEvent("networkStatusChanged", status) }
    )

    private var activeDriverType = "mock"

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)

        usbDriver.onLiveViewStatusChange = { status ->
            sendEvent("liveViewStatus", mapOf("status" to status))
        }
        usbDriver.onLiveViewFrame = { frame ->
            sendEvent("liveViewFrame", frame)
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun sendEvent(eventType: String, data: Any?) {
        mainHandler.post {
            eventSink?.success(
                mapOf(
                    "type" to eventType,
                    "data" to data
                )
            )
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getAvailableDrivers" -> {
                val hasUsb = usbDriver.isCanonDeviceAttached()
                val attachedName = usbDriver.getAttachedDeviceName()
                val drivers = listOf(
                    mapOf(
                        "id" to "mock",
                        "name" to "Mock Camera Simulator",
                        "type" to "mock",
                        "isAvailable" to true
                    ),
                    mapOf(
                        "id" to "canon_usb",
                        "name" to (attachedName ?: "Canon EOS (Wired USB-OTG)"),
                        "type" to "usb",
                        "isAvailable" to hasUsb
                    ),
                    mapOf(
                        "id" to "canon_wifi",
                        "name" to "Canon EOS (Wi-Fi PTP/IP)",
                        "type" to "wifi",
                        "isAvailable" to true
                    ),
                    mapOf(
                        "id" to "fuji_wifi",
                        "name" to "Fujifilm X-T10 (Wi-Fi PTP/IP)",
                        "type" to "wifi",
                        "isAvailable" to true
                    )
                )
                result.success(drivers)
            }

            "connectCamera" -> {
                val driverType = call.argument<String>("driverType") ?: "canon_usb"
                val ipAddress = call.argument<String>("ipAddress") ?: "192.168.1.1"
                val port = call.argument<Int>("port") ?: 15740
                activeDriverType = driverType

                scope.launch {
                    val ok = when (driverType) {
                        "canon_usb" -> usbDriver.connect()
                        "canon_wifi" -> {
                            dualNetworkManager.enableCellularRouting()
                            wifiDriver.connect(ipAddress, port)
                        }
                        "fuji_wifi" -> {
                            dualNetworkManager.enableCellularRouting()
                            fujiWifiDriver.connect(ipAddress, port)
                        }
                        else -> true
                    }
                    result.success(ok)
                }
            }

            "disconnectCamera" -> {
                when (activeDriverType) {
                    "canon_usb" -> usbDriver.disconnect()
                    "canon_wifi" -> {
                        wifiDriver.disconnect()
                        dualNetworkManager.disableCellularRouting()
                    }
                    "fuji_wifi" -> {
                        fujiWifiDriver.disconnect()
                        dualNetworkManager.disableCellularRouting()
                    }
                }
                result.success(true)
            }

            "downloadFullResolution" -> {
                val objectHandle = call.argument<Int>("objectHandle") ?: 0
                val targetPath = call.argument<String>("targetPath")
                if (targetPath.isNullOrBlank()) {
                    result.error("INVALID_ARGS", "Missing targetPath", null)
                    return
                }
                scope.launch {
                    try {
                        val downloaded = usbDriver.downloadFullResolution(objectHandle, targetPath)
                        result.success(downloaded)
                    } catch (e: Exception) {
                        result.error("DOWNLOAD_ERROR", e.message, null)
                    }
                }
            }

            "getNetworkStatus" -> {
                result.success(dualNetworkManager.getNetworkStatus())
            }

            "rescanCameraPhotos" -> {
                result.success(0)
            }

            "enableCellularSync" -> {
                dualNetworkManager.enableCellularRouting()
                result.success(true)
            }

            "startLiveView" -> {
                val ok = when (activeDriverType) {
                    "canon_usb" -> usbDriver.startLiveView()
                    else -> true
                }
                result.success(ok)
            }

            "stopLiveView" -> {
                val ok = when (activeDriverType) {
                    "canon_usb" -> usbDriver.stopLiveView()
                    else -> true
                }
                result.success(ok)
            }

            "triggerCapture" -> {
                val ok = when (activeDriverType) {
                    "canon_usb" -> usbDriver.triggerCapture()
                    else -> true
                }
                result.success(ok)
            }

            "disableCellularSync" -> {
                dualNetworkManager.disableCellularRouting()
                result.success(true)
            }

            else -> result.notImplemented()
        }
    }

    fun destroy() {
        usbDriver.destroy()
        wifiDriver.disconnect()
        fujiWifiDriver.disconnect()
        dualNetworkManager.destroy()
    }
}
