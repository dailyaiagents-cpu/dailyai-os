# ROYALTY-MODEL

Technical description of how invocation telemetry flows through the federation hub to a settlement file. This document does NOT describe pricing logic, contract terms, or commercial relationships — see partner agreement docs for those.

## Data flow

```
[partner agent] ──invoke──▶ [federated skill] ──telemetry envelope──▶ [hub aggregator] ──daily roll-up──▶ [settlement file]
                                                                              │
                                                                              ▼
                                                                       [audit ledger]
```

## Telemetry collection

Every federated invocation produces one telemetry record (schema in PROTOCOL.md). The hub's aggregator:

1. Receives batched envelopes via HTTP POST
2. Validates the partner Ed25519 signature
3. Deduplicates on `(partner_id, skill_uri, ts)`
4. Appends to `data/federation/telemetry.jsonl`

## Daily roll-up

A daily cron walks `telemetry.jsonl` for the prior 24h and emits one settlement row per partner:

```
partner_id, period, invocation_count, partner_share_total, hub_share_total
```

The current `partner_share` parameter is **15%**. This is a configuration value in the hub's `royalty-tracker` primitive (BUSL 1.1, see marketplace-primitives/royalty-tracker/). Changes to the parameter take effect on the next day boundary.

## Settlement file format

CSV at `data/federation/settlement-<YYYY-MM-DD>.csv`:

```
partner_id,period_start,period_end,invocations,partner_share_usd,hub_share_usd
```

The hub does not move money. The settlement file is consumed by an external payouts pipeline (Stripe Connect, Mercury, or partner-self-service).

## Audit ledger

Every settlement row is also written to an append-only audit ledger at `data/federation/audit.jsonl` with a SHA-256 chain (each record's `prev_hash` points to the prior record's hash). This makes the ledger tamper-evident and replayable.

## Reconciliation

A partner can request a full re-export of their settlement records via the `partner_export` MCP tool. The export covers up to 365 days. Discrepancies are resolved by comparing the partner's local invocation log with the hub's audit ledger; the audit ledger is the source of truth.

## Exclusions

The following are NOT included in royalty calculation:

- Invocations that failed quality gates (voice-scrubber blocked, decision-recorder missing)
- Invocations from non-conformant partners
- Test invocations from the hub's own self-test harness (tagged `_self_test` in telemetry)
