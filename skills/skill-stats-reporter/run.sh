#!/usr/bin/env bash
set -a
[ -f /Users/bots/Dev/daily-ai-agent-os/.env ] && source /Users/bots/Dev/daily-ai-agent-os/.env
set +a
# skill-stats-reporter/run.sh — daily skill telemetry summarizer.
# cont-18 Phase D.2.
set +e

REPO=/Users/bots/Dev/daily-ai-agent-os
LOG="$REPO/data/skill-telemetry/invocations.jsonl"
OUT_DIR="$REPO/data/skill-telemetry"
TODAY=$(date -u +%Y-%m-%d)
OUT="$OUT_DIR/$TODAY.md"
DEAD_OUT="$OUT_DIR/dead-skills-pending-review.md"

DRY_RUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    *) echo "STATUS=error reason=unknown-flag flag=$1"; exit 2 ;;
  esac
done

mkdir -p "$OUT_DIR"

if [ ! -f "$LOG" ]; then
  echo "STATUS=skip reason=no-telemetry-yet log=$LOG"
  exit 0
fi

python3 - "$LOG" "$REPO" "$OUT" "$DEAD_OUT" "$TODAY" "$DRY_RUN" <<'PY'
import sys, os, json, glob, pathlib
from datetime import datetime, timezone, timedelta
from collections import defaultdict

log_p, repo, out_p, dead_p, today, dry = sys.argv[1:7]
dry = (dry == "1")
now = datetime.now(timezone.utc)
day = timedelta(days=1)

# Read telemetry
events = []
with open(log_p) as fh:
    for line in fh:
        try:
            events.append(json.loads(line))
        except Exception:
            continue

# Bucket by skill
by_skill = defaultdict(lambda: {"starts": [], "ends": []})
for e in events:
    skill = e.get("skill", "")
    if not skill: continue
    if e.get("event") == "start":
        by_skill[skill]["starts"].append(e)
    elif e.get("event") == "end":
        by_skill[skill]["ends"].append(e)

# Universe of skills from catalog dirs
catalog = set()
for base in [pathlib.Path(repo) / "skills",
             pathlib.Path.home() / ".openclaw/skills",
             pathlib.Path.home() / ".hermes/skills"]:
    if not base.exists(): continue
    for p in base.iterdir():
        if p.is_dir() and (p / "SKILL.md").exists():
            catalog.add(p.name)
        # one nested level (hermes/<cat>/<skill>)
        if p.is_dir():
            for q in p.iterdir():
                if q.is_dir() and (q / "SKILL.md").exists():
                    catalog.add(q.name)

# Compute stats
def parse_ts(s: str):
    try:
        return datetime.fromisoformat((s or "").replace("Z", "+00:00"))
    except Exception:
        return None

dead = []
hot = []
failure_prone = []
slow = []
covered = 0

for skill in sorted(catalog):
    starts = by_skill.get(skill, {}).get("starts", [])
    ends = by_skill.get(skill, {}).get("ends", [])
    if not starts and not ends:
        # never invoked → dead candidate (only if it's been around)
        dead.append({"skill": skill, "starts_30d": 0, "last_seen": "never"})
        continue
    covered += 1
    last_start = max((parse_ts(s.get("ts")) for s in starts), default=None)
    starts_30d = sum(1 for s in starts if parse_ts(s.get("ts")) and parse_ts(s.get("ts")) > now - 30*day)
    starts_7d = sum(1 for s in starts if parse_ts(s.get("ts")) and parse_ts(s.get("ts")) > now - 7*day)
    if starts_30d == 0:
        dead.append({"skill": skill, "starts_30d": 0,
                     "last_seen": last_start.strftime("%Y-%m-%d") if last_start else "never"})
        continue
    if starts_7d / 7.0 > 10:
        hot.append({"skill": skill, "per_day_avg_7d": round(starts_7d / 7.0, 1)})
    err_7d = sum(1 for e in ends
                 if e.get("status") == "error"
                 and parse_ts(e.get("ts")) and parse_ts(e.get("ts")) > now - 7*day)
    if err_7d >= 5:
        failure_prone.append({"skill": skill, "errors_7d": err_7d})
    durations = [e.get("duration_sec", 0) for e in ends if isinstance(e.get("duration_sec"), (int, float))
                 and parse_ts(e.get("ts")) and parse_ts(e.get("ts")) > now - 7*day]
    if durations:
        durations.sort()
        median = durations[len(durations)//2]
        if median > 60:
            slow.append({"skill": skill, "median_sec": round(median, 1)})

# Build report
lines = [
    f"# Skill stats — {today}",
    "",
    "## Summary",
    f"- Total skills in catalog: {len(catalog)}",
    f"- Skills with telemetry events: {covered}",
    f"- Coverage: {covered}/{len(catalog)} ({(covered/max(1, len(catalog))*100):.0f}%)",
    "",
    f"## Dead skills (no invocations in 30 days) — {len(dead)}",
]
if dead:
    for d in dead[:50]:
        lines.append(f"- `{d['skill']}` — last seen {d['last_seen']}")
    if len(dead) > 50:
        lines.append(f"- ... and {len(dead) - 50} more")
else:
    lines.append("_(none)_")

lines += [
    "",
    f"## Hot skills (>10/day average, last 7d) — {len(hot)}",
]
for h in hot:
    lines.append(f"- `{h['skill']}` — {h['per_day_avg_7d']}/day")
if not hot:
    lines.append("_(none)_")

lines += [
    "",
    f"## Failure-prone (≥5 errors in 7d) — {len(failure_prone)}",
]
for f in failure_prone:
    lines.append(f"- `{f['skill']}` — {f['errors_7d']} errors")
if not failure_prone:
    lines.append("_(none)_")

lines += [
    "",
    f"## Slow skills (median > 60s in 7d) — {len(slow)}",
]
for s in slow:
    lines.append(f"- `{s['skill']}` — median {s['median_sec']}s")
if not slow:
    lines.append("_(none)_")

lines += [
    "",
    "---",
    f"_Generator: skills/skill-stats-reporter @ {now.isoformat()}_",
]

report = "\n".join(lines) + "\n"

if dry:
    print(report)
    print(f"\nSTATUS=ok-dryrun dead={len(dead)} hot={len(hot)} failures={len(failure_prone)} slow={len(slow)}")
    sys.exit(0)

# Write report
pathlib.Path(out_p).write_text(report)

# Write dead-skills-pending-review.md (canonical batch-review surface)
dead_lines = [
    f"# Dead skills pending review — {today}",
    "",
    "Skills in the catalog with zero telemetry events in the last 30 days.",
    "Cooper-side action: promote-or-delete in batch. Each row is one decision.",
    "",
]
if dead:
    dead_lines.append("| Skill | Last seen |")
    dead_lines.append("|---|---|")
    for d in dead:
        dead_lines.append(f"| `{d['skill']}` | {d['last_seen']} |")
else:
    dead_lines.append("_All skills in the catalog have been invoked in the last 30 days. Catalog is alive._")
pathlib.Path(dead_p).write_text("\n".join(dead_lines) + "\n")

print(f"STATUS=ok report={out_p} dead={len(dead)} hot={len(hot)} failures={len(failure_prone)} slow={len(slow)}")
PY
