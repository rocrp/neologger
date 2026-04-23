import Foundation

/// Incremental decoder for the NSLogger binary wire format.
///
/// Feed bytes with `append`, then pull decoded messages via `nextMessage`
/// until it returns `nil` (meaning: need more bytes).
public struct WireDecoder: Sendable {
  public enum DecodeError: Error, Sendable {
    case truncated
    case unsupportedPartType(UInt8)
    case partSizeTooLarge(UInt32)
  }

  private var buffer: Data = .init()

  public init() {}

  public mutating func append(_ data: Data) {
    buffer.append(data)
  }

  /// Returns the next complete message in the buffer, or nil if more bytes are needed.
  /// Throws on malformed framing (unknown part type, etc).
  public mutating func nextMessage() throws -> Message? {
    guard buffer.count >= 4 else { return nil }
    let totalSize = readUInt32(at: 0)
    let needed = 4 + Int(totalSize)
    guard buffer.count >= needed else { return nil }

    let body = buffer.subdata(in: 4..<needed)
    // Drop the parsed frame before decoding so errors still advance the stream.
    buffer.removeSubrange(0..<needed)

    return try decode(body: body)
  }

  private func decode(body: Data) throws -> Message {
    var cursor = 0
    guard cursor + 2 <= body.count else { throw DecodeError.truncated }
    let partCount = Int(UInt16(bigEndian: body.subdata(in: cursor..<cursor + 2).loadUInt16()))
    cursor += 2

    var parts: [Part] = []
    parts.reserveCapacity(partCount)
    for _ in 0..<partCount {
      guard cursor + 2 <= body.count else { throw DecodeError.truncated }
      let key = body[body.startIndex + cursor]
      let typeByte = body[body.startIndex + cursor + 1]
      cursor += 2
      guard let partType = PartType(rawValue: typeByte) else {
        throw DecodeError.unsupportedPartType(typeByte)
      }
      let value: Part.Value
      switch partType {
      case .int16:
        guard cursor + 2 <= body.count else { throw DecodeError.truncated }
        let raw = body.subdata(in: cursor..<cursor + 2).loadUInt16().bigEndian
        value = .int16(Int16(bitPattern: raw))
        cursor += 2
      case .int32:
        guard cursor + 4 <= body.count else { throw DecodeError.truncated }
        let raw = body.subdata(in: cursor..<cursor + 4).loadUInt32().bigEndian
        value = .int32(Int32(bitPattern: raw))
        cursor += 4
      case .int64:
        guard cursor + 8 <= body.count else { throw DecodeError.truncated }
        let raw = body.subdata(in: cursor..<cursor + 8).loadUInt64().bigEndian
        value = .int64(Int64(bitPattern: raw))
        cursor += 8
      case .string, .binary, .image:
        guard cursor + 4 <= body.count else { throw DecodeError.truncated }
        let size = Int(body.subdata(in: cursor..<cursor + 4).loadUInt32().bigEndian)
        cursor += 4
        guard cursor + size <= body.count else { throw DecodeError.truncated }
        let chunk = body.subdata(in: cursor..<cursor + size)
        cursor += size
        switch partType {
        case .string:
          value = .string(String(decoding: chunk, as: UTF8.self))
        case .binary:
          value = .binary(chunk)
        case .image:
          value = .image(chunk)
        default:
          fatalError("unreachable")
        }
      }
      parts.append(Part(rawKey: key, value: value))
    }
    return Message(parts: parts)
  }

  private func readUInt32(at offset: Int) -> UInt32 {
    buffer.subdata(in: offset..<offset + 4).loadUInt32().bigEndian
  }
}

extension Data {
  fileprivate func loadUInt16() -> UInt16 {
    withUnsafeBytes { raw in
      raw.loadUnaligned(as: UInt16.self)
    }
  }

  fileprivate func loadUInt32() -> UInt32 {
    withUnsafeBytes { raw in
      raw.loadUnaligned(as: UInt32.self)
    }
  }

  fileprivate func loadUInt64() -> UInt64 {
    withUnsafeBytes { raw in
      raw.loadUnaligned(as: UInt64.self)
    }
  }
}
