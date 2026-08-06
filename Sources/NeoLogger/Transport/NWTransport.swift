import Foundation
import Network

/// Network.framework adapter for `LogTransport`.
///
/// Owns everything below the seam: Bonjour discovery, dialing, TLS, wire
/// encoding, the client-info handshake (replayed as the first frame of every
/// new connection), and reconnection with a fixed retry delay. `send`
/// suspends while the viewer is unreachable and throws only after `stop()`
/// or on unusable configuration.
public actor NWTransport: LogTransport {
  public enum TransportError: Error, Sendable {
    case stopped
    case invalidPort(UInt16)
  }

  private let endpoint: TransportEndpoint
  private let clientInfo: ClientInfo?
  private let retryDelay: Duration
  /// Callback queue for Network.framework objects; all state lives on the actor.
  private nonisolated let queue = DispatchQueue(label: "neologger.transport")

  private var connection: NWConnection?
  private var browser: NWBrowser?
  private var isReady = false
  private var isConnecting = false
  private var retryScheduled = false
  private var isStopped = false
  private var stopReason: TransportError = .stopped
  /// Invalidates callbacks from torn-down connections/browsers.
  private var generation = 0
  private var readyWaiters: [CheckedContinuation<Void, Error>] = []

  public init(
    endpoint: TransportEndpoint,
    clientInfo: ClientInfo? = nil,
    retryDelay: Duration = .milliseconds(500)
  ) {
    self.endpoint = endpoint
    self.clientInfo = clientInfo
    self.retryDelay = retryDelay
  }

  public func send(_ message: Message) async throws {
    let frame = WireEncoder.encode(message)
    while true {
      try Task.checkCancellation()
      let conn = try await readyConnection()
      do {
        try await transmit(frame, over: conn)
        return
      } catch {
        // The connection died mid-send; tear it down and resend on a fresh
        // one. (The frame may already have reached the socket buffer — a
        // rare duplicate beats a silent drop for logging.)
        handleFailure(of: conn)
      }
    }
  }

  /// Cancel the connection and fail all pending sends. Terminal.
  public func stop() {
    isStopped = true
    teardownCurrent()
    failWaiters(with: TransportError.stopped)
  }

  // MARK: - Connection lifecycle

  private func readyConnection() async throws -> NWConnection {
    while true {
      if isStopped { throw stopReason }
      if isReady, let connection { return connection }
      startIfNeeded()
      if isStopped { throw stopReason }
      try await withCheckedThrowingContinuation { readyWaiters.append($0) }
    }
  }

  private func startIfNeeded() {
    guard !isStopped, !isConnecting, !isReady, !retryScheduled else { return }
    isConnecting = true
    generation += 1
    switch endpoint {
    case .bonjour(let serviceName, let useTLS):
      browse(serviceName: serviceName, useTLS: useTLS, generation: generation)
    case .host(let name, let port, let useTLS):
      guard let nwPort = NWEndpoint.Port(rawValue: port) else {
        // Unusable configuration: fail fast, permanently.
        isConnecting = false
        isStopped = true
        stopReason = .invalidPort(port)
        failWaiters(with: stopReason)
        return
      }
      connect(
        to: .hostPort(host: NWEndpoint.Host(name), port: nwPort), useTLS: useTLS,
        generation: generation)
    }
  }

  private func browse(serviceName: String?, useTLS: Bool, generation gen: Int) {
    let type = useTLS ? TransportEndpoint.sslServiceType : TransportEndpoint.plainServiceType
    let params = NWParameters()
    params.includePeerToPeer = true
    let browser = NWBrowser(for: .bonjour(type: type, domain: nil), using: params)
    self.browser = browser
    browser.browseResultsChangedHandler = { [weak self] results, _ in
      for result in results {
        if case .service(let name, _, _, _) = result.endpoint {
          if let serviceName, name != serviceName { continue }
          Task { await self?.browserFound(result.endpoint, useTLS: useTLS, generation: gen) }
          return
        }
      }
    }
    browser.stateUpdateHandler = { [weak self] state in
      if case .failed = state {
        Task { await self?.handleConnectFailure(generation: gen) }
      }
    }
    browser.start(queue: queue)
  }

  private func browserFound(_ found: NWEndpoint, useTLS: Bool, generation gen: Int) {
    guard gen == generation, !isStopped else { return }
    browser?.cancel()
    browser = nil
    connect(to: found, useTLS: useTLS, generation: gen)
  }

  private func connect(to remote: NWEndpoint, useTLS: Bool, generation gen: Int) {
    guard gen == generation, !isStopped else { return }
    let params: NWParameters
    if useTLS {
      let tls = NWProtocolTLS.Options()
      // NSLogger viewers use a self-signed certificate; accept anything.
      sec_protocol_options_set_verify_block(
        tls.securityProtocolOptions,
        { _, _, complete in complete(true) },
        queue
      )
      params = NWParameters(tls: tls)
    } else {
      params = .tcp
    }
    let conn = NWConnection(to: remote, using: params)
    connection = conn
    conn.stateUpdateHandler = { [weak self] state in
      switch state {
      case .ready:
        Task { await self?.connectionBecameReady(generation: gen) }
      case .failed, .cancelled:
        Task { await self?.handleConnectFailure(generation: gen) }
      default:
        break
      }
    }
    conn.start(queue: queue)
  }

  private func connectionBecameReady(generation gen: Int) {
    guard gen == generation, !isStopped, let conn = connection else { return }
    isConnecting = false
    isReady = true
    if let clientInfo {
      // First frame on every connection: the handshake. Ordering relative to
      // the resumed senders is guaranteed by the connection's send queue.
      let frame = WireEncoder.encode(.clientInfo(info: clientInfo))
      conn.send(content: frame, completion: .idempotent)
    }
    monitorPeerClose(on: conn, generation: gen)
    resumeWaiters()
  }

  /// The viewer never sends application data, so a standing receive exists
  /// purely to observe a peer close (FIN) promptly. Without it an idle
  /// connection stays `.ready` after the viewer goes away, and the next
  /// send is accepted into the dead socket and silently lost.
  private func monitorPeerClose(on conn: NWConnection, generation gen: Int) {
    conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) {
      [weak self] _, _, isComplete, error in
      guard let self else { return }
      Task {
        if isComplete || error != nil {
          await self.handleConnectFailure(generation: gen)
        } else {
          await self.rearmPeerCloseMonitor(generation: gen)
        }
      }
    }
  }

  private func rearmPeerCloseMonitor(generation gen: Int) {
    guard gen == generation, !isStopped, let conn = connection else { return }
    monitorPeerClose(on: conn, generation: gen)
  }

  private func handleConnectFailure(generation gen: Int) {
    guard gen == generation, !isStopped else { return }
    teardownCurrent()
    scheduleRetryIfNeeded()
  }

  private func handleFailure(of conn: NWConnection) {
    guard conn === connection, !isStopped else { return }
    teardownCurrent()
    // The failed sender redials immediately via readyConnection; repeated
    // dial failures are what the retry delay throttles.
  }

  private func teardownCurrent() {
    generation += 1
    connection?.cancel()
    connection = nil
    browser?.cancel()
    browser = nil
    isReady = false
    isConnecting = false
  }

  private func scheduleRetryIfNeeded() {
    guard !retryScheduled, !isStopped, !readyWaiters.isEmpty else { return }
    retryScheduled = true
    Task {
      try? await Task.sleep(for: retryDelay)
      self.retryFired()
    }
  }

  private func retryFired() {
    retryScheduled = false
    guard !readyWaiters.isEmpty else { return }
    startIfNeeded()
  }

  private func resumeWaiters() {
    let waiters = readyWaiters
    readyWaiters.removeAll()
    for waiter in waiters { waiter.resume() }
  }

  private func failWaiters(with error: Error) {
    let waiters = readyWaiters
    readyWaiters.removeAll()
    for waiter in waiters { waiter.resume(throwing: error) }
  }

  private func transmit(_ frame: Data, over conn: NWConnection) async throws {
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
      conn.send(
        content: frame,
        completion: .contentProcessed { error in
          if let error {
            cont.resume(throwing: error)
          } else {
            cont.resume()
          }
        })
    }
  }
}
