import Foundation
import Logging
import NeoLogger
import NeoLoggerSwiftLog
import Testing

@Suite("swift-log bridge")
struct NeoLogHandlerTests {
  @Test func bridgesLevelTagAndMetadata() async throws {
    let transport = RecordingTransport()
    let client = NeoLogger(configuration: NeoLoggerConfiguration(), transport: transport)
    let logger = Logger(label: "Test.Bridge") { NeoLogHandler(label: $0, client: client) }

    logger.info("hello", metadata: ["k": "v"])
    logger.error("boom")
    await client.flush()

    let sent = await transport.sent
    #expect(sent.compactMap(\.text) == ["hello k=v", "boom"])
    #expect(sent.first?.level == .info)
    #expect(sent.last?.level == .error)
    #expect(sent.first?.tag == "Test.Bridge")
  }

  @Test func respectsTheHandlersLogLevelThreshold() async throws {
    let transport = RecordingTransport()
    let client = NeoLogger(configuration: NeoLoggerConfiguration(), transport: transport)
    let logger = Logger(label: "T") { NeoLogHandler(label: $0, client: client) }

    logger.debug("dropped")  // below the default .info threshold
    logger.info("kept")
    await client.flush()

    #expect(await transport.sent.compactMap(\.text) == ["kept"])
  }
}
