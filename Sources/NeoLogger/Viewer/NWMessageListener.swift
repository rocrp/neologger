import Foundation
import Network

/// Viewer-side counterpart of `NWTransport`: accepts client connections,
/// optionally advertises over Bonjour, decodes arriving Frames, and yields
/// per-connection events on `events`.
///
/// One consumer should iterate `events`; the stream finishes on `stop()`.
public actor NWMessageListener {
  public enum EventKind: Sendable {
    case connected
    case message(Message)
    case disconnected
  }

  public struct Event: Sendable {
    public let connection: Int
    public let kind: EventKind
  }

  public enum ListenerError: Error, Sendable {
    case invalidPort(UInt16)
  }

  public nonisolated let events: AsyncStream<Event>
  private let eventContinuation: AsyncStream<Event>.Continuation
  /// Callback queue for Network.framework objects; all state lives on the actor.
  private nonisolated let queue = DispatchQueue(label: "neologger.listener")
  private let requestedPort: UInt16?
  private let serviceName: String?
  private let serviceType: String
  private var listener: NWListener?
  private var connections: [Int: NWConnection] = [:]
  private var decoders: [Int: WireDecoder] = [:]
  private var nextConnectionID = 0

  /// - Parameters:
  ///   - port: TCP port to bind, or nil for a system-assigned one.
  ///   - serviceName: advertise over Bonjour under this name when non-nil.
  public init(
    port: UInt16? = nil,
    serviceName: String? = nil,
    serviceType: String = TransportEndpoint.plainServiceType
  ) {
    self.requestedPort = port
    self.serviceName = serviceName
    self.serviceType = serviceType
    let pipe = AsyncStream.makeStream(of: Event.self)
    self.events = pipe.stream
    self.eventContinuation = pipe.continuation
  }

  /// Starts listening; returns the bound port.
  public func start() async throws -> UInt16 {
    let listener: NWListener
    if let requestedPort {
      guard let nwPort = NWEndpoint.Port(rawValue: requestedPort) else {
        throw ListenerError.invalidPort(requestedPort)
      }
      listener = try NWListener(using: .tcp, on: nwPort)
    } else {
      listener = try NWListener(using: .tcp)
    }
    if let serviceName {
      listener.service = NWListener.Service(name: serviceName, type: serviceType)
    }
    self.listener = listener
    listener.newConnectionHandler = { [weak self] connection in
      Task { await self?.accept(connection) }
    }
    return try await withCheckedThrowingContinuation { cont in
      let once = OnceContinuation(cont)
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

  /// Stops accepting, cancels every connection, and finishes `events`.
  public func stop() {
    listener?.cancel()
    listener = nil
    for connection in connections.values {
      connection.cancel()
    }
    connections.removeAll()
    decoders.removeAll()
    eventContinuation.finish()
  }

  /// Server-side kill of one accepted connection.
  public func dropConnection(_ id: Int) {
    connections[id]?.cancel()
  }

  // MARK: - Internals

  private func accept(_ connection: NWConnection) {
    let id = nextConnectionID
    nextConnectionID += 1
    connections[id] = connection
    decoders[id] = WireDecoder()
    eventContinuation.yield(Event(connection: id, kind: .connected))
    connection.start(queue: queue)
    receive(on: connection, id: id)
  }

  private func receive(on connection: NWConnection, id: Int) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
      [weak self] data, _, isComplete, error in
      guard let self else { return }
      Task {
        await self.didReceive(
          data ?? Data(), isComplete: isComplete, failed: error != nil,
          on: connection, id: id)
      }
    }
  }

  private func didReceive(
    _ data: Data, isComplete: Bool, failed: Bool, on connection: NWConnection, id: Int
  ) {
    guard connections[id] != nil else { return }
    if !data.isEmpty {
      decoders[id]?.append(data)
      do {
        while let message = try decoders[id]?.nextMessage() {
          eventContinuation.yield(Event(connection: id, kind: .message(message)))
        }
      } catch {
        close(id)
        return
      }
    }
    if failed || isComplete {
      close(id)
    } else {
      receive(on: connection, id: id)
    }
  }

  private func close(_ id: Int) {
    guard let connection = connections.removeValue(forKey: id) else { return }
    decoders[id] = nil
    connection.cancel()
    eventContinuation.yield(Event(connection: id, kind: .disconnected))
  }
}

/// Wraps a continuation so racing state callbacks can only resume it once.
private final class OnceContinuation<T: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<T, Error>?

  init(_ continuation: CheckedContinuation<T, Error>) {
    self.continuation = continuation
  }

  func resume(returning value: T) {
    take()?.resume(returning: value)
  }

  func resume(throwing error: Error) {
    take()?.resume(throwing: error)
  }

  private func take() -> CheckedContinuation<T, Error>? {
    lock.lock()
    defer { lock.unlock() }
    let taken = continuation
    continuation = nil
    return taken
  }
}
