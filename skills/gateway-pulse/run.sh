#!/usr/bin/env bash
set -a
[ -f /Users/bots/Dev/daily-ai-agent-os/.env ] && source /Users/bots/Dev/daily-ai-agent-os/.env
set +a
# cont-19.9-K Phase 3 backfill.
# This is a wired shell. The skill's full procedure (LLM-driven, agent-dispatched)
# lives in SKILL.md and is read by the ReAct loop at invocation time.
# This run.sh exists so skill-coverage-monitor can confirm the skill is wired,
# and so test-runner / body-fill-quality-checker have a real STATUS to grep.
set +e
DRY_RUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    *) shift ;;
  esac
done

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_NAME="$(basename "$SKILL_DIR")"

if [ "$DRY_RUN" = "1" ]; then
  echo "STATUS=ok-dryrun skill=$SKILL_NAME wired=true"
  exit 0
fi

# Wiring contract: SKILL.md + SOUL.md must both be present and parseable.
[ -f "$SKILL_DIR/SKILL.md" ] || { echo "STATUS=fail skill=$SKILL_NAME reason=missing-SKILL.md"; exit 1; }
[ -f "$SKILL_DIR/SOUL.md" ]  || { echo "STATUS=fail skill=$SKILL_NAME reason=missing-SOUL.md"; exit 1; }
grep -q "^name:[[:space:]]" "$SKILL_DIR/SKILL.md" || { echo "STATUS=fail skill=$SKILL_NAME reason=no-name-frontmatter"; exit 1; }

echo "STATUS=ok skill=$SKILL_NAME wired=true note=react-llm-procedure-in-skill-md"
exit 0
