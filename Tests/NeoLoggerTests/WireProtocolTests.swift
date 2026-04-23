import Foundation
import Testing

@testable import NeoLogger

@Suite("Wire protocol")
struct WireProtocolTests {
  @Test("Frame layout: uint32 total size + uint16 part count")
  func frameHeader() {
    let message = Message(parts: [
      Part(key: .messageType, value: .int32(MessageType.log.rawValue)),
      Part(key: .timestampS, value: .int64(0)),
      Part(key: .message, value: .string("hi")),
    ])
    let data = WireEncoder.encode(message)

    // First four bytes: size of remainder.
    let total = UInt32(
      bigEndian: data.subdata(in: 0..<4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
    #expect(Int(total) == data.count - 4)

    // Next two bytes: part count.
    let partCount = UInt16(
      bigEndian: data.subdata(in: 4..<6).withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) })
    #expect(partCount == 3)
  }

  @Test("Roundtrip: every part type")
  func roundtrip() throws {
    let message = Message(parts: [
      Part(key: .messageType, value: .int32(MessageType.log.rawValue)),
      Part(key: .timestampS, value: .int64(1_700_000_000)),
      Part(key: .timestampUs, value: .int32(123_456)),
      Part(key: .threadId, value: .string("main")),
      Part(key: .messageSeq, value: .int32(1)),
      Part(key: .tag, value: .string("Network")),
      Part(key: .level, value: .int32(3)),
      Part(key: .message, value: .string("hello world")),
      Part(key: .imageWidth, value: .int16(640)),
      Part(key: .imageHeight, value: .int16(480)),
      Part(rawKey: 100, value: .binary(Data([0x01, 0x02, 0x03, 0xFF]))),
    ])

    let encoded = WireEncoder.encode(message)
    var decoder = WireDecoder()
    decoder.append(encoded)
    let decoded = try decoder.nextMessage()
    #expect(decoded == message)
  }

  @Test("Decoder handles split byte streams")
  func splitStream() throws {
    let m1 = Message.log(
      seq: 1, timestamp: Date(timeIntervalSince1970: 1_000), threadId: "t", domain: "A", level: 0,
      text: "first")
    let m2 = Message.log(
      seq: 2, timestamp: Date(timeIntervalSince1970: 1_001), threadId: "t", domain: "B", level: 1,
      text: "second")
    let wire = WireEncoder.encode(m1) + WireEncoder.encode(m2)

    var decoder = WireDecoder()
    var decoded: [Message] = []
    for byte in wire {
      decoder.append(Data([byte]))
      while let m = try decoder.nextMessage() { decoded.append(m) }
    }
    #expect(decoded == [m1, m2])
  }

  @Test("Decoder returns nil when frame is incomplete")
  func incompleteFrame() throws {
    let message = Message.log(seq: 1, threadId: "t", domain: "A", level: 0, text: "x")
    let wire = WireEncoder.encode(message)

    var decoder = WireDecoder()
    decoder.append(wire.prefix(wire.count - 1))
    #expect(try decoder.nextMessage() == nil)

    decoder.append(wire.suffix(1))
    #expect(try decoder.nextMessage() == message)
  }

  @Test("Big-endian int encoding")
  func bigEndianInts() {
    let message = Message(parts: [Part(key: .lineNumber, value: .int32(0x0102_0304))])
    let data = WireEncoder.encode(message)
    // Layout: [4 total][2 count][1 key][1 type][4 value]
    let valueBytes = Array(data.suffix(4))
    #expect(valueBytes == [0x01, 0x02, 0x03, 0x04])
  }

  @Test("ClientInfo builder populates expected parts")
  func clientInfo() {
    let info = ClientInfo(
      name: "App",
      version: "1.0",
      osName: "macOS",
      osVersion: "14.0",
      model: "Mac",
      uniqueID: "abc"
    )
    let message = Message.clientInfo(info: info)
    let keys = message.parts.map(\.key)
    #expect(keys.contains(PartKey.messageType.rawValue))
    #expect(keys.contains(PartKey.clientName.rawValue))
    #expect(keys.contains(PartKey.clientVersion.rawValue))
    #expect(keys.contains(PartKey.osName.rawValue))
    #expect(keys.contains(PartKey.osVersion.rawValue))
    #expect(keys.contains(PartKey.clientModel.rawValue))
    #expect(keys.contains(PartKey.uniqueId.rawValue))
  }
}
