# improvement-queue

Score improvement proposals by `(impact × confidence) / cost` and surface the top-N daily.

## Install

```bash
cp -r improvement-queue/ /your/agents/lib/
mkdir -p data/improvement-queue
```

## Submit a proposal

Drop a JSON file in `data/improvement-queue/`:

```json
{
  "title": "Switch routing classifier from heuristic to local Ollama",
  "impact": 7,
  "confidence": 0.6,
  "cost_hours": 4,
  "owner": "ops",
  "submitted_at": "2026-05-08T12:00:00Z"
}
```

## Run

```bash
bash improvement-queue.sh
# default: writes data/improvement-queue/digest-<today>.md
```

## Cron

```
0 6 * * * cd /your/repo && bash kernel-audit-toolkit/improvement-queue/improvement-queue.sh
```

## License

MIT.
