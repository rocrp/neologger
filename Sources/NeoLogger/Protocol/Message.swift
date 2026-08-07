import Foundation

/// The body of a log Message: text, binary data, or a PNG image.
public enum LogPayload: Sendable, Hashable {
  case text(String)
  case data(Data)
  case image(png: Data, width: Int32, height: Int32)
}

/// An NSLogger-compatible message: an ordered list of typed parts.
///
/// A valid log message must include at least `messageType`, `timestampS`, and `threadId`.
/// Builders below assemble well-formed messages; typed accessors read them back.
public struct Message: Sendable, Hashable {
  public var parts: [Part]

  public init(parts: [Part]) {
    self.parts = parts
  }
}

// MARK: - Builders

extension Message {
  /// Build a standard log message.
  public static func log(
    seq: Int32,
    timestamp: Date = Date(),
    threadId: String,
    domain: String?,
    level: Int32,
    payload: LogPayload,
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
    switch payload {
    case .text(let text):
      parts.append(.init(key: .message, value: .string(text)))
    case .data(let data):
      parts.append(.init(key: .message, value: .binary(data)))
    case .image(let png, let width, let height):
      parts.append(.init(key: .imageWidth, value: .int32(width)))
      parts.append(.init(key: .imageHeight, value: .int32(height)))
      parts.append(.init(key: .message, value: .image(png)))
    }
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

  public static func clientInfo(info: ClientInfo, timestamp: Date = Date()) -> Message {
    var parts: [Part] = [
      .init(key: .messageType, value: .int32(MessageType.clientInfo.rawValue)),
      .init(key: .timestampS, value: .int64(Int64(timestamp.timeIntervalSince1970))),
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

// MARK: - Typed reads

extension Message {
  /// Value of the first part carrying `key`, or nil.
  public subscript(key: PartKey) -> Part.Value? {
    for part in parts where part.key == key.rawValue { return part.value }
    return nil
  }

  public var type: MessageType? {
    guard let raw = int32(.messageType) else { return nil }
    return MessageType(rawValue: raw)
  }

  public var seq: Int32? { int32(.messageSeq) }
  public var level: Level? { int32(.level).map(Level.init(rawValue:)) }
  public var tag: String? { string(.tag) }
  public var threadId: String? { string(.threadId) }
  public var filename: String? { string(.filename) }
  public var lineNumber: Int32? { int32(.lineNumber) }
  public var functionName: String? { string(.functionName) }
  public var clientName: String? { string(.clientName) }

  /// The log body reassembled from parts, if this message carries one.
  public var payload: LogPayload? {
    switch self[.message] {
    case .string(let text): .text(text)
    case .binary(let data): .data(data)
    case .image(let png):
      .image(png: png, width: int32(.imageWidth) ?? 0, height: int32(.imageHeight) ?? 0)
    default: nil
    }
  }

  /// Text body, if the payload is text (also the label of a mark).
  public var text: String? {
    if case .string(let text) = self[.message] { return text }
    return nil
  }

  public var timestamp: Date? {
    guard case .int64(let seconds) = self[.timestampS] else { return nil }
    let micros = int32(.timestampUs) ?? 0
    return Date(timeIntervalSince1970: TimeInterval(seconds) + TimeInterval(micros) / 1_000_000)
  }

  private func string(_ key: PartKey) -> String? {
    if case .string(let value) = self[key] { return value }
    return nil
  }

  private func int32(_ key: PartKey) -> Int32? {
    if case .int32(let value) = self[key] { return value }
    return nil
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
