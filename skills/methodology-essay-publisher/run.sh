#!/usr/bin/env bash
set -a
[ -f /Users/bots/Dev/daily-ai-agent-os/.env ] && source /Users/bots/Dev/daily-ai-agent-os/.env
set +a
# methodology-essay-publisher/run.sh — split methodology.md into 8 essays.
# cont-18 Phase F.1.
set +e

REPO=/Users/bots/Dev/daily-ai-agent-os
SOURCE="$REPO/docs/methodology.md"
ESSAYS_DIR="$REPO/site/essays"
DRAFTS_DIR="$REPO/data/essays/drafts"
TMPL="$REPO/skills/methodology-essay-publisher/template.html"
SCRUBBER="$REPO/tools/voice/scrubber.py"
SCORER="$REPO/tools/voice/score.py"
TODAY=$(date -u +%Y-%m-%d)
THRESHOLD=70

DRY_RUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    *) echo "STATUS=error reason=unknown-flag flag=$1"; exit 2 ;;
  esac
done

if [ ! -f "$SOURCE" ]; then
  echo "STATUS=skip reason=methodology-missing path=$SOURCE"
  exit 0
fi

mkdir -p "$ESSAYS_DIR" "$DRAFTS_DIR"

python3 - "$SOURCE" "$ESSAYS_DIR" "$DRAFTS_DIR" "$TMPL" "$SCRUBBER" "$SCORER" "$TODAY" "$THRESHOLD" "$DRY_RUN" <<'PY'
import sys, re, html, json, subprocess, pathlib, tempfile, os

source_p, essays_d, drafts_d, tmpl_p, scrubber, scorer, today, threshold, dry = sys.argv[1:10]
threshold = int(threshold)
dry = (dry == "1")

src = pathlib.Path(source_p).read_text()

# Split by "## Chapter N — title"
chapters_raw = re.split(r"^## (Chapter \d+ — [^\n]+)$", src, flags=re.M)
# chapters_raw[0] is preamble, then alternating (header, body) pairs.
chapters = []
for i in range(1, len(chapters_raw), 2):
    header = chapters_raw[i]
    body = chapters_raw[i+1] if i+1 < len(chapters_raw) else ""
    # Stop body at the next major header or end
    m = re.match(r"Chapter (\d+) — (.+)", header)
    if not m:
        continue
    num = int(m.group(1))
    title = m.group(2).strip()
    chapters.append({"n": num, "title": title, "body": body.strip()})

if not chapters:
    print("STATUS=skip reason=no-chapters-parsed")
    sys.exit(0)

def slugify(s: str) -> str:
    s = re.sub(r"[^a-zA-Z0-9 -]", "", s).lower()
    s = re.sub(r"\s+", "-", s).strip("-")
    return s[:60]

def md_to_html(md: str) -> str:
    """Tiny converter for the subset used in methodology.md.
    Headers, paragraphs, blockquotes, lists, tables, code fences."""
    lines = md.split("\n")
    out = []
    in_list = False
    in_table = False
    table_buf = []
    in_pre = False
    pre_buf = []
    in_blockquote = False
    bq_buf = []

    def flush_list():
        nonlocal in_list
        if in_list:
            out.append("</ul>")
            in_list = False

    def flush_table():
        nonlocal in_table, table_buf
        if in_table:
            rows = [r for r in table_buf if r.strip()]
            if len(rows) >= 2:
                hdr = [c.strip() for c in rows[0].strip("|").split("|")]
                body_rows = []
                for r in rows[2:]:  # skip the alignment row
                    cells = [c.strip() for c in r.strip("|").split("|")]
                    body_rows.append(cells)
                t = "<table><thead><tr>" + "".join(f"<th>{html.escape(h)}</th>" for h in hdr) + "</tr></thead><tbody>"
                for r in body_rows:
                    t += "<tr>" + "".join(f"<td>{html.escape(c)}</td>" for c in r) + "</tr>"
                t += "</tbody></table>"
                out.append(t)
            in_table = False
            table_buf = []

    def flush_blockquote():
        nonlocal in_blockquote, bq_buf
        if in_blockquote:
            txt = " ".join(b.lstrip("> ").strip() for b in bq_buf)
            out.append(f"<blockquote>{html.escape(txt)}</blockquote>")
            in_blockquote = False
            bq_buf = []

    def inline(s: str) -> str:
        s = html.escape(s)
        s = re.sub(r"`([^`]+)`", r"<code>\1</code>", s)
        s = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", s)
        s = re.sub(r"(?<![*\w])\*([^*\n]+)\*(?!\w)", r"<em>\1</em>", s)
        s = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', s)
        return s

    for line in lines:
        if line.startswith("```"):
            if in_pre:
                out.append("<pre>" + html.escape("\n".join(pre_buf)) + "</pre>")
                pre_buf = []
                in_pre = False
            else:
                flush_list(); flush_table(); flush_blockquote()
                in_pre = True
            continue
        if in_pre:
            pre_buf.append(line)
            continue
        if line.startswith("|") and line.strip().endswith("|"):
            flush_list(); flush_blockquote()
            in_table = True
            table_buf.append(line)
            continue
        else:
            if in_table:
                flush_table()
        if line.startswith("> "):
            flush_list(); flush_table()
            in_blockquote = True
            bq_buf.append(line)
            continue
        else:
            if in_blockquote:
                flush_blockquote()
        if line.startswith("### "):
            flush_list(); flush_table(); flush_blockquote()
            out.append(f"<h3>{inline(line[4:].strip())}</h3>")
        elif line.startswith("## "):
            flush_list(); flush_table(); flush_blockquote()
            out.append(f"<h2>{inline(line[3:].strip())}</h2>")
        elif line.startswith("- ") or line.startswith("* "):
            if not in_list:
                out.append("<ul>")
                in_list = True
            out.append(f"<li>{inline(line[2:].strip())}</li>")
        elif line.strip() == "":
            flush_list(); flush_table(); flush_blockquote()
            out.append("")
        else:
            flush_list(); flush_table(); flush_blockquote()
            out.append(f"<p>{inline(line)}</p>")

    flush_list(); flush_table(); flush_blockquote()
    if in_pre:
        out.append("<pre>" + html.escape("\n".join(pre_buf)) + "</pre>")
    return "\n".join(out)

def voice_score(text: str) -> int:
    fp = pathlib.Path(tempfile.mkstemp(suffix=".md")[1])
    fp.write_text(text)
    try:
        out = subprocess.check_output(["python3", scorer, str(fp)], timeout=30)
        return int(json.loads(out).get("score", 0))
    except Exception:
        return 0
    finally:
        try: fp.unlink()
        except Exception: pass

def scrubber_clean(text: str) -> tuple[bool, str]:
    fp = pathlib.Path(tempfile.mkstemp(suffix=".md")[1])
    fp.write_text(text)
    try:
        proc = subprocess.run(["python3", scrubber, str(fp)], capture_output=True, timeout=30)
        if proc.returncode == 0:
            return True, ""
        try:
            out = json.loads(proc.stdout)
            hits = out.get("hits", [])
            return False, ", ".join(h.get("match", "") for h in hits[:3])
        except Exception:
            return False, "scrubber-output-unparseable"
    finally:
        try: fp.unlink()
        except Exception: pass

# Build essays
intros = {
    1: ("AI-native is not the same as AI-assisted. This essay names the three properties that distinguish a company whose operating substrate is AI from one that merely uses AI. The combination of autonomous workflows, bounded human oversight, and voice-gated public outputs is rare and compounds — most teams have one of the three; few have all three; the gap widens every quarter as the autonomous skill catalog grows.\n\nRead this if you are deciding whether to build an AI-native runtime versus glue together off-the-shelf SaaS. The decision is structural, not tactical. By the end of the essay you will have a rubric you can score your own setup against.",),
    2: ("Daily AI Agents runs on four pillars: Hermes the brain, OpenClaw the arms, Obsidian the memory, Paperclip the audit. This essay is the architecture diagram in 800 words — what each pillar owns, what ports they bind, how they talk to each other over symmetric MCP, and what the boundary rules are.\n\nIf you are wiring up a multi-agent system, this is the chapter that saves you a week of bespoke HTTP-endpoint integration. The four pillars are independent processes with well-defined contracts; together they form one operating system, not a hairball.",),
    3: ("Skills are the procedural memory of the company. This essay covers the SOUL.md / SKILL.md / run.sh contract that every skill follows, why bash is the right language for the catalog, and the atomic capability loop that grows the catalog autonomously week after week.\n\nA 340-skill catalog is good. A growing catalog is the moat. The discipline that makes growth possible is the structural shape of each skill — readable in 60 seconds, smoke-tested before promotion, owner-tagged for auto-wire. Read this if you have a working agent and want to know why your catalog is not compounding.",),
    4: ("Public output without quality gates is corporate hype. This essay covers the two gates every public-bound output passes: voice-gate (advisory, scored against a documented rubric) and public-content scrubber (hard-blocks financial-data leaks).\n\nThe gates are simple Python; the discipline is what matters. A founder who relies on \"I'll proofread before publish\" produces 30% off-voice output by default; a founder whose pipeline has voice-gate as a hard pre-publish step produces 100% on-voice output. Read this for the rubric weights, the surface calibration, and the allowlist patterns that keep sticker prices visible without leaking realized intake.",),
    5: ("Internal numbers and public surfaces are different audiences. This essay covers the /dashboard pattern — real numbers private to the founder and investors, sticker prices and architecture facts public to everyone else. The wall between the two is enforced structurally by the public-content scrubber, not by founder vigilance.\n\nThe pattern matters because it solves a tension every founder faces: public credibility wants real numbers; competitor hygiene wants concealed numbers. The compromise most founders make — vague metrics like \"thousands of users\" — is worst of both worlds. Read this for the cleaner answer.",),
    6: ("Six patterns make the founder UX livable. This essay covers session-keeper, delegation-orchestrator, inbox-zero-batch, deep-work toggle, Sunday review, and Friday ship log. Each is a single skill; together they make the system livable. Without them, an AI-native company collapses on the founder.\n\nRead this if your AI agents are running but the founder's attention is being shredded by approval requests, surprise re-auth prompts, and after-hours notifications. The UX patterns are what determine whether the runtime is durable or whether the founder burns out at month three.",),
    7: ("Every code change passes through a 12-gate checklist before it ships. This essay covers what each gate catches, what triggering incident put the gate on the list, and why the discipline is dumb on purpose. The alternative is not \"be more careful\" — the alternative is \"ship 12 things, 4 of which are broken.\"\n\nRead this if you are bringing an LLM-based agent into a codebase and want to know why the structural-gate approach beats the heroic-vigilance approach. Each gate is a one-line mechanical check. None requires judgment. All prevent specific failures the system has seen.",),
    8: ("The methodology is at the end of Year 1. This essay walks through what the runtime looks like at Year 2 and Year 5 — catalog size, autonomy boundary, headcount equivalent, customer-account count. The 4-pillar architecture does not change; the skill count compounds.\n\nRead this if you are deciding whether to invest the year of architecture work the methodology asks for. The thesis is that AI-native is structurally different from AI-assisted, and the gap widens. By Year 5 a 10-person company running similar feature surface breaks even at a few-hundred-account customer base; the solo founder running on the runtime hits four-digit account count working 30 hours a week. The hard part is the architecture; once you have it, the compounding takes over.",),
}

def build_navigation(num: int, total: int) -> str:
    parts = []
    if num > 1:
        prev_n = num - 1
        prev = next((c for c in chapters if c["n"] == prev_n), None)
        if prev:
            parts.append(f'<a href="/essays/{prev_n:02d}-{slugify(prev["title"])}.html">← {prev["title"]}</a>')
    parts.append('<a href="/methodology.html">full paper</a>')
    if num < total:
        nxt_n = num + 1
        nxt = next((c for c in chapters if c["n"] == nxt_n), None)
        if nxt:
            parts.append(f'<a href="/essays/{nxt_n:02d}-{slugify(nxt["title"])}.html">{nxt["title"]} →</a>')
    return " &nbsp;·&nbsp; ".join(parts)

template = pathlib.Path(tmpl_p).read_text()
published = []
drafted = []

for ch in chapters:
    intro_text = intros.get(ch["n"], ("This essay covers " + ch["title"] + ".",))[0]
    full_md = f"{intro_text}\n\n{ch['body']}"

    score = voice_score(full_md)
    clean, scrub_detail = scrubber_clean(full_md)

    if score < threshold or not clean:
        # Save draft
        slug = slugify(ch["title"])
        draft_path = pathlib.Path(drafts_d) / f"{ch['n']:02d}-{slug}.md"
        draft_path.write_text(full_md)
        val_path = pathlib.Path(drafts_d) / f"{ch['n']:02d}-{slug}._VALIDATION.md"
        val_path.write_text(
            f"# Validation report — Chapter {ch['n']}: {ch['title']}\n\n"
            f"- voice-gate score: {score}/{threshold}\n"
            f"- scrubber clean: {clean}\n"
            f"- scrubber detail: {scrub_detail}\n"
        )
        drafted.append({"n": ch["n"], "title": ch["title"], "score": score, "clean": clean})
        continue

    # Publish
    body_html = md_to_html(full_md)
    nav = build_navigation(ch["n"], len(chapters))
    desc = (intro_text.split(".", 1)[0] + ".")[:160]
    out_html = (template
        .replace("{TITLE}", html.escape(ch["title"]))
        .replace("{N}", str(ch["n"]))
        .replace("{SCORE}", str(score))
        .replace("{DATE}", today)
        .replace("{DESCRIPTION}", html.escape(desc))
        .replace("{BODY}", body_html)
        .replace("{NAVIGATION}", nav))
    slug = slugify(ch["title"])
    out_path = pathlib.Path(essays_d) / f"{ch['n']:02d}-{slug}.html"
    if not dry:
        out_path.write_text(out_html)
    published.append({"n": ch["n"], "title": ch["title"], "score": score, "path": str(out_path)})

# Build index
if not dry:
    idx_lines = [
        '<!doctype html>', '<html lang="en"><head><meta charset="utf-8">',
        '<title>Methodology essays — Daily AI Agents</title>',
        '<meta name="viewport" content="width=device-width, initial-scale=1">',
        '<style>',
        'body { font: 16px/1.65 Charter, Georgia, serif; max-width: 720px; margin: 0 auto; padding: 48px 24px; color: #1a1a1a; }',
        'h1 { font-size: 28px; margin: 0 0 12px; letter-spacing: -0.01em; }',
        '.meta { color: #888; font-size: 13px; margin-bottom: 28px; }',
        'ol { list-style: none; padding: 0; counter-reset: c; }',
        'li { padding: 10px 0; border-bottom: 1px solid #eee; counter-increment: c; }',
        'li::before { content: counter(c) ". "; color: #888; font-family: ui-monospace, monospace; }',
        'a { color: #2a6; text-decoration: none; } a:hover { text-decoration: underline; }',
        '.footer { margin-top: 36px; padding-top: 16px; border-top: 1px solid #eee; color: #888; font-size: 13px; }',
        '</style></head><body>',
        '<h1>Methodology essays</h1>',
        f'<div class="meta">{len(published)} of {len(chapters)} chapters published as standalone essays. Voice-gate clean. Source: <a href="/methodology.html">full paper</a>.</div>',
        '<ol>',
    ]
    for p in sorted(published, key=lambda x: x["n"]):
        slug = slugify(p["title"])
        idx_lines.append(f'<li><a href="/essays/{p["n"]:02d}-{slug}.html">{html.escape(p["title"])}</a></li>')
    idx_lines += [
        '</ol>',
        '<div class="footer"><a href="/">home</a> &middot; <a href="/methodology.html">full paper</a> &middot; <a href="/receipts.html">receipts</a> &middot; <a href="/cookbook.html">cookbook</a></div>',
        '</body></html>',
    ]
    pathlib.Path(essays_d, "index.html").write_text("\n".join(idx_lines))

if dry:
    print(f"STATUS=ok-dryrun chapters={len(chapters)} would-publish={len(published)} would-draft={len(drafted)}")
else:
    print(f"STATUS=ok chapters={len(chapters)} published={len(published)} drafted={len(drafted)}")
    for p in published:
        print(f"  ✓ {p['n']:02d} {p['title']} ({p['score']}/100) → {p['path']}")
    for d in drafted:
        print(f"  ✗ {d['n']:02d} {d['title']} ({d['score']}/100, clean={d['clean']}) → drafts/")
PY
