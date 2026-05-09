---
name: skill-spotlight-publisher
owner_agent: content
description: Daily 09:00 CDT. Picks a skill from the catalog (weighted random; prefers skills not spotlit in last 60 days; prefers skills with measurable outcomes). Reads the SOUL.md plus SKILL.md and asks local Ollama qwen3.5 to write a 200-word non-technical explainer for a solo founder who hasn't seen DAI OS. Voice-gate (newsletter surface, threshold 70 HARD) plus scrubber HARD. If both pass auto-publishes to site/skills/<slug>/spotlight.html plus an index entry; if either fails saves to data/skill-spotlights/drafts/ for Cooper review.
trigger: launchd com.dai.skill-spotlight StartCalendarInterval Hour=9 Minute=0 (CDT)
---

# skill-spotlight-publisher

The thesis: 340 skills is an inventory; one well-explained skill per day
is a story. Daily skill-of-the-day spotlights turn the catalog into a
year-long content stream — 365 explainers per year, each one a Cooper-voice
artifact a solo founder can read in 60 seconds and decide whether to use.

## Procedure

```bash
bash skills/skill-spotlight-publisher/run.sh                # daily run
bash skills/skill-spotlight-publisher/run.sh --skill <name> # spotlight a specific skill
bash skills/skill-spotlight-publisher/run.sh --dry-run      # pick + render, no publish
```

## Pipeline

1. **Pick a skill** from `skills/<X>/SKILL.md` weighted by:
   a. Has not been spotlit in last 60 days (stored at
      `data/skill-spotlights/_history.json`). +5 weight.
   b. SKILL.md is non-trivial (>50 lines). +2 weight.
   c. owner_agent is set (P5 compliant). +1 weight.
   d. NOT a stretch-skill (heuristic: name doesn't start with `_`). +1 weight.
2. **Read** the chosen skill's SOUL.md + SKILL.md (full).
3. **Local Ollama call** (qwen3.5:latest, think=false, ~600 num_predict):
   - System prompt: VOICE.md sentence rules + spotlight framing.
   - Asks for a 200-word explainer for a solo founder unfamiliar with
     DAI OS. Three-part shape: what it solves / when to reach for it /
     the single most surprising thing about it.
4. **Voice-gate** (newsletter surface, threshold 70 HARD).
5. **Scrubber HARD** on the explainer.
6. **Both pass** → write to `site/skills/<slug>/spotlight.html`, append
   to `site/skills/index.html` (or create), append to `_history.json`.
   **Either fails** → write to `data/skill-spotlights/drafts/<YYYY-MM-DD>-<slug>.md`.

## Status codes

`STATUS=ok skill=<slug> path=<html>` (published)
`STATUS=draft skill=<slug> path=<md> reason=<voice|scrubber>` (held for review)
`STATUS=skip reason=ollama-down|no-eligible-skill`
`STATUS=error reason=<...>`

## Output schema (site/skills/<slug>/spotlight.html)

Static-template HTML wrapping a 200-word explainer with:
- Skill name (h1)
- Owner agent (subtitle)
- Three-section explainer body
- Footer link back to /skills/ and back to / and to GitHub source if public

## History tracking

`data/skill-spotlights/_history.json`:
```json
{
  "<slug>": {
    "spotlit_at": "<ISO>",
    "voice_score": <int>,
    "html_path": "<...>"
  }
}
```

Used for the "last 60 days" weighting in step 1a.

## Gates

- **Voice-gate** (newsletter, threshold 70 HARD).
- **Scrubber HARD** — the spotlight is public-facing and goes to
  site/skills/. P11 still applies: the explainer describes architecture
  and capability, not customer outcomes.
