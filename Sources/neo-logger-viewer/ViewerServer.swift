import Foundation
import NeoLogger

/// Prints one line per Message arriving from NeoLogger/NSLogger clients.
///
/// All socket and decoding work lives in the library's `NWMessageListener`;
/// this file is only the print format. The real macOS viewer app is a
/// separate product.
enum ViewerServer {
  static func run(port: UInt16 = 50000, serviceName: String = "NeoLogger Viewer") async throws {
    let listener = NWMessageListener(port: port, serviceName: serviceName)
    let boundPort = try await listener.start()
    print(
      "[viewer] listening on port \(boundPort) (Bonjour: \(TransportEndpoint.plainServiceType))")
    for await event in listener.events {
      switch event.kind {
      case .connected:
        print("[viewer] client #\(event.connection) connected")
      case .message(let message):
        print(format(message: message, clientID: event.connection))
      case .disconnected:
        print("[viewer] client #\(event.connection) closed")
      }
    }
  }

  static func format(message: Message, clientID: Int) -> String {
    let id = "[#\(clientID)]"
    switch message.type {
    case .clientInfo:
      return "\(id) CLIENT \(message.clientName ?? "?")"
    case .mark:
      return "\(id) MARK \(message.text ?? "")"
    default:
      break
    }

    let level = pad((message.level ?? .info).name, 5)
    let tag = pad(message.tag.map { "[\($0)]" } ?? "", 9)
    let location: String
    if let file = message.filename, let line = message.lineNumber {
      location = "\((file as NSString).lastPathComponent):\(line) "
    } else {
      location = ""
    }
    let body: String
    switch message.payload {
    case .text(let text): body = text
    case .data(let data): body = "<binary \(data.count) bytes>"
    case .image(let png, _, _): body = "<image \(png.count) bytes>"
    case nil: body = ""
    }
    return "\(id) \(level) \(tag) \(location)\(body)"
  }

  private static func pad(_ string: String, _ width: Int) -> String {
    string.count >= width ? string : string + String(repeating: " ", count: width - string.count)
  }
}
