import Foundation
import ImageIO
import Network

/**
 * Canon EOS Wi-Fi Passive Tethering (PTP/IP, port 15740).
 *
 * Designed for Canon EOS 6D in "Remote control (EOS Utility)" Wi-Fi mode:
 * the photographer keeps shooting normally with the camera body (optical viewfinder,
 * physical shutter) while every new image is pulled to the app automatically.
 *
 * Flow:
 *  1. TCP command channel -> InitCommandRequest (GUID + name + version 1.0)
 *     -> InitCommandAck (first time: user confirms pairing on the camera LCD)
 *  2. TCP event channel -> InitEventRequest(connectionNumber) -> InitEventAck
 *  3. OpenSession(0x1002) -> GetDeviceInfo(0x1001)
 *  4. Canon EOS: SetRemoteMode(0x9114, 1) + SetEventMode(0x9115, 1)
 *  5. Poll Canon GetEvent(0x9116) every ~300 ms. Canon EOS does NOT push the
 *     standard ObjectAdded (0x4002) event; new files appear as
 *     ObjectAddedEx (0xC181) / RequestObjectTransfer (0xC186) records.
 *  6. For each new object: GetObjectInfo(0x1008) -> [GetThumb(0x100A) for RAW]
 *     -> GetObject(0x1009) -> [TransferComplete(0x9117) when requested].
 *
 * All protocol I/O runs sequentially on a dedicated worker queue using
 * synchronous wrappers around NWConnection, which keeps the protocol code linear.
 */

// MARK: - Errors

enum PtpIpError: Error, CustomStringConvertible {
  case timeout(String)
  case closed(String)
  case protocolError(String)
  case initFail(UInt32)
  case cancelled

  var description: String {
    switch self {
    case .timeout(let msg): return "Timeout: \(msg)"
    case .closed(let msg): return "Connection closed: \(msg)"
    case .protocolError(let msg): return "Protocol error: \(msg)"
    case .initFail(let reason):
      return "Camera rejected the connection (InitFail reason \(PtpLE.h32(reason))). "
        + "Make sure the camera is in Wi-Fi 'Remote control (EOS Utility)' mode and pairing was accepted."
    case .cancelled: return "Cancelled"
    }
  }
}

// MARK: - Little-endian helpers

enum PtpLE {
  static func u16(_ b: [UInt8], _ o: Int) -> UInt16 {
    guard o >= 0, o + 2 <= b.count else { return 0 }
    let lo = UInt16(b[o])
    let hi = UInt16(b[o + 1]) << 8
    return lo | hi
  }

  static func u32(_ b: [UInt8], _ o: Int) -> UInt32 {
    guard o >= 0, o + 4 <= b.count else { return 0 }
    let b0 = UInt32(b[o])
    let b1 = UInt32(b[o + 1]) << 8
    let b2 = UInt32(b[o + 2]) << 16
    let b3 = UInt32(b[o + 3]) << 24
    return b0 | b1 | b2 | b3
  }

  static func u64(_ b: [UInt8], _ o: Int) -> UInt64 {
    let lo = UInt64(u32(b, o))
    let hi = UInt64(u32(b, o + 4)) << 32
    return lo | hi
  }

  static func put16(_ d: inout Data, _ v: UInt16) {
    d.append(UInt8(truncatingIfNeeded: v))
    d.append(UInt8(truncatingIfNeeded: v >> 8))
  }

  static func put32(_ d: inout Data, _ v: UInt32) {
    d.append(UInt8(truncatingIfNeeded: v))
    d.append(UInt8(truncatingIfNeeded: v >> 8))
    d.append(UInt8(truncatingIfNeeded: v >> 16))
    d.append(UInt8(truncatingIfNeeded: v >> 24))
  }

  static func h16(_ v: UInt16) -> String { String(format: "0x%04X", UInt32(v)) }
  static func h32(_ v: UInt32) -> String { String(format: "0x%08X", v) }

  static func hex(_ d: Data, limit: Int = 64) -> String {
    let shown = d.prefix(limit).map { String(format: "%02X", $0) }.joined(separator: " ")
    return d.count > limit ? "\(shown) …(+\(d.count - limit) bytes)" : shown
  }

  /// Null-terminated UTF-16LE string (as used in PTP/IP Init packets).
  static func utf16z(_ b: [UInt8], from start: Int) -> String {
    var units: [UInt16] = []
    var o = start
    while o + 1 < b.count {
      let u = u16(b, o)
      if u == 0 { break }
      units.append(u)
      o += 2
    }
    return String(decoding: units, as: UTF16.self)
  }
}

/// Sequential reader for PTP datasets (DeviceInfo, ObjectInfo).
struct PtpReader {
  let b: [UInt8]
  var o: Int = 0

  init(_ bytes: [UInt8]) { b = bytes }

  mutating func u16() -> UInt16 {
    let v = PtpLE.u16(b, o)
    o += 2
    return v
  }

  mutating func u32() -> UInt32 {
    let v = PtpLE.u32(b, o)
    o += 4
    return v
  }

  mutating func array16() -> [UInt16] {
    let n = Int(u32())
    guard n > 0, n < 4096 else { return [] }
    var out: [UInt16] = []
    out.reserveCapacity(n)
    for _ in 0..<n { out.append(u16()) }
    return out
  }

  /// PTP string: UInt8 char count (incl. terminator) + UTF-16LE chars.
  mutating func string() -> String {
    guard o < b.count else { return "" }
    let n = Int(b[o])
    o += 1
    guard n > 0 else { return "" }
    var units: [UInt16] = []
    for i in 0..<n {
      let u = PtpLE.u16(b, o + i * 2)
      if u == 0 { break }
      units.append(u)
    }
    o += n * 2
    return String(decoding: units, as: UTF16.self)
  }
}

// MARK: - Synchronous socket wrapper

private final class OnceBox {
  private let lock = NSLock()
  private var done = false
  private(set) var error: Error?

  @discardableResult
  func set(_ e: Error?) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    if done { return false }
    done = true
    error = e
    return true
  }
}

private final class ReceiveBox {
  var data: Data?
  var isComplete = false
  var error: NWError?
}

struct PtpIpPacket {
  let type: UInt32
  let body: Data
}

final class PtpIpSyncSocket {
  private let connection: NWConnection
  private let queue: DispatchQueue
  let label: String

  init(host: String, port: UInt16, label: String) {
    let params = NWParameters.tcp
    if let tcp = params.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
      tcp.noDelay = true
      tcp.enableKeepalive = true
      tcp.keepaliveIdle = 10
    }
    let nwPort = NWEndpoint.Port(rawValue: port) ?? NWEndpoint.Port(integerLiteral: 15740)
    connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: params)
    queue = DispatchQueue(label: "com.photoezi.ptpip.\(label)")
    self.label = label
  }

  func open(timeout: TimeInterval) throws {
    let sem = DispatchSemaphore(value: 0)
    let box = OnceBox()
    connection.stateUpdateHandler = { state in
      switch state {
      case .ready:
        if box.set(nil) { sem.signal() }
      case .failed(let err), .waiting(let err):
        if box.set(err) { sem.signal() }
      case .cancelled:
        if box.set(PtpIpError.closed("cancelled")) { sem.signal() }
      default:
        break
      }
    }
    connection.start(queue: queue)
    if sem.wait(timeout: .now() + timeout) == .timedOut {
      close()
      throw PtpIpError.timeout("\(label): TCP connect")
    }
    if let err = box.error {
      close()
      throw PtpIpError.closed("\(label): \(err)")
    }
  }

  func send(_ data: Data, timeout: TimeInterval = 10) throws {
    let sem = DispatchSemaphore(value: 0)
    let box = OnceBox()
    connection.send(content: data, completion: .contentProcessed { err in
      box.set(err)
      sem.signal()
    })
    if sem.wait(timeout: .now() + timeout) == .timedOut {
      close()
      throw PtpIpError.timeout("\(label): send")
    }
    if let err = box.error {
      throw PtpIpError.closed("\(label): send failed \(err)")
    }
  }

  /// Reads exactly `count` bytes. `timeout == nil` waits indefinitely.
  func readExact(_ count: Int, timeout: TimeInterval?) throws -> Data {
    var buffer = Data()
    if count <= 0 { return buffer }
    buffer.reserveCapacity(count)
    let deadline = timeout.map { Date().addingTimeInterval($0) }

    while buffer.count < count {
      let want = min(count - buffer.count, 1 << 20)
      let sem = DispatchSemaphore(value: 0)
      let box = ReceiveBox()
      connection.receive(minimumIncompleteLength: 1, maximumLength: want) { data, _, isComplete, error in
        box.data = data
        box.isComplete = isComplete
        box.error = error
        sem.signal()
      }
      if let deadline = deadline {
        let remaining = deadline.timeIntervalSinceNow
        if remaining <= 0 || sem.wait(timeout: .now() + remaining) == .timedOut {
          close()
          throw PtpIpError.timeout("\(label): waiting for \(count) bytes (got \(buffer.count))")
        }
      } else {
        sem.wait()
      }
      if let err = box.error {
        throw PtpIpError.closed("\(label): \(err)")
      }
      if let chunk = box.data, !chunk.isEmpty {
        buffer.append(chunk)
      } else if box.isComplete {
        throw PtpIpError.closed("\(label): remote closed the connection")
      }
    }
    return buffer
  }

  func readPacket(timeout: TimeInterval?) throws -> PtpIpPacket {
    let header = [UInt8](try readExact(8, timeout: timeout))
    let length = Int(PtpLE.u32(header, 0))
    let type = PtpLE.u32(header, 4)
    guard length >= 8, length <= 256 * 1024 * 1024 else {
      throw PtpIpError.protocolError("\(label): invalid packet length \(length)")
    }
    let body = length > 8 ? try readExact(length - 8, timeout: timeout) : Data()
    return PtpIpPacket(type: type, body: body)
  }

  func close() {
    connection.cancel()
  }
}

// MARK: - Canon EOS Wi-Fi Session

final class CanonEosWifiSession {
  typealias LogHandler = (String) -> Void
  typealias StateHandler = (String) -> Void
  typealias PhotoHandler = (
    _ id: String, _ fileName: String, _ preview: Data?, _ fullResPath: String?, _ exif: [String: Any]
  ) -> Void

  private enum Op {
    static let getDeviceInfo: UInt16 = 0x1001
    static let openSession: UInt16 = 0x1002
    static let closeSession: UInt16 = 0x1003
    static let getObjectInfo: UInt16 = 0x1008
    static let getObject: UInt16 = 0x1009
    static let getThumb: UInt16 = 0x100A
    static let eosSetRemoteMode: UInt16 = 0x9114
    static let eosSetEventMode: UInt16 = 0x9115
    static let eosGetEvent: UInt16 = 0x9116
    static let eosTransferComplete: UInt16 = 0x9117
    static let eosKeepDeviceOn: UInt16 = 0x911D
  }

  private enum Rc {
    static let ok: UInt16 = 0x2001
    static let deviceBusy: UInt16 = 0x2019
    static let sessionAlreadyOpen: UInt16 = 0x201E
  }

  private enum PType {
    static let initCommandRequest: UInt32 = 1
    static let initCommandAck: UInt32 = 2
    static let initEventRequest: UInt32 = 3
    static let initEventAck: UInt32 = 4
    static let initFail: UInt32 = 5
    static let operationRequest: UInt32 = 6
    static let operationResponse: UInt32 = 7
    static let event: UInt32 = 8
    static let startData: UInt32 = 9
    static let data: UInt32 = 10
    static let endData: UInt32 = 12
    static let probeRequest: UInt32 = 13
    static let probeResponse: UInt32 = 14
  }

  private enum EosEvent {
    static let objectAddedEx: UInt32 = 0xC181
    static let requestObjectTransfer: UInt32 = 0xC186
    static let propValueChanged: UInt32 = 0xC189
    static let availListChanged: UInt32 = 0xC18A
  }

  private struct PtpResponse {
    let code: UInt16
    let params: [UInt32]
    let data: Data
  }

  private struct EosObject {
    let handle: UInt32
    var storageId: UInt32
    var format: UInt16
    var size: UInt32
    var name: String?
    var requestedTransfer: Bool
  }

  static let clientName = "PhotoE-Zi"

  private let onLog: LogHandler
  private let onState: StateHandler
  private let onPhoto: PhotoHandler

  private let worker = DispatchQueue(label: "com.photoezi.canon.eos.worker", qos: .userInitiated)
  private let flagLock = NSLock()
  private let socketLock = NSLock()
  private var running = false
  private var cmd: PtpIpSyncSocket?
  private var evt: PtpIpSyncSocket?

  private var transactionId: UInt32 = 0
  private var connectionNumber: UInt32 = 0
  private var cameraModel = "Canon EOS (Wi-Fi)"
  private var seenHandles = Set<UInt32>()
  private var loggedEventTypes = Set<UInt32>()

  init(log: @escaping LogHandler, state: @escaping StateHandler, photo: @escaping PhotoHandler) {
    onLog = log
    onState = state
    onPhoto = photo
  }

  private var isRunning: Bool {
    flagLock.lock()
    defer { flagLock.unlock() }
    return running
  }

  private func setRunning(_ value: Bool) {
    flagLock.lock()
    running = value
    flagLock.unlock()
  }

  private func log(_ msg: String) { onLog(msg) }

  // MARK: Public API

  func connect(host: String, port: UInt16, completion: @escaping (Bool) -> Void) {
    setRunning(true)
    worker.async { [weak self] in
      guard let self = self else { return }
      var connected = false
      do {
        try self.establish(preferredHost: host, port: port)
        connected = true
        self.onState("connected")
        DispatchQueue.main.async { completion(true) }
        try self.runEventLoop()
      } catch {
        let intentional = !self.isRunning
        self.log(intentional ? "Session stopped." : "Session error: \(error)")
        self.closeSockets()
        if !connected {
          if !intentional { self.onState("error") }
          DispatchQueue.main.async { completion(false) }
        } else if !intentional {
          self.onState("disconnected")
        }
      }
      self.setRunning(false)
    }
  }

  func disconnect() {
    let wasRunning = isRunning
    setRunning(false)
    guard wasRunning else {
      closeSockets()
      return
    }
    // The worker performs a graceful CloseSession on its next loop iteration.
    // Force-close if it is blocked (e.g. waiting for pairing or a long download).
    DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) { [weak self] in
      self?.closeSockets()
    }
  }

  // MARK: Connection setup

  private func establish(preferredHost: String, port: UInt16) throws {
    let candidates = Self.candidateHosts(preferred: preferredHost)
    log("Candidate camera addresses: \(candidates.joined(separator: ", "))")

    var lastError: Error = PtpIpError.protocolError("no candidate hosts")
    var opened: PtpIpSyncSocket?
    var host = preferredHost
    for candidate in candidates {
      guard isRunning else { throw PtpIpError.cancelled }
      let socket = PtpIpSyncSocket(host: candidate, port: port, label: "cmd")
      do {
        try socket.open(timeout: candidate == preferredHost ? 5 : 3)
        opened = socket
        host = candidate
        break
      } catch {
        lastError = error
        log("TCP \(candidate):\(port) unreachable: \(error)")
        socket.close()
      }
    }
    guard let command = opened else { throw lastError }
    setSockets(cmd: command, evt: nil)
    log("TCP command channel connected to \(host):\(port)")

    // 1. InitCommandRequest -> InitCommandAck
    let initRequest = Self.buildInitCommandRequest()
    log("TX InitCommandRequest (\(initRequest.count) bytes): \(PtpLE.hex(initRequest, limit: 96))")
    try command.send(initRequest)
    log("Waiting for InitCommandAck… On first connection, confirm the pairing prompt on the camera LCD (press OK).")

    let ack = try command.readPacket(timeout: 90)
    let ackBytes = [UInt8](ack.body)
    switch ack.type {
    case PType.initCommandAck:
      connectionNumber = PtpLE.u32(ackBytes, 0)
      let cameraName = PtpLE.utf16z(ackBytes, from: 20)
      log("RX InitCommandAck: connectionNumber=\(connectionNumber), camera='\(cameraName)'")
    case PType.initFail:
      throw PtpIpError.initFail(PtpLE.u32(ackBytes, 0))
    default:
      throw PtpIpError.protocolError("expected InitCommandAck, got packet type \(ack.type)")
    }

    // 2. Event channel: InitEventRequest -> InitEventAck
    let event = PtpIpSyncSocket(host: host, port: port, label: "evt")
    try event.open(timeout: 5)
    setSockets(cmd: command, evt: event)
    var eventRequest = Data()
    PtpLE.put32(&eventRequest, 12)
    PtpLE.put32(&eventRequest, PType.initEventRequest)
    PtpLE.put32(&eventRequest, connectionNumber)
    log("TX InitEventRequest: \(PtpLE.hex(eventRequest))")
    try event.send(eventRequest)

    let eventAck = try event.readPacket(timeout: 15)
    if eventAck.type == PType.initFail {
      throw PtpIpError.initFail(PtpLE.u32([UInt8](eventAck.body), 0))
    }
    guard eventAck.type == PType.initEventAck else {
      throw PtpIpError.protocolError("expected InitEventAck, got packet type \(eventAck.type)")
    }
    log("RX InitEventAck – event channel ready")
    startEventChannelReader(event)

    // 3. OpenSession (TransactionID 0 for OpenSession per PTP spec)
    transactionId = 0
    let open = try transaction(Op.openSession, [1], timeout: 90, label: "OpenSession")
    guard open.code == Rc.ok || open.code == Rc.sessionAlreadyOpen else {
      throw PtpIpError.protocolError("OpenSession failed with \(PtpLE.h16(open.code))")
    }

    // GetDeviceInfo (best effort: model name + capability check)
    if let info = try? transaction(Op.getDeviceInfo, label: "GetDeviceInfo"), info.code == Rc.ok {
      parseDeviceInfo(info.data)
    }

    // 4. Canon EOS remote + event mode (does NOT lock the camera body for DSLR passive tethering)
    let remote = try transaction(Op.eosSetRemoteMode, [1], label: "EOS SetRemoteMode(1)")
    if remote.code != Rc.ok {
      log("Warning: SetRemoteMode returned \(PtpLE.h16(remote.code))")
    }
    let eventMode = try transaction(Op.eosSetEventMode, [1], label: "EOS SetEventMode(1)")
    if eventMode.code != Rc.ok {
      log("Warning: SetEventMode returned \(PtpLE.h16(eventMode.code))")
    }

    // Initial GetEvent dump contains the full property state; ignore any pre-existing objects.
    let first = try transaction(Op.eosGetEvent, timeout: 30, label: "EOS GetEvent(initial)", quiet: true)
    let existing = parseEvents(first.data)
    for obj in existing { seenHandles.insert(obj.handle) }
    log("Initial event dump: \(first.data.count) bytes, \(existing.count) pre-existing object(s) ignored")
  }

  private func parseDeviceInfo(_ data: Data) {
    var r = PtpReader([UInt8](data))
    _ = r.u16()      // StandardVersion
    _ = r.u32()      // VendorExtensionID
    _ = r.u16()      // VendorExtensionVersion
    _ = r.string()   // VendorExtensionDesc
    _ = r.u16()      // FunctionalMode
    let ops = r.array16()
    _ = r.array16()  // EventsSupported
    _ = r.array16()  // DevicePropertiesSupported
    _ = r.array16()  // CaptureFormats
    _ = r.array16()  // ImageFormats
    let manufacturer = r.string()
    let model = r.string()
    if !model.isEmpty {
      cameraModel = model.hasPrefix(manufacturer) || manufacturer.isEmpty ? model : "\(manufacturer) \(model)"
    }
    log("Camera: \(cameraModel), \(ops.count) operations supported")
    if !ops.isEmpty && !ops.contains(Op.eosGetEvent) {
      log("Warning: camera does not advertise EOS GetEvent (0x9116); passive tethering may not work.")
    }
  }

  private func startEventChannelReader(_ socket: PtpIpSyncSocket) {
    let thread = Thread { [weak self] in
      while true {
        guard let strong = self, strong.isRunning else { break }
        do {
          let packet = try socket.readPacket(timeout: nil)
          if packet.type == PType.probeRequest {
            try? socket.send(Self.probeResponse())
          } else if packet.type == PType.event {
            let code = PtpLE.u16([UInt8](packet.body.prefix(2)), 0)
            strong.log("RX async event \(PtpLE.h16(code))")
          }
        } catch {
          break
        }
      }
    }
    thread.name = "CanonEOS-EventChannel"
    thread.start()
  }

  // MARK: Passive event loop

  private func runEventLoop() throws {
    log("Passive tethering active. Shoot normally with the camera – new photos transfer automatically.")
    var lastKeepAlive = Date()

    while isRunning {
      let r = try transaction(Op.eosGetEvent, timeout: 30, label: "EOS GetEvent", quiet: true)
      var newObjects: [EosObject] = []
      if r.code == Rc.ok {
        newObjects = parseEvents(r.data).filter { !seenHandles.contains($0.handle) }
      } else if r.code != Rc.deviceBusy {
        log("GetEvent returned \(PtpLE.h16(r.code))")
      }

      for obj in newObjects {
        guard isRunning else { break }
        seenHandles.insert(obj.handle)
        try download(obj)
      }

      if Date().timeIntervalSince(lastKeepAlive) > 30 {
        lastKeepAlive = Date()
        _ = try transaction(Op.eosKeepDeviceOn, label: "EOS KeepDeviceOn", quiet: true)
      }

      if newObjects.isEmpty {
        Thread.sleep(forTimeInterval: r.code == Rc.deviceBusy ? 0.15 : 0.3)
      }
    }

    _ = try? transaction(Op.closeSession, timeout: 2, label: "CloseSession")
    closeSockets()
  }

  private func parseEvents(_ data: Data) -> [EosObject] {
    let b = [UInt8](data)
    var order: [UInt32] = []
    var objects: [UInt32: EosObject] = [:]
    var off = 0

    while off + 8 <= b.count {
      let size = Int(PtpLE.u32(b, off))
      let type = PtpLE.u32(b, off + 4)
      if size < 8 || off + size > b.count || type == 0 { break }

      switch type {
      case EosEvent.objectAddedEx:
        let handle = PtpLE.u32(b, off + 8)
        var obj = EosObject(
          handle: handle,
          storageId: PtpLE.u32(b, off + 0x0C),
          format: PtpLE.u16(b, off + 0x10),
          size: PtpLE.u32(b, off + 0x1C),
          name: size > 0x28 ? Self.asciiString(b, from: off + 0x28, end: off + size) : nil,
          requestedTransfer: false
        )
        if let previous = objects[handle] {
          obj.requestedTransfer = previous.requestedTransfer
        } else {
          order.append(handle)
        }
        objects[handle] = obj
        log("EOS event ObjectAddedEx: handle=\(PtpLE.h32(handle)) name=\(obj.name ?? "?")")

      case EosEvent.requestObjectTransfer:
        let handle = PtpLE.u32(b, off + 8)
        if var previous = objects[handle] {
          previous.requestedTransfer = true
          objects[handle] = previous
        } else {
          order.append(handle)
          objects[handle] = EosObject(
            handle: handle, storageId: 0, format: 0, size: 0, name: nil, requestedTransfer: true)
        }
        log("EOS event RequestObjectTransfer: handle=\(PtpLE.h32(handle))")

      case EosEvent.propValueChanged, EosEvent.availListChanged:
        break

      default:
        if !loggedEventTypes.contains(type) {
          loggedEventTypes.insert(type)
          log("EOS event type \(PtpLE.h32(type)) (\(size) bytes) – ignored")
        }
      }
      off += size
    }
    return order.compactMap { objects[$0] }
  }

  // MARK: Object download

  private func download(_ event: EosObject) throws {
    var obj = event

    // ObjectInfo is the reliable source for filename / format / size.
    let info = try transaction(Op.getObjectInfo, [obj.handle], label: "GetObjectInfo")
    if info.code == Rc.ok, info.data.count > 52 {
      var r = PtpReader([UInt8](info.data))
      obj.storageId = r.u32()
      obj.format = r.u16()
      _ = r.u16()
      obj.size = r.u32()
      r.o = 52
      let name = r.string()
      if !name.isEmpty { obj.name = name }
    }

    let fileName = obj.name ?? String(format: "IMG_%08X.JPG", obj.handle)
    let ext = (fileName as NSString).pathExtension.uppercased()
    if obj.format == 0x3001 || ["MOV", "MP4", "AVI"].contains(ext) {
      log("Skipping non-photo object \(fileName)")
      return
    }
    let isJpeg = ext == "JPG" || ext == "JPEG" || obj.format == 0x3801
    let photoId = "canon_wifi_\(obj.handle)_\(Int(Date().timeIntervalSince1970))"
    log("New photo: \(fileName) (\(obj.size) bytes, format \(PtpLE.h16(obj.format)))")

    var preview: Data?
    if !isJpeg {
      // Stage 1 for RAW: quick embedded thumbnail while the large file transfers.
      let thumb = try transaction(Op.getThumb, [obj.handle], label: "GetThumb")
      if thumb.code == Rc.ok, !thumb.data.isEmpty {
        preview = thumb.data
        onPhoto(photoId, fileName, thumb.data, nil, Self.exif(from: thumb.data, fallbackModel: cameraModel))
      }
    }

    let started = Date()
    let full = try transaction(Op.getObject, [obj.handle], timeout: 60, label: "GetObject")
    guard full.code == Rc.ok, !full.data.isEmpty else {
      log("GetObject failed for \(fileName): \(PtpLE.h16(full.code))")
      return
    }
    let seconds = max(Date().timeIntervalSince(started), 0.001)
    let megabytes = Double(full.data.count) / 1_048_576.0
    log(String(format: "Downloaded \(fileName): %.1f MB in %.1fs (%.2f MB/s)", megabytes, seconds, megabytes / seconds))

    let path = Self.saveToCache(full.data, fileName: fileName, handle: obj.handle)
    if isJpeg {
      preview = full.data
    } else if let rendered = Self.makePreviewJpeg(from: full.data) {
      preview = rendered
    }

    if obj.requestedTransfer {
      _ = try transaction(Op.eosTransferComplete, [obj.handle], label: "EOS TransferComplete")
    }

    onPhoto(photoId, fileName, preview, path, Self.exif(from: full.data, fallbackModel: cameraModel))
  }

  // MARK: Transactions

  @discardableResult
  private func transaction(
    _ op: UInt16,
    _ params: [UInt32] = [],
    timeout: TimeInterval = 20,
    label: String,
    quiet: Bool = false
  ) throws -> PtpResponse {
    guard let socket = currentCommandSocket() else {
      throw PtpIpError.closed("command channel not open")
    }
    let tid = transactionId
    transactionId &+= 1

    var packet = Data()
    PtpLE.put32(&packet, UInt32(18 + 4 * params.count))
    PtpLE.put32(&packet, PType.operationRequest)
    PtpLE.put32(&packet, 1) // DataPhaseInfo: no data-out phase
    PtpLE.put16(&packet, op)
    PtpLE.put32(&packet, tid)
    for p in params { PtpLE.put32(&packet, p) }
    if !quiet {
      log("TX \(label) op=\(PtpLE.h16(op)) tid=\(tid): \(PtpLE.hex(packet))")
    }
    try socket.send(packet)

    var data = Data()
    while true {
      let p = try socket.readPacket(timeout: timeout)
      switch p.type {
      case PType.startData:
        let total = PtpLE.u64([UInt8](p.body.prefix(12)), 4)
        if total > 0 && total < 512 * 1024 * 1024 {
          data.reserveCapacity(Int(total))
        }
      case PType.data, PType.endData:
        if p.body.count > 4 {
          data.append(p.body.subdata(in: 4..<p.body.count))
        }
      case PType.operationResponse:
        let b = [UInt8](p.body)
        let code = PtpLE.u16(b, 0)
        var responseParams: [UInt32] = []
        var o = 6
        while o + 4 <= b.count {
          responseParams.append(PtpLE.u32(b, o))
          o += 4
        }
        if !quiet || (code != Rc.ok && code != Rc.deviceBusy) {
          log("RX \(label) response \(PtpLE.h16(code)) (data \(data.count) bytes)")
        }
        return PtpResponse(code: code, params: responseParams, data: data)
      case PType.probeRequest:
        try socket.send(Self.probeResponse())
      case PType.event:
        log("RX event on command channel: \(PtpLE.hex(p.body, limit: 16))")
      default:
        log("RX unexpected packet type \(p.type) during \(label)")
      }
    }
  }

  // MARK: Socket bookkeeping

  private func setSockets(cmd newCmd: PtpIpSyncSocket?, evt newEvt: PtpIpSyncSocket?) {
    socketLock.lock()
    cmd = newCmd
    evt = newEvt
    socketLock.unlock()
  }

  private func currentCommandSocket() -> PtpIpSyncSocket? {
    socketLock.lock()
    defer { socketLock.unlock() }
    return cmd
  }

  private func closeSockets() {
    socketLock.lock()
    let c = cmd
    let e = evt
    cmd = nil
    evt = nil
    socketLock.unlock()
    c?.close()
    e?.close()
  }

  // MARK: Static helpers

  private static func clientGuid() -> [UInt8] {
    let key = "com.photoezi.ptpip.clientGuid"
    if let stored = UserDefaults.standard.data(forKey: key), stored.count == 16 {
      return [UInt8](stored)
    }
    var guid = [UInt8](repeating: 0, count: 16)
    for i in 0..<16 { guid[i] = UInt8.random(in: 0...255) }
    UserDefaults.standard.set(Data(guid), forKey: key)
    return guid
  }

  private static func buildInitCommandRequest() -> Data {
    var name = Data()
    for unit in clientName.utf16 { PtpLE.put16(&name, unit) }
    PtpLE.put16(&name, 0)

    var packet = Data()
    PtpLE.put32(&packet, UInt32(8 + 16 + name.count + 4))
    PtpLE.put32(&packet, PType.initCommandRequest)
    packet.append(contentsOf: clientGuid())
    packet.append(name)
    PtpLE.put32(&packet, 0x0001_0000) // PTP/IP protocol version 1.0
    return packet
  }

  private static func probeResponse() -> Data {
    var packet = Data()
    PtpLE.put32(&packet, 8)
    PtpLE.put32(&packet, PType.probeResponse)
    return packet
  }

  private static func asciiString(_ b: [UInt8], from start: Int, end: Int) -> String? {
    guard start < end, end <= b.count else { return nil }
    var chars: [UInt8] = []
    for i in start..<end {
      let c = b[i]
      if c == 0 { break }
      guard c >= 0x20 && c < 0x7F else { return nil }
      chars.append(c)
    }
    return chars.isEmpty ? nil : String(decoding: chars, as: UTF8.self)
  }

  /// Camera AP / LAN address candidates: user-provided first, then x.y.z.1 / x.y.z.2 of local Wi-Fi subnets.
  static func candidateHosts(preferred: String) -> [String] {
    var list: [String] = []
    func add(_ host: String) {
      let trimmed = host.trimmingCharacters(in: .whitespaces)
      if !trimmed.isEmpty && !list.contains(trimmed) { list.append(trimmed) }
    }
    add(preferred)
    for ip in localIPv4Addresses() {
      let parts = ip.split(separator: ".")
      guard parts.count == 4 else { continue }
      let prefix = parts[0...2].joined(separator: ".")
      for last in ["1", "2"] {
        let candidate = "\(prefix).\(last)"
        if candidate != ip { add(candidate) }
      }
    }
    return list
  }

  private static func localIPv4Addresses() -> [String] {
    var result: [String] = []
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return result }
    defer { freeifaddrs(ifaddr) }

    var cursor: UnsafeMutablePointer<ifaddrs>? = first
    while let entry = cursor {
      let flags = Int32(entry.pointee.ifa_flags)
      let name = String(cString: entry.pointee.ifa_name)
      if let addr = entry.pointee.ifa_addr,
         addr.pointee.sa_family == UInt8(AF_INET),
         (flags & IFF_UP) != 0,
         (flags & IFF_LOOPBACK) == 0,
         name.hasPrefix("en") {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let rc = getnameinfo(
          addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
        if rc == 0 { result.append(String(cString: host)) }
      }
      cursor = entry.pointee.ifa_next
    }
    return result
  }

  private static func saveToCache(_ data: Data, fileName: String, handle: UInt32) -> String? {
    let fm = FileManager.default
    let cacheDir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
    let destDir = cacheDir.appendingPathComponent("photoe_zi_tether", isDirectory: true)
    try? fm.createDirectory(at: destDir, withIntermediateDirectories: true, attributes: nil)
    var url = destDir.appendingPathComponent(fileName)
    if fm.fileExists(atPath: url.path) {
      let base = (fileName as NSString).deletingPathExtension
      let ext = (fileName as NSString).pathExtension
      url = destDir.appendingPathComponent("\(base)_\(String(handle, radix: 16)).\(ext)")
    }
    do {
      try data.write(to: url)
      return url.path
    } catch {
      return nil
    }
  }

  /// Renders a display JPEG (max 2400 px) from RAW (CR2) data using ImageIO.
  private static func makePreviewJpeg(from data: Data, maxPixel: Int = 2400) -> Data? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixel,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
      return nil
    }
    let output = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(output as CFMutableData, "public.jpeg" as CFString, 1, nil)
    else { return nil }
    let props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.88]
    CGImageDestinationAddImage(dest, image, props as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { return nil }
    return output as Data
  }

  /// Reads real EXIF (aperture, shutter, ISO, focal length, model) via ImageIO.
  private static func exif(from data: Data, fallbackModel: String) -> [String: Any] {
    var out: [String: Any] = ["cameraModel": fallbackModel]
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    else { return out }

    if let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
       let model = tiff[kCGImagePropertyTIFFModel] as? String, !model.isEmpty {
      out["cameraModel"] = model
    }
    guard let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] else { return out }

    if let f = (exif[kCGImagePropertyExifFNumber] as? NSNumber)?.doubleValue, f > 0 {
      out["aperture"] = String(format: "f/%.1f", f)
    }
    if let t = (exif[kCGImagePropertyExifExposureTime] as? NSNumber)?.doubleValue, t > 0 {
      out["shutterSpeed"] = t >= 1 ? String(format: "%.1fs", t) : "1/\(Int((1.0 / t).rounded()))s"
    }
    if let isoList = exif[kCGImagePropertyExifISOSpeedRatings] as? [NSNumber], let iso = isoList.first {
      out["iso"] = iso.intValue
    }
    if let fl = (exif[kCGImagePropertyExifFocalLength] as? NSNumber)?.doubleValue, fl > 0 {
      out["focalLength"] = "\(Int(fl.rounded()))mm"
    }
    if let lens = exif[kCGImagePropertyExifLensModel] as? String, !lens.isEmpty {
      out["lens"] = lens
    }
    return out
  }
}
