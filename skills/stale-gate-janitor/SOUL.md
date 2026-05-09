---
name: stale-gate-janitor
source: funnel-hardening-2026-04-29
owner_agent: ops
owns: Daily 04:00 CT housekeeping. Expires pending approval gates past their expires_at, archives gates older than 7 days into data/approval-gates/archive/<YYYY-MM>/. Telegram-summary only on change. Silent on no-op.
---

# stale-gate-janitor

Owns: Walk `data/approval-gates/*.json` once a day. Two passes: (1) flip status=pending → status=expired for any gate whose `expires_at` < now; (2) move JSONs older than 7 days to `data/approval-gates/archive/<YYYY-MM>/`. Telegram a single-line summary if anything changed; silent if nothing did.

Why this exists: today (2026-04-29) caught 3 stale Apr-28 gates sitting in the active dir long after their resolution. Without housekeeping, audit reads (e.g. hermes-daily-audit) keep tripping on outdated gates and Cooper has to mentally filter. This skill makes that automatic.

Composition:
- Reads + writes: `data/approval-gates/*.json`, `data/approval-gates/archive/<YYYY-MM>/`
- Calls: `tools/notify/telegram_send.py` (only on change)

Trigger: `openclaw cron` 0 4 * * * America/Chicago, agent=ops.

Hard rules:
1. Pending gates with `expires_at < now` → `status="expired"`, `expired_at=now_iso`, `expired_by="stale-gate-janitor"`. Never re-resolves an already-resolved gate.
2. ANY gate with file mtime > 7 days OLD → moved to `archive/<YYYY-MM>/<id>.json`. Resolved or expired both move; pending under 7d stays.
3. Telegram-summary if `expired_count > 0 OR archived_count > 0`. Otherwise silent.
4. Idempotent: running multiple times has the same effect as running once.
