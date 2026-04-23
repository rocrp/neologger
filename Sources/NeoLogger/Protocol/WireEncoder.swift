import Foundation

/// Encodes `Message` values into the NSLogger binary wire format.
///
/// Wire format (all multi-byte values are big-endian):
///
///     uint32  totalSize     // size of everything after this field
///     uint16  partCount
///     [partCount parts]:
///         uint8  partKey
///         uint8  partType
///         uint32 partSize    // only for string/binary/image parts
///         bytes  value
public enum WireEncoder {
  public static func encode(_ message: Message) -> Data {
    var body = Data()
    body.reserveCapacity(64)

    appendUInt16(UInt16(message.parts.count), to: &body)
    for part in message.parts {
      appendPart(part, to: &body)
    }

    var frame = Data(capacity: body.count + 4)
    appendUInt32(UInt32(body.count), to: &frame)
    frame.append(body)
    return frame
  }

  private static func appendPart(_ part: Part, to out: inout Data) {
    out.append(part.key)
    out.append(part.value.partType.rawValue)
    switch part.value {
    case .string(let s):
      let bytes = Data(s.utf8)
      appendUInt32(UInt32(bytes.count), to: &out)
      out.append(bytes)
    case .binary(let d):
      appendUInt32(UInt32(d.count), to: &out)
      out.append(d)
    case .image(let d):
      appendUInt32(UInt32(d.count), to: &out)
      out.append(d)
    case .int16(let v):
      appendUInt16(UInt16(bitPattern: v), to: &out)
    case .int32(let v):
      appendUInt32(UInt32(bitPattern: v), to: &out)
    case .int64(let v):
      appendUInt64(UInt64(bitPattern: v), to: &out)
    }
  }

  @inline(__always)
  private static func appendUInt16(_ v: UInt16, to out: inout Data) {
    let be = v.bigEndian
    withUnsafeBytes(of: be) { out.append(contentsOf: $0) }
  }

  @inline(__always)
  private static func appendUInt32(_ v: UInt32, to out: inout Data) {
    let be = v.bigEndian
    withUnsafeBytes(of: be) { out.append(contentsOf: $0) }
  }

  @inline(__always)
  private static func appendUInt64(_ v: UInt64, to out: inout Data) {
    let be = v.bigEndian
    withUnsafeBytes(of: be) { out.append(contentsOf: $0) }
  }
}
