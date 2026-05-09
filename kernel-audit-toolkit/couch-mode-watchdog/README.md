# couch-mode-watchdog

Five health checks every 5 minutes. Bash + curl. No agents, no daemons.

## What it checks

1. Disk free > 10%
2. CPU load < 4× cores
3. Ollama reachable at `127.0.0.1:11434` (skipped if not configured)
4. No `FATAL` / `Traceback` in last 5min of log dirs
5. Heartbeat file freshness < 10 min

Each check is a bash function. Edit, remove, add — all visible.

## Install

```bash
cp -r couch-mode-watchdog/ /your/agents/lib/
```

## Run

```bash
# Standalone
bash couch-mode-watchdog.sh

# With alert hook (any executable taking the message as $1)
bash couch-mode-watchdog.sh --alert-hook ./bin/telegram-send.sh

# Cron, every 5 min
*/5 * * * * cd /your/repo && bash kernel-audit-toolkit/couch-mode-watchdog/couch-mode-watchdog.sh --alert-hook ./bin/alert.sh
```

## Customize alert hook

Your `alert.sh` receives the alert message as `$1`. Wire it to whatever notifies you:

```bash
#!/bin/bash
# bin/telegram-send.sh
curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
  -d "chat_id=$CHAT_ID" -d "text=$1"
```

## License

MIT.
