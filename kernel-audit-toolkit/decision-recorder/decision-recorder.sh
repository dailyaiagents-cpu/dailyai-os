#!/usr/bin/env bash
# decision-recorder.sh — kernel-audit-toolkit (MIT)
# Drop-in: log every routing / budget / escalation decision your agents make,
# with rationale + counterfactual, to a JSONL file you can replay.
#
# Usage:
#   bash decision-recorder.sh --decision "<what>" --rationale "<why>" \
#     --counterfactual "<what-would-have-happened-otherwise>" \
#     [--cost-usd 0.04] [--actor agent-name] [--tags route,budget]
#
# Output: appends one JSON line to data/decisions/log.jsonl (or $LOG_PATH)
set +e

DECISION=""
RATIONALE=""
COUNTERFACTUAL=""
COST_USD=""
ACTOR="unknown"
TAGS=""
LOG_PATH="${DECISION_LOG_PATH:-./data/decisions/log.jsonl}"
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --decision) DECISION="$2"; shift 2 ;;
    --rationale) RATIONALE="$2"; shift 2 ;;
    --counterfactual) COUNTERFACTUAL="$2"; shift 2 ;;
    --cost-usd) COST_USD="$2"; shift 2 ;;
    --actor) ACTOR="$2"; shift 2 ;;
    --tags) TAGS="$2"; shift 2 ;;
    --log-path) LOG_PATH="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    *) shift ;;
  esac
done

if [ "$DRY_RUN" = "1" ]; then
  echo "STATUS=ok-dryrun would_log=$LOG_PATH actor=$ACTOR"
  exit 0
fi

[ -z "$DECISION" ] && { echo "STATUS=error reason=no-decision usage='--decision <text>'"; exit 2; }

mkdir -p "$(dirname "$LOG_PATH")"

TS=$(date -u +%FT%T.%3NZ)

python3 - "$LOG_PATH" "$TS" "$ACTOR" "$DECISION" "$RATIONALE" "$COUNTERFACTUAL" "$COST_USD" "$TAGS" <<'PYEOF'
import sys, json
out_path, ts, actor, decision, rationale, counterfactual, cost, tags = sys.argv[1:9]
record = {
    "ts": ts,
    "actor": actor,
    "decision": decision,
    "rationale": rationale,
    "counterfactual": counterfactual,
    "cost_usd": float(cost) if cost else None,
    "tags": [t.strip() for t in tags.split(",") if t.strip()],
}
with open(out_path, "a") as fh:
    fh.write(json.dumps(record) + "\n")
PYEOF

echo "STATUS=ok recorded=1 path=$LOG_PATH"
