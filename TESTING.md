# Testing NeoLogger

Three levels, pick whichever you need.

## 1. Automated tests

```bash
swift test
```

Covers:

- **WireProtocolTests** — encode/decode roundtrip, big-endian framing, split byte streams, incomplete frames, `ClientInfo` builder.
- **NeoLoggerActorTests** — the client actor through an in-process `RecordingTransport`: ordering + sequence, drop-oldest buffering (in-flight message never evicted), requeue when the transport throws, and `flush()` waiting for the in-flight ack.
- **NWTransportTests** — the `NWTransport` adapter over loopback sockets on a system-assigned port: handshake precedes the first frame, reconnection replays the handshake after the viewer drops the connection, `flush()` through the real transport, and delivery of a single post-drop log on a fresh connection.

No external processes needed. Runs in under a second on an M-series Mac.

## 2. Two-terminal smoke test

Terminal 1 — receiver:

```bash
swift run neo-logger-viewer
# [viewer] listening on port 50000 (Bonjour: _nslogger._tcp)
```

Terminal 2 — sender:

```bash
# Bonjour auto-discovery (default)
swift run neo-logger-demo

# Or explicit host:port (skips Bonjour)
swift run neo-logger-demo 127.0.0.1 50000

# Or continuous heartbeat until Ctrl-C
swift run neo-logger-demo --forever
```

Expected in terminal 1:

```
[viewer] client XXXXXXXX connecting
[XXXXXXXX] CLIENT neo-logger-demo
[XXXXXXXX] IMPO  [App]     DemoCLI.swift:38 demo starting
[XXXXXXXX] INFO  [Network] DemoCLI.swift:39 GET https://example.com → 200
[XXXXXXXX] DEBUG [DB]      DemoCLI.swift:40 SELECT * FROM users WHERE id = 42
[XXXXXXXX] WARN  [View]    DemoCLI.swift:41 tableView reload on background thread
[XXXXXXXX] ERROR [App]     DemoCLI.swift:42 something went wrong: …
[XXXXXXXX] VERB  [IO]      DemoCLI.swift:43 <binary 8 bytes>
[XXXXXXXX] MARK demo mark
```

If nothing arrives, check:

- Terminal 1 actually reached the `listening on port 50000` line before you ran the demo.
- No other process is bound to :50000 (`lsof -i :50000`).
- Explicit `127.0.0.1 50000` works but Bonjour doesn't → firewall or a local-network entitlement issue.

## 3. Against the real NSLogger.app

The wire format is identical, so the existing macOS viewer works as a drop-in receiver.

1. Launch `NSLogger.app` (download from [fpillet/NSLogger releases](https://github.com/fpillet/NSLogger/releases)).
2. `swift run neo-logger-demo` — a client row appears in its sidebar and messages stream in.
3. Tags → domains, numeric levels → level column, image/binary frames → inline preview.

## 4. From your own iOS/macOS app

Add NeoLogger as an SPM dependency, then:

```swift
import NeoLogger

await NeoLogger.shared.log(.network, .info, "hello from my app")
// or, from sync code:
NeoLog.info(.network, "hello from my app")
```

With `neo-logger-viewer` (or `NSLogger.app`) running on the same network, logs appear immediately. On iOS 14+ add to Info.plist so the OS allows local-network access:

```xml
<key>NSBonjourServices</key>
<array>
    <string>_nslogger._tcp</string>
    <string>_nslogger-ssl._tcp</string>
</array>
<key>NSLocalNetworkUsageDescription</key>
<string>Send debug logs to the developer's Mac</string>
```

## 5. Inspecting the wire bytes

For debugging the protocol itself:

```swift
let frame = WireEncoder.encode(message)
print(frame.map { String(format: "%02x", $0) }.joined(separator: " "))
```

Or decode a captured stream:

```swift
var decoder = WireDecoder()
decoder.append(capturedData)
while let m = try decoder.nextMessage() {
    print(m.parts)
}
```

Both types are pure value types in `Sources/NeoLogger/Protocol/`, so they work fine in tests, CLI tools, or Xcode playgrounds.
