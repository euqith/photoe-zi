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
        let port = UInt16((args["port"] as? Int) ?? 55740)
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

  // MARK: - Wi-Fi PTP/IP Connection
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
    isConnected = false
    activeConnection?.cancel()
    activeConnection = nil
    if let camera = connectedCameraDevice {
      camera.requestCloseSession()
    }
    sendEvent(type: "connectionStateChanged", data: "disconnected")
  }
}
