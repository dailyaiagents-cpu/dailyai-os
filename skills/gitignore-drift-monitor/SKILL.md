---
name: gitignore-drift-monitor
description: Watcher — count uncommitted files in repo, surface dominant drift class. YELLOW >100, RED >250.
scheduled: dispatched by substrate-watchers every cycle (or daily 0 12 * * *)
---

# gitignore-drift-monitor

## Procedure

```bash
out=$(bash ~/.openclaw/skills/gitignore-drift-monitor/check.sh)
echo "$out"
# No auto-fix — propose gitignore extension via approval-gate on RED
status=$(echo "$out" | grep -oE 'STATUS=(GREEN|YELLOW|RED)' | cut -d= -f2)
if [ "$status" = "RED" ]; then
  python3 ~/Dev/daily-ai-agent-os/tools/approvals/resolve_gate.py --create \
    --agent ops --action GITIGNORE_PROPOSAL \
    --reason "$(echo $out | sed 's/.*detail=//')" \
    --evidence "git status --short output" \
    --reversibility easy --timeout-min 1440 2>/dev/null
fi
```
