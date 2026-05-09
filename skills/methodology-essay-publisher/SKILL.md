---
name: methodology-essay-publisher
owner_agent: content
description: One-shot skill that splits docs/methodology.md into 8 standalone essays, adds a 2-paragraph intro and "what to read next" footer to each, runs voice-gate (essay surface, threshold 70 HARD) plus scrubber HARD, and auto-publishes passing essays to site/essays/. Drafts that fail either gate land in data/essays/drafts/ for Cooper. Site footer link added to /essays. The build-trap counter — converts existing IP into eight SEO-compounding pages without needing fresh Cooper input.
trigger: manual one-shot (run once during cont-18; not a recurring cron)
---

# methodology-essay-publisher

The thesis: the methodology paper is 6,000 words of IP that already exists. Splitting it into 8 essays multiplies organic surface area by 8x at zero marginal Cooper-time cost. Each essay is a self-contained read with a clear "next chapter" path; together they form the same paper, just navigable.

## Procedure

```bash
bash skills/methodology-essay-publisher/run.sh           # full run, both gates, auto-publish
bash skills/methodology-essay-publisher/run.sh --dry-run # parse + render, no publish
```

## Pipeline

1. Parse `docs/methodology.md` into chapters by `^## Chapter N` headers.
2. For each chapter, build an essay markdown:
   - 2-paragraph intro framing the chapter as a standalone read.
   - Chapter body verbatim.
   - "What to read next" footer linking to the previous + next chapters and the full methodology page.
3. Run voice-gate (essay surface, threshold 70 HARD).
4. Run scrubber HARD on the essay body.
5. If both pass: render `site/essays/<NN>-<slug>.html` via static template.
6. If either fails: write to `data/essays/drafts/<NN>-<slug>.md` with a `_VALIDATION.md` companion.
7. Generate `site/essays/index.html` listing all published essays.
8. Update `site/index.html` footer to include `/essays`.

## Status codes

`STATUS=ok published=<N> drafted=<M>` /
`STATUS=skip reason=methodology-missing` /
`STATUS=error reason=<...>`

## Why one-shot, not recurring

The methodology paper updates rarely (every 1-3 months). A recurring cron would re-publish identical content for no gain. Cooper triggers a re-run when the paper changes; otherwise the essays sit at their canonical URLs and accumulate organic traffic.

## P12 — counter-monitor

The 8 published HTML files are static. A counter-monitor isn't necessary because nothing depends on the files being fresh. The methodology paper itself is the source of truth; the essays are derived snapshots that drift only when Cooper edits the source.
