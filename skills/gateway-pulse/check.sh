#!/usr/bin/env bash
# gateway-pulse — probe the four pillars. Single-line stdout: STATUS=GREEN|YELLOW|RED detail=...
set +e

dets=()
status="GREEN"

# Hermes — Telegram polling client, no HTTP health endpoint. Check the
# launchd-managed PID instead. Port 4010 was the OLD budget-proxy probe;
# fixed in v18-A.10 after Cooper observed substrate=RED while Hermes was
# actively replying to Telegram.
HERMES_LIST=$(launchctl list 2>/dev/null | awk '$3=="ai.hermes.gateway" {print $1}')
if [ -n "$HERMES_LIST" ] && [ "$HERMES_LIST" != "-" ]; then
  dets+=("hermes:ok")
else
  dets+=("hermes:DOWN")
  status="RED"
fi

# OpenClaw — port 18789
if nc -z -w2 127.0.0.1 18789 2>/dev/null; then
  dets+=("openclaw:ok")
else
  dets+=("openclaw:DOWN")
  status="RED"
fi

# Paperclip — DEMOTED 2026-05-09 (cont-19.10). Paperclip is a PARKED operator
# surface, not a substrate pillar. Probe the port for observability so the
# detail field is informative, but a paperclip-down state must NOT flip
# gateway-pulse from GREEN. See .claude/skills/operator-surface-pulse/
# for the operator-surface health gate.
if curl -sf --max-time 3 -o /dev/null http://127.0.0.1:3100/ 2>/dev/null; then
  dets+=("paperclip:ok")
else
  dets+=("paperclip:parked")
fi

# Obsidian — port 27124 (https with token)
if curl -sk --max-time 3 -o /dev/null -w "%{http_code}" https://127.0.0.1:27124/ 2>/dev/null | grep -qE '^(200|401)$'; then
  dets+=("obsidian:ok")
else
  dets+=("obsidian:DOWN")
  if [ "$status" = "GREEN" ]; then status="YELLOW"; fi
fi

echo "STATUS=$status detail=$(IFS=' '; echo "${dets[*]}")"
