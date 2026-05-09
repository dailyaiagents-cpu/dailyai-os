---
name: skill-coverage-monitor
owner_agent: ops
description: Walks every skill directory in skills/ and ~/.openclaw/skills/, validates each has SOUL.md (voice ≥75), SKILL.md, run.sh (executable), and a launchd plist OR an "on-call" marker. Outputs a coverage report listing missing pieces. Run weekly + on-demand.
scheduled: openclaw cron `0 6 * * 1 America/Chicago` (agent=ops, model=local) — Monday 06:00 CT
---

# skill-coverage-monitor

## Why this exists
We have 110 skills in the repo and 344 in `~/.openclaw/skills/`. Coverage is uneven — some skills are missing SOUL.md, others have a SKILL.md but no `run.sh`, others have neither a plist nor a "called-on-demand" marker (so it's unclear how they fire). This skill walks the registry and reports missing pieces so we can fix them or retire dead skills.

## How to run

```bash
bash skills/skill-coverage-monitor/run.sh                           # report repo + ~/.openclaw skills
bash skills/skill-coverage-monitor/run.sh --root PATH               # report only PATH
bash skills/skill-coverage-monitor/run.sh --json                    # JSON output
bash skills/skill-coverage-monitor/run.sh --report PATH             # write markdown report to PATH
bash skills/skill-coverage-monitor/run.sh --voice-min N             # voice score floor (default 75)
bash skills/skill-coverage-monitor/run.sh --skill SKILL_NAME        # report only one skill
```

## Validation per skill

For each `skills/<name>/` dir, check 4 fields:

| Field | Pass condition | Severity if missing |
|---|---|---|
| `SOUL.md` | File exists; voice/score.py returns score ≥ `--voice-min` (default 75) | YELLOW (<75) or RED (file missing) |
| `SKILL.md` | File exists; has YAML frontmatter with `name:` and `description:` | RED if missing or unreadable frontmatter |
| `run.sh` | File exists; `-x` (executable). | YELLOW (not executable) or RED (file missing) |
| Trigger | Either: a `*.plist` references the skill OR `SKILL.md` declares `on-call: true` (callable from another skill) | YELLOW if both missing |

Trigger detection sources:
- `~/Library/LaunchAgents/*.plist` — search `ProgramArguments` strings for `skills/<name>/run.sh`
- `config/launchd/*.plist` (recursive, exclude `_archive/`)
- `openclaw cron list` — match skill name in cron description column
- SKILL.md frontmatter: `scheduled:`, `trigger:`, `on-call:`

## Output

Human-friendly:
```
[skill-coverage-monitor] 110 skills walked
  fully-covered:        65
  missing-trigger:      18  (no plist, no cron, no on-call)
  missing-run.sh:        4
  missing-SOUL.md:       3
  voice-below-min:       2  (SOUL.md exists but score <75)
  duplicates-in-~:       8  (same name in repo and ~/.openclaw/skills)
  reports written to:   data/skill-coverage/2026-05-07.md
```

JSON output:
```json
{
  "ts": "2026-05-07T19:30:00Z",
  "voice_min": 75,
  "total": 110,
  "summary": {"fully_covered": 65, "missing_trigger": 18, "missing_run": 4, "missing_soul": 3, "voice_low": 2, "duplicates": 8},
  "skills": [{"name":"foo", "issues": ["missing run.sh"], "voice_score": 91}, ...]
}
```

## Hard rules
1. **Read-only.** This skill never modifies skill files. It reports what's wrong.
2. **No Telegram.** Coverage is a slow signal — paged via the markdown report, not push notifications. Cooper reads at his pace.
3. **Voice gate is the only score check.** No other quality gate. We're checking *coverage* not *content*.
4. **Bounded walk.** Limit to the two registry roots: `<repo>/skills/` and `~/.openclaw/skills/`. Don't recurse system-wide.

## Self-test
`bash skills/skill-coverage-monitor/run.sh --skill skill-coverage-monitor` should report itself as fully-covered after this PR.
