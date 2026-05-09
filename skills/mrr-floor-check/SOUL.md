---
name: mrr-floor-check
owner_agent: hermes
owns: Daily MRR floor monitor. Fires Telegram alert when current MRR drops below the configured floor.
---

# mrr-floor-check

The early-warning watcher for revenue floor breaches.

## What it owns

Every day at 11:00 CDT (09:00 PT), this skill:

1. Pulls the active subscriptions from Stripe via `https://api.stripe.com/v1/subscriptions?status=active` (direct REST API with `STRIPE_SECRET_KEY` from `~/.hermes/config.yaml`).
2. Computes current MRR by summing `item.price.unit_amount * item.quantity / 100` for monthly subscriptions, plus `(unit_amount * quantity / 100) / 12` for annual subscriptions.
3. Reads the floor from `data/finance/mrr_floor.yaml`.
4. Writes a JSON snapshot to `data/finance/mrr_history/<YYYY-MM-DD>.json` including the per-subscription breakdown.
5. Fires a Telegram alert via `tools/notify/telegram_send.py --priority high` if `current_mrr < floor_usd * (alert_threshold_pct / 100)`.
6. Exits silently (no Telegram) when the floor is not breached or when `floor_usd=0` (the default during the first 30 days of operation).

## Floor-tuning protocol

The floor is intentionally 0 on day 1. Tune in 3 phases:

**Phase 1 (first 30 days).** Leave `floor_usd: 0`. The skill records daily history without alerting. Cooper reviews `data/finance/mrr_history/*.json` to understand the natural MRR shape.

**Phase 2 (day 30-60).** Compute the trailing 30-day average MRR. Set `floor_usd` to ~70% of that average. The 70% buffer absorbs typical fluctuation; a drop below 70% is a real signal.

**Phase 3 (day 60+).** Re-tune annually or after material business changes (new product line launch, pricing change, major churn event). Document the change in `data/decisions/<date>-mrr-floor-update.md`.

## When it fails loud

- Stripe API returns non-200 → Telegram high-priority alert, snapshot still written with `error` field.
- `mrr_floor.yaml` missing or malformed → Telegram alert, skill exits with status code 2.
- `tools/notify/telegram_send.py` missing → log to stderr; skill still writes the snapshot. Alert delivery is non-blocking for snapshot integrity.

## Status codes

- `STATUS=ok current_mrr=$X floor=$Y` — clean, snapshot written
- `STATUS=alert current_mrr=$X floor=$Y threshold=$Z` — floor breach, Telegram fired
- `STATUS=error reason=...` — Stripe/config failure, snapshot may be partial
