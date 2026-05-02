---
name: hermes-inbox-router
description: "Orchestrator — every 15 min, aggregate new replies across LinkedIn, Reddit, email into data/hermes_inbox/<YYYY-MM>/<reply_id>.json. Hermes-daily-audit reads this for the funnel section. Sub-skills: linkedin-reply-poll, reddit-reply-poll, email-reply-poll."
owner_agent: main
version: 1.0.0
scheduled: cron */15 * * * * via hermes cron (agent=main)
---

# hermes-inbox-router (orchestrator)

## Why this exists

Replies vanish when LinkedIn/Reddit/email each have their own log location and no
unified surface. hermes-daily-audit (06:00 CT) needs ONE source of truth for
"new replies in last 24h" so Cooper sees the funnel section accurately. This
skill aggregates them.

## Output schema (canonical)

`data/hermes_inbox/<YYYY-MM>/<reply_id>.json`:

```json
{
  "reply_id": "<surface>-<8-hex>",
  "surface": "linkedin|reddit|email",
  "from": "@handle or email-address",
  "body": "...",
  "in_reply_to": "<outbound_id or null>",
  "received_at": "<iso8601>",
  "status": "new"
}
```

`reply_id` is unique across surfaces (prefix avoids collision). `received_at`
in UTC. `status: new` until hermes-daily-audit (or another consumer) flips it.

## Procedure

```bash
DRYRUN="${HERMES_INBOX_DRYRUN:-0}"
MONTH=$(date +%Y-%m)
INBOX_DIR=${REPO_ROOT}/data/hermes_inbox/$MONTH
mkdir -p "$INBOX_DIR"

# Sub-skill 1: Reddit (cheap, no auth)
REDDIT_OUT=$(timeout 60 bash ${OPENCLAW_HOME}/skills/reddit-reply-poll/run.sh "$DRYRUN" 2>&1)
echo "[hermes-inbox-router] reddit: $REDDIT_OUT"

# Sub-skill 2: LinkedIn (browser CDP, gated on auth)
LI_OUT=$(timeout 90 bash ${OPENCLAW_HOME}/skills/linkedin-reply-poll/run.sh "$DRYRUN" 2>&1)
echo "[hermes-inbox-router] linkedin: $LI_OUT"

# Sub-skill 3: email (IMAP, gated on creds; native email-as-trigger when wired)
EMAIL_OUT=$(timeout 30 bash ${OPENCLAW_HOME}/skills/email-reply-poll/run.sh "$DRYRUN" 2>&1)
echo "[hermes-inbox-router] email: $EMAIL_OUT"

# Sub-skills write directly to $INBOX_DIR. Aggregate count for log.
NEW_COUNT=$(find "$INBOX_DIR" -name "*.json" -newermt "15 minutes ago" 2>/dev/null | wc -l | tr -d ' ')
echo "[hermes-inbox-router] aggregated: $NEW_COUNT new in last 15min — month total $(ls "$INBOX_DIR" 2>/dev/null | wc -l | tr -d ' ')"
```

## Sub-skill contract

Each sub-skill (`linkedin-reply-poll`, `reddit-reply-poll`, `email-reply-poll`)
takes one arg (`"1"` for dry-run, anything else for live) and:

1. Prints a one-line status to stdout (e.g., `STATUS=ok found=3 written=3` or
   `STATUS=gated reason=cred-missing-1cab58`).
2. Writes any new replies to `data/hermes_inbox/<YYYY-MM>/<reply_id>.json` per
   the canonical schema. Idempotent — never re-write an existing reply_id.
3. Exits 0 on success or graceful-skip (no creds, no new replies); exits 1 only
   on actual error.

## Registration

```bash
hermes cron create "*/15 * * * *" --name hermes-inbox-router --skill hermes-inbox-router --deliver local
```

`--deliver local` keeps the cron silent on no-replies. hermes-daily-audit picks
up the inbox files at 06:00 CT and includes a `📬 New replies (24h): N (LI=x, RE=y, EM=z)` line.
