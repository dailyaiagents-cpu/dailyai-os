#!/usr/bin/env bash
set -a
[ -f /Users/bots/Dev/daily-ai-agent-os/.env ] && source /Users/bots/Dev/daily-ai-agent-os/.env
set +a
# heartbeat-silence-check/run.sh — RED if heartbeats.json mtime exceeds threshold.
# cont-14: detector for the failure mode where heartbeat-collector silently
# stops writing and 22 memory-sync audits report stale data without escalating.
set +e
# cont-18 D.1: skill-invocation-tracker hooks (non-fatal, best-effort)
_TRACK="/Users/bots/Dev/daily-ai-agent-os/skills/skill-invocation-tracker/run.sh"
_SKILL_NAME="heartbeat-silence-check"
_SKILL_T0=$(date +%s)
[ -x "$_TRACK" ] && bash "$_TRACK" start "$_SKILL_NAME" >/dev/null 2>&1
trap '[ -x "$_TRACK" ] && SKILL_TRACKER_DURATION=$(( $(date +%s) - _SKILL_T0 )) bash "$_TRACK" end "$_SKILL_NAME" ${SKILL_EXIT_STATUS:-ok} >/dev/null 2>&1' EXIT

REPO=/Users/bots/Dev/daily-ai-agent-os
HEARTBEATS="$REPO/workspace/system_memory/heartbeats.json"
LAST_ALERT_FILE="$REPO/data/state/heartbeat-silence-last-alert"
VOICE_ALERT="$HOME/.hermes/skills/voice-alert/run.sh"
TELEGRAM_SEND="$REPO/tools/notify/telegram_send.py"

THRESHOLD=21600  # 6h default
RE_ALERT_INTERVAL=21600  # 6h between repeat alerts
DRY_RUN=0
QUIET=0

while [ $# -gt 0 ]; do
  case "$1" in
    --threshold-seconds) THRESHOLD="$2"; shift 2 ;;
    --threshold-seconds=*) THRESHOLD="${1#*=}"; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --quiet) QUIET=1; shift ;;
    *) echo "STATUS=error reason=unknown-flag flag=$1"; exit 2 ;;
  esac
done

if [ ! -f "$HEARTBEATS" ]; then
  echo "STATUS=error reason=heartbeats-missing path=$HEARTBEATS"
  exit 2
fi

mtime=$(stat -f %m "$HEARTBEATS" 2>/dev/null)
if [ -z "$mtime" ]; then
  echo "STATUS=error reason=stat-failed path=$HEARTBEATS"
  exit 2
fi

now=$(date -u +%s)
age=$((now - mtime))

if [ "$age" -le "$THRESHOLD" ]; then
  # GREEN — clear the rate-limit file so the next silence (if any) alerts immediately
  if [ -f "$LAST_ALERT_FILE" ]; then
    rm -f "$LAST_ALERT_FILE"
  fi
  if [ "$QUIET" = "0" ]; then
    echo "STATUS=GREEN age=${age}s threshold=${THRESHOLD}s mtime=$(date -u -r "$mtime" +%FT%TZ)"
  fi
  exit 0
fi

# RED — heartbeat is silent past threshold
mtime_iso=$(date -u -r "$mtime" +%FT%TZ)
hours=$((age / 3600))
text="HEARTBEAT-COLLECTOR SILENT for ${hours} hours. heartbeats.json mtime ${mtime_iso}. Run cont-14 revival."

if [ "$DRY_RUN" = "1" ]; then
  echo "STATUS=RED-dryrun age=${age}s threshold=${THRESHOLD}s mtime=$mtime_iso would-alert=\"$text\""
  exit 1
fi

# Rate-limit: re-alert at most every RE_ALERT_INTERVAL seconds after first RED
should_alert=1
if [ -f "$LAST_ALERT_FILE" ]; then
  last_alert=$(cat "$LAST_ALERT_FILE" 2>/dev/null)
  if [ -n "$last_alert" ]; then
    delta=$((now - last_alert))
    if [ "$delta" -lt "$RE_ALERT_INTERVAL" ]; then
      should_alert=0
    fi
  fi
fi

if [ "$should_alert" = "1" ]; then
  mkdir -p "$(dirname "$LAST_ALERT_FILE")"
  printf '%s' "$now" > "$LAST_ALERT_FILE"

  # Voice-alert (best-effort)
  if [ -x "$VOICE_ALERT" ]; then
    bash "$VOICE_ALERT" --priority high --text "$text" 2>/dev/null || true
  fi
  # Telegram-send (best-effort)
  if [ -x "$TELEGRAM_SEND" ]; then
    python3 "$TELEGRAM_SEND" --priority high --text "$text" 2>/dev/null || true
  fi

  echo "STATUS=RED age=${age}s threshold=${THRESHOLD}s mtime=$mtime_iso alerted=yes"
else
  echo "STATUS=RED age=${age}s threshold=${THRESHOLD}s mtime=$mtime_iso alerted=skipped-rate-limit"
fi

exit 1
