#!/usr/bin/env bash
set -a
[ -f /Users/bots/Dev/daily-ai-agent-os/.env ] && source /Users/bots/Dev/daily-ai-agent-os/.env
set +a
# skill-invocation-tracker/run.sh — append-only telemetry helper.
# cont-18 Phase D.1.
set +e

REPO=/Users/bots/Dev/daily-ai-agent-os
LOG_DIR="$REPO/data/skill-telemetry"
LOG_FILE="$LOG_DIR/invocations.jsonl"

mkdir -p "$LOG_DIR"

EVENT="$1"
SKILL="$2"
STATUS="$3"

case "$EVENT" in
  start)
    [ -z "$SKILL" ] && { echo "STATUS=error reason=missing-skill-name"; exit 2; }
    NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    PID="${PPID}"
    printf '{"event":"start","skill":"%s","ts":"%s","pid":%s}\n' "$SKILL" "$NOW" "$PID" >> "$LOG_FILE"
    echo "STATUS=ok event=start skill=$SKILL pid=$PID"
    ;;
  end)
    [ -z "$SKILL" ] && { echo "STATUS=error reason=missing-skill-name"; exit 2; }
    [ -z "$STATUS" ] && STATUS="ok"
    NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    PID="${PPID}"
    DURATION="${SKILL_TRACKER_DURATION:-}"
    if [ -n "$DURATION" ]; then
      printf '{"event":"end","skill":"%s","ts":"%s","pid":%s,"status":"%s","duration_sec":%s}\n' "$SKILL" "$NOW" "$PID" "$STATUS" "$DURATION" >> "$LOG_FILE"
    else
      printf '{"event":"end","skill":"%s","ts":"%s","pid":%s,"status":"%s"}\n' "$SKILL" "$NOW" "$PID" "$STATUS" >> "$LOG_FILE"
    fi
    echo "STATUS=ok event=end skill=$SKILL status=$STATUS"
    ;;
  *)
    echo "STATUS=error reason=invalid-event event=$EVENT (use start|end)"
    exit 2
    ;;
esac
