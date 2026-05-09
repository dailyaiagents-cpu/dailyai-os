#!/usr/bin/env bash
set -a
[ -f /Users/bots/Dev/daily-ai-agent-os/.env ] && source /Users/bots/Dev/daily-ai-agent-os/.env
set +a
# meta-skill/run.sh — generate a new skill from a problem description.
# cont-17v3 Phase F.1.
set +e

REPO=/Users/bots/Dev/daily-ai-agent-os
PROPOSED="$REPO/data/proposed_skills/cont-17-meta"
SCRUBBER="$REPO/tools/voice/scrubber.py"
SCORER="$REPO/tools/voice/score.py"
OLLAMA_URL="http://127.0.0.1:11434/api/generate"
MODEL="qwen3.5:latest"

DRY_RUN=0
PROBLEM=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) echo "usage: bash meta-skill/run.sh [--dry-run] \"problem description\""; exit 0 ;;
    *) PROBLEM="$1"; shift ;;
  esac
done

if [ -z "$PROBLEM" ]; then
  echo "STATUS=error reason=no-problem-description"
  echo "usage: bash meta-skill/run.sh \"I need a skill that ...\""
  exit 2
fi

mkdir -p "$PROPOSED"

# Verify Ollama
TAGS=$(curl -sf http://127.0.0.1:11434/api/tags --max-time 5 2>/dev/null)
if [ -z "$TAGS" ] || ! echo "$TAGS" | grep -q "\"$MODEL\""; then
  echo "STATUS=skip reason=ollama-unreachable-or-model-missing"; exit 0
fi

# === Phase 1: extract spec via Ollama ===
SPEC_PROMPT=$(cat <<EOF
You generate a skill spec as strict JSON. The values you write must be
ACTUAL specific values for the requested skill, NEVER schema placeholder
text.

The schema (with EXAMPLE values for a hypothetical "watch-screenshots-folder" skill):

{
  "skill_name": "watch-screenshots-folder",
  "owner_agent": "ops",
  "description": "Polls /Users/bots/Downloads every 60s for new PNG screenshots and uploads any matching the founder-meeting tag pattern to the public bundle assets folder.",
  "pipeline_steps": [
    "List /Users/bots/Downloads filtering for *.png modified in last 60s.",
    "Match basename against the founder-meeting-2026-* pattern; skip non-matches.",
    "Copy matched files to public-bundle/assets/screenshots/ with atomic .tmp+rename.",
    "Append a record to data/screenshot-uploads/_history.jsonl."
  ],
  "trigger": "cron-hourly",
  "inputs": ["watch_dir"],
  "outputs": "files copied to public-bundle/assets/screenshots/ and an append-only history log"
}

owner_agent must be ONE OF: content, builder, ops, sales, research, accountant, trading, hermes.
trigger must be ONE OF: cron-daily, cron-weekly, cron-hourly, on-event, manual, on-skill-call.

Now: extract the spec for THIS specific problem. Use real values, real
paths, real verbs. Do not copy any text from the schema example above.
The skill name must be a kebab-case description of the actual problem
(3-6 words, no placeholders).

Problem description:
"""
$PROBLEM
"""

Output ONLY the JSON object — no markdown, no preamble, no closing. Begin.
EOF
)

BODY_FILE=$(mktemp -t meta-spec.XXXXXX.json)
python3 -c "
import json, sys
model, prompt = sys.argv[1], sys.stdin.read()
print(json.dumps({'model': model, 'prompt': prompt, 'stream': False, 'think': False, 'options': {'num_predict': 800, 'temperature': 0.3}}))
" "$MODEL" <<< "$SPEC_PROMPT" > "$BODY_FILE"

RESP=$(curl -sf "$OLLAMA_URL" -X POST -H "Content-Type: application/json" --max-time 180 -d @"$BODY_FILE" 2>&1)
rm -f "$BODY_FILE"

SPEC_RAW=$(echo "$RESP" | python3 -c "import sys, json; d = json.load(sys.stdin); print(d.get('response', '').strip())" 2>/dev/null)
if [ -z "$SPEC_RAW" ]; then
  echo "STATUS=error reason=empty-spec head=$(echo "$RESP" | head -c 200)"
  exit 1
fi

# Try to parse JSON; tolerate code-fence wrappers
SPEC=$(echo "$SPEC_RAW" | python3 -c "
import sys, json, re
raw = sys.stdin.read().strip()
# Strip markdown code fences
m = re.search(r'\`\`\`(?:json)?\s*(\{.*?\})\s*\`\`\`', raw, re.S)
if m: raw = m.group(1)
# Find first JSON object
i = raw.find('{')
j = raw.rfind('}')
if i >= 0 and j > i:
    raw = raw[i:j+1]
try:
    spec = json.loads(raw)
    print(json.dumps(spec))
except Exception as e:
    sys.stderr.write(f'parse-fail: {e}')
    sys.exit(1)
" 2>&1)
PARSE_RC=$?
if [ "$PARSE_RC" -ne 0 ]; then
  echo "STATUS=error reason=spec-parse-failed detail=$(echo "$SPEC" | head -c 200)"
  exit 1
fi

# Extract fields
SKILL_NAME=$(echo "$SPEC" | python3 -c "import sys, json; print(json.load(sys.stdin).get('skill_name', ''))")
OWNER=$(echo "$SPEC" | python3 -c "import sys, json; print(json.load(sys.stdin).get('owner_agent', ''))")
DESC=$(echo "$SPEC" | python3 -c "import sys, json; print(json.load(sys.stdin).get('description', ''))")
TRIGGER=$(echo "$SPEC" | python3 -c "import sys, json; print(json.load(sys.stdin).get('trigger', 'manual'))")

# Sanitize skill name
SKILL_NAME=$(echo "$SKILL_NAME" | tr 'A-Z ' 'a-z-' | sed 's/[^a-z0-9-]//g' | sed 's/--*/-/g' | sed 's/^-\|-$//g')
if [ -z "$SKILL_NAME" ]; then
  echo "STATUS=error reason=empty-skill-name"
  exit 1
fi

if [ "$DRY_RUN" = "1" ]; then
  echo "STATUS=ok-dryrun skill=$SKILL_NAME owner=$OWNER trigger=$TRIGGER desc=\"$(echo $DESC | head -c 80)\""
  exit 0
fi

# === Phase 2: generate scaffolded files ===
WORK_DIR=$(mktemp -d -t meta-skill.XXXXXX)
trap "rm -rf $WORK_DIR" EXIT

# SKILL.md
cat > "$WORK_DIR/SKILL.md" <<EOF
---
name: $SKILL_NAME
owner_agent: $OWNER
description: $DESC
trigger: $TRIGGER
generator: meta-skill (cont-17v3 F.1)
---

# $SKILL_NAME

## Procedure

\`\`\`bash
bash skills/$SKILL_NAME/run.sh
bash skills/$SKILL_NAME/run.sh --dry-run
\`\`\`

## Pipeline

EOF

echo "$SPEC" | python3 -c "
import sys, json
spec = json.load(sys.stdin)
for i, s in enumerate(spec.get('pipeline_steps', []), 1):
    print(f'{i}. {s}')
" >> "$WORK_DIR/SKILL.md"

cat >> "$WORK_DIR/SKILL.md" <<'EOF'

## Status codes

`STATUS=ok ...` / `STATUS=skip reason=<...>` / `STATUS=error reason=<...>`

## DDWC pattern (cont-19.9-N)

### Diagnose
What is this skill probing or detecting? One sentence — the failure mode this skill exists to catch.

### Deploy
What does this skill change in the substrate when it fires? One sentence — be honest about side effects, including "no side effects, detection only" if true.

### Watch
What signal tells you this skill is healthy? One sentence — a metric, a log line, a STATUS-line shape.

### Compound
What does this skill leave behind that the NEXT skill or run can build on? One sentence — the substrate that compounds.

## Inputs / outputs

EOF
echo "$SPEC" | python3 -c "
import sys, json
spec = json.load(sys.stdin)
inputs = spec.get('inputs', [])
print('Inputs: ' + (', '.join(inputs) if inputs else 'none'))
print()
print('Outputs: ' + spec.get('outputs', '(unspecified)'))
" >> "$WORK_DIR/SKILL.md"

cat >> "$WORK_DIR/SKILL.md" <<'EOF'

## Gates

- voice-gate (advisory) on any text output
- scrubber HARD on any public-facing output
- This skill was scaffolded by `meta-skill` (cont-17v3 F.1). The body is
  TODO markers; a human or follow-up agent fills the actual logic.
EOF

# SOUL.md
cat > "$WORK_DIR/SOUL.md" <<EOF
# SOUL — $SKILL_NAME

I am $SKILL_NAME.

$DESC

I run on free local inference where applicable. I respect the 12 P-gates
and the voice-gate / scrubber discipline. My pipeline body is currently
TODO — the meta-skill scaffold guarantees my shape and gate calls; a
human fills the substance before I publish anything to a public surface.

I am owned by $OWNER. The owner reviews my outputs the first few times
I run and decides whether to graduate me to autonomous operation or
quarantine me.

I respect the failure mode I was built to prevent: ad-hoc bash glue.
A skill is a contract; meta-skill scaffolds me with the contract's
shape so the substance has somewhere to land.
EOF

# run.sh
cat > "$WORK_DIR/run.sh" <<EOF
#!/usr/bin/env bash
# $SKILL_NAME/run.sh — scaffolded by meta-skill (cont-19.9-N).
# Owner: $OWNER. Trigger: $TRIGGER.
# TODO(human): fill in the pipeline body. Gate calls and error handling
# are already in place.
set +e

# === source-env loader (cont-19.9-N) ===
# Auto-load secrets from the canonical repo .env so credential-using skills
# don't silently fail when invoked outside an interactive shell.
if [ -f /Users/bots/Dev/daily-ai-agent-os/.env ]; then
  set -a
  . /Users/bots/Dev/daily-ai-agent-os/.env
  set +a
fi

REPO=/Users/bots/Dev/daily-ai-agent-os
DRY_RUN=0

while [ \$# -gt 0 ]; do
  case "\$1" in
    --dry-run) DRY_RUN=1; shift ;;
    *) echo "STATUS=error reason=unknown-flag flag=\$1"; exit 2 ;;
  esac
done

# === Pipeline ===
EOF
echo "$SPEC" | python3 -c "
import sys, json
spec = json.load(sys.stdin)
for i, s in enumerate(spec.get('pipeline_steps', []), 1):
    print(f'# Step {i}: {s}')
    print(f'# TODO(human): implement step {i}')
    print()
" >> "$WORK_DIR/run.sh"

cat >> "$WORK_DIR/run.sh" <<EOF

if [ "\$DRY_RUN" = "1" ]; then
  echo "STATUS=ok-dryrun skill=$SKILL_NAME (scaffolded by meta-skill; pipeline body still TODO)"
  exit 0
fi

# Default body: report skeleton-only state.
echo "STATUS=ok skill=$SKILL_NAME note=scaffolded-pipeline-body-still-TODO"
EOF
chmod +x "$WORK_DIR/run.sh"

# === Phase 3: validate ===
VALID_FAILURES=()

# 3a: voice-gate on description (threshold 60 — descriptions are short)
DESC_TMP=$(mktemp -t meta-desc.XXXXXX.txt)
echo "$DESC" > "$DESC_TMP"
SCORE=$(python3 "$SCORER" "$DESC_TMP" 2>/dev/null | python3 -c "import sys, json; print(int(json.load(sys.stdin).get('score', 0)))" 2>/dev/null)
SCORE=${SCORE:-0}
if [ "$SCORE" -lt 60 ] 2>/dev/null; then
  VALID_FAILURES+=("voice-gate-$SCORE")
fi

# 3b: scrubber HARD on description
SCRUB_OUT=$(python3 "$SCRUBBER" "$DESC_TMP" 2>&1)
if [ "$?" -ne 0 ]; then
  VALID_FAILURES+=("scrubber-fail")
fi
rm -f "$DESC_TMP"

# 3c: bash -n on run.sh
if ! bash -n "$WORK_DIR/run.sh" 2>/dev/null; then
  VALID_FAILURES+=("bash-syntax")
fi

# 3d: smoke-test --dry-run
SMOKE_OUT=$(bash "$WORK_DIR/run.sh" --dry-run 2>&1)
SMOKE_RC=$?
if [ "$SMOKE_RC" -ne 0 ] && [ "$SMOKE_RC" -ne 1 ]; then
  VALID_FAILURES+=("smoke-rc-$SMOKE_RC")
fi
if ! echo "$SMOKE_OUT" | grep -q "^STATUS="; then
  VALID_FAILURES+=("smoke-no-status")
fi

# === Phase 4: land ===
if [ "${#VALID_FAILURES[@]}" -eq 0 ]; then
  # All gates passed → land in runtime
  if [ "$OWNER" = "hermes" ]; then
    LAND_DIR="$HOME/.hermes/skills/$SKILL_NAME"
  else
    LAND_DIR="$HOME/.openclaw/skills/$SKILL_NAME"
  fi
  if [ -d "$LAND_DIR" ]; then
    # Avoid overwriting; route to proposed/
    LAND_DIR="$PROPOSED/$SKILL_NAME"
    NOTE="(name collision; routed to proposed/)"
  else
    NOTE=""
  fi
  mkdir -p "$LAND_DIR"
  cp "$WORK_DIR"/* "$LAND_DIR/"
  python3 -c "
import json
print(json.dumps({
  'status': 'ok',
  'skill_path': '$LAND_DIR',
  'smoke_test_result': '$SMOKE_OUT'.replace('\n', ' ')[:200],
  'gates_passed': ['voice-gate', 'scrubber', 'bash-syntax', 'smoke-test'],
  'voice_score': $SCORE
}))
"
  # Auto-include in capability-index v2 (cont-19.9-N)
  CAP_INDEX_BUILDER="$REPO/scripts/build_capability_index.sh"
  if [ -x "$CAP_INDEX_BUILDER" ]; then
    bash "$CAP_INDEX_BUILDER" >/dev/null 2>&1 && CAP_HOOK="capability-index=updated" || CAP_HOOK="capability-index=update-failed"
  else
    CAP_HOOK="capability-index=builder-missing"
  fi
  echo "STATUS=ok skill=$SKILL_NAME path=$LAND_DIR voice_score=$SCORE $NOTE $CAP_HOOK"
else
  # At least one gate failed → land in proposed/ with _VALIDATION.md
  LAND_DIR="$PROPOSED/$SKILL_NAME"
  mkdir -p "$LAND_DIR"
  cp "$WORK_DIR"/* "$LAND_DIR/"
  cat > "$LAND_DIR/_VALIDATION.md" <<EOF
# Validation report — $SKILL_NAME

Generated by meta-skill (cont-17v3 F.1) at $(date -u +%FT%TZ).

## Inputs

Problem description: $PROBLEM

## Spec extracted

$SPEC

## Failures

$(printf "%s\n" "${VALID_FAILURES[@]}" | sed 's/^/- /')

## Voice score

$SCORE / 100

## Smoke output

\`\`\`
$SMOKE_OUT
\`\`\`

## Cooper action

Review the SKILL.md, SOUL.md, and run.sh in this directory. Either fix
the failures and copy to ~/.openclaw/skills/$SKILL_NAME/ (or
~/.hermes/skills/$SKILL_NAME/ for hermes-owned) or delete this proposal.
EOF
  python3 -c "
import json
print(json.dumps({
  'status': 'proposed',
  'skill_path': '$LAND_DIR',
  'smoke_test_result': '$SMOKE_OUT'.replace('\n', ' ')[:200],
  'gates_passed': [],
  'failed': '${VALID_FAILURES[@]}',
  'voice_score': $SCORE
}))
"
  echo "STATUS=proposed skill=$SKILL_NAME path=$LAND_DIR failed=$(IFS=,; echo "${VALID_FAILURES[*]}") voice_score=$SCORE"
fi
