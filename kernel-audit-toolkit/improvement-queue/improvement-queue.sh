#!/usr/bin/env bash
# improvement-queue.sh — kernel-audit-toolkit (MIT)
# Reads improvement proposals (one JSON file per proposal in a queue dir),
# scores each by (impact × confidence) / cost, surfaces top-3 to a digest.
#
# Run nightly via cron. Pair with the digest file in your morning brief.
#
# Proposal schema:
# {
#   "title": "<short>",
#   "impact": 0-10,
#   "confidence": 0.0-1.0,
#   "cost_hours": <float>,
#   "owner": "<agent-or-person>",
#   "submitted_at": "<ISO>"
# }
set +e

QUEUE_DIR="${QUEUE_DIR:-./data/improvement-queue}"
OUT_PATH="${OUT_PATH:-./data/improvement-queue/digest-$(date +%Y-%m-%d).md}"
TOP_N=3
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --queue-dir) QUEUE_DIR="$2"; shift 2 ;;
    --out) OUT_PATH="$2"; shift 2 ;;
    --top) TOP_N="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    *) shift ;;
  esac
done

[ -d "$QUEUE_DIR" ] || { echo "STATUS=error reason=no-queue-dir path=$QUEUE_DIR"; exit 1; }

if [ "$DRY_RUN" = "1" ]; then
  N=$(find "$QUEUE_DIR" -maxdepth 1 -name '*.json' -type f 2>/dev/null | wc -l | tr -d ' ')
  echo "STATUS=ok-dryrun proposals_found=$N top_n=$TOP_N out=$OUT_PATH"
  exit 0
fi

mkdir -p "$(dirname "$OUT_PATH")"

python3 - "$QUEUE_DIR" "$OUT_PATH" "$TOP_N" <<'PYEOF'
import sys, json, os, glob, datetime
queue_dir, out_path, top_n_s = sys.argv[1:4]
top_n = int(top_n_s)
proposals = []
for f in sorted(glob.glob(os.path.join(queue_dir, "*.json"))):
    try:
        p = json.load(open(f))
    except Exception:
        continue
    impact = float(p.get("impact", 0))
    conf = float(p.get("confidence", 0))
    cost = float(p.get("cost_hours", 0)) or 0.5
    score = (impact * conf) / max(cost, 0.1)
    p["_score"] = round(score, 3)
    p["_file"] = os.path.basename(f)
    proposals.append(p)
proposals.sort(key=lambda r: -r["_score"])
top = proposals[:top_n]
with open(out_path, "w") as fh:
    fh.write(f"# Improvement Queue Digest — {datetime.date.today().isoformat()}\n\n")
    fh.write(f"Total proposals: {len(proposals)} · top {top_n}\n\n")
    for i, p in enumerate(top, 1):
        fh.write(f"## {i}. {p.get('title', p['_file'])}\n")
        fh.write(f"- Score: **{p['_score']}** (impact={p.get('impact')} × conf={p.get('confidence')} / cost_hrs={p.get('cost_hours')})\n")
        fh.write(f"- Owner: {p.get('owner', 'unassigned')}\n")
        fh.write(f"- Submitted: {p.get('submitted_at', '?')}\n")
        fh.write(f"- File: `{p['_file']}`\n\n")
print(f"STATUS=ok proposals={len(proposals)} top={len(top)} out={out_path}")
PYEOF
