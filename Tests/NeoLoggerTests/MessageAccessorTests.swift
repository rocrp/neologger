import Foundation
import NeoLogger
import Testing

@Suite("Message typed reads")
struct MessageAccessorTests {
  @Test func logAccessorsRoundtrip() throws {
    let ts = Date(timeIntervalSince1970: 1_700_000_000.5)
    let message = Message.log(
      seq: 7, timestamp: ts, threadId: "main", domain: "Net",
      level: Level.warning.rawValue, payload: .text("hi"),
      file: "A/B.swift", line: 12, function: "f()")

    #expect(message.type == .log)
    #expect(message.seq == 7)
    #expect(message.tag == "Net")
    #expect(message.level == .warning)
    #expect(message.text == "hi")
    #expect(message.payload == .text("hi"))
    #expect(message.threadId == "main")
    #expect(message.filename == "A/B.swift")
    #expect(message.lineNumber == 12)
    #expect(message.functionName == "f()")

    let timestamp = try #require(message.timestamp)
    #expect(abs(timestamp.timeIntervalSince1970 - ts.timeIntervalSince1970) < 0.001)
  }

  @Test func payloadVariantsReassemble() {
    let data = Message.log(
      seq: 1, threadId: "t", domain: nil, level: 0, payload: .data(Data([1, 2, 3])))
    #expect(data.payload == .data(Data([1, 2, 3])))
    #expect(data.text == nil)

    let image = Message.log(
      seq: 2, threadId: "t", domain: nil, level: 0,
      payload: .image(png: Data([9]), width: 640, height: 480))
    #expect(image.payload == .image(png: Data([9]), width: 640, height: 480))
  }

  @Test func clientInfoReads() {
    let message = Message.clientInfo(
      info: ClientInfo(name: "App", version: "1", osName: "macOS", osVersion: "14"))
    #expect(message.type == .clientInfo)
    #expect(message.clientName == "App")
  }

  @Test func levelNames() {
    #expect(Level.error.name == "ERROR")
    #expect(Level.important.name == "IMPO")
    #expect(Level.noise.name == "NOISE")
    #expect(Level(rawValue: 9).name == "L9")
  }
}
