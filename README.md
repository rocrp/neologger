# NeoLogger

Modern Swift rewrite of [NSLogger](https://github.com/fpillet/NSLogger) — a network logger for iOS/macOS apps that streams traces to a desktop viewer.

- Pure Swift; no Objective-C, no C, no CFNetwork
- Built on **Network.framework** and Swift concurrency
- Wire-compatible with the existing NSLogger desktop viewer
- Ships a `swift-log` `LogHandler` bridge
- Swift 6 language mode, strict concurrency, actor-isolated client
- SPM, no third-party runtime deps (aside from `apple/swift-log`)

## Install

```swift
dependencies: [
    .package(url: "https://github.com/<you>/neologger", from: "0.1.0"),
]
```

Targets pick one of:

- `NeoLogger` — the core client
- `NeoLoggerSwiftLog` — a `swift-log` `LogHandler`

## Basic usage

```swift
import NeoLogger

// Every logging call is synchronous, non-blocking, and call-ordered.
// `NeoLog` is shorthand for `NeoLogger.shared`.
NeoLog.info(.network, "Checking paper level…")
NeoLog.error(.db, "migration failed: \(error)")
NeoLog.warning("works without a domain too")

// Own instance + waiting for delivery:
let logger = NeoLogger()
logger.log(.view, .debug, "hello")
await logger.flush()  // suspends until every accepted message is acked
```

By default, `NeoLogger.shared` browses Bonjour for `_nslogger._tcp`. Point at a specific host:

```swift
let logger = NeoLogger(configuration: .init(
    endpoint: .host(name: "192.168.1.20", port: 50000, useTLS: false)
))
logger.log(.app, .info, "launched")
```

## swift-log bridge

```swift
import Logging
import NeoLoggerSwiftLog

LoggingSystem.bootstrap { NeoLogHandler(label: $0) }

let log = Logger(label: "MyApp.Network")
log.info("request completed", metadata: ["status": "200"])
```

## Custom transports

`NeoLogger` sends through a one-method seam:

```swift
public protocol LogTransport: Sendable {
  func send(_ message: Message) async throws
}
```

`send` suspends until the message is handed off and acknowledged; the adapter owns reconnection, wire encoding, and the client-info handshake. `NWTransport` is the default adapter (Bonjour/TLS/reconnect). Inject your own for tests or other sinks:

```swift
let logger = NeoLogger(configuration: .init(), transport: MyTransport())
```

## Viewer

This package also bundles a tiny CLI viewer — handy for tests and for running without the full NSLogger.app:

```bash
swift run neo-logger-viewer            # listens on :50000
swift run neo-logger-viewer 50123      # or any port
```

It advertises `_nslogger._tcp`, decodes arriving frames and prints one line per message. Real clients built with this library (or the original NSLogger) connect automatically via Bonjour. The listening/decoding half lives in the library as `NWMessageListener` — the executable is just the print format.

## Wire format

`NeoLogger` implements the original NSLogger binary framing verbatim: `uint32 totalSize | uint16 partCount | parts…`, every multi-byte value big-endian. Part keys (`messageType`, `timestampS`, `tag`, `level`, `message`, `filename`, `lineNumber`, `functionName`, `clientInfo`, …) are modelled as typed Swift enums in `Sources/NeoLogger/Protocol/`.

The encoder and decoder are pure value types, so the protocol can be reused in tests, file replay, custom transports — anywhere. Decoded messages read back through typed accessors (`message.level`, `.tag`, `.text`, `.payload`, `.timestamp`, …).

## Testing

```bash
swift test
```

Twenty-three tests cover the wire codec (roundtrip, framing, split streams, oversized-frame rejection), typed Message reads, the client actor through an in-process transport (call-order guarantee, caller-thread labels, drop-oldest buffering, requeue-on-failure, the flush contract), the swift-log bridge, and `NWTransport` ↔ `NWMessageListener` over local sockets (handshake-first, reconnection with handshake replay, delivery after a viewer drop).

## Status

This is a clean-room Swift reimplementation. The `Client/iOS` Objective-C/C sources from upstream NSLogger are not required and are not linked. The binary protocol is intentionally compatible so the existing `NSLogger.app` macOS viewer still works as a receiver.
