---
name: meta-skill
owner_agent: hermes
description: The skill that creates skills. Reads a problem description, asks local Ollama to extract a skill spec (name, owner, pipeline, trigger, status codes), generates scaffolded SOUL.md + SKILL.md + run.sh, runs voice-gate + scrubber + bash-syntax + smoke on a synthetic input, lands the result in ~/.openclaw/skills/<name>/ if all checks pass or in data/proposed_skills/cont-17-meta/ if any fail. The runtime that writes its own tools, constrained to the SOUL+SKILL+run.sh schema and validated at every step.
trigger: callable from other skills (overnight-founder, etc.) or directly via `bash skills/meta-skill/run.sh "problem description"`
---

# meta-skill

The thesis: AI agents writing arbitrary code is risky and unbounded. AI
agents filling a structured template under hard validation is bounded
and shippable. This skill is the demonstration: a tightly-shaped pipeline
where the LLM authors only the parts of a new skill that humans would
hand-write anyway, while the bash skeleton, error handling, and gate
calls are generated deterministically.

## Procedure

```bash
bash skills/meta-skill/run.sh "I need a skill that watches X for Y and writes to Z"
bash skills/meta-skill/run.sh --dry-run "<problem>"  # parse + validate, no write
```

## Pipeline

1. **Parse** the problem string via local Ollama qwen3.5:latest. Extract:
   - `skill_name` (kebab-case, 3-6 words)
   - `owner_agent` (one of: content, builder, ops, sales, research, accountant, trading, hermes)
   - `description` (one sentence, voice-rule-compliant)
   - `pipeline_steps` (3-7 numbered steps)
   - `trigger` (cron / event / manual / on-skill-call)
   - `inputs` (named parameters; empty list OK)
   - `outputs` (paths or stdout shape)
2. **Generate** `SOUL.md` (intent + failure mode + voice anchor; 100-200 words).
3. **Generate** `SKILL.md` (frontmatter + procedure + status codes; static template
   filled with extracted fields).
4. **Generate** `run.sh` (skeleton with proper error handling, voice-gate calls
   if outputs are text-bound, smoke-test stub, TODO markers for the actual
   pipeline body).
5. **Validate**:
   a. `python3 tools/voice/score.py` on the SKILL.md description → must score >= 60.
   b. `python3 tools/voice/scrubber.py` on the description → must pass.
   c. `bash -n run.sh` → must pass syntax check.
   d. **Smoke-test**: `bash run.sh --dry-run` → must exit non-error (rc != 2)
      and produce a `STATUS=` line.
6. **Land**:
   - If all 4 validations pass → write to `~/.openclaw/skills/<name>/`
     (or `~/.hermes/skills/<name>/` for hermes-owned).
   - If any fails → write to `data/proposed_skills/cont-17-meta/<name>/`
     for Cooper review, with a `_VALIDATION.md` file detailing what failed.
7. **Output JSON** to stdout: `{status, skill_path, smoke_test_result, gates_passed}`.

## Status codes

`STATUS=ok skill=<name> path=<dir>` (all gates passed, landed in runtime)
`STATUS=proposed skill=<name> path=<dir> failed=<comma-list>` (some gate failed, landed in proposed/)
`STATUS=skip reason=<...>` (Ollama down, etc.)
`STATUS=error reason=<...>`

## Gates

- **voice-gate** (advisory threshold 60 for SKILL.md description — descriptions
  are short and don't need newsletter-tier polish).
- **scrubber HARD** on the description (it gets exposed in the skill catalog).
- **bash -n** on run.sh.
- **smoke-test --dry-run** must produce a STATUS= line and exit clean.

## What this skill WILL NOT do

- It does not write the *pipeline body* of the new skill. The body is
  TODO markers the human or a follow-up agent fills in. The meta-skill
  guarantees the *shape* and *gates*, not the substance.
- It does not bypass any of the existing voice/scrubber gates. A
  generated skill is held to the same publishing standards as a
  hand-written one.
- It does not auto-bootstrap a launchd plist. The plist is a Cooper
  decision (which schedule? which environment?). The generated skill
  is callable via `bash run.sh` from day one but does not run on a
  cron until Cooper writes the plist.

## Why this is the demonstration

A solo founder using DAI OS can speak a problem ("I need a thing that
does X") into the system and walk away with a scaffolded skill in
60 seconds. The compounding loop the methodology describes is not
hand-waving: this skill makes the catalog grow autonomously while keeping
every output under the same gate disciplines as Cooper's hand-written
skills.
