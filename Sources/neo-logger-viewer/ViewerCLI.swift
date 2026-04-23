import Foundation
import NeoLogger

// Placeholder - real implementation follows in next edit.
@main
enum ViewerCLI {
  static func main() async throws {
    print("neo-logger-viewer starting...")
    try await ViewerServer().run()
  }
}
