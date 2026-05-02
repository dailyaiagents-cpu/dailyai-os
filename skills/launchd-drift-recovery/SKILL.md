---
name: launchd-drift-recovery
description: Watcher — kickstart -k drifted critical plists. Trust-graph-gated, throttled to 1 kickstart per plist per hour.
scheduled: dispatched by substrate-watchers every cycle
---

# launchd-drift-recovery

## Procedure

```bash
out=$(bash ~/.openclaw/skills/launchd-drift-recovery/check.sh)
echo "$out"
status=$(echo "$out" | grep -oE 'STATUS=(GREEN|YELLOW|RED)' | cut -d= -f2)
if [ "$status" != "GREEN" ]; then
  detail=$(echo "$out" | sed 's/.*detail=//')
  # Try kickstart -k for each drifted plist (parse "name=state" tokens)
  for token in $(echo "$detail" | tr ',' ' '); do
    plist=$(echo "$token" | cut -d= -f1)
    [ -z "$plist" ] && continue
    [ "$plist" = "drifted:" ] && continue

    # Trust-graph check
    CHECK=$(python3 ~/Dev/daily-ai-agent-os/tools/approvals/resolve_gate.py \
      --check-autonomous --skill launchd-drift-recovery --domain service_restart \
      --usd 0 --reversibility hard 2>/dev/null)
    AUTO=$(echo "$CHECK" | jq -r '.autonomous')

    if [ "$AUTO" = "true" ]; then
      echo "  auto-kickstart $plist"
      launchctl kickstart -k "gui/$(id -u)/$plist" 2>&1 | head -3
    else
      python3 ~/Dev/daily-ai-agent-os/tools/notify/telegram_send.py \
        --text "[launchd-drift] $plist drifted; trust-graph denied auto-fix: $(echo $CHECK | jq -r '.reason')" 2>/dev/null || true
    fi
  done
fi
```
