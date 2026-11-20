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
        let rawPort = (args["port"] as? Int) ?? 55740
        let port = UInt16(rawPort == 15740 ? 55740 : rawPort)
        if rawPort == 15740 {
          NSLog("[PtpIp] Remapping Fujifilm X-T10 port 15740 -> 55740")
        }
        connectPtpIp(host: ip, port: port, use82ByteFujiPacket: false, completion: result)
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

  // MARK: - Wi-Fi PTP/IP Connection with Handshake
  private var handshakeTimeoutWorkItem: DispatchWorkItem?

  // Persistent 16-byte GUID recognized by Fujifilm Wireless PTP/IP firmware so camera remembers pairing
  private let fujiClientGuid: [UInt8] = [
    0xF2, 0xE4, 0x53, 0x8F, 0xAD, 0xA5, 0x48, 0x5D,
    0x87, 0xB2, 0x7F, 0x0B, 0xD3, 0xD5, 0xDE, 0xD0
  ]

  private func connectPtpIp(
    host: String,
    port: UInt16,
    use82ByteFujiPacket: Bool = false,
    completion: @escaping FlutterResult
  ) {
    disconnect()
    sendEvent(type: "connectionStateChanged", data: "connecting")
    NSLog("[PtpIp] Opening TCP socket to %@:%d (driver=%@, 82ByteMode=%d)...", host, port, activeDriverType, use82ByteFujiPacket ? 1 : 0)

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

    // 15-second handshake timeout (allows time for user to press MENU/OK on camera body during first-time pairing)
    let timeoutWorkItem = DispatchWorkItem { [weak self] in
      guard let self = self, !self.isConnected else { return }
      NSLog("[PtpIp] Handshake timed out after 15s on %@:%d", host, port)
      self.disconnect()
      self.sendEvent(type: "connectionStateChanged", data: "error")
      finishConnect(false)
    }
    self.handshakeTimeoutWorkItem = timeoutWorkItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 15.0, execute: timeoutWorkItem)

    connection.stateUpdateHandler = { [weak self] state in
      guard let self = self else { return }
      switch state {
      case .preparing:
        NSLog("[PtpIp] TCP Socket preparing (%@:%d)...", host, port)
      case .ready:
        NSLog("[PtpIp] TCP Socket ready to %@:%d. Initiating handshake...", host, port)
        // Step 1: TCP Socket opened successfully.
        // Step 2: Send InitCommandRequest immediately
        self.performPtpIpHandshake(
          connection: connection,
          host: host,
          port: port,
          use82ByteFujiPacket: use82ByteFujiPacket,
          finish: finishConnect
        )
      case .waiting(let err):
        NSLog("[PtpIp] TCP Socket waiting (%@:%d): %@", host, port, String(describing: err))
      case .failed(let err):
        NSLog("[PtpIp] TCP Socket failed (%@:%d): %@", host, port, String(describing: err))
        self.handshakeTimeoutWorkItem?.cancel()
        self.isConnected = false
        self.sendEvent(type: "connectionStateChanged", data: "disconnected")
        finishConnect(false)
      case .cancelled:
        NSLog("[PtpIp] TCP Socket cancelled")
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

  private func buildInitCommandPacket(use82ByteFujiPacket: Bool) -> Data {
    let appName = "PhotoEZ\0"
    let nameData = appName.data(using: .utf16LittleEndian) ?? Data()

    if use82ByteFujiPacket {
      // 82-byte (0x52) Fujifilm X-Series InitCommandRequest layout:
      // [0..3]: Length = 82 (0x52, UInt32 LE)
      // [4..7]: Type = 1 (UInt32 LE, PTPIP_INIT_COMMAND_REQ)
      // [8..23]: GUID (16 bytes)
      // [24..27]: Protocol Version / Token (4 bytes: 02 78 A8 C0)
      // [28..81]: Device Name UTF-16LE null-terminated (54 bytes, padded with zeros)
      var packet = Data(count: 82)
      var lenLE = UInt32(82).littleEndian
      packet.replaceSubrange(0..<4, with: Data(bytes: &lenLE, count: 4))

      var typeLE = UInt32(1).littleEndian
      packet.replaceSubrange(4..<8, with: Data(bytes: &typeLE, count: 4))

      packet.replaceSubrange(8..<24, with: Data(fujiClientGuid))

      let versionBytes: [UInt8] = [0x02, 0x78, 0xA8, 0xC0]
      packet.replaceSubrange(24..<28, with: Data(versionBytes))

      let copyLen = min(nameData.count, 54)
      packet.replaceSubrange(28..<(28 + copyLen), with: nameData.prefix(copyLen))
      return packet
    } else {
      // 40-byte InitCommandRequest layout:
      // [0..3]: Length = 40 (0x28, UInt32 LE)
      // [4..7]: Type = 1 (UInt32 LE, PTPIP_INIT_COMMAND_REQ)
      // [8..23]: GUID (16 bytes)
      // [24..39]: Device Name UTF-16LE null-terminated (16 bytes, padded with zeros)
      var packet = Data(count: 40)
      var lenLE = UInt32(40).littleEndian
      packet.replaceSubrange(0..<4, with: Data(bytes: &lenLE, count: 4))

      var typeLE = UInt32(1).littleEndian
      packet.replaceSubrange(4..<8, with: Data(bytes: &typeLE, count: 4))

      packet.replaceSubrange(8..<24, with: Data(fujiClientGuid))

      let copyLen = min(nameData.count, 16)
      packet.replaceSubrange(24..<(24 + copyLen), with: nameData.prefix(copyLen))
      return packet
    }
  }

  private func performPtpIpHandshake(
    connection: NWConnection,
    host: String,
    port: UInt16,
    use82ByteFujiPacket: Bool,
    finish: @escaping (Bool) -> Void
  ) {
    let packet = buildInitCommandPacket(use82ByteFujiPacket: use82ByteFujiPacket)
    let txHex = packet.map { String(format: "%02hhX", $0) }.joined(separator: " ")
    NSLog("[PtpIp] TX InitCommandRequest (%d bytes): %@", packet.count, txHex)

    connection.send(content: packet, completion: .contentProcessed { [weak self] error in
      guard let self = self, error == nil else {
        NSLog("[PtpIp] Error sending InitCommandRequest: \(String(describing: error))")
        self?.disconnect()
        self?.sendEvent(type: "connectionStateChanged", data: "error")
        finish(false)
        return
      }

      // 3. Wait for InitCommandAck (Packet Type: 0x00000002)
      self.waitForInitCommandAck(connection: connection) { [weak self] ackSuccess in
        guard let self = self else { return }
        if !ackSuccess {
          // If 40-byte packet was rejected by Fujifilm camera, auto-retry once with 82-byte (0x52) Fujifilm packet
          if self.activeDriverType == "fuji_wifi" && !use82ByteFujiPacket {
            NSLog("[PtpIp] 40-byte InitCommandRequest rejected by camera; auto-retrying with 82-byte (0x52) Fujifilm packet...")
            self.handshakeTimeoutWorkItem?.cancel()
            self.activeConnection?.cancel()
            self.activeConnection = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
              self?.connectPtpIp(host: host, port: port, use82ByteFujiPacket: true, completion: { ok in
                finish((ok as? Bool) ?? false)
              })
            }
            return
          }

          NSLog("[PtpIp] Failed waiting for InitCommandAck")
          self.disconnect()
          self.sendEvent(type: "connectionStateChanged", data: "error")
          finish(false)
          return
        }

        // 4. Send OpenSession (Operation Code: 0x1002, SessionID = 1)
        self.sendOpenSession(connection: connection) { [weak self] sessionSuccess in
          guard let self = self, sessionSuccess else {
            NSLog("[PtpIp] Failed sending OpenSession")
            self?.disconnect()
            self?.sendEvent(type: "connectionStateChanged", data: "error")
            finish(false)
            return
          }

          // 5. Update State: HANYA ubah state koneksi menjadi connected setelah langkah 1 sampai 4 berhasil
          NSLog("[PtpIp] Handshake completed successfully! Connected.")
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
    connection.receive(minimumIncompleteLength: 8, maximumLength: 65536) { (data, _, _, error) in
      guard error == nil, let data = data, data.count >= 8 else {
        NSLog("[PtpIp] Error or EOF waiting for InitCommandAck: \(String(describing: error)), count=\(data?.count ?? 0)")
        completion(false)
        return
      }
      let rxHex = data.map { String(format: "%02hhX", $0) }.joined(separator: " ")
      NSLog("[PtpIp] RX InitCommand response (%d bytes): %@", data.count, rxHex)

      let ackType = UInt32(littleEndian: data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self) })
      if ackType == 2 { // PTPIP_INIT_COMMAND_ACK = 0x00000002
        completion(true)
      } else {
        NSLog("[PtpIp] Unexpected Ack packet type: \(ackType)")
        completion(false)
      }
    }
  }

  private func sendOpenSession(connection: NWConnection, completion: @escaping (Bool) -> Void) {
    var openSessionPacket = Data()

    if activeDriverType == "fuji_wifi" {
      // Fujifilm port 55740 16-byte OpenSession container:
      // [0..3]: Length = 16 (10 00 00 00)
      // [4..5]: Container Type = 1 (01 00, Operation Request)
      // [6..7]: OpCode = 0x1002 (02 10, OpenSession)
      // [8..11]: TransID = 1 (01 00 00 00)
      // [12..15]: SessionID = 1 (01 00 00 00)
      var opLenLE = UInt32(16).littleEndian
      var containerTypeLE = UInt16(1).littleEndian
      var opCodeLE = UInt16(0x1002).littleEndian
      var transIdLE = UInt32(1).littleEndian
      var sessionIdLE = UInt32(1).littleEndian

      openSessionPacket.append(Data(bytes: &opLenLE, count: 4))
      openSessionPacket.append(Data(bytes: &containerTypeLE, count: 2))
      openSessionPacket.append(Data(bytes: &opCodeLE, count: 2))
      openSessionPacket.append(Data(bytes: &transIdLE, count: 4))
      openSessionPacket.append(Data(bytes: &sessionIdLE, count: 4))
    } else {
      // Standard PTP/IP 22-byte PTPIP_CMD_REQ: Type 6, DataPhase 1, OpCode 0x1002, TransID 1, SessionID 1
      var opLenLE = UInt32(22).littleEndian
      var opTypeLE = UInt32(6).littleEndian
      var dataPhaseLE = UInt32(1).littleEndian
      var opCodeLE = UInt16(0x1002).littleEndian
      var transIdLE = UInt32(1).littleEndian
      var sessionIdLE = UInt32(1).littleEndian

      openSessionPacket.append(Data(bytes: &opLenLE, count: 4))
      openSessionPacket.append(Data(bytes: &opTypeLE, count: 4))
      openSessionPacket.append(Data(bytes: &dataPhaseLE, count: 4))
      openSessionPacket.append(Data(bytes: &opCodeLE, count: 2))
      openSessionPacket.append(Data(bytes: &transIdLE, count: 4))
      openSessionPacket.append(Data(bytes: &sessionIdLE, count: 4))
    }

    let txSessionHex = openSessionPacket.map { String(format: "%02hhX", $0) }.joined(separator: " ")
    NSLog("[PtpIp] TX OpenSession (%d bytes): %@", openSessionPacket.count, txSessionHex)

    connection.send(content: openSessionPacket, completion: .contentProcessed { error in
      if let error = error {
        NSLog("[PtpIp] Error sending OpenSession: \(error)")
        completion(false)
      } else {
        completion(true)
      }
    })
  }

  private func startReceivingPackets() {
    guard let conn = activeConnection, isConnected else { return }
    conn.receive(minimumIncompleteLength: 8, maximumLength: 65536) { [weak self] (data, context, isComplete, error) in
      guard let self = self, let data = data, data.count >= 8 else {
        if let error = error {
          NSLog("[PtpIp] Stream receive error: \(error)")
        }
        return
      }
      let rxHex = data.map { String(format: "%02hhX", $0) }.joined(separator: " ")
      NSLog("[PtpIp] RX Stream Packet (%d bytes): %@", data.count, rxHex)
      let type = UInt32(littleEndian: data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self) })

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
