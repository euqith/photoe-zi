import Cocoa
import FlutterMacOS
import Foundation
import Network
import ImageCaptureCore
import os.log

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
  private var fujiEventConnection: NWConnection?
  private var fujiStreamConnection: NWConnection?
  private var fujiKeepAliveTimer: DispatchSourceTimer?
  private var isConnected = false
  private var isBusyWithCommand = false
  private var lastConnectedHost: String = "192.168.0.1"
  private var transactionId: UInt32 = 1
  private var connectionNumber: UInt32 = 0

  // ImageCaptureCore for Wired USB Tethering on macOS
  private var deviceBrowser: ICDeviceBrowser?
  private var connectedCameraDevice: ICCameraDevice?
  private var activeDriverType = "mock"
  private var canonWifiSession: CanonEosWifiSession?

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
        connectCanonWifi(host: ip, port: port, completion: result)
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
      if self.activeDriverType == "fuji_wifi" && self.isConnected {
        self.startFujiLiveViewStream()
      }
      result(true)

    case "stopLiveView":
      self.isLiveViewActive = false
      self.wasInLiveView = false
      self.isLiveViewReconnecting = false
      self.stopFujiLiveViewStream()
      self.sendEvent(type: "liveViewStatus", data: ["status": "inactive", "wasInLiveView": false])
      result(true)

    case "triggerCapture":
      self.wasInLiveView = self.isLiveViewActive
      if self.wasInLiveView {
        self.isLiveViewReconnecting = true
        self.sendEvent(type: "liveViewStatus", data: ["status": "reconnecting", "wasInLiveView": true])
      }
      if self.activeDriverType == "fuji_wifi" && self.isConnected {
        self.triggerFujiCapture()
      } else if let camera = self.connectedCameraDevice {
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

  private func logPtpIp(_ msg: String) {
    NSLog("[PtpIp] %@", msg)
    os_log("%{public}@", "[PtpIp] \(msg)")
  }

  private func connectPtpIp(
    host: String,
    port: UInt16,
    use82ByteFujiPacket: Bool = false,
    completion: @escaping FlutterResult
  ) {
    disconnect()
    self.lastConnectedHost = host
    self.transactionId = 1
    sendEvent(type: "connectionStateChanged", data: "connecting")
    logPtpIp("Opening TCP socket to \(host):\(port) (driver=\(activeDriverType), 82ByteMode=\(use82ByteFujiPacket ? 1 : 0))...")

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
      self.logPtpIp("Handshake timed out after 15s on \(host):\(port)")
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
        self.logPtpIp("TCP Socket preparing (\(host):\(port))...")
      case .ready:
        self.logPtpIp("TCP Socket ready to \(host):\(port). Initiating handshake...")
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
        self.logPtpIp("TCP Socket waiting (\(host):\(port)): \(err)")
      case .failed(let err):
        self.logPtpIp("TCP Socket failed (\(host):\(port)): \(err)")
        self.handshakeTimeoutWorkItem?.cancel()
        self.isConnected = false
        self.sendEvent(type: "connectionStateChanged", data: "disconnected")
        finishConnect(false)
      case .cancelled:
        self.logPtpIp("TCP Socket cancelled")
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
      // 82-byte (0x52) Fujifilm X-Series registration_message layout:
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

  private func receiveExactBytes(
    connection: NWConnection,
    count: Int,
    accumulated: Data = Data(),
    completion: @escaping (Data?) -> Void
  ) {
    let remaining = count - accumulated.count
    if remaining <= 0 {
      completion(accumulated)
      return
    }
    connection.receive(minimumIncompleteLength: min(remaining, 65536), maximumLength: remaining) { [weak self] (chunk, _, isComplete, error) in
      guard let self = self else { return }
      guard error == nil, let chunk = chunk, !chunk.isEmpty else {
        if isComplete && accumulated.count == count {
          completion(accumulated)
        } else {
          completion(nil)
        }
        return
      }
      var nextData = accumulated
      nextData.append(chunk)
      if nextData.count >= count {
        completion(nextData)
      } else {
        self.receiveExactBytes(connection: connection, count: count, accumulated: nextData, completion: completion)
      }
    }
  }

  private func receiveFujiPacket(connection: NWConnection, completion: @escaping (Data?) -> Void) {
    // 1. Read exact 4-byte Little-Endian packet length header
    connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] (lenData, _, isComplete, error) in
      guard let self = self else { return }
      guard error == nil, let lenData = lenData, lenData.count == 4 else {
        self.logPtpIp("EOF/Error reading 4-byte length: err=\(String(describing: error)), count=\(lenData?.count ?? 0), complete=\(isComplete)")
        completion(nil)
        return
      }
      let totalLen = Int(UInt32(littleEndian: lenData.withUnsafeBytes { $0.load(as: UInt32.self) }))
      if totalLen <= 4 || totalLen > 10_000_000 {
        self.logPtpIp("Invalid Fuji packet totalLen=\(totalLen)")
        completion(nil)
        return
      }
      let bodyLen = totalLen - 4
      self.receiveExactBytes(connection: connection, count: bodyLen) { [weak self] bodyData in
        guard let self = self, let bodyData = bodyData, bodyData.count == bodyLen else {
          self?.logPtpIp("EOF/Error reading packet body (expected \(bodyLen) bytes)")
          completion(nil)
          return
        }
        var fullPacket = Data(capacity: totalLen)
        fullPacket.append(lenData)
        fullPacket.append(bodyData)
        let previewLen = min(fullPacket.count, 84)
        let rxHex = fullPacket.prefix(previewLen).map { String(format: "%02hhX", $0) }.joined(separator: " ")
        self.logPtpIp("RX Packet (\(fullPacket.count) bytes): \(rxHex)\(fullPacket.count > previewLen ? " ..." : "")")
        completion(fullPacket)
      }
    }
  }

  private func makeFujiPacket(index: UInt16, type: UInt16, id: UInt32, payload: [UInt8] = []) -> Data {
    let totalLen = UInt32(4 + 2 + 2 + 4 + payload.count)
    var data = Data(capacity: Int(totalLen))
    var lenLE = totalLen.littleEndian
    var idxLE = index.littleEndian
    var typeLE = type.littleEndian
    var idLE = id.littleEndian
    data.append(Data(bytes: &lenLE, count: 4))
    data.append(Data(bytes: &idxLE, count: 2))
    data.append(Data(bytes: &typeLE, count: 2))
    data.append(Data(bytes: &idLE, count: 4))
    if !payload.isEmpty {
      data.append(Data(payload))
    }
    return data
  }

  private func nextTransId() -> UInt32 {
    let current = transactionId
    transactionId &+= 1
    return current
  }

  private func readUntilFujiOkResponse(
    connection: NWConnection,
    accumulatedDataPackets: [Data] = [],
    completion: @escaping (Bool, [Data]) -> Void
  ) {
    receiveFujiPacket(connection: connection) { [weak self] packet in
      guard let self = self, let packet = packet, packet.count >= 8 else {
        completion(false, accumulatedDataPackets)
        return
      }
      let containerType = UInt16(littleEndian: packet.subdata(in: 4..<6).withUnsafeBytes { $0.load(as: UInt16.self) })
      let code = UInt16(littleEndian: packet.subdata(in: 6..<8).withUnsafeBytes { $0.load(as: UInt16.self) })

      if containerType == 3 { // PTP Response Block (0x0003)
        if code == 0x2001 { // PTP_RC_OK (0x2001)
          completion(true, accumulatedDataPackets)
        } else {
          self.logPtpIp("Fuji command returned non-OK response code: 0x\(String(format: "%04X", code))")
          completion(false, accumulatedDataPackets)
        }
      } else {
        var nextPackets = accumulatedDataPackets
        nextPackets.append(packet)
        self.readUntilFujiOkResponse(connection: connection, accumulatedDataPackets: nextPackets, completion: completion)
      }
    }
  }

  private func sendFujiSingleCommand(
    connection: NWConnection,
    type: UInt16,
    payload: [UInt8] = [],
    label: String,
    completion: @escaping (Bool, [Data]) -> Void
  ) {
    let tid = nextTransId()
    let pkt = makeFujiPacket(index: 1, type: type, id: tid, payload: payload)
    let txHex = pkt.map { String(format: "%02hhX", $0) }.joined(separator: " ")
    logPtpIp("TX \(label) [id=\(tid)] (\(pkt.count) bytes): \(txHex)")
    connection.send(content: pkt, completion: .contentProcessed { [weak self] error in
      guard let self = self, error == nil else {
        self?.logPtpIp("Error sending \(label): \(String(describing: error))")
        completion(false, [])
        return
      }
      self.readUntilFujiOkResponse(connection: connection, completion: completion)
    })
  }

  private func sendFujiTwoPartCommand(
    connection: NWConnection,
    propCodePayload: [UInt8],
    valuePayload: [UInt8],
    label: String,
    completion: @escaping (Bool) -> Void
  ) {
    let tid = nextTransId()
    let pkt1 = makeFujiPacket(index: 1, type: 0x1016, id: tid, payload: propCodePayload)
    let pkt2 = makeFujiPacket(index: 2, type: 0x1016, id: tid, payload: valuePayload)
    let txHex1 = pkt1.map { String(format: "%02hhX", $0) }.joined(separator: " ")
    let txHex2 = pkt2.map { String(format: "%02hhX", $0) }.joined(separator: " ")
    logPtpIp("TX \(label) Part1 [id=\(tid)] (\(pkt1.count) bytes): \(txHex1)")
    logPtpIp("TX \(label) Part2 [id=\(tid)] (\(pkt2.count) bytes): \(txHex2)")

    connection.send(content: pkt1, completion: .contentProcessed { [weak self] err1 in
      guard let self = self, err1 == nil else {
        self?.logPtpIp("Error sending \(label) Part1: \(String(describing: err1))")
        completion(false)
        return
      }
      connection.send(content: pkt2, completion: .contentProcessed { [weak self] err2 in
        guard let self = self, err2 == nil else {
          self?.logPtpIp("Error sending \(label) Part2: \(String(describing: err2))")
          completion(false)
          return
        }
        self.readUntilFujiOkResponse(connection: connection) { (ok, _) in
          completion(ok)
        }
      })
    })
  }

  private func performPtpIpHandshake(
    connection: NWConnection,
    host: String,
    port: UInt16,
    use82ByteFujiPacket: Bool,
    finish: @escaping (Bool) -> Void
  ) {
    // For Fujifilm X-T10 on port 55740, start with 82-byte registration_message (or 40-byte fallback)
    let packet = buildInitCommandPacket(use82ByteFujiPacket: use82ByteFujiPacket)
    let txHex = packet.map { String(format: "%02hhX", $0) }.joined(separator: " ")
    logPtpIp("TX InitCommandRequest (\(packet.count) bytes): \(txHex)")

    connection.send(content: packet, completion: .contentProcessed { [weak self] error in
      guard let self = self, error == nil else {
        self?.logPtpIp("Error sending InitCommandRequest: \(String(describing: error))")
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
            self.logPtpIp("40-byte InitCommandRequest rejected by camera; auto-retrying with 82-byte (0x52) Fujifilm packet...")
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

          self.logPtpIp("Failed waiting for InitCommandAck")
          self.disconnect()
          self.sendEvent(type: "connectionStateChanged", data: "error")
          finish(false)
          return
        }

        if self.activeDriverType == "fuji_wifi" {
          // Complete full Fujifilm X-Series initialization sequence so camera exits "Waiting for connection"
          self.performFujiSessionInitialization(connection: connection, host: host) { [weak self] fujiOk in
            guard let self = self else { return }
            if !fujiOk {
              if !use82ByteFujiPacket {
                self.logPtpIp("Fuji session init failed after 40-byte InitCommandRequest; auto-retrying with 82-byte (0x52) Fujifilm registration packet...")
                self.handshakeTimeoutWorkItem?.cancel()
                self.activeConnection?.cancel()
                self.activeConnection = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                  self?.connectPtpIp(host: host, port: port, use82ByteFujiPacket: true, completion: { ok in
                    finish((ok as? Bool) ?? false)
                  })
                }
                return
              }
              self.logPtpIp("Failed Fujifilm X-T10 session initialization sequence")
              self.disconnect()
              self.sendEvent(type: "connectionStateChanged", data: "error")
              finish(false)
              return
            }
            self.logPtpIp("Fujifilm X-T10 handshake completed! Camera is now in Passive Tethering Mode.")
            self.handshakeTimeoutWorkItem?.cancel()
            self.isConnected = true
            self.sendEvent(type: "connectionStateChanged", data: "connected")
            // In Passive Tethering mode: Camera LCD remains active, app sits idle waiting for 0x4002 events
            finish(true)
          }
        } else {
          // Standard Canon PTP/IP OpenSession
          self.sendCanonOpenSession(connection: connection) { [weak self] sessionSuccess in
            guard let self = self, sessionSuccess else {
              self?.logPtpIp("Failed sending OpenSession")
              self?.disconnect()
              self?.sendEvent(type: "connectionStateChanged", data: "error")
              finish(false)
              return
            }

            self.logPtpIp("Handshake completed successfully! Connected.")
            self.handshakeTimeoutWorkItem?.cancel()
            self.isConnected = true
            self.sendEvent(type: "connectionStateChanged", data: "connected")
            self.startReceivingPackets()
            finish(true)
          }
        }
      }
    })
  }

  /**
   * Passive Tethering Session Initialization for Fujifilm X-T10:
   * 1. OpenSession (0x1002, SessionID = 1) -> expect 0x2001 OK
   * 2. After OpenSession, DO NOT send 0xDF01=5 or 0x101C (EnterCameraRemote) so camera LCD/EVF remains on
   * 3. Do NOT poll Live View frames
   * 4. Open secondary async event socket on port 55741 with PTPIP_INIT_EVENT_REQ
   * 5. Listen passively for Event 0x4002 (ObjectAdded)
   * 6. When ObjectAdded is detected, fetch photo via GetObject (0x1009) or 0x9022
   */
  private func performFujiSessionInitialization(
    connection: NWConnection,
    host: String,
    completion: @escaping (Bool) -> Void
  ) {
    // 1. OpenSession (0x1002, SessionID = 1)
    sendFujiSingleCommand(
      connection: connection,
      type: 0x1002,
      payload: [0x01, 0x00, 0x00, 0x00],
      label: "OpenSession(0x1002)"
    ) { [weak self] (ok1, _) in
      guard let self = self, ok1 else {
        self?.logPtpIp("OpenSession(0x1002) failed")
        completion(false)
        return
      }

      self.logPtpIp("OpenSession succeeded! Initializing passive event socket on port 55741...")
      // Connect secondary async event socket on port 55741
      self.connectFujiEventSocket(host: host)
      completion(true)
    }
  }

  private func connectFujiEventSocket(host: String) {
    fujiEventConnection?.cancel()
    let nwHost = NWEndpoint.Host(host)
    let nwPort = NWEndpoint.Port(integerLiteral: 55741)
    let evConn = NWConnection(host: nwHost, port: nwPort, using: .tcp)
    self.fujiEventConnection = evConn
    evConn.stateUpdateHandler = { [weak self] state in
      guard let self = self else { return }
      switch state {
      case .ready:
        self.logPtpIp("Fujifilm Async Event Socket connected to \(host):55741. Sending InitEventRequest...")
        self.sendFujiInitEventRequest(connection: evConn)
      case .failed(let err):
        self.logPtpIp("Fujifilm Event Socket failed: \(err)")
      case .cancelled:
        self.logPtpIp("Fujifilm Event Socket cancelled")
      default:
        break
      }
    }
    evConn.start(queue: .global(qos: .userInitiated))
  }

  private func sendFujiInitEventRequest(connection: NWConnection) {
    // PTPIP_INIT_EVENT_REQ: Length 12 (LE), Type 3 (LE), ConnectionNumber (4 bytes LE)
    var evPacket = Data(count: 12)
    var lenLE = UInt32(12).littleEndian
    var typeLE = UInt32(3).littleEndian // PTPIP_INIT_EVENT_REQ
    var connNumLE = self.connectionNumber.littleEndian
    evPacket.replaceSubrange(0..<4, with: Data(bytes: &lenLE, count: 4))
    evPacket.replaceSubrange(4..<8, with: Data(bytes: &typeLE, count: 4))
    evPacket.replaceSubrange(8..<12, with: Data(bytes: &connNumLE, count: 4))

    let txHex = evPacket.map { String(format: "%02hhX", $0) }.joined(separator: " ")
    logPtpIp("TX InitEventRequest (\(evPacket.count) bytes, connNum=\(self.connectionNumber)): \(txHex)")

    connection.send(content: evPacket, completion: .contentProcessed { [weak self] err in
      guard let self = self, err == nil else {
        self?.logPtpIp("Error sending InitEventRequest: \(String(describing: err))")
        return
      }
      self.logPtpIp("InitEventRequest sent. Now passively listening for PTP events on port 55741...")
      self.listenFujiEventPackets(connection: connection)
    })
  }

  private func listenFujiEventPackets(connection: NWConnection) {
    receiveFujiPacket(connection: connection) { [weak self] packet in
      guard let self = self, self.isConnected else { return }
      guard let packet = packet, packet.count >= 8 else {
        self.logPtpIp("Event socket closed or read error")
        return
      }

      let pType = UInt32(littleEndian: packet.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self) })
      if pType == 4 { // PTPIP_INIT_EVENT_ACK
        self.logPtpIp("RX InitEventAck from camera!")
      } else if pType == 8 { // PTPIP_EVENT
        // Packet layout:
        // [0..3]: Length (UInt32 LE)
        // [4..7]: Type = 8 (PTPIP_EVENT)
        // [8..9]: EventCode (UInt16 LE)
        // [10..13]: TransactionID (UInt32 LE)
        // [14..17]: Parameter 1 (UInt32 LE, e.g. ObjectHandle)
        if packet.count >= 10 {
          let eventCode = UInt16(littleEndian: packet.subdata(in: 8..<10).withUnsafeBytes { $0.load(as: UInt16.self) })
          let objHandle = packet.count >= 18 ? UInt32(littleEndian: packet.subdata(in: 14..<18).withUnsafeBytes { $0.load(as: UInt32.self) }) : 0
          self.logPtpIp(String(format: "RX PTP Event: 0x%04X, Handle: 0x%08X", eventCode, objHandle))
          if eventCode == 0x4002 || eventCode == 0xC101 { // ObjectAdded
            self.logPtpIp("PTP Event ObjectAdded detected! Fetching photo from camera...")
            self.fetchFujiPhoto(objectHandle: objHandle)
          }
        }
      }

      // Continue passive event listening
      if self.isConnected {
        self.listenFujiEventPackets(connection: connection)
      }
    }
  }

  private func fetchFujiPhoto(objectHandle: UInt32) {
    guard let conn = activeConnection, isConnected, !isBusyWithCommand else { return }
    isBusyWithCommand = true
    logPtpIp("Requesting captured photo (handle: 0x\(String(format: "%08X", objectHandle)))...")

    let onDataReceived = { [weak self] (dataPackets: [Data]) in
      guard let self = self else { return }
      self.isBusyWithCommand = false

      var fullData = Data()
      for packet in dataPackets {
        if packet.count > 12 {
          // Skip 4-byte length + 2-byte index + 2-byte type + 4-byte id
          fullData.append(packet.subdata(in: 12..<packet.count))
        }
      }

      var jpegBytes: Data? = nil
      if let jpegStart = fullData.range(of: Data([0xFF, 0xD8])) {
        jpegBytes = fullData.subdata(in: jpegStart.lowerBound..<fullData.count)
      } else if !fullData.isEmpty {
        jpegBytes = fullData
      }

      let photoId = "fuji_\(Int(Date().timeIntervalSince1970 * 1000))"
      let fileName = "DSCF_\(Int.random(in: 1000...9999)).JPG"
      var fullResPath: String? = nil
      if let jpegBytes = jpegBytes, !jpegBytes.isEmpty {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let destDir = cacheDir.appendingPathComponent("photoe_zi_tether", isDirectory: true)
        try? FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true, attributes: nil)
        let fileUrl = destDir.appendingPathComponent(fileName)
        try? jpegBytes.write(to: fileUrl)
        fullResPath = fileUrl.path
        self.logPtpIp("Saved photo to \(fullResPath ?? "cache") (\(jpegBytes.count) bytes)")
      }

      let payload: [String: Any] = [
        "id": photoId,
        "fileName": fileName,
        "previewBytes": (jpegBytes != nil && !jpegBytes!.isEmpty) ? FlutterStandardTypedData(bytes: jpegBytes!) : NSNull(),
        "fullResLocalPath": (fullResPath != nil) ? fullResPath! : NSNull(),
        "capturedAt": Int(Date().timeIntervalSince1970 * 1000),
        "exif": [
          "cameraModel": "Fujifilm X-T10 (Wi-Fi)",
          "aperture": "f/2.0",
          "shutterSpeed": "1/250s",
          "iso": 400,
          "focalLength": "35mm"
        ]
      ]
      self.sendEvent(type: "photoAdded", data: payload)
    }

    if objectHandle != 0 {
      var handleLE = objectHandle.littleEndian
      var handlePayload = [UInt8](repeating: 0, count: 4)
      withUnsafeBytes(of: &handleLE) { handlePayload = Array($0) }

      self.sendFujiSingleCommand(
        connection: conn,
        type: 0x1009, // GetObject
        payload: handlePayload,
        label: "GetObject(0x1009)"
      ) { [weak self] (ok, dataPackets) in
        guard let self = self else { return }
        if ok && !dataPackets.isEmpty {
          onDataReceived(dataPackets)
        } else {
          // Fallback to 0x9022 (CameraLastImage)
          self.logPtpIp("GetObject returned empty; falling back to 0x9022 (CameraLastImage)...")
          self.sendFujiSingleCommand(
            connection: conn,
            type: 0x9022,
            payload: [],
            label: "CameraLastImage(0x9022)"
          ) { (_, fbPackets) in
            onDataReceived(fbPackets)
          }
        }
      }
    } else {
      self.sendFujiSingleCommand(
        connection: conn,
        type: 0x9022,
        payload: [],
        label: "CameraLastImage(0x9022)"
      ) { (_, dataPackets) in
        onDataReceived(dataPackets)
      }
    }
  }

  private func startFujiLiveViewStream() {
    fujiStreamConnection?.cancel()
    let nwHost = NWEndpoint.Host(lastConnectedHost)
    let nwPort = NWEndpoint.Port(integerLiteral: 55742)
    let streamConn = NWConnection(host: nwHost, port: nwPort, using: .tcp)
    self.fujiStreamConnection = streamConn
    streamConn.stateUpdateHandler = { [weak self] state in
      guard let self = self else { return }
      if case .ready = state {
        self.logPtpIp("Fujifilm Live View Stream Socket connected to \(self.lastConnectedHost):55742")
        self.receiveNextFujiLiveViewFrame(connection: streamConn)
      }
    }
    streamConn.start(queue: .global(qos: .userInteractive))
  }

  private func stopFujiLiveViewStream() {
    fujiStreamConnection?.cancel()
    fujiStreamConnection = nil
  }

  private func receiveNextFujiLiveViewFrame(connection: NWConnection) {
    guard isConnected, isLiveViewActive else { return }
    receiveFujiPacket(connection: connection) { [weak self] packet in
      guard let self = self, self.isConnected, self.isLiveViewActive else { return }
      // Full packet has 4-byte length prefix + 14-byte Fuji stream header = 18-byte header before JPEG (FF D8)
      if let packet = packet, packet.count > 18 {
        let jpegData = packet.subdata(in: 18..<packet.count)
        self.sendEvent(type: "liveViewFrame", data: FlutterStandardTypedData(bytes: jpegData))
      }
      if packet != nil {
        self.receiveNextFujiLiveViewFrame(connection: connection)
      }
    }
  }

  private func triggerFujiCapture() {
    guard let conn = activeConnection, isConnected else { return }
    isBusyWithCommand = true
    sendFujiSingleCommand(
      connection: conn,
      type: 0x100E,
      payload: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
      label: "ShutterCapture(0x100E)"
    ) { [weak self] (ok, _) in
      guard let self = self else { return }
      if !ok {
        self.isBusyWithCommand = false
        return
      }
      // Download last captured image via 0x9022 (camera_last_image)
      self.sendFujiSingleCommand(
        connection: conn,
        type: 0x9022,
        payload: [],
        label: "CameraLastImage(0x9022)"
      ) { [weak self] (imgOk, dataPackets) in
        guard let self = self else { return }
        self.isBusyWithCommand = false
        var jpegBytes: Data? = nil
        if let firstData = dataPackets.first, firstData.count > 12 {
          // 4-byte length + 8-byte container header = 12 bytes before JPEG payload
          jpegBytes = firstData.subdata(in: 12..<firstData.count)
        }
        let photoId = "fuji_\(Int(Date().timeIntervalSince1970 * 1000))"
        let fileName = "DSCF_\(Int.random(in: 1000...9999)).JPG"
        var fullResPath: String? = nil
        if let jpegBytes = jpegBytes {
          let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
          let destDir = cacheDir.appendingPathComponent("photoe_zi_tether", isDirectory: true)
          try? FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true, attributes: nil)
          let fileUrl = destDir.appendingPathComponent(fileName)
          try? jpegBytes.write(to: fileUrl)
          fullResPath = fileUrl.path
        }

        let payload: [String: Any] = [
          "id": photoId,
          "fileName": fileName,
          "previewBytes": (jpegBytes != nil) ? FlutterStandardTypedData(bytes: jpegBytes!) : NSNull(),
          "fullResLocalPath": (fullResPath != nil) ? fullResPath! : NSNull(),
          "capturedAt": Int(Date().timeIntervalSince1970 * 1000),
          "exif": [
            "cameraModel": "Fujifilm X-T10 (Wi-Fi)",
            "aperture": "f/2.0",
            "shutterSpeed": "1/250s",
            "iso": 400,
            "focalLength": "35mm"
          ]
        ]
        self.sendEvent(type: "photoAdded", data: payload)

        if self.wasInLiveView {
          self.wasInLiveView = false
          DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self = self else { return }
            self.isLiveViewActive = true
            self.isLiveViewReconnecting = false
            self.sendEvent(type: "liveViewStatus", data: ["status": "active", "wasInLiveView": false])
            self.startFujiLiveViewStream()
          }
        }
      }
    }
  }

  private func waitForInitCommandAck(connection: NWConnection, completion: @escaping (Bool) -> Void) {
    receiveFujiPacket(connection: connection) { [weak self] data in
      guard let self = self, let data = data, data.count >= 8 else {
        self?.logPtpIp("Error or EOF waiting for InitCommandAck")
        completion(false)
        return
      }
      let rxHex = data.map { String(format: "%02hhX", $0) }.joined(separator: " ")
      self.logPtpIp("RX InitCommand response (\(data.count) bytes): \(rxHex)")

      let ackType = UInt32(littleEndian: data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self) })
      if ackType == 2 { // PTPIP_INIT_COMMAND_ACK = 0x00000002
        if data.count >= 12 {
          self.connectionNumber = UInt32(littleEndian: data.subdata(in: 8..<12).withUnsafeBytes { $0.load(as: UInt32.self) })
          self.logPtpIp("Extracted PTP/IP connectionNumber: \(self.connectionNumber)")
        }
        completion(true)
      } else {
        self.logPtpIp("Unexpected Ack packet type: \(ackType)")
        completion(false)
      }
    }
  }

  private func sendCanonOpenSession(connection: NWConnection, completion: @escaping (Bool) -> Void) {
    var openSessionPacket = Data()
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

    let txSessionHex = openSessionPacket.map { String(format: "%02hhX", $0) }.joined(separator: " ")
    logPtpIp("TX OpenSession (\(openSessionPacket.count) bytes): \(txSessionHex)")

    connection.send(content: openSessionPacket, completion: .contentProcessed { [weak self] error in
      if let error = error {
        self?.logPtpIp("Error sending OpenSession: \(error)")
        completion(false)
      } else {
        completion(true)
      }
    })
  }

  private func startReceivingPackets() {
    guard let conn = activeConnection, isConnected else { return }
    conn.receive(minimumIncompleteLength: 8, maximumLength: 65536) { [weak self] (data, context, isComplete, error) in
      guard let self = self else { return }
      guard error == nil, let data = data, data.count >= 8 else {
        if let error = error {
          self.logPtpIp("Stream receive error: \(error)")
        }
        if isComplete || error != nil {
          self.logPtpIp("Remote socket closed stream; disconnecting.")
          self.disconnect()
        }
        return
      }
      let rxHex = data.map { String(format: "%02hhX", $0) }.joined(separator: " ")
      self.logPtpIp("RX Stream Packet (\(data.count) bytes): \(rxHex)")
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

  // MARK: - Canon EOS Wi-Fi Passive Tethering
  private func connectCanonWifi(host: String, port: UInt16, completion: @escaping FlutterResult) {
    disconnect()
    self.lastConnectedHost = host
    sendEvent(type: "connectionStateChanged", data: "connecting")
    logPtpIp("[CanonEOS] Connecting to \(host):\(port) (Passive Tethering mode)...")

    let session = CanonEosWifiSession(
      log: { [weak self] msg in
        self?.logPtpIp("[CanonEOS] \(msg)")
      },
      state: { [weak self] stateStr in
        guard let self = self else { return }
        self.isConnected = (stateStr == "connected")
        self.sendEvent(type: "connectionStateChanged", data: stateStr)
      },
      photo: { [weak self] photoId, fileName, previewData, fullResPath, exif in
        guard let self = self else { return }
        let payload: [String: Any] = [
          "id": photoId,
          "fileName": fileName,
          "previewBytes": previewData != nil ? FlutterStandardTypedData(bytes: previewData!) : NSNull(),
          "fullResLocalPath": fullResPath ?? NSNull(),
          "capturedAt": Int(Date().timeIntervalSince1970 * 1000),
          "exif": exif
        ]
        self.sendEvent(type: "photoAdded", data: payload)
      }
    )
    self.canonWifiSession = session
    session.connect(host: host, port: port) { success in
      completion(success)
    }
  }

  func disconnect() {
    canonWifiSession?.disconnect()
    canonWifiSession = nil
    handshakeTimeoutWorkItem?.cancel()
    handshakeTimeoutWorkItem = nil
    fujiKeepAliveTimer?.cancel()
    fujiKeepAliveTimer = nil
    isConnected = false
    isBusyWithCommand = false
    fujiStreamConnection?.cancel()
    fujiStreamConnection = nil
    fujiEventConnection?.cancel()
    fujiEventConnection = nil
    activeConnection?.cancel()
    activeConnection = nil
    if let camera = connectedCameraDevice {
      camera.requestCloseSession()
    }
    sendEvent(type: "connectionStateChanged", data: "disconnected")
  }
}
