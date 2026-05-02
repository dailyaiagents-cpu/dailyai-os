#!/usr/bin/env bash
# launchd-drift-recovery — detect launchd plists that are loaded but not running
# when they should be (RunAtLoad=true, KeepAlive=true).
set +e

# Critical plists that should ALWAYS be running
CRITICAL=(
  ai.openclaw.gateway
  ai.openclaw.dispatcher
  ai.hermes.gateway
  com.dailyai.budget-proxy
)

drifted=()
for plist in "${CRITICAL[@]}"; do
  # The TOP-level state line is "\tstate = running" — nested ones are deeper-indented.
  state=$(launchctl print "gui/$(id -u)/$plist" 2>&1 | grep -E '^\s*state\s*=' | head -1 | sed 's/^[[:space:]]*state[[:space:]]*=[[:space:]]*//' | tr -d '[:space:]')
  if [ -z "$state" ]; then
    drifted+=("$plist=missing")
  elif [ "$state" != "running" ]; then
    drifted+=("$plist=$state")
  fi
done

if [ "${#drifted[@]}" -eq 0 ]; then
  echo "STATUS=GREEN detail=${#CRITICAL[@]} critical plists running"
elif [ "${#drifted[@]}" -lt "${#CRITICAL[@]}" ]; then
  echo "STATUS=YELLOW detail=drifted: $(IFS=','; echo "${drifted[*]}")"
else
  echo "STATUS=RED detail=ALL critical plists drifted: $(IFS=','; echo "${drifted[*]}")"
fi
