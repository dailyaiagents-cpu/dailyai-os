---
name: receipt-stream-publisher
owner_agent: ops
description: Hourly publish of an operational ticker — last 24h commits, voice-gate pass/fail counts, P-gate catches, smoke-tests, substrate state. Auto-publishes to site/receipts.html + site/api/receipts.json. Public surface, scrubber-HARD. Operational receipts compound into a recruitable artifact for prospects who want to verify what's actually shipping.
trigger: launchd com.dai.receipt-stream StartInterval=3600 (hourly)
---

# receipt-stream-publisher

The thesis: prospects don't trust marketing pages. They trust receipts.
A live operational ticker showing what's shipping right now — commits,
gates, smoke-tests, substrate state — is more credible than any sales page.
And it's autonomous: the system documents itself in real time.

## Procedure

```bash
bash skills/receipt-stream-publisher/run.sh           # full hourly publish
bash skills/receipt-stream-publisher/run.sh --dry-run # build the payload, don't write
```

## Pipeline

1. **Last 24h commits** — `git log --since="24 hours ago" --pretty=format:'%h %s'`
   subjects only, scrubber-checked.
2. **Voice-gate counts** — grep `voice_gate.log` (if exists) for last-24h pass/fail.
   If no log, count = 0/0 with a "no telemetry yet" footnote.
3. **P-gate catches** — grep `data/decisions/cont-*-*.md` for "P-gates triggered"
   sections in last 24h, count by gate id.
4. **Smoke-tests** — grep `logs/*.log` and `data/decisions/*.md` for
   `smoke-test|smoke test|STATUS=ok` patterns last 24h, count by skill name.
5. **Substrate state** — `bash skills/gateway-pulse/check.sh` and
   `bash skills/launchd-drift-recovery/check.sh`, normalize to
   `operational | degraded | down`.
6. **12 P-gates active** — static count from `docs/build-prompt-checklist.md`.
7. **Scrubber HARD** on the assembled JSON-text-fields. If any string fails
   scrubber, the whole publish aborts and writes a `STATUS=blocked` to
   `logs/receipt-stream-stderr.log`.
8. **Atomic write**: `site/api/receipts.json` (`.tmp` + rename), then render
   `site/receipts.html` from a static template that reads the JSON via
   relative-path fetch on page load (no rebuild on JSON-only change).

## Status codes

`STATUS=ok json=<path> html=<path>` /
`STATUS=blocked reason=scrubber-fail field=<...>` /
`STATUS=error reason=<...>`

## Output schema (receipts.json)

```json
{
  "as_of": "2026-05-06T01:00:00Z",
  "window_hours": 24,
  "commits_24h": [{"sha": "...", "subject": "..."}, ...],
  "voice_gate_24h": {"pass": 0, "fail": 0},
  "p_gate_catches_24h": {"P8": 1, "P10": 1},
  "smoke_passes_24h": {"heartbeat-silence-check": 5, "gateway-pulse": 24},
  "substrate": {"hermes": "ok", "openclaw": "ok", "obsidian": "ok", "paperclip": "ok", "drift": "GREEN"},
  "p_gates_active": 12,
  "_meta": {"generator": "receipt-stream-publisher", "hour_id": "<YYYY-MM-DDTHH>"}
}
```

## Gates

- **Scrubber HARD**: every text field flows through `tools/voice/scrubber.py`.
  Hit → abort the whole publish. False positives are acceptable; financial
  leaks are unrecoverable.
- **No voice-gate**: receipts are facts, not prose. Voice-gate is for prose.
- **P11**: receipts describe internal capabilities (ourselves), not
  outcomes (customer counts, MRR, win rate). Sticker prices stay out.

## Why hourly cadence

The artifact's value is freshness. A daily snapshot becomes a daily-news
artifact (interesting once); an hourly ticker becomes infrastructure
(always live, always probable). Free local inference is not the bottleneck —
it's a 200-line bash script with no LLM calls. Hourly is cheap.
