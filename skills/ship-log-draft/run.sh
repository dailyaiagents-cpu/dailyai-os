#!/usr/bin/env bash
# ship-log-draft/run.sh — Friday 16:00 CT auto-draft of the weekly ship log.
# Aggregates 7 days of git + skill auto-promotions + postmortems +
# improvement-queue. Voice-gates and scrubber-checks the draft.
# Telegrams Cooper to fill in the "What I learned" paragraph.
set +e
DRYRUN="${SHIP_LOG_DRYRUN:-0}"
REPO=${REPO_ROOT}
DATE=$(date +%Y-%m-%d)
DRAFT="$REPO/data/ship-log/$DATE-draft.md"
mkdir -p "$REPO/data/ship-log"

python3 - "$REPO" "$DRAFT" <<'PY'
import datetime, glob, json, pathlib, subprocess, sys

REPO = pathlib.Path(sys.argv[1])
DRAFT = pathlib.Path(sys.argv[2])
NOW = datetime.datetime.now(datetime.timezone.utc)
SINCE = NOW - datetime.timedelta(days=7)
SINCE_TS = SINCE.timestamp()

lines = []
out = lines.append

out(f"# Ship log: week ending {NOW.date().isoformat()}")
out("")
out(f"_Auto-drafted {NOW.isoformat()}. Cooper edits the \"What I learned\" section before publish._")
out("")

# Section: shipped
out("## Shipped")
out("")
r = subprocess.run(
    ["git", "log", "--oneline", "--since=7 days ago", "--no-merges"],
    cwd=str(REPO), capture_output=True, text=True,
)
commits = [l for l in (r.stdout or "").strip().split("\n") if l]
if commits:
    for c in commits[:15]:
        if " " in c:
            sha, msg = c.split(" ", 1)
        else:
            sha, msg = c, ""
        # Strip Co-Authored-By + sha noise so the public log reads cleanly
        msg = msg.split(" — ")[0].split(":")[-1].strip() if "(" not in msg else msg
        out(f"- {commits[commits.index(c)].split(' ', 1)[1] if ' ' in c else c}")
    if len(commits) > 15:
        out(f"- _and {len(commits)-15} more_")
else:
    out("_No commits this week._")
out("")

# Section: auto-promoted skills
auto = pathlib.Path.home() / ".hermes/skills/auto"
if auto.exists():
    week_skills = [p for p in auto.iterdir() if p.is_dir() and p.stat().st_mtime > SINCE_TS]
    if week_skills:
        out("## Skills auto-promoted this week")
        out("")
        for s in sorted(week_skills, key=lambda x: -x.stat().st_mtime)[:10]:
            out(f"- `{s.name}`")
        out("")

# Section: what broke
pm = REPO / "data/postmortems"
if pm.exists():
    week_pms = [p for p in sorted(pm.glob("*.md"), key=lambda x: -x.stat().st_mtime)
                if p.stat().st_mtime > SINCE_TS]
    if week_pms:
        out("## What broke (and the fix)")
        out("")
        for p in week_pms[:3]:
            text = p.read_text(encoding="utf-8", errors="replace")[:300].replace("\n", " ").strip()
            out(f"### `{p.stem}`")
            out("")
            out(f"{text}...")
            out("")

# Cooper's section — placeholder for editorial
out("## What I learned")
out("")
out("_(Cooper writes 100-200 words here — the one mental-model update that shaped the week. Voice-gate + scrubber re-check before publish.)_")
out("")

# What's next
qd = REPO / "data/improvement-queue/approved"
if qd.exists():
    nexts = sorted(qd.glob("*.md"), key=lambda p: -p.stat().st_mtime)[:3]
    if nexts:
        out("## What's next")
        out("")
        for p in nexts:
            out(f"- `{p.stem}`")
        out("")

out("---")
out("")
out("_From an autonomous AI-native solo founder operating system. Built in public._")

DRAFT.write_text("\n".join(lines))
print(f"STATUS=ok wrote={DRAFT} lines={len(lines)}")
PY

echo
echo "=== Voice-gate ==="
python3 "$REPO/tools/voice/score.py" "$DRAFT" 2>&1 | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(f'score={d[\"score\"]} passes={d[\"passes\"]}')
except Exception as e:
    print(f'parse-error: {e}')
"

echo "=== Scrubber (HARD gate) ==="
python3 "$REPO/tools/voice/scrubber.py" "$DRAFT" 2>&1 | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(f'clean={d[\"clean\"]} hits={len(d.get(\"hits\",[]))}')
    if not d['clean']:
        for h in d['hits'][:3]:
            print(f'  HIT: {h[\"category\"]} = {h[\"match\"]!r}')
except Exception as e:
    print(f'parse-error: {e}')
"

# Telegram Cooper (live mode only)
if [ "$DRYRUN" = "0" ]; then
  python3 "$REPO/tools/notify/telegram_send.py" --priority normal --respect-deep-work --text "📰 Ship log draft ready: data/ship-log/$DATE-draft.md
Edit \"What I learned\" (100-200w), then run: bash ~/.openclaw/skills/ship-log-publish/run.sh $DATE" 2>/dev/null
fi

echo "STATUS=ok draft=$DRAFT"
