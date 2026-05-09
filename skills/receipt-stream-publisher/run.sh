#!/usr/bin/env bash
set -a
[ -f /Users/bots/Dev/daily-ai-agent-os/.env ] && source /Users/bots/Dev/daily-ai-agent-os/.env
set +a
# receipt-stream-publisher/run.sh — hourly operational ticker.
# cont-17v3 Phase C.1.
set +e
# cont-18 D.1: skill-invocation-tracker hooks (non-fatal, best-effort)
_TRACK="/Users/bots/Dev/daily-ai-agent-os/skills/skill-invocation-tracker/run.sh"
_SKILL_NAME="receipt-stream-publisher"
_SKILL_T0=$(date +%s)
[ -x "$_TRACK" ] && bash "$_TRACK" start "$_SKILL_NAME" >/dev/null 2>&1
trap '[ -x "$_TRACK" ] && SKILL_TRACKER_DURATION=$(( $(date +%s) - _SKILL_T0 )) bash "$_TRACK" end "$_SKILL_NAME" ${SKILL_EXIT_STATUS:-ok} >/dev/null 2>&1' EXIT

REPO=/Users/bots/Dev/daily-ai-agent-os
JSON_OUT="$REPO/site/api/receipts.json"
HTML_OUT="$REPO/site/receipts.html"
TMPL="$REPO/skills/receipt-stream-publisher/template.html"
SCRUBBER="$REPO/tools/voice/scrubber.py"

DRY_RUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    *) echo "STATUS=error reason=unknown-flag flag=$1"; exit 2 ;;
  esac
done

mkdir -p "$(dirname "$JSON_OUT")"

# === GATHER ===
cd "$REPO"

# 1. Commits last 24h (subjects only)
COMMITS_JSON=$(git log --since="24 hours ago" --no-merges --pretty=format:'%h|%s' 2>/dev/null \
  | python3 -c "
import sys, json
items = []
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    parts = line.split('|', 1)
    if len(parts) == 2:
        items.append({'sha': parts[0], 'subject': parts[1]})
print(json.dumps(items))
")

# 2. Voice-gate pass/fail counts last 24h (telemetry log if exists)
VOICE_PASS=0; VOICE_FAIL=0
if [ -f "$REPO/logs/voice-gate-telemetry.jsonl" ]; then
  VOICE_PASS=$(awk -v cutoff=$(date -u -v-1d +%s 2>/dev/null || date -u -d '24 hours ago' +%s) '
    { gsub(/.*"ts":"/, ""); ts = substr($0, 1, 19); }
    /"result":"pass"/ { c++ } END { print c+0 }
  ' "$REPO/logs/voice-gate-telemetry.jsonl" 2>/dev/null)
  VOICE_FAIL=$(grep -c '"result":"fail"' "$REPO/logs/voice-gate-telemetry.jsonl" 2>/dev/null || echo 0)
fi

# 3. P-gate catches last 24h (grep recent decision docs)
PGATE_CATCHES=$(find "$REPO/data/decisions" -name "*.md" -mtime -1 -type f 2>/dev/null \
  | xargs grep -hoE 'P[0-9]+(?= caught| triggered| (catches|caught|fired))' 2>/dev/null \
  | sort | uniq -c | python3 -c "
import sys, json
out = {}
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    parts = line.split(None, 1)
    if len(parts) == 2:
        out[parts[1]] = int(parts[0])
print(json.dumps(out))
")
PGATE_CATCHES=${PGATE_CATCHES:-'{}'}

# 4. Smoke-test passes last 24h: count STATUS=ok lines in logs (heartbeat-silence-check, etc.)
SMOKE_PASSES=$(python3 - <<'PY'
import os, glob, time, json, re
cutoff = time.time() - 86400
counts = {}
for log in glob.glob("/Users/bots/Dev/daily-ai-agent-os/logs/*-stdout.log"):
    if os.path.getmtime(log) < cutoff:
        continue
    name = os.path.basename(log).replace("-stdout.log", "")
    try:
        with open(log, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()[-50000:]
        n = content.count("STATUS=ok") + content.count("STATUS=GREEN")
        if n > 0:
            counts[name] = n
    except Exception:
        pass
print(json.dumps(counts))
PY
)

# 5. Substrate state
DRIFT=$(bash "$REPO/skills/launchd-drift-recovery/check.sh" 2>/dev/null | head -1 | grep -oE 'STATUS=(GREEN|YELLOW|RED)' | cut -d= -f2)
DRIFT=${DRIFT:-UNKNOWN}
PULSE=$(bash "$REPO/skills/gateway-pulse/check.sh" 2>/dev/null | head -1)
HERMES=$(echo "$PULSE" | grep -oE 'hermes:[a-zA-Z]+' | cut -d: -f2)
OPENCLAW=$(echo "$PULSE" | grep -oE 'openclaw:[a-zA-Z]+' | cut -d: -f2)
OBSIDIAN=$(echo "$PULSE" | grep -oE 'obsidian:[a-zA-Z]+' | cut -d: -f2)
PAPERCLIP=$(echo "$PULSE" | grep -oE 'paperclip:[a-zA-Z]+' | cut -d: -f2)
HERMES=${HERMES:-unknown}; OPENCLAW=${OPENCLAW:-unknown}; OBSIDIAN=${OBSIDIAN:-unknown}; PAPERCLIP=${PAPERCLIP:-unknown}

# 6. P-gates active (count from build-prompt-checklist)
PGATES_ACTIVE=$(grep -cE '^## P[0-9]+ ' "$REPO/docs/build-prompt-checklist.md" 2>/dev/null)
PGATES_ACTIVE=${PGATES_ACTIVE:-0}

NOW=$(date -u +%FT%TZ)
HOUR_ID=$(date -u +%FT%H)

# === ASSEMBLE JSON ===
PAYLOAD=$(python3 - <<PY
import json
payload = {
  "as_of": "$NOW",
  "window_hours": 24,
  "commits_24h": $COMMITS_JSON,
  "voice_gate_24h": {"pass": $VOICE_PASS, "fail": $VOICE_FAIL},
  "p_gate_catches_24h": $PGATE_CATCHES,
  "smoke_passes_24h": $SMOKE_PASSES,
  "substrate": {
    "hermes": "$HERMES",
    "openclaw": "$OPENCLAW",
    "obsidian": "$OBSIDIAN",
    "paperclip": "$PAPERCLIP",
    "drift": "$DRIFT"
  },
  "p_gates_active": $PGATES_ACTIVE,
  "_meta": {"generator": "receipt-stream-publisher", "hour_id": "$HOUR_ID"}
}
print(json.dumps(payload, indent=2))
PY
)

# === SCRUBBER HARD on every commit subject ===
# Concatenate commit subjects; if scrubber finds a hit, abort.
SUBJECTS=$(python3 -c "import json; print('\n'.join(c['subject'] for c in json.loads('''$COMMITS_JSON''')))" 2>/dev/null)
if [ -n "$SUBJECTS" ]; then
  SCRUB_TMP=$(mktemp -t receipt-scrub.XXXXXX.txt)
  printf '%s\n' "$SUBJECTS" > "$SCRUB_TMP"
  SCRUB_OUT=$(python3 "$SCRUBBER" "$SCRUB_TMP" 2>&1)
  SCRUB_RC=$?
  rm -f "$SCRUB_TMP"
  if [ "$SCRUB_RC" -ne 0 ]; then
    echo "STATUS=blocked reason=scrubber-fail field=commit_subjects detail=$(echo "$SCRUB_OUT" | head -c 200 | tr '\n' ' ')"
    exit 1
  fi
fi

if [ "$DRY_RUN" = "1" ]; then
  echo "$PAYLOAD" | head -30
  echo "..."
  echo "STATUS=ok-dryrun"
  exit 0
fi

# === WRITE JSON atomically ===
TMP_JSON="$JSON_OUT.tmp"
echo "$PAYLOAD" > "$TMP_JSON" && mv "$TMP_JSON" "$JSON_OUT"

# === WRITE HTML (static template; JS reads JSON on page load) ===
cat "$TMPL" > "$HTML_OUT.tmp" && mv "$HTML_OUT.tmp" "$HTML_OUT"

echo "STATUS=ok json=$JSON_OUT html=$HTML_OUT commits=$(echo "$COMMITS_JSON" | python3 -c "import sys,json;print(len(json.load(sys.stdin)))") substrate=$DRIFT"
