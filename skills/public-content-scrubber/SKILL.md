---
name: public-content-scrubber
version: 1.0.0
owner_agent: ops
description: |
  HARD gate for public output. Scans proposed text for financial-data leaks
  (dollar amounts, MRR/revenue/P&L terms, customer counts, kalshi.com/profile
  URLs). Allows known-good config values (Path E parameters, sticker prices)
  via context-sensitive allowlist. Blocks publish on ANY hit. Cooper override
  required to proceed past a hit.
---

# public-content-scrubber

## What this catches

The privacy posture is Stripe Press / Linear / Anthropic — quality of artifact in public, financial detail private. This scrubber is the structural enforcement of that posture across every public surface (newsletters, ship logs, sales pages, founder letters, Reddit/LinkedIn drafts, brief issues, site copy).

It blocks four categories of accidental leak:

1. **Dollar amounts** — `$5,000`, `$1.2M`, `$500/mo` (unless the trailing context names a known pricing/methodology word like `max position`, `daily exposure`, `starter`, `pro`, `tier`)
2. **Financial terms** — MRR, ARR, revenue, P&L, profit, commission, bankroll, fills, win rate, edge realized, drawdown, Sharpe (unless context contains `target`, `spec`, `threshold`, `min`, `max`, `goal`, `floor`, `cap` — these signal methodology, not actual performance)
3. **Customer counts** — exact figures: "47 paying users", "200 subscribers"
4. **Trading profile URLs** — `kalshi.com/profile/<user>` (track record stays NDA-only)

## When to use

Wired into every public-output skill BEFORE publish:

- newsletter-weekly-publish
- ship-log-publish
- founder-letter-publish
- sales-page-edit
- product-page-edit
- reddit-outreach-paced
- linkedin-outreach-paced
- brief-publish
- site/index.html or any site/* edit

Pattern: drafter generates → scrubber scans → on hit, drafter rewrites → scrubber scans again → on clean, voice-gate runs (advisory) → publish.

## Procedure

```bash
python3 ${REPO_ROOT}/tools/voice/scrubber.py "$DRAFT_PATH"
EXIT=$?
if [ $EXIT -eq 0 ]; then
  echo "STATUS=clean"
elif [ $EXIT -eq 1 ]; then
  echo "STATUS=blocked"
  echo "$(cat /dev/stdin)" | python3 ${REPO_ROOT}/tools/voice/scrubber.py - > /tmp/scrubber-hits.json
  # Surface hits to drafter for revision
fi
```

Exit 0 = clean, exit 1 = hits found (block publish), exit 2 = bad input.

## Hard rules

1. **Never bypass.** Every public output goes through. False positives are acceptable; false negatives are unrecoverable.
2. **Cooper override only.** If the drafter believes a hit is a false positive, the workflow opens an approval gate `OVERRIDE_SCRUBBER_<reason>`. Cooper YES → publish proceeds with the hit on record. NO → revise.
3. **Keep updating allowlists conservatively.** New legit pricing tiers / methodology values get added to `tools/voice/scrubber.py` PRICING_CONTEXT regex. Each addition is a commit Cooper reviews.
4. **Pair with voice-gate.** The scrubber blocks; voice-gate advises. Both run; both findings surface.

## Calibration evidence (regression tests)

Verified by 7 calibration tests in tools/voice/scrubber.py:
- Path E parameters + product pricing tiers → clean
- "win rate target ≥75%" methodology language → clean
- "$5,000 MRR" → blocked (dollar + financial term)
- "47 paying users" → blocked (customer count)
- "kalshi.com/profile/cooper" → blocked (trading URL)
- "Last week trading P&L grew" → blocked (financial term)
- Plain prose with no figures → clean

The companion `tools/voice/score.py` runs in parallel as advisory voice rubric.
