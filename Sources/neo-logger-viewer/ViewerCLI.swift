import Darwin
import Foundation
import NeoLogger

/// Usage: neo-logger-viewer [port]   (default 50000)
@main
enum ViewerCLI {
  static func main() async throws {
    // Line-buffer stdout so piped/redirected runs show output in real time.
    setlinebuf(stdout)
    let port = CommandLine.arguments.dropFirst().first.flatMap(UInt16.init) ?? 50000
    print("neo-logger-viewer starting...")
    try await ViewerServer.run(port: port)
  }
}
