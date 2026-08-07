import Foundation
import NeoLogger

/// Sends a handful of messages at different levels so you can see them
/// arrive in a running viewer. Useful for manual end-to-end testing.
///
/// Usage:
///   neo-logger-demo                   # auto-discover viewer via Bonjour
///   neo-logger-demo 127.0.0.1 50000   # explicit host:port
///   neo-logger-demo --forever         # emit one message per second until Ctrl-C
///   neo-logger-demo --tls             # browse _nslogger-ssl._tcp instead
@main
enum DemoCLI {
  static let knownFlags: Set<String> = ["--forever", "--tls"]

  static func main() async throws {
    let args = Array(CommandLine.arguments.dropFirst())
    let flags = args.filter { $0.hasPrefix("--") }
    // Fail loudly: a typo'd --tsl would otherwise silently send plaintext.
    if let unknown = flags.first(where: { !knownFlags.contains($0) }) {
      print(
        "[demo] unknown flag \(unknown); known flags: \(knownFlags.sorted().joined(separator: " "))"
      )
      exit(2)
    }
    let forever = flags.contains("--forever")
    let useTLS = flags.contains("--tls")
    let positional = args.filter { !$0.hasPrefix("--") }

    let endpoint: TransportEndpoint
    if positional.count >= 2, let port = UInt16(positional[1]) {
      endpoint = .host(name: positional[0], port: port, useTLS: useTLS)
      print("[demo] sending to \(positional[0]):\(port)\(useTLS ? " over TLS" : "")")
    } else {
      endpoint = .bonjour(useTLS: useTLS)
      let type = useTLS ? TransportEndpoint.sslServiceType : TransportEndpoint.plainServiceType
      print("[demo] browsing Bonjour for \(type) viewer…")
    }

    let logger = NeoLogger(
      configuration: NeoLoggerConfiguration(
        endpoint: endpoint,
        clientInfo: ClientInfo(
          name: "neo-logger-demo",
          version: "0.1",
          osName: "macOS",
          osVersion: ProcessInfo.processInfo.operatingSystemVersionString
        )
      ))

    logger.log(.app, .important, "demo starting")
    logger.log(.network, .info, "GET https://example.com → 200")
    logger.log(.db, .debug, "SELECT * FROM users WHERE id = 42")
    logger.log(.view, .warning, "tableView reload on background thread")
    logger.log(.app, .error, "something went wrong: \(NSError(domain: "demo", code: 1))")
    logger.log(.io, .verbose, Data([0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x01, 0x02, 0x03]))
    logger.mark("demo mark")

    if forever {
      print("[demo] --forever: emitting one message per second. Ctrl-C to stop.")
      var i = 0
      while !Task.isCancelled {
        i += 1
        logger.log(.app, .info, "heartbeat #\(i) at \(Date())")
        try await Task.sleep(for: .seconds(1))
      }
    } else {
      await logger.flush()
      print("[demo] sent. bye.")
    }
  }
}
