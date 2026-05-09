#!/usr/bin/env bash
# monthly-update-detector/run.sh — cont-19.9-M-builder Phase 2 #5.
# Detection-only stale-skill walker. NEVER auto-bumps timestamps.
set +e

DRY_RUN=0
DIGEST_ONLY=0
THRESHOLD_DAYS=25
OUT_DIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --digest-only) DIGEST_ONLY=1; shift ;;
    --threshold-days) THRESHOLD_DAYS="$2"; shift 2 ;;
    --out-dir) OUT_DIR="$2"; shift 2 ;;
    *) shift ;;
  esac
done

REPO=$(git rev-parse --show-toplevel 2>/dev/null)
[ -z "$REPO" ] && REPO="/Users/bots/Dev/daily-ai-agent-os"
[ -z "$OUT_DIR" ] && OUT_DIR="$REPO/data/curator"
DATE=$(date +%Y-%m-%d)
INDEX="$REPO/data/.well-known/skills/index.json"

if [ "$DRY_RUN" = "1" ]; then
  C=$(find "$REPO/skills" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
  echo "STATUS=ok-dryrun threshold_days=$THRESHOLD_DAYS scope_skills=$C out_dir=$OUT_DIR digest_only=$DIGEST_ONLY"
  exit 0
fi

mkdir -p "$OUT_DIR"

# --- Digest mode (Sunday 09:30 CT) ---
if [ "$DIGEST_ONLY" = "1" ]; then
  WEEK_STALE=0
  TOP_STALE_FILE=$(mktemp -t stale-digest-XXXXXX)
  trap 'rm -f "$TOP_STALE_FILE"' EXIT
  # Find latest stale-skills file
  LATEST=$(ls -1t "$OUT_DIR"/stale-skills-*.md 2>/dev/null | head -1)
  if [ -z "$LATEST" ]; then
    echo "STATUS=ok mode=digest week_stale=0 silent=true note=no-daily-reports-found"
    exit 0
  fi
  WEEK_STALE=$(grep -c "^- " "$LATEST" 2>/dev/null || echo 0)
  if [ "$WEEK_STALE" = "0" ]; then
    echo "STATUS=ok mode=digest week_stale=0 silent=true"
    exit 0
  fi
  DIGEST_PATH="$OUT_DIR/stale-digest-$DATE.md"
  {
    echo "Stale skills week ending $DATE:"
    echo "Total ≥${THRESHOLD_DAYS}d-stale: $WEEK_STALE"
    echo "Top 10 by quality_score:"
    grep "^- " "$LATEST" | head -10
    echo ""
    echo "Source: $LATEST"
  } > "$DIGEST_PATH"
  echo "STATUS=ok mode=digest week_stale=$WEEK_STALE message_path=$DIGEST_PATH"
  exit 0
fi

# --- Daily scan mode ---
NOW=$(date +%s)
SEC_THRESHOLD=$((THRESHOLD_DAYS * 86400))
REPORT="$OUT_DIR/stale-skills-$DATE.md"

# Use index if present (fast path)
STALE_FILE=$(mktemp -t stale-XXXXXX)
trap 'rm -f "$STALE_FILE"' EXIT
SCANNED=0
STALE_N=0

if [ -f "$INDEX" ]; then
  # Parse via python3 utility — index already has last_updated field
  python3 - "$INDEX" "$THRESHOLD_DAYS" "$STALE_FILE" <<'PYEOF'
import sys, json, datetime
index_path, threshold_days, out_path = sys.argv[1], int(sys.argv[2]), sys.argv[3]
idx = json.load(open(index_path))
today = datetime.date.today()
stale = []
for s in idx["skills"]:
    lu = s.get("last_updated")
    if not lu:
        continue
    try:
        d = datetime.date.fromisoformat(lu)
    except Exception:
        continue
    age = (today - d).days
    if age >= threshold_days:
        stale.append((s["name"], s.get("owner_agent"), age, s.get("quality_score")))
# sort by quality_score desc (None last), then age desc
stale.sort(key=lambda r: (-(r[3] if r[3] is not None else -1), -r[2]))
with open(out_path, "w") as fh:
    for name, owner, age, qs in stale:
        owner_s = owner if owner else "—"
        qs_s = f"{qs}" if qs is not None else "—"
        fh.write(f"- `{name}` (owner: {owner_s}, age: {age}d, quality: {qs_s})\n")
print(f"SCANNED={len(idx['skills'])} STALE={len(stale)}")
PYEOF
  RC=$?
  if [ "$RC" != "0" ]; then
    echo "STATUS=error reason=index-parse-failed"
    exit 1
  fi
  SCANNED=$(find "$REPO/skills" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
  STALE_N=$(wc -l < "$STALE_FILE" | tr -d ' ')
else
  # Fallback: direct registry walk
  for d in "$REPO/skills"/*/; do
    [ -d "$d" ] || continue
    name=$(basename "$d")
    [ "$name" = "_quarantine" ] && continue
    [ "$name" = "_archive" ] && continue
    SCANNED=$((SCANNED+1))
    newest=0
    for f in "$d"/*; do
      [ -f "$f" ] || continue
      m=$(stat -f %m "$f" 2>/dev/null)
      [ -n "$m" ] && [ "$m" -gt "$newest" ] && newest=$m
    done
    [ "$newest" = "0" ] && continue
    age_sec=$((NOW - newest))
    if [ "$age_sec" -ge "$SEC_THRESHOLD" ]; then
      age_d=$((age_sec / 86400))
      echo "- \`$name\` (age: ${age_d}d)" >> "$STALE_FILE"
      STALE_N=$((STALE_N + 1))
    fi
  done
fi

# Write report
{
  echo "# Stale Skills — $DATE"
  echo
  echo "**Threshold:** ${THRESHOLD_DAYS} days since newest file mtime"
  echo "**Scanned:** $SCANNED canonical skills"
  echo "**Stale:** $STALE_N"
  echo
  echo "## Stale list (sorted by quality_score desc)"
  echo
  if [ "$STALE_N" -gt 0 ]; then
    cat "$STALE_FILE"
  else
    echo "_None._"
  fi
  echo
  echo "---"
  echo "_This is detection-only output. NO timestamps were modified. Cooper decides what to refresh._"
} > "$REPORT"

echo "STATUS=ok scanned=$SCANNED stale=$STALE_N threshold_days=$THRESHOLD_DAYS report=$REPORT"
