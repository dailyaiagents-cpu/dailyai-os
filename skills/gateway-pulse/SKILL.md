---
name: gateway-pulse
description: Probe Hermes/OpenClaw/Paperclip/Obsidian. RED on outage. Auto-bootstrap if trust-graph allows (skill=gateway-pulse, domain=service_restart, score≥0.8). Pure bash + curl + nc.
scheduled: dispatched by ~/.openclaw/skills/substrate-watchers/SKILL.md every cycle
---

# gateway-pulse

## Procedure

### Step 1 — Probe via check.sh

```bash
out=$(bash ~/.openclaw/skills/gateway-pulse/check.sh)
status=$(echo "$out" | grep -oE 'STATUS=(GREEN|YELLOW|RED)' | cut -d= -f2)
detail=$(echo "$out" | sed 's/.*detail=//')
echo "[gateway-pulse] $status — $detail"
```

### Step 2 — On RED, check trust-graph for auto-bootstrap

```bash
if [ "$status" = "RED" ]; then
  CHECK=$(python3 ~/Dev/daily-ai-agent-os/tools/approvals/resolve_gate.py \
    --check-autonomous --skill gateway-pulse --domain service_restart \
    --usd 0 --reversibility hard 2>/dev/null)
  AUTO=$(echo "$CHECK" | jq -r '.autonomous')

  if [ "$AUTO" = "true" ]; then
    # Throttle: don't bootstrap more than once per hour
    LAST=$(stat -f %m ~/.openclaw/state/gateway-pulse-last-bootstrap.ts 2>/dev/null || echo 0)
    NOW=$(date +%s)
    if [ $((NOW - LAST)) -gt 3600 ]; then
      echo "[gateway-pulse] auto-bootstrap (trust-graph approved)"
      bash ~/Dev/daily-ai-agent-os/scripts/bootstrap.sh 2>&1 | tail -5
      date +%s > ~/.openclaw/state/gateway-pulse-last-bootstrap.ts
    else
      echo "[gateway-pulse] throttled (last bootstrap $((NOW - LAST))s ago)"
    fi
  else
    # Trust-graph said no — open approval gate
    REASON=$(echo "$CHECK" | jq -r '.reason')
    python3 ~/Dev/daily-ai-agent-os/tools/approvals/resolve_gate.py --create \
      --agent ops --action SERVICE_RESTART \
      --reason "Pillars down: $detail. Bootstrap?" \
      --evidence "~/.openclaw/state/substrate-health.json" \
      --reversibility hard --timeout-min 30 2>/dev/null
  fi
fi
```

## Self-test

```bash
bash ~/.openclaw/skills/gateway-pulse/check.sh
```
