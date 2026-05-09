---
name: plist-drift-detector
owner_agent: ops
description: Every 6h, compare loaded launchd labels (launchctl list) against source-of-truth plists in config/launchd/. Telegram-alerts on missing-from-source or missing-from-loaded. State file for cooldown so we don't repeat alerts on stable drift.
scheduled: openclaw cron `0 */6 * * * America/Chicago` (agent=ops, model=local) — every 6 hours
---

# plist-drift-detector

## Why this exists
The existing `launchd-drift-recovery` watches 4 hard-coded labels. Audit on 2026-05-07 found 16 loaded-only and 12 source-only labels of drift across the broader fleet. Either class can hide a real bug (a service registered out-of-band; a service quietly removed from the loadout). This skill reconciles them and alerts only when the drift set changes — stable drift is logged but quiet.

## How to run

```bash
bash skills/plist-drift-detector/run.sh             # default — alert on change
bash skills/plist-drift-detector/run.sh --dry-run   # no Telegram, no state writes
bash skills/plist-drift-detector/run.sh --baseline  # write current drift as baseline (use after intentional changes)
bash skills/plist-drift-detector/run.sh --synthetic # synthetic test: artificially injects a missing plist into the comparison
```

## Pipeline

1. List loaded labels matching the daily-ai prefix set (`ai.openclaw.*`, `ai.hermes.*`, `ai.dailyaiagents.*`, `com.dailyai.*`, `com.dailyaiagents.*`, `com.dai.*`).
2. List source plists in `config/launchd/*.plist` (excluding `DEAD-*` archived plists).
3. Compute set differences:
   - `loaded_only` — running but no source-of-truth (suspicious — out-of-band installation)
   - `source_only` — checked into source but not loaded (suspicious — should be running)
4. Read previous run's state from `data/plist-drift/state.json`. Compare today's drift set hash to yesterday's.
5. If hash changed AND we are not in cooldown (last alert >6h ago), Telegram-alert with diff. Otherwise silent.
6. Always update state file with current drift snapshot + ts.

## Status codes

`STATUS=GREEN` — no drift
`STATUS=YELLOW drift=N hash=...` — drift exists; same as last run; silent
`STATUS=ALERT drift=N changed_from=...` — drift changed; Telegram sent

## State

`data/plist-drift/state.json`:
```json
{
  "ts": "2026-05-07T17:41Z",
  "loaded_only": ["..."],
  "source_only": ["..."],
  "hash": "sha256(loaded_only|source_only)",
  "last_alert_ts": "2026-05-07T17:41Z"
}
```

## Hard rules

1. **No destructive actions.** No load/unload of plists. Detection only. Recovery is `launchd-drift-recovery`'s job.
2. **Excludes `DEAD-*` plists.** Archived plists in source must not trigger drift.
3. **Cooldown is 6h.** Even if drift changes again, no more than 1 Telegram per 6h window.
4. **macOS-only.** `launchctl list`, basename, sort, comm.

## Self-test

Use `--synthetic` to inject a fake `com.dailyai.IMAGINARY` into the source list and verify the alert path runs without sending Telegram (synthetic mode forces `--dry-run` semantics on outbound).
