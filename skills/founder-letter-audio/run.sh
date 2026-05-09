#!/usr/bin/env bash
set -a
[ -f /Users/bots/Dev/daily-ai-agent-os/.env ] && source /Users/bots/Dev/daily-ai-agent-os/.env
set +a
# founder-letter-audio/run.sh — render a founder letter to MP3 via ElevenLabs.
# Voice-gate + scrubber HARD before any cloud call. Quota tracked against
# the 10K-char free-tier monthly cap.
set +e

REPO=/Users/bots/Dev/daily-ai-agent-os
HERMES_CONFIG=/Users/bots/.hermes/config.yaml
DEFAULT_VOICE_ID="EXAVITQu4vr4xnSDxMaL"   # Sarah — see SOUL.md voice picker
ELEVENLABS_MODEL="eleven_multilingual_v2"
MONTHLY_CHAR_LIMIT=9500

LETTER="$1"
if [ -z "$LETTER" ] || [ ! -r "$LETTER" ]; then
  echo "STATUS=error reason=letter-unreadable path=$LETTER (usage: run.sh <path-to-letter.md>)"
  exit 2
fi

# Read ElevenLabs key — prefer env, fall back to Hermes plist
EL_KEY="${ELEVENLABS_API_KEY:-}"
if [ -z "$EL_KEY" ]; then
  EL_KEY=$(grep -A 1 ELEVENLABS_API_KEY ~/Library/LaunchAgents/ai.hermes.gateway.plist 2>/dev/null | tail -1 | sed -E 's/.*<string>(.*)<\/string>.*/\1/')
fi
if [ -z "$EL_KEY" ]; then
  echo "STATUS=error reason=elevenlabs-key-missing (set ELEVENLABS_API_KEY env or in Hermes plist)"
  exit 2
fi

# Sentinel check — refuse if Cooper's placeholders are still present
if grep -q "_(Cooper writes" "$LETTER"; then
  echo "STATUS=blocked reason=letter-has-placeholders path=$LETTER"
  exit 1
fi

# Voice-gate HARD (threshold 70 — public surface, audio is permanent)
voice_score=$(python3 "$REPO/tools/voice/score.py" "$LETTER" 2>&1 | python3 -c "import sys,json; print(json.load(sys.stdin).get('score',0))" 2>/dev/null || echo "0")
voice_int=$(echo "$voice_score" | cut -d. -f1)
if [ -z "$voice_int" ] || [ "$voice_int" -lt 70 ] 2>/dev/null; then
  echo "STATUS=blocked reason=voice-gate-failed score=$voice_score threshold=70 path=$LETTER"
  exit 1
fi

# Scrubber HARD
python3 "$REPO/tools/voice/scrubber.py" "$LETTER" > /tmp/founder-audio-scrub.json 2>&1
scrub_rc=$?
if [ "$scrub_rc" -ne 0 ]; then
  echo "STATUS=blocked reason=scrubber-failed inspect=/tmp/founder-audio-scrub.json"
  exit 1
fi

# Strip Markdown formatting → clean prose for TTS
clean_text=$(python3 - "$LETTER" <<'PY'
import re, sys, pathlib
text = pathlib.Path(sys.argv[1]).read_text()
# Drop YAML frontmatter
text = re.sub(r"\A---\n.*?\n---\n", "", text, count=1, flags=re.S)
# Drop fenced code blocks
text = re.sub(r"```.*?```", "", text, flags=re.S)
# Drop HTML tags
text = re.sub(r"<[^>]+>", "", text)
# Drop the H1 + the auto-prepended Listen line if present from a prior run
lines = text.splitlines()
filtered = []
for ln in lines:
    if ln.startswith("# "):
        # H1 → keep title prose without the # prefix
        filtered.append(ln.lstrip("# ").strip())
    elif ln.startswith("🎧 Listen"):
        continue  # already-rendered listen link
    elif ln.startswith("---"):
        continue  # horizontal rules
    elif re.match(r"^#+\s", ln):
        # Lower-level headers: keep prose
        filtered.append(re.sub(r"^#+\s+", "", ln).strip())
    else:
        filtered.append(ln)
text = "\n".join(filtered)
# Inline markdown: bold/italic/links/code → prose
text = re.sub(r"\*\*(.*?)\*\*", r"\1", text)
text = re.sub(r"\*(.*?)\*", r"\1", text)
text = re.sub(r"_([^_]+)_", r"\1", text)
text = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)
_bt = chr(96)
text = re.sub(_bt + r"([^" + _bt + r"]+)" + _bt, r"\1", text)
# Collapse blank lines
text = re.sub(r"\n{3,}", "\n\n", text)
# Output
print(text.strip())
PY
)

CHAR_COUNT=$(printf '%s' "$clean_text" | wc -c | tr -d ' ')
if [ "$CHAR_COUNT" -lt 50 ]; then
  echo "STATUS=blocked reason=letter-too-short chars=$CHAR_COUNT (likely all placeholders)"
  exit 1
fi

# Quota check — read data/voice/elevenlabs_usage.json
USAGE_FILE="$REPO/data/voice/elevenlabs_usage.json"
mkdir -p "$REPO/data/voice"
CURRENT_MONTH=$(date +%Y-%m)
quota_status=$(python3 - "$USAGE_FILE" "$CURRENT_MONTH" "$CHAR_COUNT" "$MONTHLY_CHAR_LIMIT" <<'PY'
import json, sys, pathlib
usage_path = pathlib.Path(sys.argv[1])
current_month = sys.argv[2]
new_chars = int(sys.argv[3])
limit = int(sys.argv[4])

if usage_path.exists():
    try:
        usage = json.loads(usage_path.read_text())
    except Exception:
        usage = {}
else:
    usage = {}

# Roll month if needed
if usage.get("month") != current_month:
    usage = {"month": current_month, "chars_this_month": 0, "monthly_limit": limit, "renders": []}

projected = usage["chars_this_month"] + new_chars
if projected > limit:
    print(f"EXHAUST chars_used={usage['chars_this_month']} limit={limit} would_be={projected}")
else:
    print(f"OK projected={projected}")
PY
)
case "$quota_status" in
  EXHAUST*)
    echo "STATUS=error reason=quota-exhausted $quota_status"
    exit 1
    ;;
esac

# Render via ElevenLabs TTS
MP3_NAME="founder-letter-${CURRENT_MONTH}.mp3"
MP3_PATH="$REPO/site/audio/$MP3_NAME"
mkdir -p "$REPO/site/audio"

EL_PAYLOAD=$(python3 -c "import json,sys; print(json.dumps({'text':sys.stdin.read(),'model_id':'$ELEVENLABS_MODEL'}))" <<< "$clean_text")

http_code=$(curl -sS -m 120 -o "$MP3_PATH" -w "%{http_code}" \
  -H "xi-api-key: $EL_KEY" \
  -H "Content-Type: application/json" \
  -d "$EL_PAYLOAD" \
  "https://api.elevenlabs.io/v1/text-to-speech/$DEFAULT_VOICE_ID")

if [ "$http_code" != "200" ]; then
  # Capture error body
  err_body=$(head -c 400 "$MP3_PATH" 2>/dev/null)
  rm -f "$MP3_PATH"
  echo "STATUS=error reason=elevenlabs-http-$http_code body=\"$err_body\""
  exit 1
fi

# Validate the file is real audio
file_type=$(file "$MP3_PATH" 2>/dev/null)
file_size=$(stat -f%z "$MP3_PATH" 2>/dev/null)
if [ -z "$file_size" ] || [ "$file_size" -lt 5000 ] 2>/dev/null; then
  rm -f "$MP3_PATH"
  echo "STATUS=error reason=mp3-too-small size=$file_size (expected >5KB)"
  exit 1
fi
if ! echo "$file_type" | grep -qi "audio\|mpeg\|MP3"; then
  rm -f "$MP3_PATH"
  echo "STATUS=error reason=mp3-not-audio file_type=\"$file_type\""
  exit 1
fi

# Update usage file
python3 - "$USAGE_FILE" "$CURRENT_MONTH" "$CHAR_COUNT" "$MONTHLY_CHAR_LIMIT" "$DEFAULT_VOICE_ID" "$LETTER" <<'PY'
import json, sys, pathlib, datetime
usage_path = pathlib.Path(sys.argv[1])
current_month = sys.argv[2]
new_chars = int(sys.argv[3])
limit = int(sys.argv[4])
voice_id = sys.argv[5]
letter = sys.argv[6]

if usage_path.exists():
    try:
        usage = json.loads(usage_path.read_text())
    except Exception:
        usage = {}
else:
    usage = {}

if usage.get("month") != current_month:
    usage = {"month": current_month, "chars_this_month": 0, "monthly_limit": limit, "renders": []}

usage["chars_this_month"] += new_chars
usage["renders"].append({
    "date": datetime.date.today().isoformat(),
    "voice_id": voice_id,
    "chars": new_chars,
    "letter": letter,
})
usage_path.write_text(json.dumps(usage, indent=2))
PY

# Prepend the Listen link to the source letter (after the H1)
python3 - "$LETTER" "$MP3_NAME" <<'PY'
import pathlib, sys, re
p = pathlib.Path(sys.argv[1])
mp3_name = sys.argv[2]
text = p.read_text()
listen_line = f"\n🎧 Listen: /audio/{mp3_name}\n"
# Insert after first H1 line if not already present
if "🎧 Listen" in text:
    sys.exit(0)
m = re.search(r"^#\s.*$", text, flags=re.M)
if m:
    end = m.end()
    new_text = text[:end] + listen_line + text[end:]
    p.write_text(new_text)
PY

# Compute remaining quota for status line
remaining=$(python3 -c "
import json, pathlib
u = json.loads(pathlib.Path('$USAGE_FILE').read_text())
print(u.get('monthly_limit', $MONTHLY_CHAR_LIMIT) - u.get('chars_this_month', 0))
")

echo "STATUS=ok mp3=$MP3_PATH chars=$CHAR_COUNT quota_remaining=$remaining file_size=$file_size voice=$DEFAULT_VOICE_ID"
