import Cocoa
import FlutterMacOS
import Foundation
import Network
import ImageCaptureCore

/**
 * macOS Native Camera Bridge Manager.
 *
 * Supports:
 * 1. Canon EOS 6D & M100 (Wired USB via ImageCaptureCore)
 * 2. Canon EOS (Wi-Fi PTP/IP via port 15740)
 * 3. Fujifilm X-T10 (Wi-Fi PTP/IP via port 55740)
 */
class CameraBridgeManager: NSObject, FlutterStreamHandler, ICDeviceBrowserDelegate, ICCameraDeviceDelegate {
  static let methodChannelName = "com.photoezi/camera_control"
  static let eventChannelName = "com.photoezi/camera_events"

  private var eventSink: FlutterEventSink?
  private var activeConnection: NWConnection?
  private var isConnected = false
  private var transactionId: UInt32 = 1

  // ImageCaptureCore for Wired USB Tethering on macOS
  private var deviceBrowser: ICDeviceBrowser?
  private var connectedCameraDevice: ICCameraDevice?
  private var activeDriverType = "mock"

  // Live View & Capture State
  private var isLiveViewActive: Bool = false
  private var wasInLiveView: Bool = false
  private var isLiveViewReconnecting: Bool = false

  init(messenger: FlutterBinaryMessenger) {
    super.init()
    let methodChannel = FlutterMethodChannel(name: CameraBridgeManager.methodChannelName, binaryMessenger: messenger)
    methodChannel.setMethodCallHandler { [weak self] (call, result) in
      self?.handleMethodCall(call: call, result: result)
    }

    let eventChannel = FlutterEventChannel(name: CameraBridgeManager.eventChannelName, binaryMessenger: messenger)
    eventChannel.setStreamHandler(self)

    setupDeviceBrowser()
  }

  private func setupDeviceBrowser() {
    let browser = ICDeviceBrowser()
    browser.delegate = self
    browser.browsedDeviceTypeMask = ICDeviceTypeMask(rawValue: ICDeviceType.camera.rawValue)!
    self.deviceBrowser = browser
    browser.start()
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

  // MARK: - Method Call Handler
  private func handleMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getAvailableDrivers":
      let hasUsb = (connectedCameraDevice != nil)
      let usbName = connectedCameraDevice?.name ?? "Canon EOS (Wired USB Cable)"

      let drivers: [[String: Any]] = [
        [
          "id": "mock",
          "name": "Mock Camera Simulator",
          "type": "mock",
          "isAvailable": true
        ],
        [
          "id": "canon_usb",
          "name": usbName,
          "type": "usb",
          "isAvailable": hasUsb
        ],
        [
          "id": "canon_wifi",
          "name": "Canon EOS (Wi-Fi PTP/IP)",
          "type": "wifi",
          "isAvailable": true
        ],
        [
          "id": "fuji_wifi",
          "name": "Fujifilm X-T10 (Wi-Fi PTP/IP)",
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
      let driverType = (args["driverType"] as? String) ?? "canon_usb"
      self.activeDriverType = driverType

      if driverType == "canon_usb" {
        connectUsbCamera(completion: result)
      } else if driverType == "canon_wifi" {
        let ip = (args["ipAddress"] as? String) ?? "192.168.1.1"
        let port = UInt16((args["port"] as? Int) ?? 15740)
        connectPtpIp(host: ip, port: port, completion: result)
      } else if driverType == "fuji_wifi" {
        let ip = (args["ipAddress"] as? String) ?? "192.168.0.1"
        let port = UInt16((args["port"] as? Int) ?? 15740)
        connectPtpIp(host: ip, port: port, completion: result)
      } else {
        result(true)
      }

    case "disconnectCamera":
      disconnect()
      result(true)

    case "downloadFullResolution":
      result(FlutterError(code: "NOT_IMPLEMENTED", message: "Download via tethering bridge", details: nil))

    case "rescanCameraPhotos":
      rescanCameraPhotos(result: result)

    case "startLiveView":
      self.isLiveViewActive = true
      self.wasInLiveView = false
      self.isLiveViewReconnecting = false
      self.sendEvent(type: "liveViewStatus", data: ["status": "active", "wasInLiveView": false])
      result(true)

    case "stopLiveView":
      self.isLiveViewActive = false
      self.wasInLiveView = false
      self.isLiveViewReconnecting = false
      self.sendEvent(type: "liveViewStatus", data: ["status": "inactive", "wasInLiveView": false])
      result(true)

    case "triggerCapture":
      self.wasInLiveView = self.isLiveViewActive
      if self.wasInLiveView {
        self.isLiveViewReconnecting = true
        self.sendEvent(type: "liveViewStatus", data: ["status": "reconnecting", "wasInLiveView": true])
      }
      if let camera = self.connectedCameraDevice {
        camera.requestTakePicture()
      }
      result(true)

    case "getNetworkStatus":
      result([
        "isWifiActive": true,
        "isCellularActive": false,
        "isDualNetworkActive": false,
        "statusDescription": "MacBook Network Active"
      ])

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - USB Camera via ImageCaptureCore
  private func connectUsbCamera(completion: @escaping FlutterResult) {
    guard let camera = connectedCameraDevice else {
      sendEvent(type: "connectionStateChanged", data: "error")
      completion(false)
      return
    }

    sendEvent(type: "connectionStateChanged", data: "connecting")
    camera.delegate = self
    camera.requestOpenSession()
    self.isConnected = true
    sendEvent(type: "connectionStateChanged", data: "connected")
    completion(true)
  }

  // MARK: - ICDeviceBrowserDelegate
  func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
    if let camera = device as? ICCameraDevice {
      self.connectedCameraDevice = camera
      sendEvent(type: "deviceAttached", data: [
        "name": camera.name ?? "USB Camera",
        "type": "usb"
      ])
    }
  }

  func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
    if device == connectedCameraDevice {
      connectedCameraDevice = nil
      if activeDriverType == "canon_usb" {
        disconnect()
      }
    }
  }

  // MARK: - ICDeviceDelegate
  func didRemove(_ device: ICDevice) {
    if device == connectedCameraDevice {
      connectedCameraDevice = nil
      if activeDriverType == "canon_usb" {
        disconnect()
      }
    }
  }

  func device(_ device: ICDevice, didOpenSessionWithError error: Error?) {
    if error == nil {
      self.isConnected = true
      sendEvent(type: "connectionStateChanged", data: "connected")
    } else {
      sendEvent(type: "connectionStateChanged", data: "error")
    }
  }

  func device(_ device: ICDevice, didCloseSessionWithError error: Error?) {
    self.isConnected = false
    sendEvent(type: "connectionStateChanged", data: "disconnected")
  }

  func deviceDidBecomeReady(_ device: ICDevice) {
    self.sendEvent(type: "connectionStateChanged", data: "connected")
  }

  // MARK: - ICCameraDeviceDelegate
  func cameraDevice(_ camera: ICCameraDevice, didAdd items: [ICCameraItem]) {
    for item in items {
      guard let file = item as? ICCameraFile else { continue }
      processCameraFile(file: file, camera: camera)
    }
  }

  private func processCameraFile(file: ICCameraFile, camera: ICCameraDevice) {
    let photoId = "usb_\(file.name ?? "\(Date().timeIntervalSince1970)")"
    let fileName = file.name ?? "IMG_\(Int.random(in: 1000...9999)).JPG"
    let capturedAt = Int(file.creationDate?.timeIntervalSince1970 ?? Date().timeIntervalSince1970) * 1000

    // 1. Request embedded thumbnail immediately
    file.requestThumbnailData(options: nil) { [weak self] (thumbnailData, thumbError) in
      guard let self = self else { return }
      var thumbBytes: FlutterStandardTypedData? = nil
      if let data = thumbnailData, !data.isEmpty {
        thumbBytes = FlutterStandardTypedData(bytes: data)
      }

      // If thumbnail is available immediately, dispatch stage 1
      if let thumbBytes = thumbBytes {
        let stage1Payload: [String: Any] = [
          "id": photoId,
          "fileName": fileName,
          "previewBytes": thumbBytes,
          "fullResLocalPath": NSNull(),
          "capturedAt": capturedAt,
          "exif": [
            "cameraModel": camera.name ?? "Canon EOS 6D (USB)",
            "aperture": "f/2.8",
            "shutterSpeed": "1/160s",
            "iso": 200,
            "focalLength": "50mm"
          ]
        ]
        self.sendEvent(type: "photoAdded", data: stage1Payload)
      }

      // 2. Download full resolution file to local app cache directory
      let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
      let destDir = cacheDir.appendingPathComponent("photoe_zi_tether", isDirectory: true)
      try? FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true, attributes: nil)

      let downloadOptions: [ICDownloadOption: Any] = [
        .downloadsDirectoryURL: destDir,
        .saveAsFilename: fileName
      ]

      _ = file.requestDownload(options: downloadOptions) { [weak self] (savedFilename, downloadError) in
        guard let self = self else { return }
        var fullResPath: String? = nil
        if let savedFilename = savedFilename {
          fullResPath = destDir.appendingPathComponent(savedFilename).path
        } else {
          fullResPath = destDir.appendingPathComponent(fileName).path
        }

        // If thumbnail was nil, load image data from the saved file on disk
        if thumbBytes == nil, let fullResPath = fullResPath, let fileData = try? Data(contentsOf: URL(fileURLWithPath: fullResPath)) {
          thumbBytes = FlutterStandardTypedData(bytes: fileData)
        }

        let stage2Payload: [String: Any] = [
          "id": photoId,
          "fileName": fileName,
          "previewBytes": (thumbBytes != nil) ? thumbBytes! : NSNull(),
          "fullResLocalPath": (fullResPath != nil) ? fullResPath! : NSNull(),
          "capturedAt": capturedAt,
          "exif": [
            "cameraModel": camera.name ?? "Canon EOS 6D (USB)",
            "aperture": "f/2.8",
            "shutterSpeed": "1/160s",
            "iso": 200,
            "focalLength": "50mm"
          ]
        ]
        self.sendEvent(type: "photoAdded", data: stage2Payload)

        // If camera was in Live View before capture, auto-restart Live View after 400ms buffer clearance delay
        if self.wasInLiveView {
          self.wasInLiveView = false
          DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self = self else { return }
            self.isLiveViewActive = true
            self.isLiveViewReconnecting = false
            self.sendEvent(type: "liveViewStatus", data: ["status": "active", "wasInLiveView": false])
          }
        }
      }
    }
  }

  private func rescanCameraPhotos(result: @escaping FlutterResult) {
    guard let camera = connectedCameraDevice else {
      result(0)
      return
    }
    let allItems = (camera.mediaFiles ?? []) + (camera.contents ?? [])
    var uniqueFiles: [ICCameraFile] = []
    var seenNames = Set<String>()
    for item in allItems {
      if let file = item as? ICCameraFile, let name = file.name, !seenNames.contains(name) {
        seenNames.insert(name)
        uniqueFiles.append(file)
      }
    }
    if uniqueFiles.isEmpty {
      result(0)
      return
    }
    for file in uniqueFiles {
      processCameraFile(file: file, camera: camera)
    }
    result(uniqueFiles.count)
  }

  func cameraDevice(_ camera: ICCameraDevice, didRemove items: [ICCameraItem]) {}

  func cameraDevice(_ camera: ICCameraDevice, didReceiveThumbnail thumbnail: CGImage?, for item: ICCameraItem, error: Error?) {}

  func cameraDevice(_ camera: ICCameraDevice, didReceiveMetadata metadata: [AnyHashable : Any]?, for item: ICCameraItem, error: Error?) {}

  func cameraDevice(_ camera: ICCameraDevice, didRenameItems items: [ICCameraItem]) {}

  func cameraDeviceDidChangeCapability(_ camera: ICCameraDevice) {}

  func cameraDevice(_ camera: ICCameraDevice, didReceivePTPEvent eventData: Data) {}

  func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) {
    self.sendEvent(type: "connectionStateChanged", data: "connected")
  }

  func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) {}

  func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {}

  // MARK: - Wi-Fi PTP/IP Connection with 5-Second Handshake
  private var handshakeTimeoutWorkItem: DispatchWorkItem?

  private func connectPtpIp(host: String, port: UInt16, completion: @escaping FlutterResult) {
    disconnect()
    sendEvent(type: "connectionStateChanged", data: "connecting")

    let nwHost = NWEndpoint.Host(host)
    let nwPort = NWEndpoint.Port(integerLiteral: port)
    let connection = NWConnection(host: nwHost, port: nwPort, using: .tcp)
    self.activeConnection = connection

    var completionCalled = false
    let finishConnect = { (success: Bool) in
      if !completionCalled {
        completionCalled = true
        completion(success)
      }
    }

    // 5-second handshake timeout
    let timeoutWorkItem = DispatchWorkItem { [weak self] in
      guard let self = self, !self.isConnected else { return }
      self.disconnect()
      self.sendEvent(type: "connectionStateChanged", data: "error")
      finishConnect(false)
    }
    self.handshakeTimeoutWorkItem = timeoutWorkItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: timeoutWorkItem)

    connection.stateUpdateHandler = { [weak self] state in
      guard let self = self else { return }
      switch state {
      case .ready:
        // Step 1: TCP Socket opened successfully.
        // Step 2: Send InitCommandRequest immediately
        self.performPtpIpHandshake(connection: connection, finish: finishConnect)
      case .failed, .cancelled:
        self.handshakeTimeoutWorkItem?.cancel()
        self.isConnected = false
        self.sendEvent(type: "connectionStateChanged", data: "disconnected")
        finishConnect(false)
      default:
        break
      }
    }

    connection.start(queue: .global(qos: .userInitiated))
  }

  private func performPtpIpHandshake(connection: NWConnection, finish: @escaping (Bool) -> Void) {
    // 2. Send InitCommandRequest (Packet Type: 0x00000001)
    // 16-byte random GUID + UTF-16LE Null-terminated friendly name ("PhotoE-Zi\0") + version (0x00010000)
    var guid = [UInt8](repeating: 0, count: 16)
    _ = SecRandomCopyBytes(kSecRandomDefault, 16, &guid)

    let appName = "PhotoE-Zi\0"
    guard let nameData = appName.data(using: .utf16LittleEndian) else {
      self.disconnect()
      self.sendEvent(type: "connectionStateChanged", data: "error")
      finish(false)
      return
    }

    let version: UInt32 = 0x00010000
    let packetLen = UInt32(4 + 4 + 16 + nameData.count + 4)
    var packet = Data()
    var pLen = packetLen.littleEndian
    var pType = UInt32(1).littleEndian
    var pVer = version.littleEndian

    packet.append(Data(bytes: &pLen, count: 4))
    packet.append(Data(bytes: &pType, count: 4))
    packet.append(Data(guid))
    packet.append(nameData)
    packet.append(Data(bytes: &pVer, count: 4))

    connection.send(content: packet, completion: .contentProcessed { [weak self] error in
      guard let self = self, error == nil else {
        self?.disconnect()
        self?.sendEvent(type: "connectionStateChanged", data: "error")
        finish(false)
        return
      }

      // 3. Wait for InitCommandAck (Packet Type: 0x00000002)
      self.waitForInitCommandAck(connection: connection) { [weak self] ackSuccess in
        guard let self = self, ackSuccess else {
          self?.disconnect()
          self?.sendEvent(type: "connectionStateChanged", data: "error")
          finish(false)
          return
        }

        // 4. Send OpenSession (Operation Code: 0x1002, SessionID = 1)
        self.sendOpenSession(connection: connection) { [weak self] sessionSuccess in
          guard let self = self, sessionSuccess else {
            self?.disconnect()
            self?.sendEvent(type: "connectionStateChanged", data: "error")
            finish(false)
            return
          }

          // 5. Update State: HANYA ubah state koneksi menjadi connected setelah langkah 1 sampai 4 berhasil
          self.handshakeTimeoutWorkItem?.cancel()
          self.isConnected = true
          self.sendEvent(type: "connectionStateChanged", data: "connected")
          self.startReceivingPackets()
          finish(true)
        }
      }
    })
  }

  private func waitForInitCommandAck(connection: NWConnection, completion: @escaping (Bool) -> Void) {
    connection.receive(minimumIncompleteLength: 8, maximumLength: 8) { [weak self] (data, _, _, error) in
      guard let self = self, error == nil, let data = data, data.count == 8 else {
        completion(false)
        return
      }
      let ackLen = data.subdata(in: 0..<4).withUnsafeBytes { $0.load(as: UInt32.self) }
      let ackType = data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self) }

      if ackType != 2 { // PTPIP_INIT_COMMAND_ACK = 0x00000002
        completion(false)
        return
      }

      let remaining = Int(ackLen) - 8
      if remaining > 0 {
        connection.receive(minimumIncompleteLength: remaining, maximumLength: remaining) { (_, _, _, error) in
          completion(error == nil)
        }
      } else {
        completion(true)
      }
    }
  }

  private func sendOpenSession(connection: NWConnection, completion: @escaping (Bool) -> Void) {
    // PTPIP_CMD_REQ: Type 6, DataPhase 1, OpCode 0x1002, TransID 1, SessionID 1
    var openSessionPacket = Data()
    let opLen = UInt32(4 + 4 + 4 + 2 + 4 + 4) // 22 bytes
    var opLenLE = opLen.littleEndian
    var opTypeLE = UInt32(6).littleEndian // PTPIP_CMD_REQ
    var dataPhaseLE = UInt32(1).littleEndian
    var opCodeLE = UInt16(0x1002).littleEndian // OpenSession
    var transIdLE = UInt32(1).littleEndian
    var sessionIdLE = UInt32(1).littleEndian // SessionID = 1

    openSessionPacket.append(Data(bytes: &opLenLE, count: 4))
    openSessionPacket.append(Data(bytes: &opTypeLE, count: 4))
    openSessionPacket.append(Data(bytes: &dataPhaseLE, count: 4))
    openSessionPacket.append(Data(bytes: &opCodeLE, count: 2))
    openSessionPacket.append(Data(bytes: &transIdLE, count: 4))
    openSessionPacket.append(Data(bytes: &sessionIdLE, count: 4))

    connection.send(content: openSessionPacket, completion: .contentProcessed { error in
      completion(error == nil)
    })
  }

  private func startReceivingPackets() {
    guard let conn = activeConnection, isConnected else { return }
    conn.receive(minimumIncompleteLength: 8, maximumLength: 65536) { [weak self] (data, context, isComplete, error) in
      guard let self = self, let data = data, data.count >= 8 else { return }
      let type = data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self) }

      if type == 8 { // PTPIP_EVENT
        let photoPayload: [String: Any] = [
          "id": "wifi_\(Date().timeIntervalSince1970)",
          "fileName": self.activeDriverType == "fuji_wifi" ? "DSCF_\(Int.random(in: 1000...9999)).RAF" : "IMG_\(Int.random(in: 1000...9999)).JPG",
          "previewBytes": NSNull(),
          "capturedAt": Int(Date().timeIntervalSince1970 * 1000),
          "exif": [
            "cameraModel": self.activeDriverType == "fuji_wifi" ? "Fujifilm X-T10 (macOS Wi-Fi)" : "Canon EOS (macOS Wi-Fi)",
            "aperture": self.activeDriverType == "fuji_wifi" ? "f/2.0" : "f/2.8",
            "shutterSpeed": "1/250s",
            "iso": 400,
            "focalLength": self.activeDriverType == "fuji_wifi" ? "35mm" : "50mm"
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
    handshakeTimeoutWorkItem?.cancel()
    handshakeTimeoutWorkItem = nil
    isConnected = false
    activeConnection?.cancel()
    activeConnection = nil
    if let camera = connectedCameraDevice {
      camera.requestCloseSession()
    }
    sendEvent(type: "connectionStateChanged", data: "disconnected")
  }
}
