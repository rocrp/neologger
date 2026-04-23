import Foundation
import NeoLogger
import Network

/// Minimal TCP + Bonjour server that decodes NSLogger frames and prints
/// them as one line per message.
///
/// Enough to validate that a NeoLogger client is sending correctly. The real
/// macOS viewer app is a separate product.
final class ViewerServer: @unchecked Sendable {
  private let queue = DispatchQueue(label: "neologger.viewer.server")
  private let port: NWEndpoint.Port
  private let serviceName: String

  init(port: UInt16 = 50000, serviceName: String = "NeoLogger Viewer") {
    self.port = NWEndpoint.Port(rawValue: port) ?? 50000
    self.serviceName = serviceName
  }

  func run() async throws {
    let listener = try NWListener(
      using: .tcp,
      on: port
    )
    listener.service = NWListener.Service(
      name: serviceName,
      type: TransportEndpoint.plainServiceType
    )

    listener.stateUpdateHandler = { state in
      switch state {
      case .ready:
        print(
          "[viewer] listening on port \(listener.port?.rawValue ?? 0) (Bonjour: \(TransportEndpoint.plainServiceType))"
        )
      case .failed(let error):
        print("[viewer] listener failed: \(error)")
      default:
        break
      }
    }

    listener.newConnectionHandler = { [weak self] connection in
      guard let self else { return }
      Task.detached { await self.handle(connection: connection) }
    }

    listener.start(queue: queue)
    // Run forever.
    try await Task.sleep(nanoseconds: UInt64.max)
  }

  private func handle(connection: NWConnection) async {
    let id = UUID().uuidString.prefix(8)
    print("[viewer] client \(id) connecting")
    connection.start(queue: queue)

    var decoder = WireDecoder()
    while true {
      let chunk: Data
      do {
        chunk = try await receive(connection: connection)
      } catch {
        print("[viewer] client \(id) disconnected: \(error)")
        connection.cancel()
        return
      }
      if chunk.isEmpty {
        print("[viewer] client \(id) closed")
        connection.cancel()
        return
      }
      decoder.append(chunk)
      do {
        while let message = try decoder.nextMessage() {
          print(Self.format(message: message, clientID: String(id)))
        }
      } catch {
        print("[viewer] client \(id) decode error: \(error)")
        connection.cancel()
        return
      }
    }
  }

  private func receive(connection: NWConnection) async throws -> Data {
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
      connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
        data, _, isComplete, error in
        if let error {
          cont.resume(throwing: error)
          return
        }
        if isComplete {
          cont.resume(returning: Data())
          return
        }
        cont.resume(returning: data ?? Data())
      }
    }
  }

  static func format(message: Message, clientID: String) -> String {
    var messageType: Int32 = 0
    var tag: String?
    var level: Int32 = 0
    var text: String = ""
    var file: String?
    var line: Int32?
    var clientName: String?

    for part in message.parts {
      guard let key = PartKey(rawValue: part.key) else { continue }
      switch (key, part.value) {
      case (.messageType, .int32(let v)): messageType = v
      case (.tag, .string(let s)): tag = s
      case (.level, .int32(let v)): level = v
      case (.message, .string(let s)): text = s
      case (.message, .binary(let d)): text = "<binary \(d.count) bytes>"
      case (.message, .image(let d)): text = "<image \(d.count) bytes>"
      case (.filename, .string(let s)): file = (s as NSString).lastPathComponent
      case (.lineNumber, .int32(let v)): line = v
      case (.clientName, .string(let s)): clientName = s
      default: break
      }
    }

    if messageType == MessageType.clientInfo.rawValue {
      return "[\(clientID)] CLIENT \(clientName ?? "?")"
    }
    if messageType == MessageType.mark.rawValue {
      return "[\(clientID)] MARK \(text)"
    }

    let location: String
    if let file, let line {
      location = "\(file):\(line) "
    } else {
      location = ""
    }
    let levelName = Self.levelName(level)
    let tagPart = tag.map { "[\($0)] " } ?? ""
    return "[\(clientID)] \(levelName) \(tagPart)\(location)\(text)"
  }

  private static func levelName(_ v: Int32) -> String {
    switch v {
    case 0: "ERROR"
    case 1: "WARN "
    case 2: "IMPO "
    case 3: "INFO "
    case 4: "DEBUG"
    case 5: "VERB "
    case 6: "NOISE"
    default: "L\(v)"
    }
  }
}
