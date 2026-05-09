---
name: state-of-company-publisher
owner_agent: hermes
description: Sundays 18:00 CDT. Composes a public state-of-the-company narrative covering the past 7 days — what shipped, what was caught, what's being tested next. Reads private inputs (open handoffs by specialist, latest sunday-review, recent decisions, recent P-gate catches) and emits a sanitized public-safe markdown narrative through voice-gate (newsletter surface, threshold 70+) and scrubber HARD. Auto-publishes to site/state.html if both gates pass; otherwise saves to data/state-drafts/ for Cooper.
trigger: launchd com.dai.state-publisher StartCalendarInterval Weekday=0 Hour=18 Minute=0
---

# state-of-company-publisher

The thesis: a weekly narrative of the company's substrate, gates, and
testing-cadence is more credible than a marketing page. Cooper writes the
private sunday-review; this skill composes the public counterpart, scrubbed
of MRR, customer counts, and lead names — surface only the architecture
and the methodology.

The output replaces last week's `site/state.html`; one canonical URL.

## Procedure

```bash
bash skills/state-of-company-publisher/run.sh           # full publish
bash skills/state-of-company-publisher/run.sh --dry-run # build + gate, no write
```

## Pipeline

1. **Inputs (read-only, private):**
   - Open handoff counts by specialist (no titles): `data/team_bus/handoffs/open/*`
   - Latest sunday-review (if exists): `data/founder-reviews/<latest>.md` —
     extract a 200-word public-safe summary
   - Recent decisions: `data/decisions/cont-*-*.md` last 7 days, summarize each
     with title + 1-sentence outcome
   - Recent P-gate catches: grep `data/decisions/*.md` for "P-gates triggered"
2. **Voice anchor:** VOICE.md sentence rules + last 2 founder-letter drafts.
3. **Local Ollama call** (qwen3.5:latest, think=false, ~1500 num_predict):
   - System prompt: VOICE.md + "weekly state of the company" framing
   - Constraints: ≥3 sections (shipped, caught, testing), no MRR, no customers,
     no lead names, no auth tokens, no API keys
4. **Voice-gate** (newsletter surface, threshold 70 hard).
5. **Scrubber HARD** on the assembled narrative.
6. **If both pass** → `site/state.html` (replaces last week's).
   **If either fails** → `data/state-drafts/<YYYY-MM-DD>.md` for Cooper.

## Status codes

`STATUS=ok html=<path> score=<N>` /
`STATUS=draft path=<draft> reason=<voice-fail|scrubber-fail> score=<N>` /
`STATUS=skip reason=<...>` / `STATUS=error reason=<...>`

## Output schema (public site/state.html)

Static-template HTML wrapping a markdown body that contains:

```
# State of the company — week of <YYYY-MM-DD>

## What we shipped this week

3-5 bullets, each one specific commit/decision.

## What we caught this week

3-5 bullets, each one specific gate or P-fire that prevented broken work
from shipping. (P-gates as an artifact, not the bugs themselves.)

## What we're testing next

2-4 bullets, each one a specific experiment with a falsifier.

---
_Auto-published by state-of-company-publisher. Voice-gate <score>/100,
scrubber clean. Source markdown: data/state-published/<YYYY-MM-DD>.md._
```

## Gates

- **Voice-gate** (newsletter surface, threshold 70 HARD this time, not advisory).
- **Scrubber HARD**.
- **P11**: state-of-company describes architecture and methodology only.
  Forbidden: MRR, customer counts, lead names, win rates, P&L, fills.

## Why weekly cadence

Daily would become noise. Monthly loses momentum. Weekly is the natural
unit for "what shipped this week" — Cooper's git log already has a weekly
shape, and the audience reads in weekly digests.
