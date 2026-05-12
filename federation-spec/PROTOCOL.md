# PROTOCOL

The federation uses two existing open protocols. The hub does not invent a wire format; it composes the discovery layer on top.

## Tool calls — MCP

Tool calls between an agent and a federated skill use the Model Context Protocol.

- Spec: https://modelcontextprotocol.io
- Transport: stdio (default), HTTP+SSE (optional for hub-resident skills)
- Server cards: each federated skill ships a `.well-known/mcp/<name>/card.json` matching the schema in the spec

The hub's discovery endpoint is itself an MCP server: it exposes one tool, `find_skill(query)`, returning the URI list of matching cards. A federated agent can then call those skills directly via their declared transport.

### Royalty attribution on server cards (added in spec 1.1.0)

Every server card MUST include a top-level `royalty_attribution` block so any consumer of the card — whether the federation hub directly, the Official MCP Registry, Smithery, MCPMarket, Cline, or a downstream subregistry — can map invocations back to a settlement entry.

```json
"royalty_attribution": {
  "urn": "urn:dailyaiagents:hub:<skill-slug>",
  "tracker_endpoint": "https://hub.usedailyai.com/v1/telemetry",
  "partner_share_pct": 15,
  "settlement_currency": "USD",
  "spec_version": "1.0"
}
```

Field semantics:

- `urn` — opaque identifier the hub uses to credit invocations of this skill. Follows the URN format `urn:dailyaiagents:hub:<skill-slug>`. Stable across registry re-listings; never reassigned.
- `tracker_endpoint` — HTTPS POST endpoint that accepts batched telemetry envelopes (see "Telemetry envelope" below). One endpoint per hub.
- `partner_share_pct` — current partner-share percentage paid out per invocation (mirrors `ROYALTY-MODEL.md` line 31). Provided for partner transparency; the registered settlement value at execution time is the authoritative number.
- `settlement_currency` — ISO 4217 currency code. USD only as of spec 1.1.0.
- `spec_version` — version of the royalty-attribution sub-spec. Independent of the federation spec version. `"1.0"` for the field as defined here.

Cards published before spec 1.1.0 (i.e. without `royalty_attribution`) are still accepted by the hub for backwards compatibility, but receive no royalty allocation; the hub treats them as donated capacity.

Cross-registry mirror: when this card is exported as an Official MCP Registry `server.json`, the same block is mirrored under
`_meta.io.modelcontextprotocol.registry/publisher-provided.com.dailyaiagents.federation.{royalty_attribution_urn,tracker_endpoint,partner_share_pct,settlement_currency,spec_version}`
because the Official Registry's `_meta` namespace policy forbids top-level extension fields and preserves only data under `io.modelcontextprotocol.registry/publisher-provided`.

## Agent-to-agent comms — A2A

Cross-substrate agent messaging uses the A2A working draft from the agent-protocol working group. (Canonical URL: search the most recent version of the protocol — agents are expected to load the link at startup, not hard-code a version into their substrate.)

- Auth: Ed25519 signature on every message body
- Transport: HTTP+JSON (default), WebSocket (optional for streaming sessions)
- Identity: each partner publishes an Agent Card at `<partner-host>/.well-known/agent-card.json` with their public key

The hub maintains a partner directory mapping partner IDs to their Agent Card URLs. A federated agent resolves a partner by ID, fetches the card, verifies signatures.

## Telemetry envelope

Every federated invocation emits a telemetry record to the hub. Schema:

```json
{
  "ts": "<ISO-8601 UTC>",
  "partner_id": "<sha256 of partner agent card>",
  "skill_uri": "skill://<hub>/<name>",
  "duration_ms": <int>,
  "outcome": "ok" | "error" | "timeout",
  "voice_scrubber_pass": true | false,
  "decision_recorder_event_id": "<uuid|null>"
}
```

Telemetry is batched to the hub at most once per minute. The hub deduplicates on `(partner_id, skill_uri, ts)`.

## Discovery cache

Partners cache the hub's `find_skill` responses for up to 5 minutes. The hub publishes a `Cache-Control: max-age=300` header. Stale-while-revalidate is allowed up to 60 seconds.

## Conformance

A partner is considered conformant if all of:

1. Every federated skill has a valid `.well-known/mcp/<name>/card.json`
2. Their Agent Card is reachable and verifies
3. Telemetry envelopes match the schema above
4. Quality gates from `QUALITY-GATES.md` pass on each invocation

The hub revokes federation membership on three conformance failures within a 30-day window.
