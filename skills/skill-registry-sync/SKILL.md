---
name: skill-registry-sync
description: Auto-wire newly-shipped skills into owner-agent SOUL.md by reading `owner_agent:` frontmatter and rewriting the block between AUTO-GENERATED-SKILLS markers. Eliminates the hand-edit-or-silently-fail pattern. Cron 0 */6 * * * CT.
scheduled: cron 0 */6 * * * America/Chicago via openclaw cron (agent=ops)
---

# skill-registry-sync

## Why this exists

Every new skill needs to be listed in its owner-agent's SOUL.md "Available Skills" section, otherwise the agent doesn't know to dispatch to it. This has been forgotten in 3 recent ship sessions, causing silent dispatch failures Cooper had to debug manually. This skill makes the wire-in automatic.

## Inputs

```json
{
  "dry_run": false
}
```

`dry_run=true` walks the skills, computes the would-be block, prints the diffs, but does NOT modify any SOUL.md.

## Procedure

### Step 1 — Walk skills + parse frontmatter

```python
import pathlib, re, json, subprocess, datetime
home = pathlib.Path.home()
skills_dir = home / ".openclaw/skills"

# Map agent_id → list of skill names
by_agent = {}
no_owner = []

for skill_dir in sorted(skills_dir.iterdir()):
    if not skill_dir.is_dir():
        continue
    soul_path = skill_dir / "SOUL.md"
    if not soul_path.exists():
        continue
    text = soul_path.read_text(errors="replace")
    # Parse leading --- frontmatter
    m = re.match(r"^---\n(.*?)\n---\n", text, re.DOTALL)
    if not m:
        no_owner.append(skill_dir.name)
        continue
    fm = m.group(1)
    owner_match = re.search(r"^owner_agent:\s*(.+?)\s*$", fm, re.MULTILINE)
    if not owner_match:
        no_owner.append(skill_dir.name)
        continue
    owner = owner_match.group(1).strip()
    by_agent.setdefault(owner, []).append(skill_dir.name)

# Sort skills alphabetically per agent
for k in by_agent:
    by_agent[k].sort()

print(f"[registry] {sum(len(v) for v in by_agent.values())} skills with owner_agent across {len(by_agent)} agents")
print(f"[registry] {len(no_owner)} skills without owner_agent (skipped, see WARN log)")
```

### Step 2 — Locate SOUL.md files (repo + runtime)

```python
repo = home / "Dev/daily-ai-agent-os"
def soul_pair(agent_id):
    if agent_id == "main":
        return [
            repo / "tools/hermes/SOUL.md",
            home / ".hermes/SOUL.md",
        ]
    repo_soul_candidates = [
        repo / f"openclaw/{agent_id}-agent/SOUL.md",
        repo / f"openclaw/{agent_id}-commander-agent/SOUL.md",  # ops uses ops-commander-agent
    ]
    repo_soul = next((p for p in repo_soul_candidates if p.exists()), repo_soul_candidates[0])
    return [
        repo_soul,
        home / f".openclaw/agents/{agent_id}/SOUL.md",
    ]
```

### Step 3 — Marker-aware rewrite

```python
START = "<!-- AUTO-GENERATED-SKILLS-START -->"
END = "<!-- AUTO-GENERATED-SKILLS-END -->"

def render_block(skills):
    lines = ["", START, "<!-- DO NOT EDIT INSIDE THIS BLOCK. Run skill-registry-sync to refresh. -->"]
    lines.append("")
    if not skills:
        lines.append("_(no skills currently registered to this agent)_")
    else:
        for s in skills:
            lines.append(f"- `{s}` — `~/.openclaw/skills/{s}/SKILL.md`")
    lines.append("")
    lines.append(END)
    return "\n".join(lines)

def patch_soul(path, skills):
    if not path.exists():
        return ("missing", str(path))
    text = path.read_text(errors="replace")
    block = render_block(skills)
    if START in text and END in text:
        # Replace existing block
        new_text = re.sub(
            re.escape(START) + r".*?" + re.escape(END),
            block.strip(),
            text,
            count=1,
            flags=re.DOTALL,
        )
        if new_text == text:
            return ("nochange", str(path))
        path.write_text(new_text)
        return ("rewrote", str(path))
    # No markers — try to insert at "## Available Skills" / "## Skills" header
    header_re = re.compile(r"^(##+\s+(?:Available\s+)?Skills\b.*)$", re.MULTILINE | re.IGNORECASE)
    m = header_re.search(text)
    if m:
        # Insert AFTER the header (and any blank line)
        insert_at = m.end()
        new_text = text[:insert_at] + "\n" + block + text[insert_at:]
        path.write_text(new_text)
        return ("inserted-with-markers", str(path))
    return ("warn-no-header", str(path))
```

### Step 4 — Apply across all agents

```python
results = []
for agent_id, skills in sorted(by_agent.items()):
    for path in soul_pair(agent_id):
        if dry_run:
            block = render_block(skills)
            results.append({"agent": agent_id, "path": str(path), "would_write_lines": block.count("\n") + 1})
        else:
            status, p = patch_soul(path, skills)
            results.append({"agent": agent_id, "path": p, "status": status, "n_skills": len(skills)})
            print(f"  [{status}] {agent_id} → {p}")
```

### Step 5 — Re-sync runtime via existing tool

```bash
if [ "$DRY_RUN" != "true" ]; then
    bash ~/Dev/daily-ai-agent-os/deploy-agents/sync-agent-souls.sh --yes 2>&1 | tail -5
fi
```

### Step 6 — Telegram-summary on change

```python
changed = [r for r in results if r.get("status") in ("rewrote", "inserted-with-markers")]
warned = [r for r in results if r.get("status", "").startswith("warn") or r.get("status") == "missing"]
if changed and not dry_run:
    msg = (
        f"[skill-registry-sync] rewrote {len(changed)} SOULs across "
        f"{len(set(r['agent'] for r in changed))} agents. "
        f"Skills missing owner_agent: {len(no_owner)}. "
        f"Warnings: {len(warned)}."
    )
    subprocess.run(
        ["python3.11", str(repo / "tools/notify/telegram_send.py"), "--text", msg],
        timeout=10, check=False,
    )
```

## Self-test

```bash
#!/usr/bin/env bash
# Dry-run: walk skills, parse frontmatter, render the would-be block, no writes.
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
assert len(by_agent) >= 1, "FAIL: no skills found at all"
print("[self-test] PASS")
PYEOF
```

## Composition

- Reads: `~/.openclaw/skills/*/SOUL.md` frontmatter only.
- Reads + writes: `tools/hermes/SOUL.md`, `~/.hermes/SOUL.md`, `openclaw/<id>-agent/SOUL.md`, `~/.openclaw/agents/<id>/SOUL.md`.
- Calls: `deploy-agents/sync-agent-souls.sh --yes`, `tools/notify/telegram_send.py`.

## Hard rules

1. Only rewrites between AUTO-GENERATED-SKILLS-START / END markers.
2. Skills without `owner_agent:` are skipped + logged.
3. SOULs without markers AND without an "Available Skills" header are NOT modified — logged as warn.
4. Telegram only on actual changes.
