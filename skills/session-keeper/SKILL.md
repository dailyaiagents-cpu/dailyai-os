---
name: session-keeper
version: 1.0.0
owner_agent: ops
description: |
  Daily 09:00 CT browser-session audit. Probes 3 default targets (linkedin,
  linkedin, reddit) via Chrome CDP at 9223. URL-redirect detection (more
  robust than DOM selectors). Writes ~/.openclaw/state/session-keeper/
  <date>.json. Opens approval gates for expired sessions with the exact
  CDP-spawn command Cooper taps. Telegram-summary only when something
  expired or unknown — silence on all-live is valid.
scheduled: launchd plist or hermes cron — daily 09:00 CT
---

# session-keeper

## Why this exists

Sales, content, ops — every specialist that depends on a logged-in
browser session breaks silently when the session expires. By the time
the user sees an outage in the inbox-router or "0 leads found" in the brief,
the actual problem (linkedin logged out 18h ago) is buried.

This skill audits the 3 default targets every morning and surfaces
expired sessions before Cooper opens Telegram for the day.

## Targets

`~/.openclaw/state/session-keeper/targets.json`. Initial 3:

| Target | URL | Login URL | Marker |
|---|---|---|---|
| stripe | dashboard.stripe.com | dashboard.stripe.com/login | URL stays on /dashboard when live |
| linkedin | linkedin.com/feed/ | linkedin.com/login | URL stays on /feed when live; redirects to authwall when expired |
| reddit | reddit.com/ | reddit.com/login | URL stays on reddit.com/ when live |

Add Stripe / Gumroad / Gmail-web by editing targets.json once Cooper has
those tabs logged in on agent-chrome. URL-redirect detection is the
canonical primitive — DOM selectors break on UI updates.

## Procedure

```bash
bash ${OPENCLAW_HOME}/skills/session-keeper/run.sh
```

`SESSION_KEEPER_DRYRUN=1` → scan only, no gate, no Telegram.

The bash + python flow:

1. Read targets.json
2. For each target: PUT /json/new?<url> → wait 3s → GET /json → find tab by id → read final URL
3. Match final URL against `logged_in_marker.value` (live) or `logged_out_marker.value` (expired); else "unknown"
4. Close the spawned tab (CDP /json/close/<id>)
5. Write `~/.openclaw/state/session-keeper/<YYYY-MM-DD>.json` with full results
6. For each expired: open `LOGIN_<NAME>` approval gate with the curl-PUT command Cooper taps
7. Telegram-summary only if expired OR unknown count > 0

## Hard rules

1. **URL-redirect detection over DOM selectors.** UI updates break selectors; URL paths are stable.
2. **Always close spawned tabs.** Otherwise the agent-chrome instance accumulates dead tabs.
3. **Silent on all-live.** Cooper doesn't need a "everything fine" message every morning.
4. **One gate per expired target per day.** If yesterday's gate is still pending and target is still expired today, don't open a duplicate — extend the timeout via resolve_gate.py if needed (Cooper-side decision).
5. **Cooper-tap commands in gate evidence.** The `--evidence` field contains the literal `curl -s -X PUT ...` command — Cooper copies/runs in Terminal, that opens the login tab on agent-chrome, Cooper signs in, future probes auto-flip to live.
6. **3 default targets only.** Stripe/Gumroad/Gmail-web added once Cooper has those tabs already logged in. Probing a never-logged-in service produces noise.

## Self-test

```bash
SESSION_KEEPER_DRYRUN=1 bash ~/.openclaw/skills/session-keeper/run.sh
```

Output: `STATUS=ok live=N expired=N unknown=N` + per-category lists.
Acceptance: scans 3 targets, writes state file, no false positives on
currently-active sessions.
