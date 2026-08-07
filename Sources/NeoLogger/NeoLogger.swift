import Foundation

#if canImport(UIKit)
  import UIKit
#endif
#if canImport(AppKit)
  import AppKit
#endif

/// Configuration for a `NeoLogger` instance.
public struct NeoLoggerConfiguration: Sendable {
  public var endpoint: TransportEndpoint
  public var clientInfo: ClientInfo
  /// Max messages buffered while offline. Oldest are dropped when full.
  public var maxBufferedMessages: Int

  public init(
    endpoint: TransportEndpoint = .bonjour(),
    clientInfo: ClientInfo = .current(),
    maxBufferedMessages: Int = 8192
  ) {
    self.endpoint = endpoint
    self.clientInfo = clientInfo
    self.maxBufferedMessages = maxBufferedMessages
  }
}

extension ClientInfo {
  /// Best-effort client info derived from the current process / OS.
  public static func current() -> ClientInfo {
    let bundle = Bundle.main
    let name =
      bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
      ?? ProcessInfo.processInfo.processName
    let version =
      bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
      ?? "unknown"

    #if canImport(UIKit) && !os(watchOS)
      let device = UIDevice.current
      return ClientInfo(
        name: name,
        version: version,
        osName: device.systemName,
        osVersion: device.systemVersion,
        model: device.model
      )
    #elseif canImport(AppKit)
      let os = ProcessInfo.processInfo.operatingSystemVersion
      let osVersion = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
      return ClientInfo(
        name: name,
        version: version,
        osName: "macOS",
        osVersion: osVersion,
        model: "Mac"
      )
    #else
      let os = ProcessInfo.processInfo.operatingSystemVersion
      let osVersion = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
      return ClientInfo(
        name: name,
        version: version,
        osName: ProcessInfo.processInfo.operatingSystemVersionString,
        osVersion: osVersion
      )
    #endif
  }
}

/// Fire-and-forget shorthand for `NeoLogger.shared` — every logging entry
/// point is synchronous, so `NeoLog.info(.network, "…")` works from any code.
public let NeoLog = NeoLogger.shared

/// A modern Swift NSLogger-compatible client.
///
/// Logging entry points are synchronous, non-blocking, and call-ordered:
/// sequence numbers and timestamps are assigned at the call site (under the
/// intake lock), and the thread label is the caller's. A background drain
/// moves buffered messages into the transport, which owns the connection,
/// wire encoding, and the client-info handshake. Messages queued while the
/// viewer is unreachable stay buffered (oldest dropped beyond
/// `maxBufferedMessages`); the in-flight message is never dropped.
public actor NeoLogger {
  /// Shared instance. You may create your own `NeoLogger` instances as well.
  public static let shared = NeoLogger()

  private let transport: any LogTransport
  private nonisolated let intake: Intake
  private var inFlight = false
  private var flushWaiters: [CheckedContinuation<Void, Never>] = []

  /// Creates a logger backed by the Network.framework transport.
  public init(configuration: NeoLoggerConfiguration = NeoLoggerConfiguration()) {
    self.init(
      configuration: configuration,
      transport: NWTransport(endpoint: configuration.endpoint, clientInfo: configuration.clientInfo)
    )
  }

  /// Creates a logger that sends through the given transport.
  public init(
    configuration: NeoLoggerConfiguration = NeoLoggerConfiguration(),
    transport: any LogTransport
  ) {
    self.intake = Intake(capacity: configuration.maxBufferedMessages)
    self.transport = transport
  }

  // MARK: Logging

  public nonisolated func log(
    _ domain: Domain,
    _ level: Level,
    _ message: String,
    file: String = #fileID,
    line: Int = #line,
    function: String = #function
  ) {
    ingest(domain, level, .text(message), file, line, function)
  }

  public nonisolated func log(
    _ domain: Domain,
    _ level: Level,
    _ data: Data,
    file: String = #fileID,
    line: Int = #line,
    function: String = #function
  ) {
    ingest(domain, level, .data(data), file, line, function)
  }

  public nonisolated func logImage(
    _ domain: Domain,
    _ level: Level,
    pngData: Data,
    width: Int,
    height: Int,
    file: String = #fileID,
    line: Int = #line,
    function: String = #function
  ) {
    ingest(
      domain, level, .image(png: pngData, width: Int32(width), height: Int32(height)),
      file, line, function)
  }

  public nonisolated func mark(_ text: String = "Mark") {
    kickIfNeeded(intake.append { seq in .mark(seq: seq, text: text) })
  }

  // MARK: Severity shortcuts

  public nonisolated func error(
    _ domain: Domain = .app, _ message: String,
    file: String = #fileID, line: Int = #line, function: String = #function
  ) { log(domain, .error, message, file: file, line: line, function: function) }

  public nonisolated func warning(
    _ domain: Domain = .app, _ message: String,
    file: String = #fileID, line: Int = #line, function: String = #function
  ) { log(domain, .warning, message, file: file, line: line, function: function) }

  public nonisolated func important(
    _ domain: Domain = .app, _ message: String,
    file: String = #fileID, line: Int = #line, function: String = #function
  ) { log(domain, .important, message, file: file, line: line, function: function) }

  public nonisolated func info(
    _ domain: Domain = .app, _ message: String,
    file: String = #fileID, line: Int = #line, function: String = #function
  ) { log(domain, .info, message, file: file, line: line, function: function) }

  public nonisolated func debug(
    _ domain: Domain = .app, _ message: String,
    file: String = #fileID, line: Int = #line, function: String = #function
  ) { log(domain, .debug, message, file: file, line: line, function: function) }

  public nonisolated func verbose(
    _ domain: Domain = .app, _ message: String,
    file: String = #fileID, line: Int = #line, function: String = #function
  ) { log(domain, .verbose, message, file: file, line: line, function: function) }

  public nonisolated func noise(
    _ domain: Domain = .app, _ message: String,
    file: String = #fileID, line: Int = #line, function: String = #function
  ) { log(domain, .noise, message, file: file, line: line, function: function) }

  // Message-only variants: without these, `error("boom")` would bind the
  // string to the Domain slot (Domain is ExpressibleByStringLiteral) and
  // fail to compile.

  public nonisolated func error(
    _ message: String,
    file: String = #fileID, line: Int = #line, function: String = #function
  ) { log(.app, .error, message, file: file, line: line, function: function) }

  public nonisolated func warning(
    _ message: String,
    file: String = #fileID, line: Int = #line, function: String = #function
  ) { log(.app, .warning, message, file: file, line: line, function: function) }

  public nonisolated func important(
    _ message: String,
    file: String = #fileID, line: Int = #line, function: String = #function
  ) { log(.app, .important, message, file: file, line: line, function: function) }

  public nonisolated func info(
    _ message: String,
    file: String = #fileID, line: Int = #line, function: String = #function
  ) { log(.app, .info, message, file: file, line: line, function: function) }

  public nonisolated func debug(
    _ message: String,
    file: String = #fileID, line: Int = #line, function: String = #function
  ) { log(.app, .debug, message, file: file, line: line, function: function) }

  public nonisolated func verbose(
    _ message: String,
    file: String = #fileID, line: Int = #line, function: String = #function
  ) { log(.app, .verbose, message, file: file, line: line, function: function) }

  public nonisolated func noise(
    _ message: String,
    file: String = #fileID, line: Int = #line, function: String = #function
  ) { log(.app, .noise, message, file: file, line: line, function: function) }

  // MARK: Flush

  /// Wait until every message accepted before this call has been handed to
  /// the transport and acknowledged. May wait indefinitely while no viewer
  /// is reachable; race with a timeout if you need a bound.
  public func flush() async {
    while !(intake.isEmpty && !inFlight) {
      await withCheckedContinuation { flushWaiters.append($0) }
    }
  }

  // MARK: Internals

  private nonisolated func ingest(
    _ domain: Domain, _ level: Level, _ payload: LogPayload,
    _ file: String, _ line: Int, _ function: String
  ) {
    let threadId = Self.threadLabel()
    kickIfNeeded(
      intake.append { seq in
        .log(
          seq: seq,
          threadId: threadId,
          domain: domain.rawValue,
          level: level.rawValue,
          payload: payload,
          file: file,
          line: Int32(line),
          function: function
        )
      })
  }

  private nonisolated func kickIfNeeded(_ kick: Bool) {
    if kick {
      Task { await self.drain() }
    }
  }

  private func drain() async {
    while true {
      while let message = intake.popFirst() {
        inFlight = true
        do {
          try await transport.send(message)
          inFlight = false
        } catch {
          // Terminal transport failure (stopped/cancelled): keep the message;
          // the next log call kicks a fresh drain.
          inFlight = false
          intake.prepend(message)
          intake.abortDrain()
          return
        }
      }
      if intake.finishIfEmpty() { break }
    }
    let waiters = flushWaiters
    flushWaiters.removeAll()
    for waiter in waiters { waiter.resume() }
  }

  private static func threadLabel() -> String {
    if Thread.isMainThread { return "main" }
    if let name = Thread.current.name, !name.isEmpty { return name }
    return String(format: "thread-%p", Thread.current)
  }
}

/// Lock-guarded staging buffer between synchronous call sites and the actor's
/// drain. Sequence numbers and timestamps are assigned under the lock, so
/// messages leave in call order; queued messages beyond capacity are dropped
/// oldest-first (never the in-flight one — the drain holds that).
final class Intake: @unchecked Sendable {
  private let lock = NSLock()
  private let capacity: Int
  private var sequence: Int32 = 0
  private var buffer: [Message] = []
  private var drainScheduled = false

  init(capacity: Int) {
    self.capacity = capacity
  }

  /// Appends the message built with the next sequence number.
  /// Returns true when the caller must kick a drain.
  func append(_ build: (Int32) -> Message) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    sequence &+= 1
    if capacity > 0, buffer.count >= capacity {
      buffer.removeFirst()
    }
    buffer.append(build(sequence))
    if drainScheduled { return false }
    drainScheduled = true
    return true
  }

  func popFirst() -> Message? {
    lock.lock()
    defer { lock.unlock() }
    return buffer.isEmpty ? nil : buffer.removeFirst()
  }

  func prepend(_ message: Message) {
    lock.lock()
    defer { lock.unlock() }
    buffer.insert(message, at: 0)
  }

  var isEmpty: Bool {
    lock.lock()
    defer { lock.unlock() }
    return buffer.isEmpty
  }

  /// True (releasing the drain slot) only when the buffer is empty —
  /// otherwise the drain must keep going.
  func finishIfEmpty() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard buffer.isEmpty else { return false }
    drainScheduled = false
    return true
  }

  /// Give up the drain slot after a terminal send failure so the next
  /// append kicks a fresh drain.
  func abortDrain() {
    lock.lock()
    defer { lock.unlock() }
    drainScheduled = false
  }
}
