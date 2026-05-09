---
name: heartbeat-silence-check
owner_agent: ops
description: Detects when workspace/system_memory/heartbeats.json mtime exceeds the silence threshold (default 6h). Voice-alerts + Telegram-pings Cooper at high priority. Counter-measure for the v11.0 archive-too-aggressive failure that left the heartbeat-collector silent for 67h before cont-14 revived it.
scheduled: launchd com.dailyai.heartbeat-silence-check every 30 min
trigger: callable from any cron/skill that wants to validate observability isn't silently dead
---

# heartbeat-silence-check

A monitor-the-monitor. The heartbeat-collector writes
`workspace/system_memory/heartbeats.json` every 15 minutes. When that
write stops happening, the memory-sync audits silently report stale data
forever. cont-14 found a 67-hour silence that 22 audits failed to
escalate. This skill closes that gap by checking the file's mtime on a
schedule and voice-alerting + Telegramming when it ages past 6 hours.

## Procedure

```bash
bash skills/heartbeat-silence-check/run.sh
```

Exit codes:
- 0: GREEN (mtime within threshold)
- 1: RED (mtime exceeds threshold, alert fired)
- 2: error (file missing / read failure)

## Flags

- `--threshold-seconds N` (default 21600 = 6h) — age past which RED fires
- `--dry-run` — print the verdict, skip voice-alert + Telegram
- `--quiet` — emit nothing on GREEN (default emits one-line status)

## Silence-detector design choices

- **6h threshold**, not 1h — collector's own StartInterval is 15 min, so
  4 misses = 60 min would be too tight. 6h is "definitely something is
  wrong, not a transient launchd hiccup."
- **High priority alerting** — voice-alert priority=high (Daniel/200wpm)
  + Telegram priority=high. The whole point is to break through and
  notice. Low-priority would be the same failure mode this skill exists
  to fix.
- **No auto-revival** — this skill is a detector, not a fixer. Cooper
  (or a follow-up ops session) decides whether to re-bootstrap the
  collector vs. dig in.
- **Skill, not Python** — per CLAUDE.md "SKILLS NOT PYTHON" rule and P8
  build-prompt-checklist. The detection is a 20-line bash; no daemon,
  no library — fits the skill mold cleanly.

## Anti-runaway

If the silence-detector itself fires repeatedly (say, every 30 min for
hours because the underlying collector is broken and Cooper is asleep),
the alerts would become noise. Mitigation: a `data/state/heartbeat-silence-last-alert`
timestamp file. Re-alert at most once every 6 hours after first RED.
Once the collector recovers (mtime fresh), the timestamp file is
deleted on the next GREEN run. This avoids the alert-storm pattern.

## Wired

- Cron `com.dailyai.heartbeat-silence-check` at 30-min cadence
  (`StartInterval=1800`).
- Plist at `config/launchd/com.dailyai.heartbeat-silence-check.plist`.
