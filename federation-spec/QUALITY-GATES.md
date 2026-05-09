# QUALITY-GATES

Substrate-level checks every federation partner has to clear. The hub enforces these via telemetry inspection plus periodic active probes.

## Gate 1 — voice-scrubber pass

Every federated invocation that produces user-facing output (text, audio transcript, image caption) MUST run that output through a voice-scrubber check before returning. The scrubber pattern is open-source under MIT in `kernel-audit-toolkit/voice-scrubber/`. Partners can use the reference implementation or substitute an equivalent.

The hub verifies via the `voice_scrubber_pass: bool` field in the telemetry envelope. Invocations with `voice_scrubber_pass: false` are excluded from royalty calculation and counted as a conformance failure.

## Gate 2 — decision-recorder event

Every routing or model-selection decision inside the partner's agent that touches a federated skill MUST be recorded via a decision-recorder-equivalent log. The hub does not require any specific schema; it requires a non-empty `decision_recorder_event_id` (UUID) in the telemetry envelope.

The hub samples 1% of invocations for replay verification: it asks the partner to return the decision-recorder event content for the given UUID. Partners that fail replay verification three times within 30 days are revoked.

## Gate 3 — substrate health probe

The hub probes each partner's Agent Card endpoint every 60 minutes:

- HTTP 200 within 5 seconds
- Card schema version matches a hub-supported version
- Skills index URL reachable, returns valid `index.json`

Three consecutive probe failures move the partner to a degraded state. Five mark the partner offline for federation discovery. The partner can return to active state by passing one successful probe.

## Gate 4 — capability tag honesty

Skills published with `capability_tags` that don't reflect actual capability are flagged. The hub maintains a sample test corpus per capability tag; periodically a federated skill is invoked with a corpus prompt matched to its declared tags. Outputs that fail to demonstrate the capability mark the skill (not the partner) as misclassified. The partner is asked to either fix the implementation or remove the misleading tags.

## Gate 5 — invocation idempotency

Federated skills SHOULD be idempotent for read-style operations and MUST declare their idempotency posture in the card:

```json
"idempotent": "read" | "write-with-idempotency-key" | "non-idempotent"
```

Skills marked `non-idempotent` are flagged in discovery results and not included in retry loops. Lying about idempotency posture (declaring `read` while having side effects) is a Gate-4-equivalent honesty failure.

## Gate 6 — no private-data leakage

Federated skills MUST NOT include private telemetry (specific dollar amounts, partner identifiers other than the invoker's, or paths to internal substrate state) in their outputs. The hub's voice-scrubber pattern includes a default leakage banlist; partners are expected to extend it.

This is the gate that protects the federation from accidental private-data exposure. Daily AI Agents enforces it internally via the same `visibility-gate` skill that protects our own substrate; partners can reuse the pattern.

## Conformance reporting

Each partner has a public conformance dashboard at `https://<hub>/partners/<partner-id>/health`. The dashboard shows the last 30 days of probe results, gate pass/fail counts, and current state (active / degraded / offline / revoked).
