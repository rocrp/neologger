import Foundation

/// The seam through which Messages leave the client.
///
/// Contract:
/// - `send` suspends until the message has been handed to the underlying
///   connection and acknowledged. While the peer is unreachable it waits —
///   the adapter owns reconnection — so it throws only terminally
///   (the transport was stopped, the task was cancelled, or the
///   configuration is unusable).
/// - Adapters own everything below the seam: wire encoding, connection
///   lifecycle, and any per-connection handshake.
public protocol LogTransport: Sendable {
  func send(_ message: Message) async throws
}
