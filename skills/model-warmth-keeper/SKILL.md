---
name: model-warmth-keeper
description: Ping primary local LLM models every 4 min during business hours so cold eviction doesn't bite the next dispatcher fork. Logs to ~/.openclaw/logs/warmth-keeper.log. Telegrams PROBLEM only after 15+ min straight unreachable.
triggered_by: hermes-on-demand (CEO dispatches via openclaw agent when reasoning calls for this skill)
---

# model-warmth-keeper

## Why this exists

2026-04-28 NIGHT-1 run logged: `Ollama qwen3.6/qwen3.5 hit llm-idle-timeout watchdog`. Models eviction-time out during idle, next dispatch waits 30+s for warmup, occasionally that warmup itself OOMs because two models race for memory. This skill keeps the primary specialists warm with cheap 1-token pings.

## Models pinged

| Provider | Endpoint | Models |
|----------|----------|--------|
| Ollama | http://127.0.0.1:11434/api/generate | `qwen3.6:latest`, `qwen3.5:latest`, `qwen3.5:27B` |
| LM Studio | http://127.0.0.1:1234/v1/chat/completions | `qwen/qwen3-coder-next` |

## Procedure

### Step 1 — Time-of-day guard

```python
import datetime
hour = datetime.datetime.now().hour
# Skip pings during 00:00–05:59 CT (Mac is set to America/Chicago).
# That's "off hours" — pings can be skipped to save battery / power.
if hour < 6:
    print("[warmth-keeper] off-hours, skipping ping cycle")
    raise SystemExit(0)
```

### Step 2 — Ping each model

```python
import urllib.request, json, time, pathlib
LOG = pathlib.Path.home() / ".openclaw/logs/warmth-keeper.log"
LOG.parent.mkdir(parents=True, exist_ok=True)

def log(msg):
    with open(LOG, "a") as f:
        f.write(f"{datetime.datetime.utcnow().isoformat()}Z {msg}\n")

OLLAMA_MODELS = ["qwen3.6:latest", "qwen3.5:latest", "qwen3.5:27B"]
LMSTUDIO_MODELS = ["qwen/qwen3-coder-next"]

def ping_ollama(model):
    body = json.dumps({"model": model, "prompt": "OK", "stream": False, "options": {"num_predict": 1}}).encode()
    req = urllib.request.Request("http://127.0.0.1:11434/api/generate", data=body,
                                 headers={"Content-Type": "application/json"}, method="POST")
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            r.read()
        return ("ok", round(time.time() - t0, 3), None)
    except Exception as e:
        return ("fail", round(time.time() - t0, 3), str(e)[:120])

def ping_lmstudio(model):
    body = json.dumps({
        "model": model,
        "messages": [{"role": "user", "content": "OK"}],
        "max_tokens": 1,
        "stream": False
    }).encode()
    req = urllib.request.Request("http://127.0.0.1:1234/v1/chat/completions", data=body,
                                 headers={"Content-Type": "application/json"}, method="POST")
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            r.read()
        return ("ok", round(time.time() - t0, 3), None)
    except Exception as e:
        return ("fail", round(time.time() - t0, 3), str(e)[:120])

failures = []
for m in OLLAMA_MODELS:
    status, dt, err = ping_ollama(m)
    log(f"ollama {m} {status} {dt}s {err or ''}")
    if status == "fail":
        failures.append(("ollama", m, err))

for m in LMSTUDIO_MODELS:
    status, dt, err = ping_lmstudio(m)
    log(f"lmstudio {m} {status} {dt}s {err or ''}")
    if status == "fail":
        failures.append(("lmstudio", m, err))
```

### Step 3 — Track outage windows

A single failure shouldn't page Cooper. Only fire PROBLEM if a model has been failing for ≥15 min (≥4 consecutive cycles).

```python
STATE = pathlib.Path.home() / ".openclaw/state/warmth-keeper-outages.json"
STATE.parent.mkdir(parents=True, exist_ok=True)
state = json.loads(STATE.read_text()) if STATE.exists() else {}

now_iso = datetime.datetime.utcnow().isoformat()
new_state = {}
to_alert = []

for provider, model, err in failures:
    key = f"{provider}/{model}"
    started = state.get(key, {}).get("first_failure", now_iso)
    consecutive = state.get(key, {}).get("consecutive", 0) + 1
    new_state[key] = {"first_failure": started, "consecutive": consecutive, "last_err": err}
    # 4+ consecutive (240s × 4 = 16 min) → alert
    if consecutive >= 4 and not state.get(key, {}).get("alerted"):
        to_alert.append((provider, model, started, err))
        new_state[key]["alerted"] = True

# Clear state for models that are now ok
all_keys = [f"ollama/{m}" for m in OLLAMA_MODELS] + [f"lmstudio/{m}" for m in LMSTUDIO_MODELS]
for k in all_keys:
    if k not in {f"{p}/{m}" for p, m, _ in failures}:
        if k in state and state[k].get("alerted"):
            log(f"RECOVERED {k} after {state[k].get('consecutive', '?')} cycles")
        # not adding to new_state means cleared

STATE.write_text(json.dumps(new_state, indent=2))
```

### Step 4 — PROBLEM Telegram only on sustained outage

```python
import subprocess
for provider, model, since, err in to_alert:
    msg = f"[PROBLEM] model-warmth-keeper: {provider}/{model} unreachable for ≥15 min (since {since}). Last err: {err}"
    try:
        subprocess.run([
            "python3.11", "${REPO_ROOT}/tools/notify/telegram_send.py",
            "--text", msg
        ], timeout=10, check=False)
    except Exception:
        pass
    log(f"ALERT {msg}")
```

## Self-test

```bash
# Confirm Ollama and LM Studio are reachable right now
curl -s --max-time 2 http://127.0.0.1:11434/api/tags >/dev/null && echo "ollama: ok" || echo "ollama: down"
curl -s --max-time 2 http://127.0.0.1:1234/v1/models >/dev/null && echo "lmstudio: ok" || echo "lmstudio: down"
# Run a single ping cycle
python3.11 -c "
import urllib.request, json, time
body = json.dumps({'model': 'qwen3.5:latest', 'prompt': 'OK', 'stream': False, 'options': {'num_predict': 1}}).encode()
req = urllib.request.Request('http://127.0.0.1:11434/api/generate', data=body, headers={'Content-Type': 'application/json'}, method='POST')
t0 = time.time()
with urllib.request.urlopen(req, timeout=15) as r:
    r.read()
print(f'qwen3.5:latest pinged in {time.time()-t0:.2f}s — PASS')
"
```

## Composition

- Reads from local Ollama / LM Studio inference endpoints.
- Writes to `~/.openclaw/logs/warmth-keeper.log` and `~/.openclaw/state/warmth-keeper-outages.json`.
- Notifies via **notify/telegram_send** on sustained outage.

## Hard rules

1. NEVER ping during 00:00–05:59 CT (off-hours).
2. PROBLEM Telegram fires only after 4+ consecutive failures (≥15 min). Single failures stay in the log.
3. RECOVERED is logged but not Telegrammed (Cooper doesn't need a chime when something silently fixes itself).
4. Each ping is `num_predict=1` (Ollama) / `max_tokens=1` (LM Studio) — minimum work.
