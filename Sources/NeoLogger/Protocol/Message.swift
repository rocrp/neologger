import Foundation

/// An NSLogger-compatible message: an ordered list of typed parts.
///
/// A valid log message must include at least `messageType`, `timestampS`, and `threadId`.
/// Helpers below assemble well-formed messages for the common cases.
public struct Message: Sendable, Hashable {
  public var parts: [Part]

  public init(parts: [Part]) {
    self.parts = parts
  }
}

extension Message {
  /// Build a standard log message.
  public static func log(
    seq: Int32,
    timestamp: Date = Date(),
    threadId: String,
    domain: String?,
    level: Int32,
    text: String,
    file: String? = nil,
    line: Int32? = nil,
    function: String? = nil
  ) -> Message {
    var parts: [Part] = []
    parts.append(.init(key: .messageType, value: .int32(MessageType.log.rawValue)))
    parts.append(contentsOf: timestampParts(timestamp))
    parts.append(.init(key: .threadId, value: .string(threadId)))
    parts.append(.init(key: .messageSeq, value: .int32(seq)))
    if let domain { parts.append(.init(key: .tag, value: .string(domain))) }
    parts.append(.init(key: .level, value: .int32(level)))
    parts.append(.init(key: .message, value: .string(text)))
    if let file { parts.append(.init(key: .filename, value: .string(file))) }
    if let line { parts.append(.init(key: .lineNumber, value: .int32(line))) }
    if let function { parts.append(.init(key: .functionName, value: .string(function))) }
    return Message(parts: parts)
  }

  /// Build a log message containing binary data.
  public static func logData(
    seq: Int32,
    timestamp: Date = Date(),
    threadId: String,
    domain: String?,
    level: Int32,
    data: Data,
    file: String? = nil,
    line: Int32? = nil,
    function: String? = nil
  ) -> Message {
    var parts: [Part] = []
    parts.append(.init(key: .messageType, value: .int32(MessageType.log.rawValue)))
    parts.append(contentsOf: timestampParts(timestamp))
    parts.append(.init(key: .threadId, value: .string(threadId)))
    parts.append(.init(key: .messageSeq, value: .int32(seq)))
    if let domain { parts.append(.init(key: .tag, value: .string(domain))) }
    parts.append(.init(key: .level, value: .int32(level)))
    parts.append(.init(key: .message, value: .binary(data)))
    if let file { parts.append(.init(key: .filename, value: .string(file))) }
    if let line { parts.append(.init(key: .lineNumber, value: .int32(line))) }
    if let function { parts.append(.init(key: .functionName, value: .string(function))) }
    return Message(parts: parts)
  }

  /// Build a log message containing a PNG-encoded image.
  public static func logImage(
    seq: Int32,
    timestamp: Date = Date(),
    threadId: String,
    domain: String?,
    level: Int32,
    pngData: Data,
    width: Int32,
    height: Int32,
    file: String? = nil,
    line: Int32? = nil,
    function: String? = nil
  ) -> Message {
    var parts: [Part] = []
    parts.append(.init(key: .messageType, value: .int32(MessageType.log.rawValue)))
    parts.append(contentsOf: timestampParts(timestamp))
    parts.append(.init(key: .threadId, value: .string(threadId)))
    parts.append(.init(key: .messageSeq, value: .int32(seq)))
    if let domain { parts.append(.init(key: .tag, value: .string(domain))) }
    parts.append(.init(key: .level, value: .int32(level)))
    parts.append(.init(key: .imageWidth, value: .int32(width)))
    parts.append(.init(key: .imageHeight, value: .int32(height)))
    parts.append(.init(key: .message, value: .image(pngData)))
    if let file { parts.append(.init(key: .filename, value: .string(file))) }
    if let line { parts.append(.init(key: .lineNumber, value: .int32(line))) }
    if let function { parts.append(.init(key: .functionName, value: .string(function))) }
    return Message(parts: parts)
  }

  public static func mark(seq: Int32, timestamp: Date = Date(), text: String) -> Message {
    var parts: [Part] = []
    parts.append(.init(key: .messageType, value: .int32(MessageType.mark.rawValue)))
    parts.append(contentsOf: timestampParts(timestamp))
    parts.append(.init(key: .messageSeq, value: .int32(seq)))
    parts.append(.init(key: .message, value: .string(text)))
    return Message(parts: parts)
  }

  public static func clientInfo(info: ClientInfo) -> Message {
    var parts: [Part] = [
      .init(key: .messageType, value: .int32(MessageType.clientInfo.rawValue)),
      .init(key: .timestampS, value: .int64(Int64(Date().timeIntervalSince1970))),
      .init(key: .threadId, value: .string("main")),
      .init(key: .clientName, value: .string(info.name)),
      .init(key: .clientVersion, value: .string(info.version)),
      .init(key: .osName, value: .string(info.osName)),
      .init(key: .osVersion, value: .string(info.osVersion)),
    ]
    if let model = info.model {
      parts.append(.init(key: .clientModel, value: .string(model)))
    }
    if let uniqueID = info.uniqueID {
      parts.append(.init(key: .uniqueId, value: .string(uniqueID)))
    }
    return Message(parts: parts)
  }

  private static func timestampParts(_ date: Date) -> [Part] {
    let t = date.timeIntervalSince1970
    let seconds = Int64(t.rounded(.down))
    let fractional = t - Double(seconds)
    let micros = Int32((fractional * 1_000_000.0).rounded())
    return [
      .init(key: .timestampS, value: .int64(seconds)),
      .init(key: .timestampUs, value: .int32(micros)),
    ]
  }
}

public struct ClientInfo: Sendable, Hashable {
  public var name: String
  public var version: String
  public var osName: String
  public var osVersion: String
  public var model: String?
  public var uniqueID: String?

  public init(
    name: String,
    version: String,
    osName: String,
    osVersion: String,
    model: String? = nil,
    uniqueID: String? = nil
  ) {
    self.name = name
    self.version = version
    self.osName = osName
    self.osVersion = osVersion
    self.model = model
    self.uniqueID = uniqueID
  }
}
