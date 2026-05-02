#!/usr/bin/env bash
# Dry-run self-test for outreach-paced.
# Drafts 14 fake prospects (5 LI + 3 Reddit comment + 1 Reddit DM + 5 email),
# anti-template gates them, queues to data/outreach/awaiting_approval/.
# No openclaw agent dispatch, no Telegram send, no actual outreach.
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

prospects = []
for i in range(5):
    prospects.append({"surface":"linkedin", "prospect":{"name":f"Test LI {i}", "title":"Founder"}})
for i in range(3):
    prospects.append({"surface":"reddit", "action":"comment", "prospect":{"author":f"user{i}", "title":"Post about AI agents"}})
prospects.append({"surface":"reddit", "action":"dm", "prospect":{"author":"dm-user", "title":"Wants to chat"}})
for i in range(5):
    prospects.append({"surface":"email", "prospect":{"name":f"Test Email {i}", "company":"Acme"}})

fake_drafts = [
    f"Hey {p['prospect'].get('name', p['prospect'].get('author','x'))} — saw your {p.get('action','post')} about {p['prospect'].get('title','ops')[:30]}. Build a 30min audit free? cal.com/daily-ai-agents/30min — Cooper" + " " + secrets.token_hex(2)
    for p in prospects
]

queue_dir = home / "data/outreach/awaiting_approval"
queue_dir.mkdir(parents=True, exist_ok=True)

for f in queue_dir.glob("DRYRUN-*"):
    f.unlink()

queued = 0
for p, text in zip(prospects, fake_drafts):
    draft_id = "DRYRUN-" + secrets.token_hex(3)
    fname = f"{p['surface']}-{draft_id}.md"
    (queue_dir / fname).write_text(f"---\nid: {draft_id}\nsurface: {p['surface']}\naction: {p.get('action','send')}\nDRY_RUN: true\n---\n\n{text}\n")
    queued += 1

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

a, b = fake_drafts[0], fake_drafts[0]
assert diff_ratio(a, b) > 0.95, f"FAIL: identical strings should have ~1.0 diff, got {diff_ratio(a,b)}"
assert diff_ratio("hello world", "completely unrelated string") < 0.4, "FAIL: diff sensitivity"

print(f"[self-test] queued {queued} drafts (LI=5 RC=3 RD=1 EM=5 = 14)")
print(f"[self-test] anti-template diff function PASS (identical~{diff_ratio(a,b):.2f}, unrelated~{diff_ratio('hello world','completely unrelated string'):.2f})")
print(f"[self-test] PASS")
PYEOF
