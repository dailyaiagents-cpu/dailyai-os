#!/usr/bin/env bash
set -a
[ -f /Users/bots/Dev/daily-ai-agent-os/.env ] && source /Users/bots/Dev/daily-ai-agent-os/.env
set +a
# state-of-company-publisher/run.sh — weekly Sunday public narrative.
# cont-17v3 Phase C.2.
set +e

REPO=/Users/bots/Dev/daily-ai-agent-os
HTML_OUT="$REPO/site/state.html"
TMPL="$REPO/skills/state-of-company-publisher/template.html"
DRAFTS="$REPO/data/state-drafts"
PUB="$REPO/data/state-published"
TODAY=$(date -u +%Y-%m-%d)
SCRUBBER="$REPO/tools/voice/scrubber.py"
SCORER="$REPO/tools/voice/score.py"
OLLAMA_URL="http://127.0.0.1:11434/api/generate"
MODEL="qwen3.5:latest"

DRY_RUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    *) echo "STATUS=error reason=unknown-flag flag=$1"; exit 2 ;;
  esac
done

mkdir -p "$DRAFTS" "$PUB"

# Ollama ready check
if [ "$DRY_RUN" = "0" ]; then
  TAGS=$(curl -sf http://127.0.0.1:11434/api/tags --max-time 5 2>/dev/null)
  if [ -z "$TAGS" ] || ! echo "$TAGS" | grep -q "\"$MODEL\""; then
    echo "STATUS=skip reason=ollama-unreachable-or-model-missing"; exit 0
  fi
fi

# === Inputs ===
CTX=$(mktemp -t state-ctx.XXXXXX.md)
{
  echo "# Inputs for state-of-company composition (private; final output is sanitized)"
  echo
  echo "## Open handoff queue depth (counts only, no titles)"
  cd "$REPO"
  for spec in content builder ops sales research accountant trading; do
    n=$(ls "$REPO/data/team_bus/handoffs/open/" 2>/dev/null | grep -- "-to-$spec\.md\|-to-$spec-" | wc -l | tr -d ' ')
    echo "- $spec: $n"
  done

  echo
  echo "## Recent decisions (cont-* docs, last 7 days)"
  find "$REPO/data/decisions" -name "cont-*.md" -mtime -7 -type f 2>/dev/null | sort | while read f; do
    title=$(grep -m1 '^# ' "$f" | head -c 120)
    [ -n "$title" ] && echo "- $(basename "$f"): $title"
  done

  echo
  echo "## Recent commits (last 7 days, subjects only)"
  cd "$REPO" && git log --since="7 days ago" --no-merges --pretty=format:'- %h %s' 2>/dev/null | head -25

  echo
  echo "## P-gate catches in recent decision docs"
  find "$REPO/data/decisions" -name "*.md" -mtime -7 -type f 2>/dev/null \
    | xargs grep -ohE 'P[0-9]+ (caught|triggered|fired)' 2>/dev/null | sort | uniq -c | head -10

  echo
  echo "## Voice anchor (sentence rules)"
  sed -n '23,50p' "$REPO/VOICE.md"
} > "$CTX"

if [ "$DRY_RUN" = "1" ]; then
  echo "STATUS=ok-dryrun ctx=$CTX bytes=$(wc -c < "$CTX")"
  exit 0
fi

# === System prompt ===
SYS=$(cat <<'PROMPT'
You are the public-narrative writer for Daily AI Agents. Each Sunday you
draft a 350-500 word "state of the company" for the public website. Cooper
publishes the private sunday-review separately; your output is the public
counterpart and must NEVER name MRR, customer counts, lead names, win rates,
P&L figures, fills, or anything tied to private revenue or trading state.

VOICE — copy this verbatim. You are NOT writing in default LLM voice.
- Signal-dense, technically specific, slightly playful, emotionally even.
- Active voice. Average 12-18 words per sentence (newsletter surface).
- Every paragraph has a number, a name, a date, or a concrete example.
- Banned phrases: leverage (verb), synergy, game-changing, revolutionary,
  disrupt, unlock, actionable, world-class, cutting-edge, paradigm,
  10x, 100x, mind-blowing, "let's dive in", "in today's fast-paced world",
  "imagine a world where", "delve into", "tapestry of", "navigate the
  complexities", "at the end of the day", "here's the thing", "essentially",
  "basically", "literally" (non-literal), "obviously", "simply", "really",
  "very" (default).
- No throat-clearing. No CTA. End with one open question for readers.

STRUCTURE — exactly this:

# State of the company — week of {DATE}

## What we shipped

Three to five bullets. Each one cites a specific commit subject, decision
file, or skill name. Concrete.

## What we caught

Three to five bullets. Each names a P-gate that fired (P1-P12) or a
substrate-watcher that flagged drift, and what it prevented. Specific.

## What we are testing next

Two to four bullets. Each one names an experiment plus a falsifier (what
within 30 days would tell us the experiment was wrong).

End with: one open question for readers, no CTA, no link.

NO REVENUE. NO CUSTOMER COUNT. NO P&L. NO LEAD NAMES. NO PRIVATE URLS.
Talk about the architecture, the substrate, the gates, the methodology.

Output the markdown skeleton exactly as specified. NOTHING ELSE — no
preamble, no closing.
PROMPT
)

FULL_PROMPT="$SYS

# CONTEXT (read this before drafting)

$(cat "$CTX")

# YOUR TASK

Draft the state-of-the-company markdown for the week of $TODAY. Begin."

BODY_FILE=$(mktemp -t ollama-body.XXXXXX.json)
python3 -c "
import json, sys
model, prompt = sys.argv[1], sys.stdin.read()
print(json.dumps({'model': model, 'prompt': prompt, 'stream': False, 'think': False, 'options': {'num_predict': 1500, 'temperature': 0.6}}))
" "$MODEL" <<< "$FULL_PROMPT" > "$BODY_FILE"

RESP=$(curl -sf "$OLLAMA_URL" -X POST -H "Content-Type: application/json" --max-time 240 -d @"$BODY_FILE" 2>&1)
rm -f "$BODY_FILE" "$CTX"

DRAFT=$(echo "$RESP" | python3 -c "import sys, json; d = json.load(sys.stdin); print(d.get('response', ''))" 2>/dev/null)
if [ -z "$DRAFT" ]; then
  echo "STATUS=error reason=empty-draft response_head=$(echo "$RESP" | head -c 200)"
  exit 1
fi

# === Voice-gate (HARD threshold 70) ===
DRAFT_TMP=$(mktemp -t state-draft.XXXXXX.md)
echo "$DRAFT" > "$DRAFT_TMP"
SCORE_JSON=$(python3 "$SCORER" "$DRAFT_TMP" 2>/dev/null || echo '{"score": 0}')
SCORE=$(echo "$SCORE_JSON" | python3 -c "import sys, json; print(int(json.load(sys.stdin).get('score', 0)))" 2>/dev/null)
SCORE=${SCORE:-0}

if [ "$SCORE" -lt 70 ] 2>/dev/null; then
  DRAFT_PATH="$DRAFTS/$TODAY.md"
  cp "$DRAFT_TMP" "$DRAFT_PATH"
  rm -f "$DRAFT_TMP"
  echo "STATUS=draft path=$DRAFT_PATH reason=voice-fail score=$SCORE threshold=70"
  exit 0
fi

# === Scrubber HARD ===
SCRUB_OUT=$(python3 "$SCRUBBER" "$DRAFT_TMP" 2>&1)
SCRUB_RC=$?
if [ "$SCRUB_RC" -ne 0 ]; then
  DRAFT_PATH="$DRAFTS/$TODAY.md"
  cp "$DRAFT_TMP" "$DRAFT_PATH"
  rm -f "$DRAFT_TMP"
  echo "STATUS=draft path=$DRAFT_PATH reason=scrubber-fail score=$SCORE detail=$(echo "$SCRUB_OUT" | head -c 200 | tr '\n' ' ')"
  exit 0
fi

# === Both gates passed → publish ===
PUB_PATH="$PUB/$TODAY.md"
mv "$DRAFT_TMP" "$PUB_PATH"

# Render HTML wrapping the markdown body
python3 - "$TMPL" "$PUB_PATH" "$HTML_OUT" "$SCORE" "$TODAY" <<'PY'
import sys, html, pathlib
tmpl, body_md, html_out, score, today = sys.argv[1:6]
body = pathlib.Path(body_md).read_text()
# minimal markdown → HTML (headers + paragraphs + bullets)
import re
out_lines = []
in_list = False
for line in body.split('\n'):
    if line.startswith('# '):
        out_lines.append(f'<h1>{html.escape(line[2:])}</h1>')
    elif line.startswith('## '):
        if in_list: out_lines.append('</ul>'); in_list = False
        out_lines.append(f'<h2>{html.escape(line[3:])}</h2>')
    elif line.startswith('- '):
        if not in_list: out_lines.append('<ul>'); in_list = True
        out_lines.append(f'<li>{html.escape(line[2:])}</li>')
    elif line.strip() == '':
        if in_list: out_lines.append('</ul>'); in_list = False
        out_lines.append('')
    else:
        if in_list: out_lines.append('</ul>'); in_list = False
        out_lines.append(f'<p>{html.escape(line)}</p>')
if in_list: out_lines.append('</ul>')
body_html = '\n'.join(out_lines)
template = pathlib.Path(tmpl).read_text()
final = template.replace('{BODY}', body_html).replace('{SCORE}', str(score)).replace('{DATE}', today)
pathlib.Path(html_out).write_text(final)
PY

echo "STATUS=ok html=$HTML_OUT md=$PUB_PATH score=$SCORE"
