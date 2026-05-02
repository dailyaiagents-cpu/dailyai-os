#!/usr/bin/env bash
# Dry-run self-test for skill-registry-sync. Walks skills, parses owner_agent,
# prints what would be written, no actual SOUL writes.
set -euo pipefail
REPO="${REPO:-$HOME/Dev/daily-ai-agent-os}"
cd "$REPO"

python3.11 - <<'PYEOF'
import pathlib, re
home = pathlib.Path.home()
skills_dir = home / ".openclaw/skills"

by_agent = {}
no_owner = []
for skill_dir in sorted(skills_dir.iterdir()):
    if not skill_dir.is_dir():
        continue
    soul = skill_dir / "SOUL.md"
    if not soul.exists():
        continue
    text = soul.read_text(errors="replace")
    m = re.match(r"^---\n(.*?)\n---\n", text, re.DOTALL)
    if not m:
        no_owner.append(skill_dir.name)
        continue
    om = re.search(r"^owner_agent:\s*(.+?)\s*$", m.group(1), re.MULTILINE)
    if not om:
        no_owner.append(skill_dir.name)
        continue
    by_agent.setdefault(om.group(1).strip(), []).append(skill_dir.name)

for k in by_agent:
    by_agent[k].sort()

print(f"[self-test] {sum(len(v) for v in by_agent.values())} skills with owner_agent across {len(by_agent)} agents")
for agent in sorted(by_agent):
    print(f"  {agent}: {len(by_agent[agent])} → {by_agent[agent][:5]}{'...' if len(by_agent[agent])>5 else ''}")
print(f"[self-test] {len(no_owner)} skills without owner_agent (would be skipped)")
assert len(by_agent) >= 1 or len(no_owner) >= 1, "FAIL: no skills found at all"
print("[self-test] PASS (dry-run, no SOUL writes)")
PYEOF
