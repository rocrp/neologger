# Viewer-side listening lives in the library as NWMessageListener

Date: 2026-08-06
Status: Accepted

## Context

- The chunk-receive → decoder-feed loop was implemented twice: `ViewerServer` and the test target's `FrameListener` each owned NWListener setup, per-connection state, and error handling — already drifting (different error paths, different chunk sizes).
- The library shipped the codec but no listening counterpart to `NWTransport`, so every Frame consumer re-built socket plumbing.

## Decision

- A concrete public actor `NWMessageListener` in the library: binds a port (or system-assigned), optionally advertises over Bonjour, decodes Frames per connection, and yields `AsyncStream<Event>` (`connected` / `message` / `disconnected`, keyed by connection id). `dropConnection` and `stop` cover admin/test needs.
- No protocol at this seam: one adapter = a hypothetical seam. Add a protocol only when a second listener implementation exists.
- The viewer executable is format-and-print only; tests consume the same module (the transport suite doubles as the listener's integration test).

## Alternatives Considered

| Option | Result | Reason |
|---|---|---|
| Listener module with event stream | Chosen | absorbs both duplicated receive loops; one place for framing/lifecycle bugs |
| Per-connection `MessageStream` only | Rejected | both consumers immediately re-implement listener + connection lifecycle around it |
| Protocol seam for the listener | Rejected | single adapter today; hypothetical seam |

## Consequences

- + Locality: receive/framing bugs concentrate in one module; viewer is ~60 LOC of formatting.
- + Test `FrameListener` deleted; `ResumeOnce` moved into the library as the listener's internal `OnceContinuation`.
- - A listener bug can confound transport tests (accepted: the codec is covered separately by pure tests).
- ? Revisit the no-protocol call if a non-Network.framework listener (file replay, mock) ever appears.
