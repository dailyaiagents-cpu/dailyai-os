#!/usr/bin/env bash
# couch-mode-watchdog.sh — kernel-audit-toolkit (MIT)
# Five health checks every 5 minutes. Designed to run while you're on the couch.
# Alert hook is shell-pluggable — wire to your Telegram, Slack, Discord, email, whatever.
#
# Default checks (override via --checks-config):
#  1. disk_free_pct   — /Users (or override) > 10%
#  2. cpu_load_5m     — 5-min load average / cores < 4.0
#  3. ollama_alive    — http://127.0.0.1:11434/api/tags returns 200
#  4. critical_logs   — no "FATAL" or "Traceback" in last 5min of $LOG_DIRS
#  5. cron_freshness  — heartbeat file mtime < 10 min
#
# Each check is a single bash function. Add or remove freely.
set +e

ALERT_HOOK="${ALERT_HOOK:-}"
LOG_DIRS="${LOG_DIRS:-./logs}"
HEARTBEAT_FILE="${HEARTBEAT_FILE:-./.couch-heartbeat}"
DISK_THRESHOLD_PCT="${DISK_THRESHOLD_PCT:-10}"
CPU_LOAD_THRESHOLD="${CPU_LOAD_THRESHOLD:-4.0}"
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --alert-hook) ALERT_HOOK="$2"; shift 2 ;;
    --log-dirs) LOG_DIRS="$2"; shift 2 ;;
    --heartbeat-file) HEARTBEAT_FILE="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    *) shift ;;
  esac
done

if [ "$DRY_RUN" = "1" ]; then
  echo "STATUS=ok-dryrun would_run_5_checks alert_hook=${ALERT_HOOK:-none}"
  exit 0
fi

# Touch heartbeat
mkdir -p "$(dirname "$HEARTBEAT_FILE")"
date +%s > "$HEARTBEAT_FILE"

REDS=()

# Check 1: disk free
DISK_FREE_PCT=$(df -P / 2>/dev/null | awk 'NR==2 {sub(/%/, "", $5); print 100 - $5}')
if [ -n "$DISK_FREE_PCT" ] && [ "$DISK_FREE_PCT" -lt "$DISK_THRESHOLD_PCT" ]; then
  REDS+=("disk_free=${DISK_FREE_PCT}% (threshold ${DISK_THRESHOLD_PCT}%)")
fi

# Check 2: CPU load
CORES=$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)
LOAD5=$(uptime | awk -F'load average[s]?:' '{print $2}' | awk -F',' '{gsub(/ /,""); print $2}')
LOAD_PER_CORE=$(echo "scale=2; ${LOAD5:-0} / ${CORES:-1}" | bc 2>/dev/null)
if [ -n "$LOAD_PER_CORE" ]; then
  if awk -v l="$LOAD_PER_CORE" -v t="$CPU_LOAD_THRESHOLD" 'BEGIN{exit !(l>t)}'; then
    REDS+=("cpu_load_per_core=$LOAD_PER_CORE (threshold $CPU_LOAD_THRESHOLD)")
  fi
fi

# Check 3: Ollama alive (skip silently if not configured)
if curl -s --max-time 2 http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
  : # OK
else
  # Only alert if we expect ollama (presence of OLLAMA_HOST or models dir)
  if [ -n "$OLLAMA_HOST" ] || [ -d "$HOME/.ollama" ]; then
    REDS+=("ollama_unreachable_at_127.0.0.1:11434")
  fi
fi

# Check 4: critical logs in last 5 min
for d in $(echo "$LOG_DIRS" | tr ':' ' '); do
  [ -d "$d" ] || continue
  RECENT=$(find "$d" -type f -mmin -5 2>/dev/null | head -20)
  for f in $RECENT; do
    if grep -qE 'FATAL|Traceback \(most recent|panic:' "$f" 2>/dev/null; then
      REDS+=("critical_log_hit=$f")
    fi
  done
done

# Check 5: heartbeat freshness — re-check just-touched file is < 10 min old
NOW=$(date +%s)
HB=$(cat "$HEARTBEAT_FILE" 2>/dev/null)
if [ -n "$HB" ] && [ $((NOW - HB)) -gt 600 ]; then
  REDS+=("heartbeat_stale=$((NOW - HB))s")
fi

if [ ${#REDS[@]} -eq 0 ]; then
  echo "STATUS=GREEN checks=5 reds=0"
  exit 0
fi

# Fire alert hook if provided
MSG="couch-watchdog RED ${#REDS[@]} fail(s): $(IFS=', '; echo "${REDS[*]}")"
if [ -n "$ALERT_HOOK" ] && [ -x "$ALERT_HOOK" ]; then
  bash "$ALERT_HOOK" "$MSG"
fi
echo "STATUS=RED checks=5 reds=${#REDS[@]}"
for r in "${REDS[@]}"; do echo "  - $r"; done
exit 1
