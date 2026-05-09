---
name: gateway-pulse
source: substrate-inflection-2026-04-29
owner_agent: ops
owns: Probe the four pillars (Hermes :4010, OpenClaw :18789, Paperclip :3100, Obsidian :27124) every cycle. RED on any pillar down. Auto-recover via bash scripts/bootstrap.sh if trust-graph allows.
---

# gateway-pulse

Owns: Watcher 4 of substrate-resilience. Detect pillar outages within 1 cycle. Trust-graph-checked auto-fix on outage (calls bootstrap.sh).

Composition: bash + curl + nc + tools/approvals/resolve_gate.py --check-autonomous.
Probe: ~/.openclaw/skills/gateway-pulse/check.sh prints `STATUS=GREEN|YELLOW|RED detail=...`.
Mother substrate-watchers reads check.sh output every hour.

Hard rules: ONE auto-recovery per hour max. After 3 consecutive RED cycles, escalate via approval-gate (don't loop forever).
