import Foundation
import NeoLogger
import Network
import Testing

private let testClientInfo = ClientInfo(
  name: "TestApp", version: "1.2.3", osName: "macOS", osVersion: "14.0")

@Suite("NWTransport ↔ NWMessageListener over local sockets", .serialized)
struct NWTransportTests {
  @Test(.timeLimit(.minutes(1)))
  func handshakePrecedesTheFirstMessage() async throws {
    let listener = NWMessageListener()
    let port = try await listener.start()
    let events = observe(listener)

    let transport = NWTransport(
      endpoint: .host(name: "127.0.0.1", port: port, useTLS: false),
      clientInfo: testClientInfo,
      retryDelay: .milliseconds(50)
    )
    try await transport.send(
      .log(seq: 1, threadId: "t", domain: "Test", level: 0, payload: .text("hello")))

    try await eventually { await events.messages(on: 0).count >= 2 }
    let messages = await events.messages(on: 0)
    #expect(messages.first?.type == .clientInfo)
    #expect(messages.compactMap(\.text).contains("hello"))
    await transport.stop()
    await listener.stop()
  }

  @Test(.timeLimit(.minutes(1)))
  func reconnectsAndReplaysTheHandshakeAfterTheViewerDropsTheConnection() async throws {
    let listener = NWMessageListener()
    let port = try await listener.start()
    let events = observe(listener)

    let transport = NWTransport(
      endpoint: .host(name: "127.0.0.1", port: port, useTLS: false),
      clientInfo: testClientInfo,
      retryDelay: .milliseconds(50)
    )
    try await transport.send(
      .log(seq: 1, threadId: "t", domain: "Test", level: 0, payload: .text("first")))
    try await eventually { await events.messages(on: 0).compactMap(\.text).contains("first") }

    await listener.dropConnection(0)

    // The client may not have observed the drop yet, so keep sending until a
    // message lands on a second connection.
    var n: Int32 = 1
    try await eventually {
      n += 1
      try await transport.send(
        .log(seq: n, threadId: "t", domain: "Test", level: 0, payload: .text("after-\(n)")))
      let count = await events.connectionCount
      let second = await events.messages(on: 1)
      return count >= 2 && !second.isEmpty
    }

    let second = await events.messages(on: 1)
    #expect(second.first?.type == .clientInfo)
    #expect(second.compactMap(\.text).allSatisfy { $0.hasPrefix("after-") })
    await transport.stop()
    await listener.stop()
  }

  @Test(.timeLimit(.minutes(1)))
  func neoLoggerFlushMeansDeliveredToTheTransport() async throws {
    let listener = NWMessageListener()
    let port = try await listener.start()
    let events = observe(listener)

    let logger = NeoLogger(
      configuration: NeoLoggerConfiguration(clientInfo: testClientInfo),
      transport: NWTransport(
        endpoint: .host(name: "127.0.0.1", port: port, useTLS: false),
        clientInfo: testClientInfo,
        retryDelay: .milliseconds(50)
      )
    )
    logger.log(
      .network, .info, "hello over the wire", file: "E2E.swift", line: 42, function: "test()")
    await logger.flush()

    try await eventually { await events.messages(on: 0).count >= 2 }
    let messages = await events.messages(on: 0)
    #expect(messages.first?.type == .clientInfo)
    #expect(messages.compactMap(\.text).contains("hello over the wire"))
    await listener.stop()
  }

  /// Regression: the viewer's cancel() is a graceful FIN, and an idle client
  /// connection stays .ready — without the peer-close monitor the next send
  /// is accepted into the dead socket and silently lost (and pre-seam code
  /// never reconnected at all). A single post-drop log must arrive on a
  /// fresh connection, preceded by the handshake.
  @Test(.timeLimit(.minutes(1)))
  func aSingleLogAfterAViewerDropIsDeliveredOnANewConnection() async throws {
    let listener = NWMessageListener()
    let port = try await listener.start()
    let events = observe(listener)

    let logger = NeoLogger(
      configuration: NeoLoggerConfiguration(clientInfo: testClientInfo),
      transport: NWTransport(
        endpoint: .host(name: "127.0.0.1", port: port, useTLS: false),
        clientInfo: testClientInfo,
        retryDelay: .milliseconds(50)
      )
    )
    logger.log(.app, .info, "first")
    await logger.flush()
    try await eventually { await events.messages(on: 0).compactMap(\.text).contains("first") }

    await listener.dropConnection(0)
    // Give the standing peer-close monitor a moment to observe the FIN.
    try await Task.sleep(for: .milliseconds(500))

    logger.log(.app, .info, "second")
    try await eventually {
      let count = await events.connectionCount
      let second = await events.messages(on: 1)
      return count >= 2 && second.compactMap(\.text).contains("second")
    }
    #expect(await events.messages(on: 1).first?.type == .clientInfo)
    await listener.stop()
  }
}
