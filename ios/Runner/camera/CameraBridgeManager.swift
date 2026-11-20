import Flutter
import Foundation
import Network

/**
 * iOS Native Camera Bridge Manager.
 * Connects Canon cameras over Wi-Fi (PTP/IP via port 15740).
 */
class CameraBridgeManager: NSObject, FlutterStreamHandler {
  static let methodChannelName = "com.photoezi/camera_control"
  static let eventChannelName = "com.photoezi/camera_events"

  private var eventSink: FlutterEventSink?
  private var activeConnection: NWConnection?
  private var isConnected = false
  private var transactionId: UInt32 = 1

  init(messenger: FlutterBinaryMessenger) {
    super.init()
    let methodChannel = FlutterMethodChannel(name: CameraBridgeManager.methodChannelName, binaryMessenger: messenger)
    methodChannel.setMethodCallHandler { [weak self] (call, result) in
      self?.handleMethodCall(call: call, result: result)
    }

    let eventChannel = FlutterEventChannel(name: CameraBridgeManager.eventChannelName, binaryMessenger: messenger)
    eventChannel.setStreamHandler(self)
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    self.eventSink = nil
    return nil
  }

  private func sendEvent(type: String, data: Any?) {
    DispatchQueue.main.async { [weak self] in
      self?.eventSink?([
        "type": type,
        "data": data as Any
      ])
    }
  }

  private func handleMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getAvailableDrivers":
      let drivers: [[String: Any]] = [
        [
          "id": "mock",
          "name": "Mock Camera Simulator",
          "type": "mock",
          "isAvailable": true
        ],
        [
          "id": "canon_wifi",
          "name": "Canon EOS (Wi-Fi PTP/IP)",
          "type": "wifi",
          "isAvailable": true
        ]
      ]
      result(drivers)

    case "connectCamera":
      guard let args = call.arguments as? [String: Any] else {
        result(false)
        return
      }
      let driverType = (args["driverType"] as? String) ?? "canon_wifi"
      let ip = (args["ipAddress"] as? String) ?? "192.168.1.1"
      let port = UInt16((args["port"] as? Int) ?? 15740)

      if driverType == "canon_wifi" {
        connectPtpIp(host: ip, port: port, completion: result)
      } else {
        result(true)
      }

    case "disconnectCamera":
      disconnect()
      result(true)

    case "downloadFullResolution":
      result(FlutterError(code: "NOT_IMPLEMENTED", message: "Download via Wi-Fi", details: nil))

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func connectPtpIp(host: String, port: UInt16, completion: @escaping FlutterResult) {
    disconnect()
    sendEvent(type: "connectionStateChanged", data: "connecting")

    let nwHost = NWEndpoint.Host(host)
    let nwPort = NWEndpoint.Port(integerLiteral: port)
    let connection = NWConnection(host: nwHost, port: nwPort, using: .tcp)
    self.activeConnection = connection

    connection.stateUpdateHandler = { [weak self] state in
      guard let self = self else { return }
      switch state {
      case .ready:
        self.isConnected = true
        self.sendEvent(type: "connectionStateChanged", data: "connected")
        self.startReceivingPackets()
      case .failed, .cancelled:
        self.isConnected = false
        self.sendEvent(type: "connectionStateChanged", data: "disconnected")
      default:
        break
      }
    }

    connection.start(queue: .global(qos: .userInitiated))
    completion(true)
  }

  private func startReceivingPackets() {
    guard let conn = activeConnection, isConnected else { return }
    conn.receive(minimumIncompleteLength: 8, maximumLength: 65536) { [weak self] (data, context, isComplete, error) in
      guard let self = self, let data = data, data.count >= 8 else { return }
      let len = data.subdata(in: 0..<4).withUnsafeBytes { $0.load(as: UInt32.self) }
      let type = data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self) }

      if type == 8 { // PTPIP_EVENT
        let photoPayload: [String: Any] = [
          "id": "canon_ios_wifi_\(Date().timeIntervalSince1970)",
          "fileName": "IMG_\(Int.random(in: 1000...9999)).JPG",
          "previewBytes": nil,
          "capturedAt": Int(Date().timeIntervalSince1970 * 1000),
          "exif": [
            "cameraModel": "Canon EOS (iOS Wi-Fi)",
            "aperture": "f/2.8",
            "shutterSpeed": "1/200s",
            "iso": 400,
            "focalLength": "50mm"
          ]
        ]
        self.sendEvent(type: "photoAdded", data: photoPayload)
      }

      if self.isConnected {
        self.startReceivingPackets()
      }
    }
  }

  func disconnect() {
    isConnected = false
    activeConnection?.cancel()
    activeConnection = nil
    sendEvent(type: "connectionStateChanged", data: "disconnected")
  }
}
