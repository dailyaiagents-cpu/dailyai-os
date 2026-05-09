---
name: cron-self-heal
description: Watcher — surfaces crons in error state. RED if >33% failing, YELLOW otherwise. Future: glob-match per-skill expected_output_glob frontmatter for richer health.
scheduled: dispatched by substrate-watchers every cycle
---

# cron-self-heal

## Procedure

```bash
out=$(bash ~/.openclaw/skills/cron-self-heal/check.sh)
echo "$out"
# On RED: trust-graph-checked alert (no auto-fix; cron errors need investigation)
status=$(echo "$out" | grep -oE 'STATUS=(GREEN|YELLOW|RED)' | cut -d= -f2)
if [ "$status" = "RED" ]; then
  python3 ~/Dev/daily-ai-agent-os/tools/notify/telegram_send.py --text "[cron-self-heal] $(echo $out | sed 's/.*detail=//')" 2>/dev/null || true
fi
```
