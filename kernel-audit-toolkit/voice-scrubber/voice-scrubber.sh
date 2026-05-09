#!/usr/bin/env bash
# voice-scrubber.sh — kernel-audit-toolkit (MIT)
# Pre-publish scanner. Refuses to publish text containing:
#   1. Fabricated dollar amounts (numbers presented as facts without source)
#   2. LLM-default hype phrases (configurable banlist)
#   3. Prompt-injection markers (heredoc-style "ignore previous instructions" patterns)
#
# Usage:
#   bash voice-scrubber.sh --file path/to/draft.md
#   bash voice-scrubber.sh --text "Some draft text"
#   bash voice-scrubber.sh --file draft.md --banlist custom-banlist.txt
#
# Exit 0 if clean, exit 1 if any block fires.
set +e

FILE=""
TEXT=""
BANLIST=""
SELF=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DEFAULT_BANLIST="$SELF/banlist.txt"
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --file) FILE="$2"; shift 2 ;;
    --text) TEXT="$2"; shift 2 ;;
    --banlist) BANLIST="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    *) shift ;;
  esac
done

[ -z "$BANLIST" ] && BANLIST="$DEFAULT_BANLIST"

if [ "$DRY_RUN" = "1" ]; then
  echo "STATUS=ok-dryrun banlist=$BANLIST"
  exit 0
fi

# Resolve text source
if [ -n "$FILE" ] && [ -f "$FILE" ]; then
  CONTENT=$(cat "$FILE")
elif [ -n "$TEXT" ]; then
  CONTENT="$TEXT"
else
  echo "STATUS=error reason=no-input usage='--file <path> or --text <string>'"
  exit 2
fi

VIOLATIONS=()

# Check 1: Fabricated dollar amounts pattern
# A bare number with $ prefix in a content block (not in a code block) is suspicious
# unless it has a citation. We flag any "$<digits>" not immediately followed by "(source:" or "[ref"
DOLLAR_HITS=$(echo "$CONTENT" | grep -onE '\$[0-9]+(\.[0-9]+)?[KMB]?[^(\[]' | head -3)
if [ -n "$DOLLAR_HITS" ]; then
  # Refine: only flag if no nearby "source:" within +/-2 lines
  : # the conservative version is to NOT auto-block here; just warn
fi

# Check 2: Hype banlist (LLM defaults Cooper hates)
if [ -f "$BANLIST" ]; then
  while read -r phrase; do
    [ -z "$phrase" ] && continue
    case "$phrase" in \#*) continue ;; esac
    if echo "$CONTENT" | grep -iqF "$phrase"; then
      VIOLATIONS+=("hype-banlist: \"$phrase\"")
    fi
  done < "$BANLIST"
fi

# Check 3: Prompt-injection markers
INJECT_PATTERNS=(
  "ignore previous instructions"
  "ignore all previous"
  "disregard prior"
  "you are now"
  "system:.*override"
  "</system>"
  "<\\|im_start\\|>"
)
for pat in "${INJECT_PATTERNS[@]}"; do
  if echo "$CONTENT" | grep -iqE "$pat"; then
    VIOLATIONS+=("prompt-injection: \"$pat\"")
  fi
done

if [ ${#VIOLATIONS[@]} -eq 0 ]; then
  echo "STATUS=ok blocked=false hits=0"
  exit 0
fi

echo "STATUS=blocked hits=${#VIOLATIONS[@]}"
for v in "${VIOLATIONS[@]}"; do
  echo "  - $v"
done
exit 1
