# decision-recorder

Drop-in JSONL logger for agent decisions. Each line: `{ts, actor, decision, rationale, counterfactual, cost_usd, tags}`.

## Why

When an agent picks model A over model B, or escalates to a human, or skips a turn, the rationale is usually only in the prompt context. After a week, you can't reconstruct *why* the decision was made. This script forces the rationale + counterfactual into a replayable log.

## Install

```bash
cp decision-recorder.sh /your/agents/lib/
chmod +x /your/agents/lib/decision-recorder.sh
```

## Use

```bash
bash decision-recorder.sh \
  --decision "route_to_ollama" \
  --rationale "task_complexity_score=0.3, ollama_handles_simple_classification" \
  --counterfactual "would_have_routed_to_sonnet, +$0.04" \
  --cost-usd 0.0 \
  --actor "router-skill" \
  --tags "route,budget"
```

Append-only. No truncation, no rotation in this script — pair with `logrotate` if you care.

## Replay

```bash
# What did we decide yesterday?
jq -c '. | select(.ts | startswith("2026-05-07"))' data/decisions/log.jsonl | head
```

## License

MIT (see ../LICENSE).
