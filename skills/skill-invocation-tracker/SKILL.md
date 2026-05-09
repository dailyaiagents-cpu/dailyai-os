---
name: skill-invocation-tracker
owner_agent: ops
description: Append-only telemetry helpers — track_start and track_end. Adds two-line instrumentation to any skill so the catalog produces measurable invocation counts, success rates, and median wallclock. Read by skill-stats reporter daily to identify dead skills (0 invocations in 30d) and hot skills (>10/day).
trigger: callable from any skill (typically a 2-line at start + 1-line at end pattern)
---

# skill-invocation-tracker

The thesis: a skill catalog without telemetry is a graveyard waiting to happen. With telemetry, dead skills surface for promote/delete and hot skills surface for optimization budgets.

## Procedure

```bash
# At the start of any skill's run.sh:
bash skills/skill-invocation-tracker/run.sh start <skill-name>
# At the end:
bash skills/skill-invocation-tracker/run.sh end <skill-name> <status>
# where status is ok | error | skip
```

The skill writes one JSON line per call to `data/skill-telemetry/invocations.jsonl`.

## Output schema

```json
{"event": "start", "skill": "overnight-founder", "ts": "<ISO>", "pid": 12345}
{"event": "end",   "skill": "overnight-founder", "ts": "<ISO>", "pid": 12345, "status": "ok", "duration_sec": 34.1}
```

The reader pairs start/end by `pid`. Unmatched starts (orphan PIDs older than 30 minutes) are flagged as `crashed`.

## Status codes

`STATUS=ok event=<start|end>` / `STATUS=error reason=<...>`

## Why append-only

A live counter file is a contention point. Append-only JSONL is reader-friendly, append-cheap, trivially shippable as a daily snapshot.

## Permitted in meta-skill template

The meta-skill scaffold (cont-17v3 F.1) gets an automatic two-line instrumentation snippet from cont-18 D.1. Future scaffolded skills inherit telemetry by default.
