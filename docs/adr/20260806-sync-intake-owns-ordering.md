# Logging entry points are synchronous; the Intake assigns order

Date: 2026-08-06
Status: Accepted

## Context

- Fire-and-forget logging was per-call `Task.detached` in two places (the `NeoLog` enum and `NeoLogHandler`): cross-call ordering and `messageSeq` were task-scheduling order, timestamps were assigned at drain time, and the thread label was captured on the actor's executor — always a meaningless pool thread, never the caller's.
- `NeoLog` was hardwired to `.shared` while `NeoLogger` supports instances, and its convenience surface had drifted (no image API, missing `.important`/`.noise`).
- One concept — "a log Message" — was assembled by three near-identical builders × three actor methods × five shortcuts (11 edit sites to add a field).

## Decision

- Every logging entry point is a `nonisolated` synchronous method on the `NeoLogger` actor. A lock-guarded `Intake` assigns sequence number and timestamp atomically at the call site: intra-thread call order is a guaranteed invariant (cross-thread order = lock acquisition order). The thread label is the caller's.
- The three `Message` builders collapse into one `Message.log(payload:)` taking `LogPayload` (`.text` / `.data` / `.image`); adding a field is a one-builder edit.
- The `NeoLog` module is deleted; `public let NeoLog = NeoLogger.shared` preserves the call-site idiom (`NeoLog.info(...)`) with zero forwarding code. Message-only severity overloads exist because `Domain` is `ExpressibleByStringLiteral` — `error("boom")` would otherwise bind the string to the Domain slot and fail to compile.
- Drain-kick contract: at most one live drain, guarded by `Intake.drainScheduled`; `append` returns whether the caller must kick.
- Do not: reintroduce per-call `Task` spawning in any logging frontend; do not move sequence assignment back into the actor.

## Alternatives Considered

| Option | Result | Reason |
|---|---|---|
| nonisolated sync intake + lock | Chosen | call-order guarantee, caller-thread label, call-site timestamps, zero per-call task churn |
| `Task.detached` per call (status quo) | Rejected | unordered, unbounded task creation, wrong thread label — the defects being removed |
| `AsyncStream` as the intake | Rejected | cannot assign seq atomically with enqueue; drop-oldest eviction needs the buffer, still needs a lock |

## Consequences

- + Ordering and thread-label are in-process testable (`syncCallsArriveInCallOrderWithContiguousSequence`, `capturesTheCallersThreadLabel`).
- + `NeoLog.swift` deleted; `NeoLogHandler` drops its `Task.detached`; full 7-level shortcut set.
- - Each log call takes a short lock and builds the Message on the caller's thread (bounded work, no I/O) — acceptable for a logging intake; do not add I/O there.
- - Breaking: `await logger.log(...)` no longer compiles (methods are sync now) — intended under no-backward-compat.
