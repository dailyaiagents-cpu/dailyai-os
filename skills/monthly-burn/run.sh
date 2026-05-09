#!/usr/bin/env bash
set -a
[ -f /Users/bots/Dev/daily-ai-agent-os/.env ] && source /Users/bots/Dev/daily-ai-agent-os/.env
set +a
# monthly-burn/run.sh — aggregate monthly cost-by-source.
# cont-18 Phase H.1.
set +e

REPO=/Users/bots/Dev/daily-ai-agent-os
OUT_DIR="$REPO/data/finance/burn"
MANUAL_DIR="$REPO/data/finance/manual"
TODAY=$(date -u +%Y-%m-%d)
MONTH=$(date -u +%Y-%m)
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --month) MONTH="$2"; shift 2 ;;
    --month=*) MONTH="${1#*=}"; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    *) echo "STATUS=error reason=unknown-flag flag=$1"; exit 2 ;;
  esac
done

mkdir -p "$OUT_DIR" "$MANUAL_DIR"

read_manual() {
  local source="$1"
  local f="$MANUAL_DIR/${source}-${MONTH}.txt"
  if [ -f "$f" ]; then
    # File contains a single dollar amount or a number.
    local v
    v=$(cat "$f" | tr -d '$,' | head -1)
    echo "$v"
  fi
}

# === Sources ===
# cont-19 E.1: hard-coded defaults for sources we know are stable.
# Codex OAuth = $20/mo (ChatGPT Plus subscription). Hermes uses this; no
# Anthropic-direct API path (per cont-18 token-caching audit). The "Anthropic"
# row in this report is therefore the Codex line, renamed.
CODEX_OAUTH="20.00"
ANTHROPIC=$(read_manual anthropic)
# Stripe fees + GitHub Actions: $0 today (no Stripe revenue, no CI minutes
# consumed beyond GitHub free tier). Manual entries override the hard-coded $0.
STRIPE_FEES=${STRIPE_FEES:-"0.00"}
GITHUB_ACTIONS=${GITHUB_ACTIONS:-"0.00"}

# ElevenLabs from existing usage file (if any)
ELEVENLABS=""
EL_FILE="$REPO/data/voice/elevenlabs_usage.json"
if [ -f "$EL_FILE" ]; then
  ELEVENLABS=$(python3 -c "
import json, sys
try:
    d = json.load(open('$EL_FILE'))
    # crude estimate: characters * 0.18/1M USD (current rate)
    chars = d.get('total_chars_this_month', 0)
    print(f'{chars * 0.18 / 1_000_000:.2f}')
except Exception:
    print('')
" 2>/dev/null)
fi

# Cloudflare — placeholder (worker not yet deployed per cont-10)
CLOUDFLARE="0.00"

# Domain registrations — from JSON if exists, pro-rated
DOMAINS=""
DOM_FILE="$REPO/data/finance/domain-registrations.json"
if [ -f "$DOM_FILE" ]; then
  DOMAINS=$(python3 -c "
import json
try:
    d = json.load(open('$DOM_FILE'))
    monthly = sum(item.get('annual_cost', 0) / 12.0 for item in d.get('domains', []))
    print(f'{monthly:.2f}')
except Exception:
    print('')
" 2>/dev/null)
fi

# === Compose ===
# cont-19 E.1: emit row + classify in same scope (fixes cont-18 subshell bug
# where totals[]/gaps[] wouldn't propagate from $(fmt_row ...) command-substitution).
gaps=()
totals=()
ROWS=()

emit_row() {
  local source="$1"
  local val="$2"
  local sot="$3"
  if [ -z "$val" ]; then
    ROWS+=("| $source | Cooper-manual-entry | $sot | manual gap |")
    gaps+=("$source")
  else
    ROWS+=("| $source | \$$val | $sot | automated |")
    totals+=("$val")
  fi
}

emit_row 'Codex OAuth (ChatGPT Plus)' "$CODEX_OAUTH" 'cont-19 E.1: hard-coded $20/mo subscription'
emit_row 'Anthropic API direct' "${ANTHROPIC:-0.00}" 'data/finance/manual/anthropic-<YYYY-MM>.txt (default $0; not used)'
emit_row 'ElevenLabs' "$ELEVENLABS" 'data/voice/elevenlabs_usage.json'
emit_row 'Cloudflare' "$CLOUDFLARE" 'placeholder — worker not yet deployed'
emit_row 'Stripe fees' "$STRIPE_FEES" 'cont-19 E.1: $0 default; manual override at data/finance/manual/stripe-fees-<YYYY-MM>.txt'
emit_row 'GitHub Actions' "$GITHUB_ACTIONS" 'cont-19 E.1: $0 default; under GitHub free tier'
emit_row 'Domain registrations' "$DOMAINS" 'data/finance/domain-registrations.json'

TOTAL=0
for v in "${totals[@]}"; do
  TOTAL=$(echo "$TOTAL + $v" | bc -l 2>/dev/null || echo "$TOTAL")
done

# === Write report ===
OUT="$OUT_DIR/$MONTH.md"
TMP="$OUT.tmp"

{
  echo "# Monthly burn — $MONTH"
  echo
  echo "_Generated $TODAY. Manual-entry rows are gaps; each one points at the next MCP wrapper or file format to automate._"
  echo
  echo "## Sources"
  echo
  echo "| Source | This month | Source-of-truth | Status |"
  echo "|---|---|---|---|"
  for r in "${ROWS[@]}"; do
    echo "$r"
  done
  echo "| **Total burn (automated only)** | **\$$(printf '%.2f' "$TOTAL" 2>/dev/null || echo "$TOTAL")** | | |"
  echo
  if [ "${#gaps[@]}" -gt 0 ]; then
    echo "## Manual-entry gaps"
    echo
    for g in "${gaps[@]}"; do
      echo "- **$g** — drop a single dollar amount in the source-of-truth file before next month's run."
    done
    echo
  fi
  echo "## Cooper actions"
  echo
  echo "1. Drop manual entries for any \`Cooper-manual-entry\` rows above."
  echo "2. When Stripe MCP comes back online, this skill will auto-pull the fees row."
  echo "3. When the verify-license Cloudflare Worker deploys (cont-10 K.7), wire the CF row to its metrics."
  echo
  echo "---"
  echo
  echo "_Generator: skills/monthly-burn @ $(date -u +%FT%TZ)_"
} > "$TMP"

if [ "$DRY_RUN" = "1" ]; then
  cat "$TMP"
  rm -f "$TMP"
  echo "STATUS=ok-dryrun month=$MONTH gaps=${#gaps[@]}"
  exit 0
fi

mv "$TMP" "$OUT"
echo "STATUS=ok month=$MONTH out=$OUT total=\$$(printf '%.2f' "$TOTAL" 2>/dev/null) manual_gaps=${#gaps[@]}"
