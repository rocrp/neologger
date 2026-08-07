# Testing NeoLogger

Three levels, pick whichever you need.

## 1. Automated tests

```bash
swift test
```

Covers (five suites):

- **WireProtocolTests** — encode/decode roundtrip, big-endian framing, split byte streams, incomplete frames, oversized-frame rejection, `ClientInfo` builder.
- **MessageAccessorTests** — typed reads (`type`/`seq`/`level`/`tag`/`text`/`payload`/`timestamp`/…) and `Level.name`.
- **NeoLoggerActorTests** — the client actor through an in-process `RecordingTransport`: call-order + contiguous sequence from sync call sites, caller-thread labels, drop-oldest buffering (in-flight message never evicted), requeue when the transport throws, `flush()` waiting for the in-flight ack, all seven severity shortcuts.
- **NeoLogHandlerTests** — the swift-log bridge end to end (level mapping, label → tag, metadata rendering, threshold).
- **NWTransportTests** — `NWTransport` ↔ `NWMessageListener` over loopback sockets on a system-assigned port: handshake precedes the first frame, reconnection replays the handshake after the viewer drops the connection, `flush()` through the real transport, delivery of a single post-drop log on a fresh connection, and a TLS connection to a listener serving a self-signed certificate.

No viewer or other service needs to be running. Runs in about a second on an M-series Mac.

Not covered automatically: the **Bonjour browse path** — mDNS is machine-wide and flaky to assert on, so it is verified by the smoke test and the HIL checklist below instead. See [ADR: Bonjour browse is verified by HIL only](docs/adr/20260807-bonjour-browse-is-hil-only.md).

The TLS test is the one exception to "no external processes": it shells out to `/usr/bin/openssl` to mint a throwaway self-signed identity (`Tests/NeoLoggerTests/TLSIdentityFixture.swift`), because no public API self-signs a certificate. The identity is imported with `kSecImportToMemoryOnly`, so it never reaches a keychain — that constant needs macOS 15, and on older systems the test is skipped rather than allowed to leave a private key behind.

## 2. Two-terminal smoke test

Terminal 1 — receiver:

```bash
swift run neo-logger-viewer          # or: swift run neo-logger-viewer 50123
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

# Or over TLS — browses _nslogger-ssl._tcp, which NSLogger.app always
# advertises. neo-logger-viewer is plain TCP only, so use NSLogger.app here.
swift run neo-logger-demo --tls
```

Expected in terminal 1:

```
[viewer] client #0 connected
[#0] CLIENT neo-logger-demo
[#0] IMPO  [App]     DemoCLI.swift:51 demo starting
[#0] INFO  [Network] DemoCLI.swift:52 GET https://example.com → 200
[#0] DEBUG [DB]      DemoCLI.swift:53 SELECT * FROM users WHERE id = 42
[#0] WARN  [View]    DemoCLI.swift:54 tableView reload on background thread
[#0] ERROR [App]     DemoCLI.swift:55 something went wrong: Error Domain=demo Code=1 "(null)"
[#0] VERB  [IO]      DemoCLI.swift:56 <binary 8 bytes>
[#0] MARK demo mark
[viewer] client #0 closed
```

If nothing arrives, check:

- Terminal 1 actually reached the `listening on port 50000` line before you ran the demo.
- No other process is bound to :50000 (`lsof -i :50000`).
- Explicit `127.0.0.1 50000` works but Bonjour doesn't → firewall or a local-network entitlement issue.

## 3. Against the real NSLogger.app (HIL checklist)

The wire format is identical, so the existing macOS viewer works as a drop-in receiver. This checklist is the release gate — it covers the paths no automated test reaches (Bonjour browse, the real viewer's parser, TLS end to end).

Launch `NSLogger.app` (from [fpillet/NSLogger releases](https://github.com/fpillet/NSLogger/releases)), then:

| # | Step | Expect |
|---|---|---|
| 1 | `swift run neo-logger-demo` (no args — exercises **Bonjour browse**) | client row appears without any host/port given |
| 2 | Inspect the client row | CLIENTINFO name `neo-logger-demo`, version, OS name/version |
| 3 | Inspect the message rows | levels colour the rows (warning amber, error red); tags render as domains with the numeric level beside them |
| 3b | `file:line` — off by default. Enable per client, then relaunch NSLogger.app:<br>`defaults write com.florentpillet.NSLogger clientApplicationSettings -dict-add "neo-logger-demo" '{"_showFunctionNames" = 1;}'` | each row gains a `main() (DemoCLI.swift:51)` header |
| 4 | The `.io` verbose row and the mark | binary shown as a data/hex row; `demo mark` as a mark row |
| 5 | `swift run neo-logger-demo --forever`, then quit and relaunch NSLogger.app mid-run | client reconnects on its own and the new session starts with CLIENTINFO again |
| 6 | `swift run neo-logger-demo --tls` (NSLogger.app serves SSL unconditionally — no preference to flip) | messages arrive over TLS; the viewer's self-signed cert is accepted |
| 7 | Optional: `NeoLog.info` from a real iOS app (see §4) | messages arrive from the device |

Steps 1, 5 and 6 are the ones with no automated equivalent: Bonjour browse (by decision, see the ADR above), reconnect against the real app, and `_nslogger-ssl._tcp` discovery. Step 6's transport-level TLS *is* covered by `swift test`; what HIL adds is the real viewer's certificate and the SSL service type.

## 4. From your own iOS/macOS app

Add NeoLogger as an SPM dependency, then:

```swift
import NeoLogger

NeoLog.info(.network, "hello from my app")  // synchronous, works anywhere
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
