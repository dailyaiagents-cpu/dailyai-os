#!/usr/bin/env bash
set -a
[ -f /Users/bots/Dev/daily-ai-agent-os/.env ] && source /Users/bots/Dev/daily-ai-agent-os/.env
set +a
# plist-drift-detector — every 6h, reconcile launchctl loaded labels vs config/launchd/*.plist
# Alert via Telegram on drift-set change; cooldown 6h so stable drift is silent.

set +e

DRY_RUN=0
BASELINE=0
SYNTHETIC=0
DIFF_MODE=0    # cont-19.9-J: --diff prints per-file action plan
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --baseline) BASELINE=1; shift ;;
    --synthetic) SYNTHETIC=1; DRY_RUN=1; shift ;;
    --diff) DIFF_MODE=1; DRY_RUN=1; shift ;;
    *) echo "STATUS=error reason=unknown-flag flag=$1" >&2; exit 2 ;;
  esac
done

# cont-19.9-J: PLIST_REPO can point to the worktree; default to main clone.
# When run from a worktree (skills/plist-drift-detector/run.sh), prefer the
# worktree's own config/launchd if it exists.
REPO="${PLIST_REPO:-/Users/bots/Dev/daily-ai-agent-os}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKTREE_GUESS="$(cd "$SCRIPT_DIR/../.." && pwd)"
if [ -z "$PLIST_REPO" ] && [ -d "$WORKTREE_GUESS/config/launchd" ]; then
  REPO="$WORKTREE_GUESS"
fi
LAUNCHD_SRC_DIR="$REPO/config/launchd"
STATE_DIR="$REPO/data/plist-drift"
STATE_FILE="$STATE_DIR/state.json"
COOLDOWN_SEC=$((6 * 3600))

mkdir -p "$STATE_DIR"

NOW_EPOCH=$(date -u +%s)
TS=$(date -u +%FT%TZ)

LOADED=$(launchctl list 2>/dev/null \
  | awk '/^[0-9-]+[[:space:]]+[0-9-]+[[:space:]]+(ai\.openclaw|com\.dailyai|com\.dai\.|ai\.hermes|ai\.dailyaiagents|com\.dailyaiagents)/ {print $3}' \
  | sort -u)

if [ ! -d "$LAUNCHD_SRC_DIR" ]; then
  echo "STATUS=error reason=missing-source-dir path=$LAUNCHD_SRC_DIR"
  exit 2
fi

# cont-19.9-J: recurse subdirectories. Round 1 used `ls *.plist` (top-level
# only) which missed plists in cont-12-voice-watcher/, cont-9-mrr-and-digest/.
# We exclude DEAD-* and anything under _archive/.
SOURCE=$(find "$LAUNCHD_SRC_DIR" -type f -name '*.plist' \
  -not -path '*/_archive/*' \
  2>/dev/null \
  | xargs -n1 basename 2>/dev/null \
  | sed 's/\.plist$//' \
  | grep -v '^DEAD-' \
  | sort -u)

# cont-19.9-J: external-allow file. Anything listed here is loaded by other
# tooling (e.g. ~/Library/LaunchAgents/ direct installs, hermes installer)
# and must NOT be reported as "loaded but no source plist".
EXTERNAL_FILE="$LAUNCHD_SRC_DIR/_external/known.txt"
EXTERNAL=""
if [ -f "$EXTERNAL_FILE" ]; then
  EXTERNAL=$(grep -v '^#' "$EXTERNAL_FILE" 2>/dev/null | grep -v '^[[:space:]]*$' | sort -u)
fi

# Synthetic test injection
if [ "$SYNTHETIC" -eq 1 ]; then
  SOURCE=$(printf '%s\ncom.dailyai.IMAGINARY-SYNTHETIC\n' "$SOURCE" | sort -u)
fi

LOADED_ONLY_RAW=$(comm -23 <(printf '%s\n' "$LOADED") <(printf '%s\n' "$SOURCE"))
SOURCE_ONLY=$(comm -13 <(printf '%s\n' "$LOADED") <(printf '%s\n' "$SOURCE"))

# Strip externally-known labels from LOADED_ONLY (they're legit user-installed)
if [ -n "$EXTERNAL" ]; then
  LOADED_ONLY=$(comm -23 <(printf '%s\n' "$LOADED_ONLY_RAW") <(printf '%s\n' "$EXTERNAL"))
  EXTERNAL_MATCHED=$(comm -12 <(printf '%s\n' "$LOADED_ONLY_RAW") <(printf '%s\n' "$EXTERNAL"))
else
  LOADED_ONLY="$LOADED_ONLY_RAW"
  EXTERNAL_MATCHED=""
fi

LOADED_ONLY_N=$(echo "$LOADED_ONLY" | grep -c .)
SOURCE_ONLY_N=$(echo "$SOURCE_ONLY" | grep -c .)
LOADED_COUNT=$(echo "$LOADED" | grep -c .)
SOURCE_COUNT=$(echo "$SOURCE" | grep -c .)
EXTERNAL_COUNT=$(echo "$EXTERNAL" | grep -c .)
DRIFT_N=$((LOADED_ONLY_N + SOURCE_ONLY_N))

# Hash for change detection
HASH=$(printf 'L:%s\nS:%s\n' "$LOADED_ONLY" "$SOURCE_ONLY" | shasum -a 256 | awk '{print $1}' | head -c 12)

PREV_HASH=""
PREV_LAST_ALERT=0
if [ -f "$STATE_FILE" ]; then
  PREV_HASH=$(jq -r '.hash // empty' "$STATE_FILE" 2>/dev/null)
  PREV_LAST_ALERT=$(jq -r '.last_alert_epoch // 0' "$STATE_FILE" 2>/dev/null)
fi

CHANGED=0
if [ "$HASH" != "$PREV_HASH" ]; then CHANGED=1; fi
COOLDOWN_OK=1
if [ "$PREV_LAST_ALERT" -gt 0 ]; then
  ELAPSED=$((NOW_EPOCH - PREV_LAST_ALERT))
  if [ "$ELAPSED" -lt "$COOLDOWN_SEC" ]; then COOLDOWN_OK=0; fi
fi

ACTION="silent"
LAST_ALERT_EPOCH="$PREV_LAST_ALERT"

# cont-19.9-J: --diff prints a per-file decision plan and exits.
# For each loaded-only label: source plist exists? newer? → keep loaded / commit
# For each source-only label: try `launchctl print` to see if it's somewhere unexpected
if [ "$DIFF_MODE" -eq 1 ]; then
  echo "# plist-drift --diff (read-only)"
  echo "# loaded=$LOADED_COUNT  source=$SOURCE_COUNT  external_allowed=$(echo "$EXTERNAL_MATCHED" | grep -c .)"
  echo "# loaded_only=$LOADED_ONLY_N  source_only=$SOURCE_ONLY_N  drift=$DRIFT_N"
  echo
  echo "## loaded-only — running but no source plist (decide: bootstrap-source or accept-as-external)"
  if [ -n "$LOADED_ONLY" ]; then
    while IFS= read -r label; do
      [ -z "$label" ] && continue
      # Try to find a plist on disk
      sys_plist=""
      for path in "$HOME/Library/LaunchAgents/$label.plist" \
                  "/Library/LaunchAgents/$label.plist" \
                  "/Library/LaunchDaemons/$label.plist"; do
        [ -f "$path" ] && { sys_plist="$path"; break; }
      done
      if [ -n "$sys_plist" ]; then
        printf '  %-50s [external] from %s\n' "$label" "$sys_plist"
      else
        printf '  %-50s [unknown-installer] — no plist on disk\n' "$label"
      fi
    done <<< "$LOADED_ONLY"
  else
    echo "  (none)"
  fi
  echo
  echo "## source-only — checked into source but not loaded (decide: bootstrap or retire)"
  if [ -n "$SOURCE_ONLY" ]; then
    while IFS= read -r label; do
      [ -z "$label" ] && continue
      # find which file matches under config/launchd
      file=$(find "$LAUNCHD_SRC_DIR" -name "$label.plist" -not -path '*/_archive/*' 2>/dev/null | head -1)
      if [ -n "$file" ]; then
        # When was the source last touched?
        mtime=$(stat -f %Sm -t %Y-%m-%dT%H:%MZ "$file" 2>/dev/null)
        printf '  %-50s [source] %s (mtime %s)\n' "$label" "$file" "$mtime"
      else
        printf '  %-50s [source-missing!?]\n' "$label"
      fi
    done <<< "$SOURCE_ONLY"
  else
    echo "  (none)"
  fi
  echo
  if [ -n "$EXTERNAL_MATCHED" ]; then
    echo "## external-allowlisted — ignored from drift count"
    echo "$EXTERNAL_MATCHED" | sed 's/^/  /'
  fi
  exit 0
fi

# Build alert body
LO_LIST=$(echo "$LOADED_ONLY" | sed 's/^/  - /' | head -50)
SO_LIST=$(echo "$SOURCE_ONLY" | sed 's/^/  - /' | head -50)
ALERT_BODY=$(cat <<EOF
[plist-drift] hash=$HASH was=${PREV_HASH:-NONE} drift=$DRIFT_N
loaded_only=$LOADED_ONLY_N (running, no source plist)
$LO_LIST
source_only=$SOURCE_ONLY_N (in source, not loaded)
$SO_LIST
EOF
)

if [ "$DRIFT_N" -eq 0 ]; then
  STATUS_LINE="STATUS=GREEN drift=0 hash=$HASH"
elif [ "$BASELINE" -eq 1 ]; then
  STATUS_LINE="STATUS=BASELINED drift=$DRIFT_N hash=$HASH"
elif [ "$CHANGED" -eq 1 ] && [ "$COOLDOWN_OK" -eq 1 ]; then
  if [ "$DRY_RUN" -eq 0 ]; then
    python3 "$REPO/tools/notify/telegram_send.py" --text "$ALERT_BODY" >/dev/null 2>&1 || true
    LAST_ALERT_EPOCH="$NOW_EPOCH"
    ACTION="alerted"
  else
    ACTION="dry-run-would-alert"
  fi
  STATUS_LINE="STATUS=ALERT drift=$DRIFT_N hash=$HASH changed_from=${PREV_HASH:-NONE} action=$ACTION"
else
  STATUS_LINE="STATUS=YELLOW drift=$DRIFT_N hash=$HASH (silent: changed=$CHANGED cooldown_ok=$COOLDOWN_OK)"
fi

# Write state (skip on synthetic to avoid polluting real state)
if [ "$SYNTHETIC" -eq 0 ] && [ "$DRY_RUN" -eq 0 ]; then
  jq -n \
    --arg ts "$TS" \
    --arg hash "$HASH" \
    --arg lo "$LOADED_ONLY" \
    --arg so "$SOURCE_ONLY" \
    --argjson last_alert_epoch "$LAST_ALERT_EPOCH" \
    '{
      ts: $ts,
      hash: $hash,
      loaded_only: ($lo | split("\n") | map(select(. != ""))),
      source_only: ($so | split("\n") | map(select(. != ""))),
      last_alert_epoch: $last_alert_epoch
    }' > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
fi

echo "$STATUS_LINE"

# Print drift set inline for cron logs
if [ "$DRIFT_N" -gt 0 ] && [ "$LOADED_ONLY_N" -gt 0 ]; then
  echo "  loaded_only:"
  echo "$LOADED_ONLY" | sed 's/^/    /'
fi
if [ "$DRIFT_N" -gt 0 ] && [ "$SOURCE_ONLY_N" -gt 0 ]; then
  echo "  source_only:"
  echo "$SOURCE_ONLY" | sed 's/^/    /'
fi

# Exit codes: 0 GREEN, 1 YELLOW (drift, no alert), 2 ALERT
case "$STATUS_LINE" in
  STATUS=GREEN*) exit 0 ;;
  STATUS=ALERT*) exit 2 ;;
  *) exit 1 ;;
esac
