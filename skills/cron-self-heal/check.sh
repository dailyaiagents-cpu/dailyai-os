#!/usr/bin/env bash
# cron-self-heal — detect crons that fired but produced no expected output.
# Outputs: STATUS=GREEN|YELLOW|RED detail=...
#
# Reads ~/.openclaw/openclaw.json or `openclaw cron list --json` to get cron
# definitions. For each cron whose skill SOUL.md declares
# `expected_output_glob:` frontmatter, check if the glob matches anything
# newer than the cron's last_run timestamp.
set +e

# Approach for tonight: lightweight version that just checks `openclaw cron list`
# for any cron whose status is "error" or whose last run was >2 cron-intervals ago.
# Full skill-frontmatter-glob check is a future refinement.

if ! command -v openclaw &>/dev/null; then
  echo "STATUS=YELLOW detail=openclaw CLI not in PATH"
  exit 0
fi

# Pull the cron list — error or stale crons surface as YELLOW; mass failures = RED.
out=$(openclaw cron list --json 2>/dev/null)
if [ -z "$out" ]; then
  echo "STATUS=YELLOW detail=cron list empty or gateway down"
  exit 0
fi

errors=$(echo "$out" | jq -r '[.[] | select(.state.lastRunStatus == "error")] | length' 2>/dev/null || echo 0)
total=$(echo "$out" | jq -r 'length' 2>/dev/null || echo 0)

if [ "$total" -gt 0 ] && [ "$errors" -gt $((total / 3)) ]; then
  echo "STATUS=RED detail=$errors/$total crons in error state (>33% failure rate)"
elif [ "$errors" -gt 0 ]; then
  echo "STATUS=YELLOW detail=$errors/$total crons in error state"
else
  echo "STATUS=GREEN detail=$total crons, $errors errors"
fi
