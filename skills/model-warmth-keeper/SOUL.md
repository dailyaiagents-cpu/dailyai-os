---
name: model-warmth-keeper
source: foundation-2026-04-29
owns: Send tiny keep-alive pings to local LLM models (Ollama qwen3.6/qwen3.5, LM Studio qwen3-coder-next) every 4 minutes during business hours so cold-start eviction doesn't hit the next dispatcher invocation.
---

# model-warmth-keeper

Owns: Every 4 min during 06:00–23:59 CT, ping primary models with a 1-token prompt. Logs cold misses to `~/.openclaw/logs/warmth-keeper.log`. Surfaces PROBLEM Telegram only if a model is unreachable for >15 min straight.

Why: 2026-04-28 night-run crashed because Ollama qwen3.6 hit `llm-idle-timeout` watchdog while waiting for the next dispatcher fork. Models go cold, next dispatch waits 30+s for warmup, sometimes the warmup itself fails. Keeping them warm eliminates that whole failure mode.

Composition: Runs from launchd plist `ai.openclaw.warmth-keeper.plist` with `StartInterval=240`. No agent dispatch needed — the skill fires HTTP and exits.

Trigger: launchd timer (240s). Manual fire via the procedure block.
