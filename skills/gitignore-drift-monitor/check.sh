#!/usr/bin/env bash
# gitignore-drift-monitor — count uncommitted files, alert on dominant drift class.
set +e
cd ~/Dev/daily-ai-agent-os 2>/dev/null || exit 0

count=$(git status --short 2>/dev/null | wc -l | tr -d ' ')
if [ "$count" -lt 100 ]; then
  echo "STATUS=GREEN detail=$count uncommitted (under 100 threshold)"
  exit 0
fi

# Find the dominant directory class
top_class=$(git status --short 2>/dev/null | awk '{print $2}' | awk -F/ '{print $1"/"$2}' | sort | uniq -c | sort -rn | head -1)
top_count=$(echo "$top_class" | awk '{print $1}')
top_path=$(echo "$top_class" | awk '{print $2}')

if [ "$count" -gt 250 ]; then
  echo "STATUS=RED detail=$count uncommitted, dominant=$top_path ($top_count)"
else
  echo "STATUS=YELLOW detail=$count uncommitted, dominant=$top_path ($top_count)"
fi
