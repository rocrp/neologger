# Transport seam carries Messages; adapter owns encoding, handshake, reconnection

Date: 2026-08-06
Status: Accepted

## Context

- `NeoLogger` (actor) constructed its own `NWTransport` in `init` — no seam. Buffering, the Handshake, and retry were untestable without real sockets; three defects hid there: reconnect wedge (`isStarted` never reset after `.failed`, Bonjour browser never re-browsed), `flush()` returning before sends were acked (demo + E2E compensated with sleeps), and loss of the in-flight message when `send` threw.
- Wire encoding leaked above the transport: the drain loop called `WireEncoder.encode` and tracked `hasSentClientInfo` itself.

## Decision

- Public seam: `protocol LogTransport: Sendable { func send(_ message: Message) async throws }`.
- `send` suspends until the message is handed off and acknowledged; the adapter owns reconnection (fresh Bonjour browse per attempt, fixed retry delay, injectable for tests). It throws only terminally (stopped / cancelled / invalid config).
- The adapter owns wire encoding and replays the Handshake as the first frame of every new connection.
- The adapter keeps a standing receive on each connection purely to observe a peer close (FIN) promptly. Without it an idle connection stays `.ready` after the Viewer goes away and the next send is accepted into the dead socket and silently lost.
- `NeoLogger` owns only: message building, sequencing, the bounded buffer (drop-oldest; the in-flight message is never evicted and is re-queued on terminal failure), and `flush()` = every accepted message acked.
- Do not: move readiness/retry back into the actor; do not carry `Data` across the seam.

## Alternatives Considered

| Option | Result | Reason |
|---|---|---|
| Message-level seam; adapter owns encoding + Handshake | Chosen | Handshake is coupled to connection lifecycle only the adapter observes; wire format genuinely varies per adapter (file replay / other encodings) |
| Data-level `send(Data)` | Rejected | Leaves encoder + Handshake state in the actor — the exact leak being removed |
| Actor-driven retry (`send` throws, actor backs off) | Rejected | Splits one connection state machine across two modules; the wedge bug lived in that split |
| Internal-only seam (`@testable`) | Rejected | README promises custom transports; a one-method public protocol is cheap and two in-repo adapters already exist |

## Consequences

- + Actor behavior (drop-oldest, ordering, no-loss, flush) tests run in-process against a recording transport; the wedge reproduction is an `NWTransport` adapter test over local sockets.
- + `flush()` contract is real: continuation-based, no polling; demo's compensating sleep deleted.
- - `flush()` may wait indefinitely while no Viewer is reachable (accepted; callers race a timeout if they need a bound).
- - Handshake timestamp is now built per connection instead of frozen at logger init; benign for viewers.
- ? Revisit the protocol shape if a second wire format needs framing policy above the adapter.

## Notes

- The wedge was confirmed by running a black-box repro against the pre-seam tree in a worktree (test failed: no second connection ever appeared). The same repro then ALSO failed on the first seam implementation — `NWConnection.cancel()` on the peer is a graceful FIN, the idle client connection stayed `.ready`, and the single post-drop send was silently swallowed. The peer-close monitor exists because of that second failure; the scenario is pinned by `aSingleLogAfterAViewerDropIsDeliveredOnANewConnection`.
- Delivery guarantee is "handed to the connection and acknowledged by the network stack" (`contentProcessed`), not end-to-end: NSLogger's wire protocol has no application-level acks, so a frame written in the instant between peer close and its detection can still be lost. Do not promise stronger semantics without protocol changes.
- Remaining review candidates (log-record intake, shared frame receiver, typed Message reads) are independent of this seam and still open.
