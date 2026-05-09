---
name: monthly-burn
owner_agent: accountant
description: Aggregates monthly cash burn across Anthropic, ElevenLabs, Cloudflare, Stripe fees, GitHub Actions, and domain registrations. Reads from MCP servers where available; falls back to manual env-var or file-based entries. Output to data/finance/burn/<YYYY-MM>.md as the canonical monthly burn statement. Manual-entry rows are flagged so Cooper sees what is automated vs what still needs hand-update.
trigger: launchd com.dai.monthly-burn 1st of month 09:00 CT + manual trigger
---

# monthly-burn

The thesis: a founder cannot manage what they cannot see. Cost visibility per source per month is the table that decides which experiments live and which die. The skill reads MCP-exposed sources where possible; everything else surfaces as `Cooper-manual-entry` so the gap is visible.

## Procedure

```bash
bash skills/monthly-burn/run.sh           # current month
bash skills/monthly-burn/run.sh --month 2026-04 # specific month
bash skills/monthly-burn/run.sh --dry-run
```

## Pipeline

For each cost source:

1. **Anthropic**: read `data/finance/manual/anthropic-<YYYY-MM>.txt` if it exists (Cooper paste). Otherwise `Cooper-manual-entry`.
2. **ElevenLabs**: read `data/voice/elevenlabs_usage.json` if present + token-cost calc.
3. **Cloudflare**: placeholder — no Cloudflare worker billed yet. Once `verify-license` deploys, read CF metrics.
4. **Stripe fees**: query Stripe MCP if loaded; otherwise read `data/finance/manual/stripe-<YYYY-MM>.txt`.
5. **GitHub Actions minutes**: query GitHub MCP if loaded; otherwise `Cooper-manual-entry`.
6. **Domain registrations**: read `data/finance/domain-registrations.json` (annual entries; pro-rated to month).
7. **Stripe payouts received**: subtract from gross to compute net (income side).

Sum to a monthly total. Flag any `Cooper-manual-entry` rows.

## Output schema (data/finance/burn/<YYYY-MM>.md)

```
# Monthly burn — <YYYY-MM>

## Sources

| Source | This month | Source-of-truth | Status |
|---|---|---|---|
| Anthropic | $X | data/finance/manual/anthropic-... | automated/manual |
| ElevenLabs | $Y | data/voice/elevenlabs_usage.json | automated |
| Cloudflare | $0 | n/a (worker not deployed) | placeholder |
| Stripe fees | $Z | Stripe MCP / manual | automated/manual |
| GitHub Actions | $W | GitHub MCP / manual | automated/manual |
| Domain registrations | $V | data/finance/domain-registrations.json | automated |
| **Total burn** | $T | | |

## Manual-entry gaps

- <list of sources that fell back to Cooper-manual-entry>

## Trend

- Last month total: $T_prev
- Delta: ±$D
```

## Status codes

`STATUS=ok month=<YYYY-MM> total=<dollars> manual_gaps=<N>` /
`STATUS=skip reason=<...>` / `STATUS=error reason=<...>`

## Why this is permitted Python (well, bash)

Each cost source is queried via MCP tools or file reads. No MCP server is being authored here — the aggregator skill is just bash + jq calling the existing MCP-server-exposed tools or reading files. Skill, not Python.

## P12 — counter-monitor

If the latest `data/finance/burn/<YYYY-MM>.md` is older than 35 days (one month + buffer), the heartbeat-silence pattern catches it.
