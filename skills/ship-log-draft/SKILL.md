---
name: ship-log-draft
version: 1.0.0
owner_agent: content
description: |
  Friday 16:00 CT auto-draft of the weekly ship log. Aggregates 7 days of git
  commits + auto-promoted skills + postmortems + improvement-queue entries
  into data/ship-log/<date>-draft.md. Voice-gates (advisory, score 70+) and
  scrubber-checks (HARD gate). Telegrams Cooper to fill the "What I learned"
  paragraph before running ship-log-publish.
scheduled: hermes cron or launchd plist — Friday 16:00 CT
---

# ship-log-draft

## Why this exists

VISION.md / Phase F.2: "qualitative weekly receipts." The Friday ship log is the public artifact that proves the system shipped this week. Not "$N MRR" or "X customers" — what actually shipped, what broke, what was learned. Anyone who reads /log/ for 4 weeks understands how the system thinks.

## Procedure

```bash
bash ${OPENCLAW_HOME}/skills/ship-log-draft/run.sh
```

`SHIP_LOG_DRYRUN=1` → write the draft, run gates, but skip the Telegram notification.

The draft has 5 sections:
1. **Shipped** — `git log --since='7 days ago' --no-merges`, top 15 commits
2. **Skills auto-promoted** — `~/.hermes/skills/auto/` directories created in last 7 days
3. **What broke (and the fix)** — `data/postmortems/*.md` mtimed in last 7 days, top 3
4. **What I learned** — Cooper-only placeholder; 100-200 words; the one mental-model update that shaped the week
5. **What's next** — `data/improvement-queue/approved/*.md` top 3

## The gate flow

1. Draft written to `data/ship-log/<date>-draft.md`
2. **Voice-gate** runs immediately (advisory — score < 70 warns, doesn't block)
3. **Scrubber** runs immediately (advisory at draft stage; HARD gate at publish)
4. Cooper sees the Telegram, edits the "What I learned" section + any flagged commit-message lines
5. Cooper runs `ship-log-publish <date>` which re-runs both gates HARD

The draft stage is intermediate. Commit messages legitimately reference financial terms ("Stripe MCP + live MRR in /dashboard" describes architecture, not P&L). The scrubber flags them at draft so Cooper can rewrite them before publish.

## Hard rules

1. **Cooper writes "What I learned".** Never auto-generated. The placeholder text contains a sentinel string that ship-log-publish detects and blocks on.
2. **Scrubber HARD-gates publish, not draft.** Drafts may contain financial terms in commit-message context; publish requires clean.
3. **No financial figures fabricated.** The draft surfaces real commit messages verbatim; if a commit message accidentally includes a dollar amount, the publish-time scrubber catches it.
4. **5-section structure preserved.** Cooper edits "What I learned"; the other 4 sections are auto-aggregated.

## Self-test

```bash
SHIP_LOG_DRYRUN=1 bash ~/.openclaw/skills/ship-log-draft/run.sh
ls ${REPO_ROOT}/data/ship-log/$(date +%Y-%m-%d)-draft.md
```

Acceptance: 5 sections, voice-gate ≥70, draft persists for Cooper editorial.
