---
name: monthly-update-detector
owner_agent: builder
on-call: false
scheduled: cron 0 3 * * * America/Chicago + Sun 0 9 30 * * 0 America/Chicago for digest
description: "Nightly 03:00 CT scan: identifies skills whose newest file mtime crossed 25 days. Writes stale-list to data/curator/stale-skills-<date>.md. NEVER auto-bumps timestamps — only Cooper decides what to refresh. Sunday 09:30 CT weekly Telegram digest summarizes stale skills sorted by quality_score (high-value first)."
---

# monthly-update-detector

## Why this exists

Validated finding (cont-19.9-M brief): monthly-updated skills outrank 90-day-stale ones in every skill marketplace tested. So the registry needs to know which skills have decayed. **But auto-bumping `last_updated` to game ranking is fraud** — it teaches the system to lie to itself. This skill detects, never edits.

## Inputs
- `--dry-run` — count + report path, no writes
- `--digest-only` — write Sunday digest from latest 7 daily reports
- `--threshold-days N` (default 25) — staleness cutoff
- `--out-dir <path>` (default `<repo>/data/curator/`)

## Output
- `STATUS=ok scanned=<n> stale=<m> threshold_days=<d> report=<path>` — daily scan
- `STATUS=ok mode=digest week_stale=<n> message_path=<path>` — Sunday digest
- `STATUS=ok-dryrun ...`
- Daily report `data/curator/stale-skills-<YYYY-MM-DD>.md`: one line per stale skill, sorted by quality_score descending, with: name, owner_agent, days-since-update, quality_score
- Sunday digest `data/curator/stale-digest-<YYYY-MM-DD>.md`: ≤15 lines for Telegram

## Side effects
- Writes daily and weekly reports
- **NEVER edits any SKILL.md, SOUL.md, or run.sh**
- **NEVER writes to capability-index.json or marketplace.json**
- Telegram emission deferred to existing send pipeline (reads `stale-digest-*.md`)

## Hard rules
- Detection only. No content modification, ever.
- If `data/.well-known/skills/index.json` is missing, fall back to direct registry walk — never block.
- The threshold of 25 days is the warning line. Real refresh prompt fires at 30 days (cron escalates).
