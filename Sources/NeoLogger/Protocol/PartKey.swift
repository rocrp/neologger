import Foundation

/// Part key byte. Values < 100 are reserved; user defined keys start at 100.
/// See NSLogger `LoggerCommon.h` for the canonical definitions.
public enum PartKey: UInt8, Sendable, Hashable {
  case messageType = 0
  case timestampS = 1
  case timestampMs = 2
  case timestampUs = 3
  case threadId = 4
  case tag = 5
  case level = 6
  case message = 7
  case imageWidth = 8
  case imageHeight = 9
  case messageSeq = 10
  case filename = 11
  case lineNumber = 12
  case functionName = 13

  case clientName = 20
  case clientVersion = 21
  case osName = 22
  case osVersion = 23
  case clientModel = 24
  case uniqueId = 25
}

public enum PartType: UInt8, Sendable, Hashable {
  case string = 0
  case binary = 1
  case int16 = 2
  case int32 = 3
  case int64 = 4
  case image = 5
}

public enum MessageType: Int32, Sendable, Hashable {
  case log = 0
  case blockStart = 1
  case blockEnd = 2
  case clientInfo = 3
  case disconnect = 4
  case mark = 5
}
