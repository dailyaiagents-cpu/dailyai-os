#!/usr/bin/env bash
set -a
[ -f /Users/bots/Dev/daily-ai-agent-os/.env ] && source /Users/bots/Dev/daily-ai-agent-os/.env
set +a
# skill-spotlight-publisher/run.sh — daily skill-of-the-day publisher.
# cont-17v3 Phase E.1.
set +e
# cont-18 D.1: skill-invocation-tracker hooks (non-fatal, best-effort)
_TRACK="/Users/bots/Dev/daily-ai-agent-os/skills/skill-invocation-tracker/run.sh"
_SKILL_NAME="skill-spotlight-publisher"
_SKILL_T0=$(date +%s)
[ -x "$_TRACK" ] && bash "$_TRACK" start "$_SKILL_NAME" >/dev/null 2>&1
trap '[ -x "$_TRACK" ] && SKILL_TRACKER_DURATION=$(( $(date +%s) - _SKILL_T0 )) bash "$_TRACK" end "$_SKILL_NAME" ${SKILL_EXIT_STATUS:-ok} >/dev/null 2>&1' EXIT

REPO=/Users/bots/Dev/daily-ai-agent-os
HISTORY="$REPO/data/skill-spotlights/_history.json"
DRAFTS="$REPO/data/skill-spotlights/drafts"
SITE_SKILLS="$REPO/site/skills"
TMPL="$REPO/skills/skill-spotlight-publisher/template.html"
SCRUBBER="$REPO/tools/voice/scrubber.py"
SCORER="$REPO/tools/voice/score.py"
OLLAMA_URL="http://127.0.0.1:11434/api/generate"
MODEL="qwen3.5:latest"
TODAY=$(date -u +%Y-%m-%d)

DRY_RUN=0
FORCE_SKILL=""
while [ $# -gt 0 ]; do
  case "$1" in
    --skill) FORCE_SKILL="$2"; shift 2 ;;
    --skill=*) FORCE_SKILL="${1#*=}"; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    *) echo "STATUS=error reason=unknown-flag flag=$1"; exit 2 ;;
  esac
done

mkdir -p "$DRAFTS" "$SITE_SKILLS"
[ -f "$HISTORY" ] || echo '{}' > "$HISTORY"

# === PICK A SKILL ===
if [ -n "$FORCE_SKILL" ]; then
  SLUG="$FORCE_SKILL"
  if [ ! -f "$REPO/skills/$SLUG/SKILL.md" ]; then
    echo "STATUS=error reason=skill-not-found slug=$SLUG"; exit 1
  fi
else
  SLUG=$(python3 - <<PY
import json, os, random, time, pathlib
repo = pathlib.Path("$REPO")
hist = json.loads((repo / "data/skill-spotlights/_history.json").read_text())
now = time.time()
sixty_days = 60 * 86400

candidates = []
for d in sorted((repo / "skills").iterdir()):
    if not d.is_dir(): continue
    skill_md = d / "SKILL.md"
    if not skill_md.exists(): continue
    name = d.name
    if name.startswith("_") or name.startswith("."): continue
    weight = 1
    body = skill_md.read_text()
    if "owner_agent:" in body: weight += 1
    if len(body.splitlines()) > 50: weight += 2
    h = hist.get(name)
    if h:
        try:
            from datetime import datetime, timezone
            spotlit = datetime.fromisoformat(h["spotlit_at"].replace("Z", "+00:00")).timestamp()
            if now - spotlit > sixty_days: weight += 5
            else: weight = max(1, weight - 3)  # recently spotlit; penalize
        except: weight += 5
    else:
        weight += 5
    candidates.append((name, weight))

if not candidates:
    print("")
    raise SystemExit(0)

# weighted random
total = sum(w for _, w in candidates)
pick = random.uniform(0, total)
acc = 0
for name, w in candidates:
    acc += w
    if pick <= acc:
        print(name); break
PY
  )
fi

if [ -z "$SLUG" ]; then
  echo "STATUS=skip reason=no-eligible-skill"; exit 0
fi

SKILL_DIR="$REPO/skills/$SLUG"
if [ ! -f "$SKILL_DIR/SKILL.md" ]; then
  echo "STATUS=error reason=skill-md-missing slug=$SLUG"
  exit 1
fi

# === Read SOUL + SKILL ===
SKILL_BODY=$(cat "$SKILL_DIR/SKILL.md")
SOUL_BODY=$(cat "$SKILL_DIR/SOUL.md" 2>/dev/null)
OWNER=$(grep -m1 '^owner_agent:' "$SKILL_DIR/SKILL.md" | cut -d: -f2 | tr -d ' \r\n')
OWNER=${OWNER:-unassigned}

if [ "$DRY_RUN" = "1" ]; then
  echo "STATUS=ok-dryrun slug=$SLUG owner=$OWNER soul_lines=$(echo "$SOUL_BODY" | wc -l) skill_lines=$(echo "$SKILL_BODY" | wc -l)"
  exit 0
fi

# Verify Ollama
TAGS=$(curl -sf http://127.0.0.1:11434/api/tags --max-time 5 2>/dev/null)
if [ -z "$TAGS" ] || ! echo "$TAGS" | grep -q "\"$MODEL\""; then
  echo "STATUS=skip reason=ollama-unreachable-or-model-missing"; exit 0
fi

# === System prompt ===
SYS=$(cat <<'PROMPT'
You are writing one daily spotlight in the Daily AI Agents voice.
Audience: a solo founder who has not seen DAI OS. They glance at one
short post and decide whether to keep reading. Your job is to make them
decide yes.

VOICE — Daily AI Agents per VOICE.md.
- Active voice. Average 12-18 words per sentence.
- Each paragraph contains a number, name, date, or concrete example.
- Banned: leverage (verb), synergy, game-changing, unlock, actionable,
  cutting-edge, paradigm, 10x, "let's dive in", "in today's fast-paced
  world", "delve into", "tapestry of", "essentially", "basically",
  "literally" (non-literal), "obviously", "simply", "really", "very".
- No throat-clearing. No CTA at the end.

SHAPE — exactly 3 paragraphs, total ~200 words:

Paragraph 1 — what problem it solves. Two sentences. Name the failure
mode the founder has actually had ("you forgot to commit the gitignore
patch and 400 auto-generated files filled the diff" rather than "manage
your git workflow").

Paragraph 2 — when to reach for it. Two to three sentences. Name a
specific trigger ("when your dirty tree exceeds 200 files", "every time
the substrate-watchers fire YELLOW", "when prepping a public surface
that quotes a commit count"). Concrete.

Paragraph 3 — the single most surprising thing about how it works. Two
sentences. Lean toward implementation cleverness over feature lists. The
founder reads this and thinks "huh, I would not have built it that way."

NEVER quote MRR, customer counts, win rates, or anything that could leak
private revenue or trading state. The skill catalog describes capability,
not realized outcome (P11).

Output the three paragraphs separated by blank lines. NOTHING ELSE — no
preamble, no closing, no header.
PROMPT
)

FULL_PROMPT="$SYS

# SKILL TO SPOTLIGHT: $SLUG (owned by $OWNER)

## SOUL.md

$SOUL_BODY

## SKILL.md

$SKILL_BODY

# YOUR TASK

Write the three-paragraph spotlight in Cooper's voice. Begin."

BODY_FILE=$(mktemp -t ollama-body.XXXXXX.json)
python3 -c "
import json, sys
model, prompt = sys.argv[1], sys.stdin.read()
print(json.dumps({'model': model, 'prompt': prompt, 'stream': False, 'think': False, 'options': {'num_predict': 600, 'temperature': 0.6}}))
" "$MODEL" <<< "$FULL_PROMPT" > "$BODY_FILE"

RESP=$(curl -sf "$OLLAMA_URL" -X POST -H "Content-Type: application/json" --max-time 180 -d @"$BODY_FILE" 2>&1)
rm -f "$BODY_FILE"

EXPLAINER=$(echo "$RESP" | python3 -c "import sys, json; d = json.load(sys.stdin); print(d.get('response', '').strip())" 2>/dev/null)
if [ -z "$EXPLAINER" ]; then
  echo "STATUS=error reason=empty-explainer head=$(echo "$RESP" | head -c 200)"
  exit 1
fi

# === Voice-gate (HARD threshold 70) ===
EXP_TMP=$(mktemp -t spotlight.XXXXXX.md)
echo "$EXPLAINER" > "$EXP_TMP"
SCORE_JSON=$(python3 "$SCORER" "$EXP_TMP" 2>/dev/null || echo '{"score": 0}')
SCORE=$(echo "$SCORE_JSON" | python3 -c "import sys, json; print(int(json.load(sys.stdin).get('score', 0)))" 2>/dev/null)
SCORE=${SCORE:-0}

GATE_FAIL=""
if [ "$SCORE" -lt 70 ] 2>/dev/null; then
  GATE_FAIL="voice-fail-$SCORE"
fi

# === Scrubber HARD ===
SCRUB_OUT=$(python3 "$SCRUBBER" "$EXP_TMP" 2>&1)
SCRUB_RC=$?
if [ "$SCRUB_RC" -ne 0 ]; then
  GATE_FAIL="${GATE_FAIL:+$GATE_FAIL,}scrubber-fail"
fi

if [ -n "$GATE_FAIL" ]; then
  DRAFT_PATH="$DRAFTS/$TODAY-$SLUG.md"
  cp "$EXP_TMP" "$DRAFT_PATH"
  rm -f "$EXP_TMP"
  echo "STATUS=draft skill=$SLUG path=$DRAFT_PATH reason=$GATE_FAIL score=$SCORE"
  exit 0
fi

# === Both gates passed → publish ===
SLUG_DIR="$SITE_SKILLS/$SLUG"
mkdir -p "$SLUG_DIR"
HTML_OUT="$SLUG_DIR/spotlight.html"

python3 - "$TMPL" "$EXP_TMP" "$HTML_OUT" "$SLUG" "$OWNER" "$SCORE" "$TODAY" <<'PY'
import sys, html, pathlib
tmpl, body_md, html_out, slug, owner, score, today = sys.argv[1:8]
body = pathlib.Path(body_md).read_text().strip()
paras = [p.strip() for p in body.split('\n\n') if p.strip()]
body_html = '\n'.join(f'<p>{html.escape(p)}</p>' for p in paras)
template = pathlib.Path(tmpl).read_text()
final = (template
    .replace('{SLUG}', slug)
    .replace('{OWNER}', owner)
    .replace('{SCORE}', str(score))
    .replace('{DATE}', today)
    .replace('{BODY}', body_html))
pathlib.Path(html_out).write_text(final)
PY

# === Update history ===
python3 - "$HISTORY" "$SLUG" "$SCORE" "$HTML_OUT" "$TODAY" <<'PY'
import sys, json, pathlib
hist_path, slug, score, html_path, today = sys.argv[1:6]
p = pathlib.Path(hist_path)
hist = json.loads(p.read_text())
from datetime import datetime, timezone
hist[slug] = {
    "spotlit_at": datetime.now(timezone.utc).isoformat(),
    "voice_score": int(score),
    "html_path": html_path,
    "date": today,
}
p.write_text(json.dumps(hist, indent=2))
PY

# === Update site/skills/index.html ===
python3 - "$SITE_SKILLS" "$HISTORY" "$REPO" <<'PY'
import sys, json, pathlib, html
site_skills = pathlib.Path(sys.argv[1])
hist = json.loads(pathlib.Path(sys.argv[2]).read_text())
repo = pathlib.Path(sys.argv[3])
items = sorted(hist.items(), key=lambda kv: kv[1].get("date", ""), reverse=True)
rows = []
for slug, h in items:
    date = h.get("date", "?")
    rows.append(f'<li><a href="/skills/{slug}/spotlight.html">{html.escape(slug)}</a> <span class="date">{html.escape(date)}</span></li>')
idx_html = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<title>Skill spotlights — Daily AI Agents</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
body {{ font: 16px/1.6 Charter, Georgia, serif; max-width: 720px; margin: 0 auto; padding: 48px 24px; color: #1a1a1a; }}
h1 {{ font-size: 28px; margin: 0 0 12px; letter-spacing: -0.01em; }}
.meta {{ color: #888; font-size: 13px; margin-bottom: 28px; }}
ul {{ list-style: none; padding: 0; }}
li {{ padding: 8px 0; border-bottom: 1px solid #eee; display: flex; justify-content: space-between; }}
.date {{ color: #888; font-size: 13px; }}
a {{ color: #2a6; text-decoration: none; }}
a:hover {{ text-decoration: underline; }}
.footer {{ margin-top: 36px; padding-top: 16px; border-top: 1px solid #eee; color: #888; font-size: 13px; }}
</style></head><body>
<h1>Skill spotlights</h1>
<div class="meta">One Daily AI Agents skill explained per day. {len(items)} published.</div>
<ul>{''.join(rows)}</ul>
<div class="footer"><a href="/">home</a> · <a href="/receipts.html">receipts</a></div>
</body></html>"""
(site_skills / "index.html").write_text(idx_html)
PY

rm -f "$EXP_TMP"
echo "STATUS=ok skill=$SLUG path=$HTML_OUT score=$SCORE owner=$OWNER"
