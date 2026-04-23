import Foundation

/// A single typed part inside a message.
public struct Part: Sendable, Hashable {
  public let key: UInt8
  public let value: Value

  public init(key: PartKey, value: Value) {
    self.key = key.rawValue
    self.value = value
  }

  public init(rawKey: UInt8, value: Value) {
    self.key = rawKey
    self.value = value
  }

  public enum Value: Sendable, Hashable {
    case string(String)
    case binary(Data)
    case int16(Int16)
    case int32(Int32)
    case int64(Int64)
    case image(Data)

    public var partType: PartType {
      switch self {
      case .string: .string
      case .binary: .binary
      case .int16: .int16
      case .int32: .int32
      case .int64: .int64
      case .image: .image
      }
    }
  }
}
