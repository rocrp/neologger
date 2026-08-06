import Foundation
import NeoLogger
import Network
import Testing

private let testClientInfo = ClientInfo(
  name: "TestApp", version: "1.2.3", osName: "macOS", osVersion: "14.0")

/// Test-side viewer stand-in: accepts connections on a system-assigned port
/// and decodes arriving frames, kept separate per connection.
final class FrameListener: @unchecked Sendable {
  private let queue = DispatchQueue(label: "neologger.test.listener")
  private let lock = NSLock()
  private var listener: NWListener?
  private var connections: [NWConnection] = []
  private var decoders: [WireDecoder] = []
  private var messagesByConnection: [[Message]] = []

  /// Starts listening and returns the system-assigned port.
  func start() async throws -> UInt16 {
    let listener = try NWListener(using: .tcp)
    self.listener = listener
    listener.newConnectionHandler = { [weak self] connection in
      self?.accept(connection)
    }
    return try await withCheckedThrowingContinuation { cont in
      let once = ResumeOnce(cont)
      listener.stateUpdateHandler = { state in
        switch state {
        case .ready:
          once.resume(returning: listener.port?.rawValue ?? 0)
        case .failed(let error):
          once.resume(throwing: error)
        default:
          break
        }
      }
      listener.start(queue: queue)
    }
  }

  var connectionCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return connections.count
  }

  func messages(onConnection index: Int) -> [Message] {
    lock.lock()
    defer { lock.unlock() }
    guard index < messagesByConnection.count else { return [] }
    return messagesByConnection[index]
  }

  /// Server-side kill of one accepted connection.
  func dropConnection(_ index: Int) {
    lock.lock()
    let connection = index < connections.count ? connections[index] : nil
    lock.unlock()
    connection?.cancel()
  }

  func stop() {
    listener?.cancel()
    lock.lock()
    let all = connections
    lock.unlock()
    for connection in all { connection.cancel() }
  }

  private func accept(_ connection: NWConnection) {
    lock.lock()
    connections.append(connection)
    decoders.append(WireDecoder())
    messagesByConnection.append([])
    let index = connections.count - 1
    lock.unlock()
    connection.start(queue: queue)
    receive(on: connection, index: index)
  }

  private func receive(on connection: NWConnection, index: Int) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
      [weak self] data, _, isComplete, error in
      guard let self else { return }
      if let data, !data.isEmpty {
        self.lock.lock()
        self.decoders[index].append(data)
        while let message = try? self.decoders[index].nextMessage() {
          self.messagesByConnection[index].append(message)
        }
        self.lock.unlock()
      }
      if error == nil, !isComplete {
        self.receive(on: connection, index: index)
      } else {
        connection.cancel()
      }
    }
  }
}

@Suite("NWTransport adapter over local sockets", .serialized)
struct NWTransportTests {
  @Test(.timeLimit(.minutes(1)))
  func handshakePrecedesTheFirstMessage() async throws {
    let listener = FrameListener()
    let port = try await listener.start()
    defer { listener.stop() }

    let transport = NWTransport(
      endpoint: .host(name: "127.0.0.1", port: port, useTLS: false),
      clientInfo: testClientInfo,
      retryDelay: .milliseconds(50)
    )
    try await transport.send(
      .log(seq: 1, threadId: "t", domain: "Test", level: 0, text: "hello"))

    try await eventually { listener.messages(onConnection: 0).count >= 2 }
    let messages = listener.messages(onConnection: 0)
    #expect(messages.first?.isClientInfo == true)
    #expect(messages.compactMap(\.text).contains("hello"))
    await transport.stop()
  }

  @Test(.timeLimit(.minutes(1)))
  func reconnectsAndReplaysTheHandshakeAfterTheViewerDropsTheConnection() async throws {
    let listener = FrameListener()
    let port = try await listener.start()
    defer { listener.stop() }

    let transport = NWTransport(
      endpoint: .host(name: "127.0.0.1", port: port, useTLS: false),
      clientInfo: testClientInfo,
      retryDelay: .milliseconds(50)
    )
    try await transport.send(
      .log(seq: 1, threadId: "t", domain: "Test", level: 0, text: "first"))
    try await eventually {
      listener.messages(onConnection: 0).compactMap(\.text).contains("first")
    }

    listener.dropConnection(0)

    // The client may not have observed the drop yet, so keep sending until a
    // message lands on a second connection. Pre-seam code never reconnected
    // and would hang here forever.
    var n: Int32 = 1
    try await eventually {
      n += 1
      try await transport.send(
        .log(seq: n, threadId: "t", domain: "Test", level: 0, text: "after-\(n)"))
      return listener.connectionCount >= 2 && !listener.messages(onConnection: 1).isEmpty
    }

    let second = listener.messages(onConnection: 1)
    #expect(second.first?.isClientInfo == true)
    #expect(second.compactMap(\.text).allSatisfy { $0.hasPrefix("after-") })
    await transport.stop()
  }

  @Test(.timeLimit(.minutes(1)))
  func neoLoggerFlushMeansDeliveredToTheTransport() async throws {
    let listener = FrameListener()
    let port = try await listener.start()
    defer { listener.stop() }

    let logger = NeoLogger(
      configuration: NeoLoggerConfiguration(clientInfo: testClientInfo),
      transport: NWTransport(
        endpoint: .host(name: "127.0.0.1", port: port, useTLS: false),
        clientInfo: testClientInfo,
        retryDelay: .milliseconds(50)
      )
    )
    await logger.log(
      .network, .info, "hello over the wire", file: "E2E.swift", line: 42, function: "test()")
    await logger.flush()

    try await eventually { listener.messages(onConnection: 0).count >= 2 }
    let messages = listener.messages(onConnection: 0)
    #expect(messages.first?.isClientInfo == true)
    #expect(messages.compactMap(\.text).contains("hello over the wire"))
  }

  /// Regression: the viewer's cancel() is a graceful FIN, and an idle client
  /// connection stays .ready — pre-monitor code accepted the next send into
  /// the dead socket and silently lost it (and pre-seam code never
  /// reconnected at all). A single post-drop log must arrive on a fresh
  /// connection, preceded by the handshake.
  @Test(.timeLimit(.minutes(1)))
  func aSingleLogAfterAViewerDropIsDeliveredOnANewConnection() async throws {
    let listener = FrameListener()
    let port = try await listener.start()
    defer { listener.stop() }

    let logger = NeoLogger(
      configuration: NeoLoggerConfiguration(clientInfo: testClientInfo),
      transport: NWTransport(
        endpoint: .host(name: "127.0.0.1", port: port, useTLS: false),
        clientInfo: testClientInfo,
        retryDelay: .milliseconds(50)
      )
    )
    await logger.log(.app, .info, "first")
    await logger.flush()
    try await eventually {
      listener.messages(onConnection: 0).compactMap(\.text).contains("first")
    }

    listener.dropConnection(0)
    // Give the standing peer-close monitor a moment to observe the FIN.
    try await Task.sleep(for: .milliseconds(500))

    await logger.log(.app, .info, "second")
    try await eventually {
      listener.connectionCount >= 2
        && listener.messages(onConnection: 1).compactMap(\.text).contains("second")
    }
    #expect(listener.messages(onConnection: 1).first?.isClientInfo == true)
  }
}
