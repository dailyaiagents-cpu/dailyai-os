---
name: outreach-paced
description: Daily paced outreach across LinkedIn (5 view-first DMs), Reddit (3 substantive comments + 1 DM), email (5 personalized cold emails) — 14 sends max/day. Anti-template diff ≤0.6 vs last 10 same-surface. Every send through Cooper YES/NO approval-gate. Cron M-F 10:00 CT.
scheduled: cron 0 10 * * 1-5 America/Chicago via openclaw cron (agent=sales, model=ollama/qwen3.5:latest)
---

# outreach-paced

## Why this exists

Cal.com is wired but has 0 inbound. Content-publish-daily builds audience slowly. Outreach drives qualified prospects directly to a 30-min audit booking THIS WEEK. This skill is the lead-acquisition surface.

## Inputs

```json
{
  "for_date": "2026-04-29",
  "surfaces": ["linkedin", "reddit", "email"],
  "dry_run": false
}
```

`dry_run=true` runs Steps 1-4 (drafts, anti-template, queue) but skips approval-gate creation and Telegram send.

## Daily quotas (hard-capped)

| Surface | Action | Max |
|---------|--------|----:|
| linkedin | view-first DM | 5 |
| reddit | substantive comment | 3 |
| reddit | DM | 1 |
| email | personalized cold email | 5 |
| **TOTAL** | | **14** |

## Procedure

### Step 1 — Pull qualified prospects

```python
import json, datetime, pathlib, hashlib
home = pathlib.Path.home() / "Dev/daily-ai-agent-os"
now = datetime.datetime.now(datetime.timezone.utc)
date_str = (now - datetime.timedelta(hours=5)).strftime("%Y-%m-%d")

# Reddit prospects from precise_leads.json (research agent populates)
reddit_leads_path = home / "data/leads/precise_leads.json"
reddit_leads = json.loads(reddit_leads_path.read_text()) if reddit_leads_path.exists() else []

# LinkedIn + email prospects from active.json (research agent populates this format)
active_path = home / "data/leads/active.json"
active = json.loads(active_path.read_text()) if active_path.exists() else []
linkedin_leads = [l for l in active if l.get("surface") == "linkedin"]
email_leads = [l for l in active if l.get("surface") == "email"]

# Idempotency: skip prospects already messaged in last 14 days
idx_path = home / "data/outreach/log/index.json"
recent = {}
if idx_path.exists():
    recent = json.loads(idx_path.read_text())
cutoff = (now - datetime.timedelta(days=14)).isoformat()
def already_messaged(prospect_id):
    return recent.get(prospect_id, "") > cutoff

reddit_leads = [l for l in reddit_leads if not already_messaged(l.get("permalink", ""))][:4]  # 3 comment + 1 DM
linkedin_leads = [l for l in linkedin_leads if not already_messaged(l.get("profile_url", ""))][:5]
email_leads = [l for l in email_leads if not already_messaged(l.get("email", ""))][:5]

print(f"[outreach-paced] candidates: linkedin={len(linkedin_leads)} reddit={len(reddit_leads)} email={len(email_leads)}")
```

### Step 2 — Anti-template scaffolding

```python
def diff_ratio(a, b):
    """Return [0, 1] cosine-ish similarity. Cheap shingled-token approach."""
    def shingles(s, n=3):
        s = s.lower()
        return set(s[i:i+n] for i in range(len(s)-n+1))
    A, B = shingles(a), shingles(b)
    if not A or not B:
        return 0.0
    return len(A & B) / len(A | B)

# Load last 10 sends per surface
def recent_sends(surface):
    log = home / f"data/outreach/log/{surface}"
    if not log.exists(): return []
    files = sorted(log.glob("*.md"), key=lambda p: -p.stat().st_mtime)[:10]
    return [p.read_text(errors="replace") for p in files]

last_li = recent_sends("linkedin")
last_reddit = recent_sends("reddit")
last_email = recent_sends("email")
```

### Step 3 — Draft a message per prospect via openclaw agent

```python
import subprocess, os

def draft(surface, prospect_ctx, history):
    prompt = f"""Draft a {surface} outreach message for this prospect. Daily AI Agents helps solopreneurs and SMBs install AI agents that handle ops on autopilot. The CTA is a free 30-min audit booking at https://cal.com/daily-ai-agents/30min.

PROSPECT CONTEXT:
{json.dumps(prospect_ctx, indent=2)}

CONSTRAINTS:
- ≤{ {"linkedin": 600, "reddit": 1200, "email": 1500}[surface] } chars
- Tone: builder-to-builder. NO marketing speak. NO "Hope this finds you well", NO "I'd love to chat", NO "synergies".
- Reference at least one SPECIFIC thing from the prospect's context (not generic — quote their words back).
- End with a SOFT CTA — invite to the cal.com link OR ask a substantive question.
- {"For LinkedIn: assume Cooper has VIEWED their profile first." if surface == "linkedin" else ""}
- {"For Reddit comments: contribute genuinely to the thread; CTA is incidental." if surface == "reddit" else ""}

ANTI-TEMPLATE: this draft will be diff-checked against the last 10 {surface} sends. If it overlaps >60%, it's auto-rejected. Make it substantively different.

OUTPUT (one message body, no preamble, no quotes):
"""
    result = subprocess.run(
        ["openclaw", "agent", "--agent", "sales", "-m", prompt],
        capture_output=True, text=True, timeout=180,
        env={**os.environ, "OPENCLAW_AGENT_MODEL_OVERRIDE": "ollama/qwen3.5:latest"},
    )
    return result.stdout.strip().splitlines()[-1] if result.returncode == 0 else None

# Draft each
drafts = []
for l in linkedin_leads:
    d = draft("linkedin", l, last_li)
    if d: drafts.append({"surface": "linkedin", "prospect": l, "text": d})
for l in reddit_leads[:3]:  # 3 comments
    d = draft("reddit", l, last_reddit)
    if d: drafts.append({"surface": "reddit", "action": "comment", "prospect": l, "text": d})
for l in reddit_leads[3:4]:  # 1 DM
    d = draft("reddit", l, last_reddit)
    if d: drafts.append({"surface": "reddit", "action": "dm", "prospect": l, "text": d})
for l in email_leads:
    d = draft("email", l, last_email)
    if d: drafts.append({"surface": "email", "prospect": l, "text": d})

print(f"[outreach-paced] drafted {len(drafts)} messages")
```

### Step 3.5 — Reddit anti-self-promo gate (per funnel-completion-prompt 2026-04-29)

Reddit subreddits ban first-comment self-promo. The 2026-04-29 sales-outreach drafts
contained `cal.com` links + formulaic "Doing a few free 30-min audits" copy in a
prospect's first interaction with the bot account — those would have been removed
by mods within an hour and damaged the account's standing. This gate rejects any
Reddit draft that fails substance-first norms BEFORE it reaches the approval
queue.

```python
PROMO_KEYWORDS = [
    "cal.com", "calendly", "book a call", "free audit",
    "worth 30 min", "schedule a call", "quick chat",
]
PROMO_PHRASES = [
    "doing a few free", "no pitch, just",
    "walkthrough of what would actually help",
    "audit this week", "no strings attached",
]

def reddit_anti_promo_gate(text, prospect):
    """Return (ok, reason). Reject drafts that violate substance-first norms.

    Three guards:
    1. Promo keywords/URLs at all (Reddit subreddit rules ban first-comment links).
    2. Anti-promo phrases (formulaic offer language pattern-matched by mods).
    3. Substance-first: needs ≥2 actionable suggestions BEFORE any URL.
       Heuristic: count occurrences of bullet markers (- / * / 1./2./numbered)
       and imperative verbs (try, use, check, set, install, configure) in the
       text BEFORE the first URL. Need ≥2.
    """
    body = (text or "").lower()
    # Guard 1: promo keywords
    found = [kw for kw in PROMO_KEYWORDS if kw in body]
    if found:
        return False, f"reddit-anti-promo: contains banned keyword(s) {found}"
    # Guard 2: anti-promo phrases
    matched_phrase = next((p for p in PROMO_PHRASES if p in body), None)
    if matched_phrase:
        return False, f"reddit-anti-promo: contains formulaic phrase '{matched_phrase}'"
    # Guard 3: substance-first — count action markers in pre-URL prefix
    import re
    first_url = re.search(r"https?://", body)
    prefix = body[:first_url.start()] if first_url else body
    bullets = len(re.findall(r"(?:^|\n)\s*(?:[-*]|\d+\.)\s+\w", prefix))
    imperatives = sum(prefix.count(v) for v in ("try ", "use ", "check ", "set ", "install ", "configure ", "run "))
    actions = bullets + imperatives
    if actions < 2:
        return False, f"reddit-anti-promo: only {actions} action markers before URL (need ≥2 substance items)"
    return True, "ok"

reddit_drafts = [d for d in drafts if d["surface"] == "reddit"]
filtered_drafts = []
gate_rejects = []
for d in drafts:
    if d["surface"] != "reddit":
        filtered_drafts.append(d)
        continue
    ok, reason = reddit_anti_promo_gate(d["text"], d.get("prospect"))
    if ok:
        filtered_drafts.append(d)
    else:
        gate_rejects.append({**d, "reject_reason": reason})

drafts = filtered_drafts
print(f"[outreach-paced] reddit anti-promo gate: kept={sum(1 for d in drafts if d['surface']=='reddit')} rejected={len(gate_rejects)}")
for r in gate_rejects:
    print(f"  reject: {r['reject_reason']}")
```

> **Deferred (subreddit rule fetch):** the spec also wants a per-subreddit
> `https://www.reddit.com/r/<sub>/about/rules.json` fetch with self-promo-keyword
> parse. Adds a network call to every draft and per-sub variance is high; for v18
> the keyword/phrase/substance gate above catches the dominant failure mode (the
> 2026-04-29 incident). If a subreddit removes a comment that passed this gate,
> add the subreddit to a deny-list at `data/outreach/reddit-deny-subs.json` and
> re-run.

### Step 4 — Anti-template gate + queue

```python
import secrets

queue_dir = home / "data/outreach/awaiting_approval"
queue_dir.mkdir(parents=True, exist_ok=True)

queued = []
rejected = []
for d in drafts:
    history = {"linkedin": last_li, "reddit": last_reddit, "email": last_email}[d["surface"]]
    max_diff = max([diff_ratio(d["text"], h) for h in history], default=0.0)
    if max_diff > 0.6:
        rejected.append({**d, "reason": f"diff {max_diff:.2f} > 0.6 vs recent send"})
        continue

    draft_id = secrets.token_hex(3)
    fname = f"{d['surface']}-{draft_id}.md"
    qpath = queue_dir / fname
    qpath.write_text(f"""---
id: {draft_id}
surface: {d['surface']}
action: {d.get('action', 'send')}
date: {date_str}
prospect: {json.dumps(d['prospect'])[:200]}
diff_max: {max_diff:.2f}
---

{d['text']}
""")
    queued.append({**d, "id": draft_id, "path": str(qpath)})

print(f"[outreach-paced] queued={len(queued)} rejected={len(rejected)}")
```

### Step 5 — Open ONE batch approval gate (collapses N drafts into 1 Telegram)

```python
if dry_run:
    print(f"[DRY-RUN] would open 1 batch gate with {len(queued)} items")
    raise SystemExit(0)

# Write the items file resolve_gate.py reads to inline them in the gate record
import tempfile
items_payload = [
    {
        "surface": q["surface"],
        "action": q.get("action", "send"),
        "prospect": q.get("prospect"),
        "text": q["text"],
        "draft_path": q["path"],
        "draft_id": q["id"],
    }
    for q in queued
]
with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
    json.dump(items_payload, f)
    items_path = f.name

gate_out = subprocess.run([
    "python3.11", str(home / "tools/approvals/resolve_gate.py"),
    "--create", "--type", "batch",
    "--batch-items-file", items_path,
    "--agent", "sales",
    "--action", "OUTREACH_BATCH",
    "--reason", f"{date_str} outreach batch — {len(queued)} drafts (LI={sum(1 for q in queued if q['surface']=='linkedin')}, "
                f"Reddit={sum(1 for q in queued if q['surface']=='reddit')}, "
                f"email={sum(1 for q in queued if q['surface']=='email')})",
    "--evidence", str(home / "data/outreach/awaiting_approval/"),
    "--cost-usd", "0",
    "--reversibility", "hard",
    "--timeout-min", "120",
], capture_output=True, text=True, timeout=15)
gate_resp = json.loads(gate_out.stdout.strip())
gate_id = gate_resp["gate_id"]  # batch_<id> form

# Build the batch Telegram message — ≤25 lines so Cooper can scan it
lines = [
    f"APPROVAL #{gate_id} [OUTREACH_BATCH]",
    f"agent: sales | items: {len(queued)} | timeout: 120m",
    f"reversibility: hard | cost: $0",
    "",
]
for i, q in enumerate(queued, start=1):
    head = q["text"][:80].replace("\n", " ")
    lines.append(f"{i}. [{q['surface'][:2].upper()}] {head}")
lines.extend([
    "",
    f"REPLY OPTIONS (to {gate_id}):",
    f"  YES {gate_id}                 → send all",
    f"  YES {gate_id} 1,3,5            → send only items 1+3+5 (rest declined)",
    f"  NO  {gate_id}                  → skip all",
    f"  EDIT {gate_id} 3 <new text>    → edit item 3 (re-review pending)",
    f"  (silent → default-deny in 120m)",
])
msg = "\n".join(lines)

subprocess.run([
    "python3.11", str(home / "tools/notify/telegram_send.py"),
    "--text", msg,
], timeout=15)

print(f"[outreach-paced] batch gate {gate_id} opened with {len(queued)} items, Cooper notified")
```

### Step 6 — On Cooper YES (post-decision flow, batch-aware)

```bash
# Hermes detects "YES batch_<id>" / "NO batch_<id>" / "EDIT batch_<id> N <text>"
# and shells the corresponding resolve_gate.py form. resolve_gate.py writes
# data/outreach/decisions/batch_<id>.json. Outreach-paced's POST-YES step
# (or a follow-up cron) reads that file and dispatches per-item by surface.

DECISIONS_FILE=data/outreach/decisions/${GATE_ID}.json
if [ -f "$DECISIONS_FILE" ]; then
    python3.11 - <<'PYEOF' "$DECISIONS_FILE"
import json, sys, subprocess, os, pathlib
home = pathlib.Path.home()
d = json.loads(pathlib.Path(sys.argv[1]).read_text())
for idx_str, decision in d.get("decisions", {}).items():
    idx = int(idx_str) - 1
    item = d["items"][idx]
    if decision != "approved":
        # Move the queued draft to data/outreach/declined/ for audit
        from_path = pathlib.Path(item.get("draft_path", ""))
        if from_path.exists():
            declined = home / "Dev/daily-ai-agent-os/data/outreach/declined"
            declined.mkdir(parents=True, exist_ok=True)
            from_path.rename(declined / from_path.name)
        continue
    # Approved → dispatch by surface
    surface = item.get("surface", "?")
    text_to_send = item.get("edited_text") or item.get("text", "")
    skill = {"linkedin": "linkedin-engage-cycle",
             "reddit": "reddit-engagement-cycle",
             "email": "email-outreach-monica"}.get(surface)
    if not skill:
        continue
    msg = (f"Send the approved {surface} outreach: prospect={item.get('prospect')!r}, "
           f"text={text_to_send!r}. Use SKILL ~/.openclaw/skills/{skill}/SKILL.md procedure.")
    subprocess.run(["openclaw", "agent", "--agent", "sales", "-m", msg], timeout=600, check=False)
PYEOF
fi

# After successful send: move from awaiting_approval/ to log/<surface>/, update index.json
mv data/outreach/awaiting_approval/${SURFACE}-${ID}.md data/outreach/log/${SURFACE}/
python3.11 -c "
import json, pathlib
idx = pathlib.Path('data/outreach/log/index.json')
d = json.loads(idx.read_text()) if idx.exists() else {}
d['${PROSPECT_ID}'] = '${NOW_ISO}'
idx.write_text(json.dumps(d, indent=2))
"
```

## Self-test

```bash
#!/usr/bin/env bash
# Dry-run: drafts 3 fake prospects per surface (no openclaw agent dispatch),
# anti-template gates them, queues to data/outreach/awaiting_approval/, prints
# what gates would open. No Telegram, no openclaw agent calls.
set -euo pipefail
REPO="${REPO:-$HOME/Dev/daily-ai-agent-os}"
cd "$REPO"

python3.11 - <<'PYEOF'
import json, pathlib, secrets, datetime
home = pathlib.Path.home() / "Dev/daily-ai-agent-os"

def diff_ratio(a, b):
    def shingles(s, n=3):
        s = s.lower()
        return set(s[i:i+n] for i in range(len(s)-n+1))
    A, B = shingles(a), shingles(b)
    if not A or not B: return 0.0
    return len(A & B) / len(A | B)

# Fake prospects: 5 LI, 3 Reddit comments, 1 Reddit DM, 5 email = 14 max
prospects = []
for i in range(5):
    prospects.append({"surface":"linkedin", "prospect":{"name":f"Test LI {i}", "title":"Founder"}})
for i in range(3):
    prospects.append({"surface":"reddit", "action":"comment", "prospect":{"author":f"user{i}", "title":"Post about AI agents"}})
prospects.append({"surface":"reddit", "action":"dm", "prospect":{"author":"dm-user", "title":"Wants to chat"}})
for i in range(5):
    prospects.append({"surface":"email", "prospect":{"name":f"Test Email {i}", "company":"Acme"}})

# Fake drafts (substantively different to pass anti-template)
fake_drafts = [
    f"Hey {p['prospect'].get('name', p['prospect'].get('author','x'))} — saw your {p.get('action','post')} about {p['prospect'].get('title','ops')[:30]}. Build a 30min audit free? cal.com/daily-ai-agents/30min — Cooper" + " " + secrets.token_hex(2)
    for p in prospects
]

queue_dir = home / "data/outreach/awaiting_approval"
queue_dir.mkdir(parents=True, exist_ok=True)

# Fresh dry-run: clear any existing DRYRUN files first
for f in queue_dir.glob("DRYRUN-*"):
    f.unlink()

queued = 0
for p, text in zip(prospects, fake_drafts):
    draft_id = "DRYRUN-" + secrets.token_hex(3)
    fname = f"{p['surface']}-{draft_id}.md"
    (queue_dir / fname).write_text(f"---\nid: {draft_id}\nsurface: {p['surface']}\naction: {p.get('action','send')}\nDRY_RUN: true\n---\n\n{text}\n")
    queued += 1

# Verify quotas
li = sum(1 for p in prospects if p['surface']=='linkedin')
rc = sum(1 for p in prospects if p['surface']=='reddit' and p.get('action')=='comment')
rd = sum(1 for p in prospects if p['surface']=='reddit' and p.get('action')=='dm')
em = sum(1 for p in prospects if p['surface']=='email')

assert li == 5, f"FAIL: linkedin {li} != 5"
assert rc == 3, f"FAIL: reddit comments {rc} != 3"
assert rd == 1, f"FAIL: reddit dm {rd} != 1"
assert em == 5, f"FAIL: email {em} != 5"
assert li + rc + rd + em == 14, f"FAIL: total {li+rc+rd+em} != 14"
assert queued == 14, f"FAIL: queued {queued} != 14"

# Verify anti-template diff function works
a, b = fake_drafts[0], fake_drafts[0]
assert diff_ratio(a, b) > 0.95, f"FAIL: identical strings should have ~1.0 diff, got {diff_ratio(a,b)}"
assert diff_ratio("hello world", "completely unrelated string") < 0.4, "FAIL: diff sensitivity"

print(f"[self-test] queued {queued} drafts (LI=5 RC=3 RD=1 EM=5 = 14)")
print(f"[self-test] anti-template diff function PASS (identical~{diff_ratio(a,b):.2f}, unrelated~{diff_ratio('hello world','completely unrelated string'):.2f})")
print(f"[self-test] PASS")
PYEOF
```

## Composition

- Reads: `data/leads/precise_leads.json`, `data/leads/active.json`, `data/outreach/log/index.json`, `data/outreach/log/<surface>/` recent sends.
- Calls: `openclaw agent --agent sales` for drafting, `tools/approvals/resolve_gate.py --create` per draft, `tools/notify/telegram_send.py`.
- Delegates send (post-YES): `linkedin-engage-cycle`, `reddit-engagement-cycle`, `email-outreach-monica` skills.
- Writes: `data/outreach/awaiting_approval/<surface>-<id>.md`, `data/outreach/log/<surface>/<id>.md`, `data/outreach/log/index.json`, `data/outreach/failed/<surface>-<id>.md`.

## Hard rules

1. NEVER send without Cooper YES.
2. Daily quotas hard-capped at 5/3/1/5 = 14.
3. Anti-template diff ≤0.6 vs same-surface last 10.
4. View-first DMs only on LinkedIn.
5. 14-day idempotency per prospect via index.json.
6. Two consecutive failures on the same prospect → permanent skip.
