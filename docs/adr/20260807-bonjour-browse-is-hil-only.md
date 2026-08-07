# Bonjour browse is verified by HIL only, not by an automated test

Date: 2026-08-07
Status: Accepted

## Context

- Every automated transport test dials `.host`. The `.bonjour` path — browse → first-match connect → fresh re-browse on each reconnect attempt (`NWTransport.browse` / `browserFound`) — has no coverage.
- mDNS is a shared, machine-wide resource: a test that advertises and browses is visible to (and perturbed by) every other responder on the LAN, and depends on timing the framework does not let us control. That makes it flaky by nature, not by implementation.
- The rest of the reconnect state machine — retry throttling, generation invalidation, handshake replay, peer-close detection — is already covered through `.host`, so browse is the only genuinely untested step.

## Decision

- Do not write an automated Bonjour test, gated by an env var or otherwise. Browse is verified by the NSLogger.app HIL checklist (issue #1) and by the two-terminal smoke test, both recorded in `TESTING.md`.
- Test the code around browse instead: everything after the endpoint is resolved is reachable via `.host`, so keep new reconnect/lifecycle coverage there.
- Revisit if `browse` grows real logic — service-name filtering rules, multi-result ranking, or a browse-specific retry policy. Discovery selection logic would then belong in a pure function tested directly, with only the `NWBrowser` call left to HIL.

## Alternatives Considered

| Option | Result | Reason |
|---|---|---|
| HIL-only, recorded in TESTING.md | Chosen | browse is a handful of lines; the state machine behind it is covered via `.host`; no flaky test to babysit |
| Env-var-gated local mDNS test | Rejected | a test that does not run in CI is a test nobody runs; still flaky where it does run, and it would need a real advertiser to be meaningful |
| Fake/inject an `NWBrowser` seam | Rejected | mocking the browser asserts on our own stub, not on discovery; the bug class here (wrong service type, wrong endpoint shape) survives the mock |

## Consequences

- + No flaky test in the suite; the browse contract is checked where it is real — against an actual viewer.
- - A regression in `browse` (wrong service type, bad name filter) ships unless someone runs the smoke test or HIL. Both are one command.
- ? Bonjour is now an explicit line item in the `TESTING.md` HIL checklist so it cannot be skipped silently when tagging a release.

## Notes

- Contrast with TLS (issue #2), which *did* get an automated test: a TLS far end is constructible in-process (self-signed identity → `NWMessageListener(tlsIdentity:)`), so it costs nothing and is deterministic. Bonjour has no in-process equivalent — that asymmetry, not effort, is what decides it.
- Closes issue #3.
