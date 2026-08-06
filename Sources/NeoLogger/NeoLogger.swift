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

/// A modern Swift NSLogger-compatible client.
///
/// Calls are non-blocking: `log(...)` returns immediately after enqueuing.
/// A background task drains the queue into the transport, which owns the
/// connection, wire encoding, and the client-info handshake. Messages
/// enqueued while the viewer is unreachable stay buffered (oldest dropped
/// beyond `maxBufferedMessages`); the in-flight message is never dropped.
public actor NeoLogger {
  /// Shared instance. You may create your own `NeoLogger` instances as well.
  public static let shared = NeoLogger()

  private let transport: any LogTransport
  private let config: NeoLoggerConfiguration
  private var sequence: Int32 = 0
  private var pending: [Message] = []
  private var inFlight = false
  private var drainTask: Task<Void, Never>?
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
    self.config = configuration
    self.transport = transport
  }

  // MARK: Public API

  public func log(
    _ domain: Domain,
    _ level: Level,
    _ message: String,
    file: String = #fileID,
    line: Int = #line,
    function: String = #function
  ) {
    enqueue(
      .log(
        seq: nextSeq(),
        threadId: Self.threadLabel(),
        domain: domain.rawValue,
        level: level.rawValue,
        text: message,
        file: file,
        line: Int32(line),
        function: function
      ))
  }

  public func log(
    _ domain: Domain,
    _ level: Level,
    _ data: Data,
    file: String = #fileID,
    line: Int = #line,
    function: String = #function
  ) {
    enqueue(
      .logData(
        seq: nextSeq(),
        threadId: Self.threadLabel(),
        domain: domain.rawValue,
        level: level.rawValue,
        data: data,
        file: file,
        line: Int32(line),
        function: function
      ))
  }

  public func logImage(
    _ domain: Domain,
    _ level: Level,
    pngData: Data,
    width: Int,
    height: Int,
    file: String = #fileID,
    line: Int = #line,
    function: String = #function
  ) {
    enqueue(
      .logImage(
        seq: nextSeq(),
        threadId: Self.threadLabel(),
        domain: domain.rawValue,
        level: level.rawValue,
        pngData: pngData,
        width: Int32(width),
        height: Int32(height),
        file: file,
        line: Int32(line),
        function: function
      ))
  }

  public func mark(_ text: String = "Mark") {
    enqueue(.mark(seq: nextSeq(), text: text))
  }

  /// Wait until every message accepted before this call has been handed to
  /// the transport and acknowledged. May wait indefinitely while no viewer
  /// is reachable; race with a timeout if you need a bound.
  public func flush() async {
    while !(pending.isEmpty && !inFlight) {
      await withCheckedContinuation { flushWaiters.append($0) }
    }
  }

  // MARK: Internals

  private func enqueue(_ message: Message) {
    if pending.count >= config.maxBufferedMessages {
      pending.removeFirst()
    }
    pending.append(message)
    ensureDrainTaskRunning()
  }

  private func ensureDrainTaskRunning() {
    if drainTask == nil {
      drainTask = Task { [weak self] in
        await self?.drain()
      }
    }
  }

  private func drain() async {
    while !pending.isEmpty {
      let message = pending.removeFirst()
      inFlight = true
      do {
        try await transport.send(message)
        inFlight = false
      } catch {
        // Terminal transport failure (stopped/cancelled): keep the message
        // for a future drain rather than dropping it.
        inFlight = false
        pending.insert(message, at: 0)
        break
      }
    }
    drainTask = nil
    if pending.isEmpty {
      let waiters = flushWaiters
      flushWaiters.removeAll()
      for waiter in waiters { waiter.resume() }
    }
  }

  private func nextSeq() -> Int32 {
    sequence &+= 1
    return sequence
  }

  private static func threadLabel() -> String {
    if Thread.isMainThread { return "main" }
    if let name = Thread.current.name, !name.isEmpty { return name }
    return String(format: "thread-%p", Thread.current)
  }
}
