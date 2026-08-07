import Foundation

/// Where the logger should send its traces.
public enum TransportEndpoint: Sendable, Hashable {
  /// Discover an NSLogger viewer on the local network via Bonjour.
  case bonjour(serviceName: String? = nil, useTLS: Bool = false)

  /// Connect to a specific host and port.
  case host(name: String, port: UInt16, useTLS: Bool = false)
}

extension TransportEndpoint {
  /// Bonjour service types used by the NSLogger viewer.
  public static let plainServiceType = "_nslogger._tcp"
  public static let sslServiceType = "_nslogger-ssl._tcp"
}
