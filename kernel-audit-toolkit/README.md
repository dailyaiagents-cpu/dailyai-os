# Kernel Audit Toolkit

**License:** MIT — drop-in for any AI agent system. No attribution required.

The substrate-monitoring kit Daily AI Agents LLC runs internally, packaged for anyone running a multi-agent system. Four components, each standalone, no shared dependencies.

## Components

| Component | What it does |
|---|---|
| `decision-recorder/` | Logs every routing/budget/escalation decision with rationale + counterfactual. JSONL append. |
| `voice-scrubber/` | Pre-publish scanner: blocks hallucinated dollar amounts, fabricated metrics, prompt injection text. |
| `improvement-queue/` | Nightly cron: scores improvement proposals by impact × confidence / cost. Surfaces top-3 daily. |
| `couch-mode-watchdog/` | 5 health checks every 5 minutes. Telegram-or-equivalent alert on RED. |

## Why drop-in

Each component is a single bash script (or bash + minimal python3 stdlib). No package manager. No framework. Read the script, drop it in, run it.

## Install

```bash
git clone https://github.com/dailyaiagents-cpu/dailyai-os
cd dailyai-os/kernel-audit-toolkit
# Each component has its own README with run instructions.
```

## Hosted version (planned cont-O — Daily AI Agents LLC)

A $9/mo hosted version is planned for cont-O. Database is a paid Langfuse instance; public dashboards optional. The MIT-licensed self-host always remains free.

## Why MIT (not BUSL)

This toolkit is the substrate-discipline pattern itself. We don't compete on logging-decisions-with-rationale; we compete on having a higher-quality decision tree to begin with. Adopting the toolkit makes everyone's stack better. The moat is the federation network effect, not the audit pattern. (Marketplace primitives, capability-index v2 schema, white-label exporter, royalty tracker — those are BUSL 4-year. Different licenses, different business models.)

## What this is NOT

- Not a full agent framework. Bring your own dispatch / memory / orchestration.
- Not a multi-tenant SaaS. The hosted $9/mo version (cont-O) is single-team-per-instance.
- Not opinionated about your prompt format, model provider, or runtime.

## Status

This toolkit is shipped concurrent with cont-19.9-N of the Daily AI Agents private substrate. Each component is hardened by 4+ months of internal use. Bugs welcome via GitHub Issues.
