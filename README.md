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

// 1. Fire-and-forget from sync code (recommended for app code).
NeoLog.info(.network, "Checking paper level…")
NeoLog.error(.db, "migration failed: \(error)")

// 2. Or drive the actor directly for full control.
await NeoLogger.shared.log(.view, .debug, "hello")
await NeoLogger.shared.flush()
```

By default, `NeoLogger.shared` browses Bonjour for `_nslogger._tcp`. Point at a specific host:

```swift
let logger = NeoLogger(configuration: .init(
    endpoint: .host(name: "192.168.1.20", port: 50000, useTLS: false)
))
await logger.log(.app, .info, "launched")
```

## swift-log bridge

```swift
import Logging
import NeoLoggerSwiftLog

LoggingSystem.bootstrap { NeoLogHandler(label: $0) }

let log = Logger(label: "MyApp.Network")
log.info("request completed", metadata: ["status": "200"])
```

## Viewer

This package also bundles a tiny CLI viewer — handy for tests and for running without the full NSLogger.app:

```bash
swift run neo-logger-viewer
```

It listens on `:50000`, advertises `_nslogger._tcp`, decodes arriving frames and prints one line per message. Real clients built with this library (or the original NSLogger) connect automatically via Bonjour.

## Wire format

`NeoLogger` implements the original NSLogger binary framing verbatim: `uint32 totalSize | uint16 partCount | parts…`, every multi-byte value big-endian. Part keys (`messageType`, `timestampS`, `tag`, `level`, `message`, `filename`, `lineNumber`, `functionName`, `clientInfo`, …) are modelled as typed Swift enums in `Sources/NeoLogger/Protocol/`.

The encoder and decoder are pure value types, so the protocol can be reused in tests, file replay, custom transports — anywhere.

## Testing

```bash
swift test
```

Seven tests cover wire roundtrip, framing, split-stream delivery, incomplete-frame handling, and a live end-to-end send through Network.framework.

## Status

This is a clean-room Swift reimplementation. The `Client/iOS` Objective-C/C sources from upstream NSLogger are not required and are not linked. The binary protocol is intentionally compatible so the existing `NSLogger.app` macOS viewer still works as a receiver.
