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

  @Test func deliversInOrderWithIncreasingSequence() async throws {
    let transport = RecordingTransport()
    let logger = makeLogger(transport: transport)
    await logger.log(.app, .info, "a")
    await logger.log(.app, .info, "b")
    await logger.log(.app, .info, "c")
    await logger.flush()

    let sent = await transport.sent
    #expect(sent.compactMap(\.text) == ["a", "b", "c"])
    let seqs = sent.compactMap(\.seq)
    #expect(seqs == seqs.sorted())
    #expect(Set(seqs).count == 3)
  }

  @Test func dropsOldestBeyondBufferLimitButNeverTheInFlightMessage() async throws {
    let transport = RecordingTransport(mode: .gated)
    let logger = makeLogger(transport: transport, maxBuffered: 4)

    await logger.log(.app, .info, "m1")
    // Wait until m1 is in flight (parked inside the gated transport) so the
    // buffer arithmetic below is deterministic.
    try await eventually { await transport.attempts == 1 }

    for i in 2...6 { await logger.log(.app, .info, "m\(i)") }
    await transport.set(mode: .open)
    await logger.flush()

    // m2 was evicted (oldest in the buffer); in-flight m1 was untouchable.
    #expect(await transport.sent.compactMap(\.text) == ["m1", "m3", "m4", "m5", "m6"])
  }

  @Test func requeuesTheInFlightMessageWhenTheTransportThrows() async throws {
    let transport = RecordingTransport(mode: .failing)
    let logger = makeLogger(transport: transport)

    await logger.log(.app, .info, "x")
    try await eventually { await transport.attempts >= 1 }

    await transport.set(mode: .open)
    await logger.log(.app, .info, "y")  // restarts the drain
    await logger.flush()

    #expect(await transport.sent.compactMap(\.text) == ["x", "y"])
  }

  @Test func flushWaitsUntilTheInFlightSendIsAcknowledged() async throws {
    let transport = RecordingTransport(mode: .gated)
    let logger = makeLogger(transport: transport)
    await logger.log(.app, .info, "x")

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
}
