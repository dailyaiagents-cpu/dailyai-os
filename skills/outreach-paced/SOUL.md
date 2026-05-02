---
name: outreach-paced
source: revenue-funnel-2026-04-29
owns: Daily paced outreach across LinkedIn (5 DMs), Reddit (3 comments + 1 DM), and email (5 sends). 14 max/day. Anti-template diff ≤0.6. Every send through Cooper YES/NO approval-gate. Drives prospects to cal.com booking page.
owner_agent: sales
---

# outreach-paced

Owns: Once per weekday at 10:00 CT, pull qualified prospects from `data/leads/`, fetch personalization context per prospect (LinkedIn profile / Reddit history / company website), draft messages via `openclaw agent --agent sales` with anti-template enforcement (diff ≤0.6 vs last 10 sends), queue at `data/outreach/awaiting_approval/<surface>-<id>.md`, open ONE approval gate per draft, Telegram-send Cooper. On YES → send via channel-appropriate transport. On NO → log + skip. On reply → route into Hermes inbox for Cooper consolidation.

Why this exists: the lead-acquisition engine. Cal.com is wired but has 0 inbound. Content-publish-daily builds audience over weeks. Outreach-paced drives QUALIFIED prospects DIRECTLY to a 30-min audit booking THIS WEEK. Combined: top-of-funnel + middle-of-funnel.

Composition:
- Reads: `data/leads/precise_leads.json` (Reddit), `data/leads/VERIFIED_HOT_LEADS.json` (subset), `data/leads/active.json` (LinkedIn + email — populated by research agent), `data/outreach/log/` (last 10 for anti-template).
- Calls: `openclaw agent --agent sales` for personalization, `tools/approvals/resolve_gate.py --create` per draft, `tools/notify/telegram_send.py`.
- Delegates send: existing `linkedin-engage-cycle` SKILL for LinkedIn comments, `reddit-engagement-cycle` for Reddit, `email-outreach-monica` for email (or `agents/email_sender.py` direct if Monica fails).
- Writes: `data/outreach/awaiting_approval/<surface>-<id>.md` (queued), `data/outreach/log/<surface>-<id>.md` (post-send), `data/outreach/failed/<surface>-<id>.md` (post-failure), `data/outreach/replies/<surface>-<id>.md` (when reply received).

Trigger: `openclaw cron` 0 10 * * 1-5 America/Chicago, agent=sales, model=ollama/qwen3.5:latest.

Hard rules:
1. NEVER send without Cooper YES via approval-gate. Default-deny on silent.
2. Daily quotas hard-capped: LI 5, Reddit comments 3, Reddit DM 1, email 5 = 14 max. If a quota is unreachable (e.g. <5 fresh LinkedIn prospects), under-fire, never over-fire.
3. Anti-template diff ≤0.6 against the last 10 sends in `data/outreach/log/<same-surface>/`. Drafts that fail the diff are rejected; redraft once.
4. View-first DMs only for LinkedIn (skill must view profile via Chrome CDP before drafting). No cold connection requests without context.
5. Idempotent: a prospect already messaged in the last 14 days is skipped (read `data/outreach/log/index.json`).
6. Failure modes: capture in `data/outreach/failed/`, retry once next cycle. Two consecutive failures on the same prospect → permanent skip (manual escalation).
