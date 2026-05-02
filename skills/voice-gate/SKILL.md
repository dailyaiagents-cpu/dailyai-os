---
name: voice-gate
version: 1.0.0
owner_agent: content
description: |
  Score a piece of writing against VOICE.md's rubric. Returns score + findings.
  ADVISORY ONLY — not a hard gate. Author (Cooper or LLM drafter) reviews
  findings and decides whether each is a real issue or false positive.
  The hard gate for public output is `public-content-scrubber` (financials).
---

# voice-gate (advisory)

## What this is, what this isn't

This skill is a **coach**, not a gatekeeper. It runs the VOICE.md rubric over a draft and flags concerns. It does NOT block publish. The author reviews findings and decides whether each is a real issue or a false positive.

**Why advisory:** regex-based phrase detection can't reliably distinguish use from citation. "Leverage" the verb is fine in Cooper's writing; "leverage synergistic value" is not. Without an LLM judge, the rubric over-fires on legitimate prose. Calibrated to threshold 70 against Cooper's existing writing samples, but VISION.md (43.5) and the architecture audit (0) score below threshold because they cite the very phrases they're warning against.

**What this catches reliably:** clean LLM-default drafts. "We're leveraging AI to revolutionize..." scores ~70 even with the conservative weights — and a human reading the findings sees the three banned phrases highlighted, knows to rewrite.

**What this misses:** subtle drift, generic-but-not-cliché writing, content that's technically clean but voicelessly bland.

## When to use

Before publishing any of:
- Newsletter drafts
- Friday ship logs
- Founder's monthly letters
- Sales page edits
- Reddit/LinkedIn outreach drafts
- Solo AI Founder Brief issues
- Public site copy edits

Don't use for: postmortems Cooper writes himself, internal decisions docs, code comments, Telegram replies, vault notes, audit doc sections.

## Procedure

```bash
python3 ${REPO_ROOT}/tools/voice/score.py "$PATH_TO_DRAFT" "$SURFACE"
```

Surface options: `default`, `newsletter`, `brief`, `product`, `postmortem`, `telegram`. Each has a different sentence-length target.

Output is JSON with:
- `score`: 0-100
- `passes`: true if ≥70 (advisory threshold)
- `stats`: sentence count, paragraph count, avg sentence words
- `findings`: per-category deductions (banned-phrases / sentence-length / specificity / passive-voice / filler-tokens)

For each finding, the author considers:
1. Is the flagged phrase actually a problem in this context, or a false positive?
2. If it's a problem, is the suggested fix worth the rewrite cost?
3. If multiple findings, prioritize banned-phrase hits first (highest signal)

## Integration with drafting flow

The drafting skill (newsletter-weekly-publish, ship-log-draft, founder-letter-draft) calls voice-gate after generating the draft. If score < 70, the drafter prepends a revision note to the draft:

> Voice-gate flagged this draft (score N/100). Consider: <list of top 3 findings>. Revise or override.

The author (LLM or Cooper) reads the note + findings and either revises or proceeds. Final approval is the author's, not the gate's.

## Hard rules

1. **Never block publish on score alone.** Voice-gate is advisory.
2. **Always surface findings.** Even on a passing score, if there are 1+ findings, show them.
3. **Don't auto-rewrite.** If the drafter wants a second pass, it's a separate skill invocation, not implicit.
4. **Pair with public-content-scrubber for hard gates.** Voice is taste; financial-data leaks are facts. The scrubber blocks; voice-gate advises.
