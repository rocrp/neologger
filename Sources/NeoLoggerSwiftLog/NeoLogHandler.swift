import Foundation
import Logging
import NeoLogger

/// A `swift-log` `LogHandler` that sends messages through `NeoLogger`.
///
/// Usage:
/// ```swift
/// LoggingSystem.bootstrap { NeoLogHandler(label: $0) }
/// ```
public struct NeoLogHandler: LogHandler {
  public var logLevel: Logger.Level = .info
  public var metadata: Logger.Metadata = [:]

  /// The logger's label, mapped to the NSLogger `tag` field.
  public let label: String

  private let client: NeoLogger

  public init(label: String, client: NeoLogger = NeoLogger.shared) {
    self.label = label
    self.client = client
  }

  public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
    get { metadata[key] }
    set { metadata[key] = newValue }
  }

  public func log(event: LogEvent) {
    let merged = self.metadata.merging(event.metadata ?? [:]) { _, new in new }
    let text =
      merged.isEmpty
      ? event.message.description
      : "\(event.message.description) \(Self.formatMetadata(merged))"

    client.log(
      Domain(rawValue: label),
      Self.map(event.level),
      text,
      file: event.file,
      line: Int(clamping: event.line),
      function: event.function
    )
  }

  private static func map(_ level: Logger.Level) -> Level {
    switch level {
    case .trace: .noise
    case .debug: .debug
    case .info: .info
    case .notice: .important
    case .warning: .warning
    case .error: .error
    case .critical: .error
    }
  }

  private static func formatMetadata(_ meta: Logger.Metadata) -> String {
    meta.sorted(by: { $0.key < $1.key })
      .map { "\($0.key)=\($0.value)" }
      .joined(separator: " ")
  }
}
