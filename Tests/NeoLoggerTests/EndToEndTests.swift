import Foundation
import Network
import Testing

@testable import NeoLogger

/// Spins up an in-process TCP listener, points a NeoLogger at it, and checks
/// that CLIENTINFO + a log message arrive with the expected wire bytes.
@Suite("End-to-end over Network.framework", .serialized)
struct EndToEndTests {
  @Test(.timeLimit(.minutes(1)))
  func logsReachLocalListener() async throws {
    let port = try await pickFreePort()
    let listener = CapturingListener(port: port)
    try listener.start()
    defer { listener.stop() }

    let client = NeoLogger(
      configuration: NeoLoggerConfiguration(
        endpoint: .host(name: "127.0.0.1", port: port, useTLS: false),
        clientInfo: ClientInfo(
          name: "TestApp", version: "1.2.3", osName: "macOS", osVersion: "14.0")
      ))

    await client.log(
      .network, .info, "hello over the wire", file: "E2E.swift", line: 42, function: "test()")
    await client.flush()

    // Wait up to 2 seconds for messages to arrive + decode.
    let deadline = Date().addingTimeInterval(2)
    while Date() < deadline, listener.decodedMessages.count < 2 {
      try await Task.sleep(nanoseconds: 20_000_000)
    }

    let messages = listener.decodedMessages
    #expect(messages.count >= 2, "expected CLIENTINFO + log message, got \(messages.count)")

    let clientInfo = messages.first { message in
      message.parts.contains { part in
        guard part.key == PartKey.messageType.rawValue,
          case .int32(let v) = part.value
        else { return false }
        return v == MessageType.clientInfo.rawValue
      }
    }
    #expect(clientInfo != nil)

    let log = messages.first { message in
      message.parts.contains { part in
        part.key == PartKey.message.rawValue
          && (part.value == .string("hello over the wire"))
      }
    }
    #expect(log != nil)
  }

  private func pickFreePort() async throws -> UInt16 {
    // Random high port. If occupied, listener.start will fail — acceptable for a local test.
    UInt16.random(in: 49152...65000)
  }
}

final class CapturingListener: @unchecked Sendable {
  private let port: NWEndpoint.Port
  private var listener: NWListener?
  private let queue = DispatchQueue(label: "neologger.test.listener")
  private var decoder = WireDecoder()
  private var _decoded: [Message] = []
  private let lock = NSLock()

  init(port: UInt16) {
    self.port = NWEndpoint.Port(rawValue: port)!
  }

  var decodedMessages: [Message] {
    lock.lock()
    defer { lock.unlock() }
    return _decoded
  }

  func start() throws {
    let listener = try NWListener(using: .tcp, on: port)
    listener.newConnectionHandler = { [weak self] conn in
      self?.handle(connection: conn)
    }
    listener.start(queue: queue)
    self.listener = listener
  }

  func stop() {
    listener?.cancel()
  }

  private func handle(connection: NWConnection) {
    connection.start(queue: queue)
    receive(on: connection)
  }

  private func receive(on conn: NWConnection) {
    conn.receive(minimumIncompleteLength: 1, maximumLength: 32 * 1024) {
      [weak self] data, _, isComplete, error in
      guard let self else { return }
      if let data, !data.isEmpty {
        lock.lock()
        decoder.append(data)
        do {
          while let m = try decoder.nextMessage() {
            _decoded.append(m)
          }
        } catch {
          // stop on decode errors
        }
        lock.unlock()
      }
      if error == nil, !isComplete {
        self.receive(on: conn)
      } else {
        conn.cancel()
      }
    }
  }
}
