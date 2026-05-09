---
name: cron-self-heal
source: substrate-inflection-2026-04-29
owner_agent: ops
owns: Detect crons that fired but produced no expected artifact (the failure mode that killed NIGHT 1 RUN 1). RED if >33% of crons in error state; YELLOW on lower error rate.
---

# cron-self-heal

Watcher 5 of substrate-resilience. Probe via check.sh. Future work: per-skill `expected_output_glob:` frontmatter for richer per-cron health.
