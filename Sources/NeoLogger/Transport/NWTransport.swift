import Foundation
import Network

/// NWConnection-backed transport. Handles Bonjour discovery, TLS, and reconnection.
///
/// This type is internal-ish (public for the viewer to reuse patterns). The
/// `NeoLoggerClient` actor drives it and owns all sequencing decisions; this
/// class just wraps Network.framework primitives.
final class NWTransport: @unchecked Sendable {
  private let endpoint: TransportEndpoint
  private let queue: DispatchQueue
  private var connection: NWConnection?
  private var browser: NWBrowser?
  private var readyContinuations: [CheckedContinuation<Void, Error>] = []
  private var isStarted = false

  enum TransportError: Error, Sendable {
    case stopped
    case connectionFailed(String)
    case browserFailed(String)
  }

  init(endpoint: TransportEndpoint) {
    self.endpoint = endpoint
    self.queue = DispatchQueue(label: "neologger.transport")
  }

  /// Wait for a live connection to the viewer. Creates one if necessary.
  func waitUntilReady() async throws {
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
      queue.async {
        if let conn = self.connection, case .ready = conn.state {
          cont.resume()
          return
        }
        self.readyContinuations.append(cont)
        if !self.isStarted {
          self.isStarted = true
          self.startLocked()
        }
      }
    }
  }

  func send(_ data: Data) async throws {
    try await waitUntilReady()
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
      queue.async {
        guard let conn = self.connection else {
          cont.resume(throwing: TransportError.stopped)
          return
        }
        conn.send(
          content: data,
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

  func stop() {
    queue.async {
      self.isStarted = false
      self.connection?.cancel()
      self.connection = nil
      self.browser?.cancel()
      self.browser = nil
      self.failReadyContinuations(with: TransportError.stopped)
    }
  }

  // MARK: - Internals (run on self.queue)

  private func startLocked() {
    switch endpoint {
    case .bonjour(let serviceName, let useTLS):
      startBonjourBrowseLocked(name: serviceName, useTLS: useTLS)
    case .host(let name, let port, let useTLS):
      let host = NWEndpoint.Host(name)
      guard let nwPort = NWEndpoint.Port(rawValue: port) else {
        failReadyContinuations(with: TransportError.connectionFailed("invalid port \(port)"))
        return
      }
      connectLocked(to: .hostPort(host: host, port: nwPort), useTLS: useTLS)
    }
  }

  private func startBonjourBrowseLocked(name: String?, useTLS: Bool) {
    let serviceType = useTLS ? TransportEndpoint.sslServiceType : TransportEndpoint.plainServiceType
    let descriptor = NWBrowser.Descriptor.bonjour(type: serviceType, domain: nil)
    let params = NWParameters()
    params.includePeerToPeer = true
    let browser = NWBrowser(for: descriptor, using: params)
    self.browser = browser
    browser.browseResultsChangedHandler = { [weak self] results, _ in
      guard let self else { return }
      for result in results {
        if case .service(let svcName, _, _, _) = result.endpoint {
          if let name, svcName != name { continue }
          self.browser?.cancel()
          self.browser = nil
          self.connectLocked(to: result.endpoint, useTLS: useTLS)
          return
        }
      }
    }
    browser.stateUpdateHandler = { [weak self] state in
      if case .failed(let error) = state {
        self?.failReadyContinuations(with: TransportError.browserFailed("\(error)"))
      }
    }
    browser.start(queue: queue)
  }

  private func connectLocked(to endpoint: NWEndpoint, useTLS: Bool) {
    let params: NWParameters
    if useTLS {
      let tlsOptions = NWProtocolTLS.Options()
      // NSLogger uses a self-signed certificate on the viewer side; accept anything.
      sec_protocol_options_set_verify_block(
        tlsOptions.securityProtocolOptions,
        { _, _, completion in completion(true) },
        queue
      )
      params = NWParameters(tls: tlsOptions)
    } else {
      params = NWParameters.tcp
    }
    let conn = NWConnection(to: endpoint, using: params)
    connection = conn
    conn.stateUpdateHandler = { [weak self] state in
      guard let self else { return }
      switch state {
      case .ready:
        self.resumeReadyContinuations()
      case .failed(let error):
        self.failReadyContinuations(with: error)
        self.connection = nil
      case .cancelled:
        self.failReadyContinuations(with: TransportError.stopped)
        self.connection = nil
      default:
        break
      }
    }
    conn.start(queue: queue)
  }

  private func resumeReadyContinuations() {
    let conts = readyContinuations
    readyContinuations.removeAll()
    for c in conts { c.resume() }
  }

  private func failReadyContinuations(with error: Error) {
    let conts = readyContinuations
    readyContinuations.removeAll()
    for c in conts { c.resume(throwing: error) }
  }
}
