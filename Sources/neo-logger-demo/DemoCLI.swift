import Foundation
import NeoLogger

/// Sends a handful of messages at different levels so you can see them
/// arrive in a running viewer. Useful for manual end-to-end testing.
///
/// Usage:
///   neo-logger-demo                   # auto-discover viewer via Bonjour
///   neo-logger-demo 127.0.0.1 50000   # explicit host:port
///   neo-logger-demo --forever         # emit one message per second until Ctrl-C
@main
enum DemoCLI {
  static func main() async throws {
    let args = Array(CommandLine.arguments.dropFirst())
    let forever = args.contains("--forever")
    let positional = args.filter { !$0.hasPrefix("--") }

    let endpoint: TransportEndpoint
    if positional.count >= 2, let port = UInt16(positional[1]) {
      endpoint = .host(name: positional[0], port: port, useTLS: false)
      print("[demo] sending to \(positional[0]):\(port)")
    } else {
      endpoint = .bonjour()
      print("[demo] browsing Bonjour for _nslogger._tcp viewer…")
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

    await logger.log(.app, .important, "demo starting")
    await logger.log(.network, .info, "GET https://example.com → 200")
    await logger.log(.db, .debug, "SELECT * FROM users WHERE id = 42")
    await logger.log(.view, .warning, "tableView reload on background thread")
    await logger.log(.app, .error, "something went wrong: \(NSError(domain: "demo", code: 1))")
    await logger.log(.io, .verbose, Data([0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x01, 0x02, 0x03]))
    await logger.mark("demo mark")

    if forever {
      print("[demo] --forever: emitting one message per second. Ctrl-C to stop.")
      var i = 0
      while !Task.isCancelled {
        i += 1
        await logger.log(.app, .info, "heartbeat #\(i) at \(Date())")
        try await Task.sleep(for: .seconds(1))
      }
    } else {
      await logger.flush()
      print("[demo] sent. bye.")
    }
  }
}
