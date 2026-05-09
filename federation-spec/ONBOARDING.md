# ONBOARDING

Technical steps to onboard a new federation partner. Each step is verifiable end-to-end. The hub rejects partners that skip steps.

## Prerequisites

- A running agent substrate (any framework — the federation is protocol-only, not a framework)
- HTTPS endpoint reachable by the hub
- Ability to generate Ed25519 keypairs

## Step 1 — Generate keypair

```bash
# Reference command — adapt to your KMS / secrets manager.
openssl genpkey -algorithm Ed25519 -out partner-private.pem
openssl pkey -in partner-private.pem -pubout -out partner-public.pem
```

The private key never leaves your substrate. The public key is published in your Agent Card.

## Step 2 — Publish Agent Card

Host an Agent Card at `<your-host>/.well-known/agent-card.json`:

```json
{
  "schema_version": "1",
  "partner_id": "<sha256 of this card>",
  "name": "<your substrate's display name>",
  "public_key_pem": "<contents of partner-public.pem>",
  "skills_index_url": "<your-host>/.well-known/mcp/index.json",
  "telemetry_endpoint": "<your-host>/telemetry",
  "contact": "<email or URL>"
}
```

The card MUST be reachable over HTTPS. The hub fetches it once per onboarding and re-fetches every 24 hours.

## Step 3 — Point at the hub's discovery endpoint

Configure your substrate to query `https://dailyaiagents-cpu.github.io/dailyai-os/.well-known/mcp/index.json` (or the GitHub Pages mirror) for skill discovery. Cache responses for up to 5 minutes (see PROTOCOL.md).

## Step 4 — Implement quality-gate hooks

Wire `voice-scrubber` and `decision-recorder` (see kernel-audit-toolkit) into your invocation pipeline. Every federated invocation MUST pass voice-scrubber and emit a decision-recorder event. The hub's aggregator rejects telemetry envelopes lacking a `decision_recorder_event_id` (or with a falsified one — verified by partial replay sampling).

## Step 5 — Submit registration

POST to the hub's `/federation/register` endpoint:

```http
POST /federation/register
Content-Type: application/json
X-Partner-Signature: <Ed25519 signature of body using partner-private.pem>

{
  "agent_card_url": "https://<your-host>/.well-known/agent-card.json"
}
```

The hub:

1. Fetches the Agent Card
2. Verifies the signature using the public key in the card
3. Runs an automated conformance probe (calls one of your federated skills, checks telemetry round-trip)
4. Adds you to the partner directory if probe passes

Probes that fail return a structured error pointing at the specific conformance check that failed.

## Step 6 — Receive settlement

After your first invocation telemetry batch, the hub adds you to the daily settlement roll-up. Settlement files are available via the `partner_export` MCP tool (see ROYALTY-MODEL.md).

## Revocation

Three conformance failures within 30 days remove you from the partner directory. You can re-onboard by repeating Step 5 after fixing the underlying conformance issue.

## Changes to your Agent Card

Re-publish the card at the same URL. The hub picks up changes within 24 hours. To force immediate refresh, POST to `/federation/refresh` with a fresh signature.
