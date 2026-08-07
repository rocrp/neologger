import Foundation
import NeoLogger
import Testing

/// In-process `LogTransport` adapter: records Messages, and can gate sends
/// (suspend until opened) or fail them.
actor RecordingTransport: LogTransport {
  enum Mode { case open, gated, failing }
  struct Failure: Error {}

  private(set) var sent: [Message] = []
  /// Times `send` was entered, including gated and failed attempts.
  private(set) var attempts = 0
  private var mode: Mode
  private var gateWaiters: [CheckedContinuation<Void, Never>] = []

  init(mode: Mode = .open) {
    self.mode = mode
  }

  func send(_ message: Message) async throws {
    attempts += 1
    while mode == .gated {
      await withCheckedContinuation { gateWaiters.append($0) }
    }
    if mode == .failing { throw Failure() }
    sent.append(message)
  }

  func set(mode: Mode) {
    self.mode = mode
    if mode != .gated {
      let waiters = gateWaiters
      gateWaiters.removeAll()
      for waiter in waiters { waiter.resume() }
    }
  }
}

@Suite("NeoLogger actor over an in-process transport")
struct NeoLoggerActorTests {
  private func makeLogger(transport: RecordingTransport, maxBuffered: Int = 8192) -> NeoLogger {
    NeoLogger(
      configuration: NeoLoggerConfiguration(maxBufferedMessages: maxBuffered),
      transport: transport
    )
  }

  @Test func syncCallsArriveInCallOrderWithContiguousSequence() async throws {
    let transport = RecordingTransport()
    let logger = makeLogger(transport: transport)
    for i in 1...200 {
      logger.log(.app, .info, "m\(i)")
    }
    await logger.flush()

    let sent = await transport.sent
    #expect(sent.compactMap(\.text) == (1...200).map { "m\($0)" })
    #expect(sent.compactMap(\.seq) == (1...200).map(Int32.init))
  }

  @Test func capturesTheCallersThreadLabel() async throws {
    let transport = RecordingTransport()
    let logger = makeLogger(transport: transport)
    let thread = Thread {
      logger.log(.app, .info, "from a named thread")
    }
    thread.name = "worker-7"
    thread.start()
    try await eventually { await !transport.sent.isEmpty }
    await logger.flush()
    #expect(await transport.sent.first?.threadId == "worker-7")
  }

  @Test func dropsOldestBeyondBufferLimitButNeverTheInFlightMessage() async throws {
    let transport = RecordingTransport(mode: .gated)
    let logger = makeLogger(transport: transport, maxBuffered: 4)

    logger.log(.app, .info, "m1")
    // Wait until m1 is in flight (parked inside the gated transport) so the
    // buffer arithmetic below is deterministic.
    try await eventually { await transport.attempts == 1 }

    for i in 2...6 {
      logger.log(.app, .info, "m\(i)")
    }
    await transport.set(mode: .open)
    await logger.flush()

    // m2 was evicted (oldest in the buffer); in-flight m1 was untouchable.
    #expect(await transport.sent.compactMap(\.text) == ["m1", "m3", "m4", "m5", "m6"])
  }

  @Test func requeuesTheInFlightMessageWhenTheTransportThrows() async throws {
    let transport = RecordingTransport(mode: .failing)
    let logger = makeLogger(transport: transport)

    logger.log(.app, .info, "x")
    try await eventually { await transport.attempts >= 1 }

    await transport.set(mode: .open)
    logger.log(.app, .info, "y")  // kicks a fresh drain
    await logger.flush()

    #expect(await transport.sent.compactMap(\.text) == ["x", "y"])
  }

  @Test func flushWaitsUntilTheInFlightSendIsAcknowledged() async throws {
    let transport = RecordingTransport(mode: .gated)
    let logger = makeLogger(transport: transport)
    logger.log(.app, .info, "x")

    let done = Flag()
    let flusher = Task {
      await logger.flush()
      await done.set()
    }
    try await Task.sleep(for: .milliseconds(100))
    #expect(await done.value == false)

    await transport.set(mode: .open)
    await flusher.value
    #expect(await done.value)
    #expect(await transport.sent.count == 1)
  }

  @Test func severityShortcutsCoverAllSevenLevels() async throws {
    let transport = RecordingTransport()
    let logger = makeLogger(transport: transport)
    logger.error("e")
    logger.warning("w")
    logger.important("im")
    logger.info("i")
    logger.debug("d")
    logger.verbose("v")
    logger.noise("n")
    await logger.flush()

    let levels = await transport.sent.compactMap(\.level)
    #expect(levels == [.error, .warning, .important, .info, .debug, .verbose, .noise])
  }
}
