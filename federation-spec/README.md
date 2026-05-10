# Federation Spec

Technical protocol documents for connecting an AI-agent substrate to the Daily AI Agents federation hub at `dailyaiagents-cpu/dailyai-os`. The spec covers tool-call protocol (MCP), agent-to-agent messaging (A2A), telemetry contracts, partner onboarding, and the substrate-level quality gates a partner has to clear.

This is a public, read-only specification. The spec itself is licensed under the same MIT terms as the kernel-audit-toolkit. Implementations of the federation hub primitives (capability-index, royalty-tracker, white-label-exporter, marketplace-fee-logic) live under BUSL 1.1 in a separate repo path.

## Audience

- Engineers integrating an existing agent substrate with the federation hub
- Authors of new agent runtimes who want their skills discoverable across hubs
- Operators wiring telemetry pipelines into the hub's settlement layer

## Documents in this directory

| File | Scope |
|---|---|
| [PROTOCOL.md](PROTOCOL.md) | Wire-level protocols: MCP for tool calls, A2A for agent-to-agent. |
| [ROYALTY-MODEL.md](ROYALTY-MODEL.md) | Telemetry-to-settlement data flow. Partner-share parameter. |
| [ONBOARDING.md](ONBOARDING.md) | Steps for a new federation partner. |
| [QUALITY-GATES.md](QUALITY-GATES.md) | Substrate-level checks every partner must pass. |

## Versioning

This spec follows semver. Breaking protocol changes require a major-version bump and a 90-day deprecation window. The hub publishes a `/.well-known/federation-spec.json` document declaring the supported spec versions.

**Current version: `1.1.0`** (bumped 2026-05-09 in cont-19.9-P-mcp-distribution to add the `royalty_attribution` field to server cards — see PROTOCOL.md).

| Version | Date | Change |
|---|---|---|
| 1.0.0 | 2026-05-08 | cont-19.9-N initial draft. MCP + A2A protocols, telemetry envelope, quality gates 1–6, royalty model. |
| 1.1.0 | 2026-05-09 | cont-19.9-P additive change. Adds `royalty_attribution` field to server cards (`.well-known/mcp/<name>/card.json` and Official Registry `server.json` `_meta` block) so cross-listed skills carry their settlement URN regardless of which registry is the discovery surface. Fully backwards-compatible (field optional in 1.0.0 consumers). |

## Status

cont-19.9-P draft. Not finalized. Comments via GitHub Issues at `dailyaiagents-cpu/dailyai-os`.
