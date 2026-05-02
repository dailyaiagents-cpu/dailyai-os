#!/usr/bin/env bash
# session-keeper/run.sh — daily 09:00 CT browser-session audit.
# Probes 3 default targets via Chrome CDP at 9223. Writes state file +
# opens approval gates for expired sessions. Telegram-summary.
# Pure read + curl + write — no LLM in loop.
#
# SESSION_KEEPER_DRYRUN=1 → scan only, no gate creation, no Telegram.
set +e
DRYRUN="${SESSION_KEEPER_DRYRUN:-0}"
REPO=${REPO_ROOT}
HOME_DIR=${HOME}
TARGETS=$HOME_DIR/.openclaw/state/session-keeper/targets.json
TODAY=$(date -u +%Y-%m-%d)
OUT_FILE=$HOME_DIR/.openclaw/state/session-keeper/$TODAY.json
mkdir -p "$(dirname "$OUT_FILE")"

[ -e "$TARGETS" ] || { echo "STATUS=error reason=targets-file-missing path=$TARGETS"; exit 1; }

# Single python invocation does the full probe across targets.
# CDP flow: POST /json/new?<url> → creates new tab → wait 3s for redirects →
# GET /json → find the tab by its WebSocket id or by URL match → read final URL →
# match against logged_in_marker / logged_out_marker → close the tab.
python3 - "$TARGETS" "$OUT_FILE" "$DRYRUN" "$REPO" <<'PY'
import json, sys, time, re, urllib.request, urllib.parse, urllib.error, datetime, subprocess, pathlib

TARGETS_PATH, OUT_FILE, DRYRUN, REPO = sys.argv[1], sys.argv[2], sys.argv[3] == "1", sys.argv[4]
NOW = datetime.datetime.now(datetime.timezone.utc).isoformat()

def cdp_get(port, path):
    try:
        return json.load(urllib.request.urlopen(f"http://127.0.0.1:{port}{path}", timeout=3))
    except Exception as e:
        return {"_error": str(e)}

def cdp_text(port, path):
    try:
        return urllib.request.urlopen(f"http://127.0.0.1:{port}{path}", timeout=3).read().decode()
    except Exception as e:
        return f"_error: {e}"

def open_tab(port, url):
    enc = urllib.parse.quote(url, safe="")
    try:
        # PUT /json/new?url is the canonical CDP REST endpoint to spawn a tab
        req = urllib.request.Request(f"http://127.0.0.1:{port}/json/new?{enc}", method="PUT")
        return json.load(urllib.request.urlopen(req, timeout=3))
    except Exception as e:
        return {"_error": str(e)}

def close_tab(port, tid):
    try:
        urllib.request.urlopen(f"http://127.0.0.1:{port}/json/close/{tid}", timeout=3).read()
    except Exception:
        pass

targets = json.load(open(TARGETS_PATH))
results = {"audited_at": NOW, "targets": {}}

for name, cfg in targets.items():
    port = cfg["cdp_port"]
    initial_url = cfg["url"]
    spawn = open_tab(port, initial_url)
    if "_error" in spawn or "id" not in spawn:
        results["targets"][name] = {
            "status": "unknown",
            "reason": f"cdp-spawn-failed: {spawn.get('_error','no-id')}",
            "audited_at": NOW,
        }
        continue
    tid = spawn["id"]
    time.sleep(3)  # let redirects settle
    listing = cdp_get(port, "/json")
    final_url = None
    if isinstance(listing, list):
        for t in listing:
            if t.get("id") == tid:
                final_url = t.get("url", "")
                break
    close_tab(port, tid)

    if not final_url:
        results["targets"][name] = {"status": "unknown", "reason": "tab-not-listable-after-spawn", "audited_at": NOW}
        continue

    # Detect status by URL-redirect markers (more robust than DOM).
    logged_out_pat = cfg.get("logged_out_marker", {}).get("value", "")
    logged_in_pat = cfg.get("logged_in_marker", {}).get("value", "")
    status = "unknown"
    if logged_out_pat and re.search(logged_out_pat, final_url):
        status = "expired"
    elif logged_in_pat and re.search(logged_in_pat, final_url):
        status = "live"
    results["targets"][name] = {
        "status": status,
        "final_url": final_url,
        "initial_url": initial_url,
        "audited_at": NOW,
    }

# Persist
pathlib.Path(OUT_FILE).write_text(json.dumps(results, indent=2))

# Summary
live = [n for n, r in results["targets"].items() if r["status"] == "live"]
expired = [n for n, r in results["targets"].items() if r["status"] == "expired"]
unknown = [n for n, r in results["targets"].items() if r["status"] == "unknown"]
print(f"STATUS=ok live={len(live)} expired={len(expired)} unknown={len(unknown)}")
print(f"  live: {live}")
print(f"  expired: {expired}")
print(f"  unknown: {unknown}")

if DRYRUN:
    print("DRYRUN — skipping gate creation + Telegram")
    sys.exit(0)

# Open approval gate per expired target
gate_ids = []
for name in expired:
    cfg = targets[name]
    login_url = cfg.get("login_url", initial_url)
    spawn_cmd = f"curl -s -X PUT 'http://127.0.0.1:9223/json/new?{urllib.parse.quote(login_url, safe='')}' >/dev/null"
    try:
        r = subprocess.run([
            "python3", f"{REPO}/tools/approvals/resolve_gate.py", "--create",
            "--agent", "ops",
            "--action", f"LOGIN_{name.upper()}",
            "--reason", f"Session-keeper detected {name} expired (final_url={results['targets'][name]['final_url'][:80]}). Cooper: tap to spawn login tab on agent-chrome.",
            "--evidence", f"Run: {spawn_cmd}\nThen sign in to {login_url} in the new Chrome tab.",
            "--reversibility", "easy",
            "--timeout-min", "1440",
        ], capture_output=True, text=True, timeout=15)
        if r.returncode == 0:
            try:
                resp = json.loads(r.stdout)
                gate_ids.append(resp.get("gate_id", "?"))
            except Exception:
                gate_ids.append("created")
    except Exception as e:
        print(f"gate creation failed for {name}: {e}")

# Telegram summary (skip if zero expired AND zero unknown — silence is valid)
if expired or unknown:
    msg_lines = [f"🔑 Session audit ({NOW[:10]}): {len(live)} live, {len(expired)} expired, {len(unknown)} unknown"]
    for n in expired:
        msg_lines.append(f"  EXPIRED {n} — see gate {gate_ids[expired.index(n)] if expired.index(n) < len(gate_ids) else '?'}")
    for n in unknown:
        msg_lines.append(f"  UNKNOWN {n} — {results['targets'][n].get('reason','no-detail')}")
    msg = "\n".join(msg_lines)
    try:
        subprocess.run([
            "python3", f"{REPO}/tools/notify/telegram_send.py", "--text", msg,
        ], timeout=10)
    except Exception:
        pass
PY
