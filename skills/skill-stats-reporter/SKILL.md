---
name: skill-stats-reporter
owner_agent: ops
description: Reads data/skill-telemetry/invocations.jsonl and produces daily stats — dead skills (zero invocations in last 30d), hot skills (>10 invocations/day on average), failure rates per skill, median wallclock per skill. Auto-publishes the dead-skill list to data/skill-telemetry/dead-skills-pending-review.md so future sessions can promote-or-delete in batch.
trigger: launchd com.dai.skill-stats StartCalendarInterval Hour=8 Minute=15 (CDT) — runs after morning crons settle
---

# skill-stats-reporter

The thesis: a 340-skill catalog needs an observable shape — which are alive, which are dead, which fail too often, which take too long. Without it, the catalog is opaque. With it, Cooper can promote winners and retire losers in 5-minute batches.

## Procedure

```bash
bash skills/skill-stats-reporter/run.sh           # full daily run
bash skills/skill-stats-reporter/run.sh --dry-run # build report, don't write
```

## Pipeline

1. Read `data/skill-telemetry/invocations.jsonl` (entire log; small for a year).
2. Bucket events by skill: `start` count, `end` count, `end status` distribution, durations.
3. Walk the catalog directories (`skills/`, `~/.openclaw/skills/`) for the universe of skill names.
4. Cross-reference:
   - **dead skills**: in catalog, 0 `start` events in last 30 days.
   - **hot skills**: >10 `start` events/day on average over last 7 days.
   - **failure-prone**: ≥5 `end status=error` events in last 7 days.
   - **slow skills**: median `duration_sec` > 60s over last 7 days.
5. Write `data/skill-telemetry/<YYYY-MM-DD>.md` (full report).
6. Auto-publish the dead-skill list to `data/skill-telemetry/dead-skills-pending-review.md` (replaces last week's; one canonical surface for batch review).

## Output

`data/skill-telemetry/<YYYY-MM-DD>.md` contains six sections:

```
# Skill stats — <YYYY-MM-DD>

## Summary
- Total skills in catalog: N
- Skills with telemetry: M
- Coverage: M/N (%)

## Dead skills (no invocations in 30d)
...

## Hot skills (>10/day, last 7d)
...

## Failure-prone skills (≥5 errors in 7d)
...

## Slow skills (median > 60s in 7d)
...
```

## Status codes

`STATUS=ok report=<path> dead=<N> hot=<M>` / `STATUS=skip reason=no-telemetry-yet` / `STATUS=error reason=<...>`

## P12 — counter-monitor for the reporter

If the reporter has not run in 25 hours, the heartbeat-silence pattern picks it up via the `data/skill-telemetry/<YYYY-MM-DD>.md` mtime. (Cooper-side: add the file to the silence-detector's watch list when this skill graduates from cont-18.)
