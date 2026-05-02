---
name: delegation-orchestrator
version: 1.0.0
owner_agent: ops
description: |
  The convention + fault tree for proactive cross-agent help. Specialists
  that hit a blocked state write a delegation request to
  data/delegations/pending/<ts>-<source>.json. The tools/delegation_tick.py
  daemon polls every 60s and dispatches to the named target agent via
  openclaw agent. Retry-cap 2; failures move to data/delegations/failed/.
---

# delegation-orchestrator

## Why this exists

When the outreach-paced specialist hits "linkedin session expired," it shouldn't
loop trying to fix it itself. It should write a delegation: "ops, please
run session-keeper for linkedin." The ops agent runs the helper, opens the
right gate, the user resolves it, outreach resumes. No specialist is stuck
indefinitely; no Cooper-time wasted on routing.

This file is the convention + fault tree specialists read to know who to
delegate to. The actual dispatch happens in `tools/delegation_tick.py`
(daemon-tick, every 60s, permitted helper).

## The convention

A specialist in a blocked state writes JSON to
`data/delegations/pending/<unix-timestamp>-<source>.json`:

```json
{
  "source_agent": "outreach-paced",
  "next_action": "ops",
  "task": "run session-keeper for linkedin target",
  "context_diff": "session-keeper reports linkedin status=expired since 2026-05-02T...",
  "priority": "high",
  "max_attempts": 2
}
```

Fields:
- `source_agent` — who hit the block (informational)
- `next_action` — the openclaw agent id who should help (e.g., `ops`, `accountant`, `research`)
- `task` — single-message instruction; daemon-tick passes this verbatim to `openclaw agent --agent <next_action> -m "<task>"`
- `context_diff` — optional, appended to task if present (keeps requests small)
- `priority` — `low|medium|high` (informational; daemon-tick doesn't reorder)
- `max_attempts` — int, default 2

The daemon-tick (`tools/delegation_tick.py`):
1. Polls `data/delegations/pending/` every 60s
2. For each request: attempts++ check vs max_attempts
3. Calls `openclaw agent --agent <next_action> -m "<task>" --timeout 120 --json`
4. On rc=0: moves to `data/delegations/done/`
5. On rc≠0 with attempts < max: writes request back, retries next tick
6. On attempts ≥ max: moves to `data/delegations/failed/` with `final_status: max-attempts-exhausted`

## Fault tree (specialists read this to know who to delegate to)

| Source agent | Trigger | next_action | task |
|---|---|---|---|
| outreach-paced | linkedin session expired | ops | "run session-keeper for linkedin target" |
| hermes-inbox-router | reddit poll returns 401 | ops | "rotate reddit credentials; verify session-keeper for reddit" |
| research | paywall hit on `<publisher>` | accountant | "do we have a subscription to `<publisher>`?" |
| sales | LinkedIn DM rate-limit | ops | "rotate session or switch surface for linkedin" |
| sales | Reddit account suspension | ops | "check reddit account state" |
| content | image-gen quota exceeded | ops | "check API key state for `<provider>`" |
| ops | ollama model unreachable | ops | "run model-warmth-keeper recovery" |
| accountant | Stripe webhook failed signature | ops | "check STRIPE_WEBHOOK_SECRET freshness" |

This table extends as the company encounters new blocked-state patterns.

## Each specialist's SOUL.md gets this paragraph

> When you hit a blocked state — auth failure, rate limit, missing
> credential, downstream service down — DO NOT loop trying to fix it.
> Write a delegation request per `delegation-orchestrator` skill's
> convention to `data/delegations/pending/<unix>-<your-id>.json`, then
> exit with a status=blocked summary in your reply. The orchestrator
> daemon picks it up within 60 seconds and dispatches to the right
> helper.

## Hard rules

1. **Write-once, daemon-pick-up.** Specialists write the JSON and exit; they don't poll for completion. The daemon owns dispatch.
2. **Max 2 retries per request.** Beyond that → failed/ and Telegram-alert (HIGH priority).
3. **No agent-self-loops.** A request whose `next_action` equals `source_agent` is allowed (e.g., ops self-recovery via warmth-keeper) but flagged in logs for audit.
4. **No silent failures.** Every entry in `failed/` should produce a Telegram alert at the next inbox-zero batch (Tier 3.1).

## Self-test

```bash
# Synthetic delegation
cat > ${REPO_ROOT}/data/delegations/pending/$(date +%s)-test.json <<'JSON'
{
  "source_agent": "test",
  "next_action": "ops",
  "task": "Reply with the literal string 'delegation-test-ok' and nothing else.",
  "priority": "low",
  "max_attempts": 1
}
JSON

# Wait one tick interval (60s) — daemon picks up
sleep 65
ls ${REPO_ROOT}/data/delegations/done/*test*.json 2>/dev/null
```

Acceptance: round-trip <90s, request lands in done/.
