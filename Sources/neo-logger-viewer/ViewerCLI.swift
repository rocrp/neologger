import Darwin
import Foundation
import NeoLogger

@main
enum ViewerCLI {
  static func main() async throws {
    // Line-buffer stdout so piped/redirected runs show output in real time.
    setlinebuf(stdout)
    print("neo-logger-viewer starting...")
    try await ViewerServer().run()
  }
}
