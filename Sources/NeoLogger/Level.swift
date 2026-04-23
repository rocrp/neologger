import Foundation

/// Log severity. Lower numbers are more severe.
///
/// Mirrors NSLogger's numeric levels so traces display the same way in the
/// existing NSLogger macOS viewer.
public struct Level: RawRepresentable, Sendable, Hashable {
  public let rawValue: Int32
  public init(rawValue: Int32) { self.rawValue = rawValue }

  public static let error = Level(rawValue: 0)
  public static let warning = Level(rawValue: 1)
  public static let important = Level(rawValue: 2)
  public static let info = Level(rawValue: 3)
  public static let debug = Level(rawValue: 4)
  public static let verbose = Level(rawValue: 5)
  public static let noise = Level(rawValue: 6)

  public static func custom(_ value: Int32) -> Level { Level(rawValue: value) }
}

/// A logical grouping tag (maps to NSLogger's tag/domain field).
public struct Domain: RawRepresentable, Sendable, Hashable, ExpressibleByStringLiteral {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }
  public init(stringLiteral value: String) { self.rawValue = value }

  public static let app: Domain = "App"
  public static let view: Domain = "View"
  public static let layout: Domain = "Layout"
  public static let controller: Domain = "Controller"
  public static let routing: Domain = "Routing"
  public static let service: Domain = "Service"
  public static let network: Domain = "Network"
  public static let model: Domain = "Model"
  public static let cache: Domain = "Cache"
  public static let db: Domain = "DB"
  public static let io: Domain = "IO"

  public static func custom(_ value: String) -> Domain { Domain(rawValue: value) }
}
