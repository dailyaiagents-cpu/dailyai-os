---
name: skill-registry-sync
source: funnel-hardening-2026-04-29
owner_agent: ops
owns: Auto-wire newly-shipped skills into their owner-agent SOUL.md "Available Skills" section. Eliminates the hand-edit-every-SOUL-or-skill-silently-fails pattern that has caused 3+ silent dispatch failures across recent ship sessions.
---

# skill-registry-sync

Owns: Walk `~/.openclaw/skills/*/SOUL.md`, read each skill's `owner_agent:` frontmatter, group skills by owner. For each agent (main, content, sales, research, builder, ops, accountant, trading), rewrite ONLY the block between `<!-- AUTO-GENERATED-SKILLS-START -->` and `<!-- AUTO-GENERATED-SKILLS-END -->` markers in BOTH the repo SOUL (`tools/hermes/SOUL.md` for main, `openclaw/<id>-agent/SOUL.md` for the rest) AND the runtime SOUL (`~/.hermes/SOUL.md`, `~/.openclaw/agents/<id>/SOUL.md`). Hand-edits OUTSIDE the markers are preserved.

Why this exists: 3 sessions in a row (foundation, revenue-funnel, even today) shipped a skill that wouldn't dispatch because Cooper had to manually edit the owner-agent's SOUL.md to list it. This skill removes the manual step. From now on, ship a skill with `owner_agent:` in its SOUL frontmatter, this skill picks it up on the next 6-hour cron tick.

Composition:
- Reads: `~/.openclaw/skills/*/SOUL.md` (frontmatter only)
- Reads + writes: `tools/hermes/SOUL.md`, `openclaw/<id>-agent/SOUL.md`, `~/.hermes/SOUL.md`, `~/.openclaw/agents/<id>/SOUL.md`
- Calls: `bash deploy-agents/sync-agent-souls.sh --yes` after rewriting (so runtime sees changes)

Trigger: `openclaw cron` 0 */6 * * * America/Chicago, agent=ops. Manual fire allowed.

Hard rules:
1. ONLY rewrites the block between `<!-- AUTO-GENERATED-SKILLS-START -->` / `<!-- AUTO-GENERATED-SKILLS-END -->`. Hand-edits outside that block are preserved.
2. If a SOUL.md has no markers, INSERT them at the position of the existing "Available Skills" header (a `##` or `###` heading containing the word "Skills" or "Available Skills"). If neither marker nor header exists, do NOT auto-modify the SOUL — log a warning instead.
3. A skill without `owner_agent:` is excluded from auto-wire (logs a warning, never silently registers under a guessed owner).
4. After writing, runs the existing `deploy-agents/sync-agent-souls.sh --yes` so the runtime + repo are synchronized.
5. Telegram-summary only on changes (added/removed). Silent on no-op runs.
