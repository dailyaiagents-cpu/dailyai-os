---
name: mrr-floor-check
owner_agent: hermes
description: Daily Stripe MRR query against a configured floor. Writes snapshot JSON to data/finance/mrr_history/, fires Telegram high-priority alert on floor breach. Floor is 0 by default (silent) until Cooper tunes it after 30 days of data.
trigger: launchd com.dai.mrr-floor.plist daily at 11:00 CDT (09:00 PT) or manual via bash run.sh
---

# mrr-floor-check

Daily MRR-vs-floor watcher. Pulls Stripe active subscriptions, sums monthly + annualized MRR, compares against `data/finance/mrr_floor.yaml`, snapshots to history, alerts Cooper if breached.

See SOUL.md for the floor-tuning protocol (Phase 1/2/3) and failure modes.

## Manual run

```bash
bash ~/.hermes/skills/mrr-floor-check/run.sh
```

Output: `data/finance/mrr_history/<YYYY-MM-DD>.json` plus stdout `STATUS=...` line.

## Required env / config

- `~/.hermes/config.yaml` must contain `STRIPE_SECRET_KEY:` (already set since cont-7)
- `data/finance/mrr_floor.yaml` must exist (created in this ship; default `floor_usd: 0`)

## Outputs

- `data/finance/mrr_history/<YYYY-MM-DD>.json` — daily snapshot:
  ```json
  {
    "date": "2026-05-01",
    "current_mrr_usd": 0.00,
    "floor_usd": 0,
    "alert_threshold_pct": 90,
    "alert_triggered": false,
    "subscription_count": 0,
    "subscriptions": []
  }
  ```
- Telegram message via `tools/notify/telegram_send.py --priority high` ONLY when alert triggered.

## Status codes

`STATUS=ok current_mrr=$X floor=$Y` / `STATUS=alert ...` / `STATUS=error reason=...`
