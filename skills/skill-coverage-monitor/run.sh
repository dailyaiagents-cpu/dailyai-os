#!/usr/bin/env bash
set -a
[ -f /Users/bots/Dev/daily-ai-agent-os/.env ] && source /Users/bots/Dev/daily-ai-agent-os/.env
set +a
# skill-coverage-monitor — walk skill registry, validate 4 fields per skill.

set +e

JSON_ONLY=0
REPORT_PATH=""
ROOT_OVERRIDE=""
VOICE_MIN=75
SKILL_FILTER=""
while [ $# -gt 0 ]; do
  case "$1" in
    --json) JSON_ONLY=1; shift ;;
    --report) REPORT_PATH="$2"; shift 2 ;;
    --root) ROOT_OVERRIDE="$2"; shift 2 ;;
    --voice-min) VOICE_MIN="$2"; shift 2 ;;
    --skill) SKILL_FILTER="$2"; shift 2 ;;
    *) echo "STATUS=error reason=unknown-flag flag=$1" >&2; exit 2 ;;
  esac
done

REPO="${COVERAGE_REPO:-/Users/bots/Dev/daily-ai-agent-os}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKTREE_GUESS="$(cd "$SCRIPT_DIR/../.." && pwd)"
if [ -z "$COVERAGE_REPO" ] && [ -d "$WORKTREE_GUESS/skills" ]; then
  REPO="$WORKTREE_GUESS"
fi

VOICE_SCORER="$REPO/tools/voice/score.py"

# Roots to walk
if [ -n "$ROOT_OVERRIDE" ]; then
  ROOTS=("$ROOT_OVERRIDE")
else
  ROOTS=("$REPO/skills" "$HOME/.openclaw/skills")
fi

TS=$(date -u +%FT%TZ)

# Pre-build trigger set: which skills are referenced by any plist or cron
trigger_set_file=$(mktemp -t skill-coverage-XXXXXX)
trap 'rm -f "$trigger_set_file"' EXIT

# launchd plists referencing skills/<name>/run.sh
for plist_dir in "$HOME/Library/LaunchAgents" "$REPO/config/launchd"; do
  [ -d "$plist_dir" ] || continue
  find "$plist_dir" -type f -name '*.plist' -not -path '*/_archive/*' 2>/dev/null \
    | xargs grep -hoE 'skills/[a-z0-9_.-]+/run\.sh' 2>/dev/null \
    | sed -E 's@skills/([^/]+)/run\.sh@\1@' \
    | sort -u >> "$trigger_set_file"
done

# openclaw cron list — match skill names
openclaw cron list 2>/dev/null \
  | awk '{print $2}' \
  | grep -vE '^(NAME|--|$)' \
  | sort -u >> "$trigger_set_file"

trigger_set_sorted=$(sort -u "$trigger_set_file")

declare -a SKILL_NAMES SKILL_PATHS SKILL_ISSUES SKILL_VOICE
TOTAL=0
FULL=0
MISS_TRIG=0
MISS_RUN=0
MISS_SOUL=0
VOICE_LOW=0
DUPLICATES=0

# Track names seen across roots
seen_names_file=$(mktemp -t skill-coverage-seen-XXXXXX)
trap 'rm -f "$trigger_set_file" "$seen_names_file"' EXIT

for root in "${ROOTS[@]}"; do
  [ -d "$root" ] || continue
  for skill_dir in "$root"/*/; do
    [ -d "$skill_dir" ] || continue
    name=$(basename "$skill_dir")
    [ "$name" = "_quarantine" ] && continue
    [ "$name" = "_archive" ] && continue

    if [ -n "$SKILL_FILTER" ] && [ "$name" != "$SKILL_FILTER" ]; then continue; fi

    # Detect duplicates across roots
    if grep -qFx "$name" "$seen_names_file" 2>/dev/null; then
      DUPLICATES=$((DUPLICATES + 1))
    else
      echo "$name" >> "$seen_names_file"
    fi

    TOTAL=$((TOTAL + 1))

    issues=()

    # SKILL.md check
    if [ -f "$skill_dir/SKILL.md" ]; then
      if ! grep -qE '^name:[[:space:]]*' "$skill_dir/SKILL.md" 2>/dev/null; then
        issues+=("SKILL.md missing 'name:' frontmatter")
      fi
    else
      issues+=("missing SKILL.md")
    fi

    # SOUL.md + voice score
    voice_score=""
    if [ -f "$skill_dir/SOUL.md" ]; then
      if [ -f "$VOICE_SCORER" ]; then
        voice_json=$(python3 "$VOICE_SCORER" "$skill_dir/SOUL.md" 2>/dev/null)
        voice_score=$(echo "$voice_json" | jq -r '.score // empty' 2>/dev/null)
        if [ -n "$voice_score" ]; then
          # Bash 3.2: integer compare; floor the score
          voice_int=${voice_score%.*}
          [ -z "$voice_int" ] && voice_int=0
          if [ "$voice_int" -lt "$VOICE_MIN" ]; then
            issues+=("voice_score=$voice_score (<$VOICE_MIN)")
            VOICE_LOW=$((VOICE_LOW + 1))
          fi
        fi
      fi
    else
      issues+=("missing SOUL.md")
      MISS_SOUL=$((MISS_SOUL + 1))
    fi

    # run.sh check
    if [ -f "$skill_dir/run.sh" ]; then
      if [ ! -x "$skill_dir/run.sh" ]; then
        issues+=("run.sh not executable")
      fi
    else
      # Some skills are pure-prose SKILL.md — they declare on-call:true. Allow that.
      if [ -f "$skill_dir/SKILL.md" ] && grep -qE '^on-call:[[:space:]]*true' "$skill_dir/SKILL.md" 2>/dev/null; then
        : # OK — on-call (no run.sh required)
      else
        issues+=("missing run.sh")
        MISS_RUN=$((MISS_RUN + 1))
      fi
    fi

    # Trigger check
    has_trigger=0
    if echo "$trigger_set_sorted" | grep -qFx "$name" 2>/dev/null; then
      has_trigger=1
    fi
    # Or SKILL.md declares scheduled/trigger/on-call
    if [ -f "$skill_dir/SKILL.md" ]; then
      if grep -qE '^(scheduled|trigger|on-call):[[:space:]]*[^[:space:]]' "$skill_dir/SKILL.md" 2>/dev/null; then
        has_trigger=1
      fi
    fi
    if [ "$has_trigger" -eq 0 ]; then
      issues+=("no trigger (no plist, no cron, no on-call)")
      MISS_TRIG=$((MISS_TRIG + 1))
    fi

    if [ ${#issues[@]} -eq 0 ]; then
      FULL=$((FULL + 1))
    fi

    SKILL_NAMES+=("$name")
    SKILL_PATHS+=("$skill_dir")
    SKILL_ISSUES+=("${issues[*]}")
    SKILL_VOICE+=("${voice_score:-null}")
  done
done

# Output
print_human() {
  echo "[skill-coverage-monitor] $TOTAL skills walked  voice_min=$VOICE_MIN"
  printf '  fully-covered:    %d\n' "$FULL"
  printf '  missing-trigger:  %d\n' "$MISS_TRIG"
  printf '  missing-run.sh:   %d\n' "$MISS_RUN"
  printf '  missing-SOUL.md:  %d\n' "$MISS_SOUL"
  printf '  voice-below-min:  %d\n' "$VOICE_LOW"
  printf '  duplicates-in-~:  %d\n' "$DUPLICATES"
}

build_json() {
  printf '{"ts":"%s","voice_min":%d,"total":%d,"summary":{"fully_covered":%d,"missing_trigger":%d,"missing_run":%d,"missing_soul":%d,"voice_low":%d,"duplicates":%d},"skills":[' \
    "$TS" "$VOICE_MIN" "$TOTAL" "$FULL" "$MISS_TRIG" "$MISS_RUN" "$MISS_SOUL" "$VOICE_LOW" "$DUPLICATES"
  i=0
  while [ $i -lt $TOTAL ]; do
    [ $i -gt 0 ] && printf ','
    nm="${SKILL_NAMES[$i]}"
    path="${SKILL_PATHS[$i]}"
    iss="${SKILL_ISSUES[$i]}"
    vs="${SKILL_VOICE[$i]}"
    iss_json=$(printf '%s' "$iss" | jq -Rs 'split(" ") | map(select(. != "")) | if length == 0 then [] else . end' 2>/dev/null)
    [ -z "$iss_json" ] && iss_json='[]'
    [ -z "$vs" ] || [ "$vs" = "null" ] && vs="null" || vs="\"$vs\""
    printf '{"name":"%s","path":"%s","voice_score":%s,"issues":%s}' "$nm" "$path" "$vs" "$iss_json"
    i=$((i+1))
  done
  printf ']}'
}

JSON_OUT=$(build_json)

if [ "$JSON_ONLY" -eq 1 ]; then
  echo "$JSON_OUT"
else
  print_human
fi

if [ -n "$REPORT_PATH" ]; then
  mkdir -p "$(dirname "$REPORT_PATH")"
  {
    echo "# skill-coverage-monitor — $TS"
    echo
    echo "Voice min: $VOICE_MIN"
    echo
    echo "| Metric | Count |"
    echo "|---|---|"
    echo "| Total skills walked | $TOTAL |"
    echo "| Fully covered | $FULL |"
    echo "| Missing trigger | $MISS_TRIG |"
    echo "| Missing run.sh | $MISS_RUN |"
    echo "| Missing SOUL.md | $MISS_SOUL |"
    echo "| Voice below min | $VOICE_LOW |"
    echo "| Duplicates across roots | $DUPLICATES |"
    echo
    echo "## Issues by skill"
    echo "| Skill | Voice | Issues |"
    echo "|---|---|---|"
    i=0
    while [ $i -lt $TOTAL ]; do
      nm="${SKILL_NAMES[$i]}"
      vs="${SKILL_VOICE[$i]}"
      iss="${SKILL_ISSUES[$i]}"
      [ -z "$iss" ] && iss="(ok)"
      printf '| %s | %s | %s |\n' "$nm" "$vs" "$iss"
      i=$((i+1))
    done
  } > "$REPORT_PATH"
fi

# Exit codes
if [ "$MISS_TRIG" -gt 0 ] || [ "$MISS_RUN" -gt 0 ] || [ "$MISS_SOUL" -gt 0 ]; then
  exit 1
fi
exit 0
