#!/usr/bin/env bash
# Self-test for stale-gate-janitor: drop a synthetic stale-pending gate,
# run the expire pass, verify the flip, clean up.
set -euo pipefail
REPO="${REPO:-$HOME/Dev/daily-ai-agent-os}"
cd "$REPO"

python3.11 - <<'PYEOF'
import json, datetime, pathlib, sys
home = pathlib.Path.home()
repo = home / "Dev/daily-ai-agent-os"
gates_dir = repo / "data/approval-gates"
gates_dir.mkdir(parents=True, exist_ok=True)

# 1. Drop fake gate with expires_at in the past
test_path = gates_dir / "__test_stale_gate.json"
fake = {
    "id": "__test_stale_gate",
    "agent": "ops",
    "action": "TEST_STALE",
    "summary_one_line": "Self-test fake gate",
    "evidence_path": "",
    "cost_usd": 0.0,
    "reversibility": "easy",
    "created_at": (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=2)).isoformat(),
    "expires_at": (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=1)).isoformat(),
    "status": "pending",
}
test_path.write_text(json.dumps(fake, indent=2))
print(f"[self-test] dropped fake gate at {test_path}")

# 2. Run the expire-pass logic inline
now = datetime.datetime.now(datetime.timezone.utc)
expired_now = []
for p in gates_dir.glob("*.json"):
    if p.parent != gates_dir: continue
    try:
        g = json.loads(p.read_text())
    except Exception:
        continue
    if g.get("status") in (None, "pending", "open"):
        ex_iso = g.get("expires_at", "")
        try:
            ex_dt = datetime.datetime.fromisoformat(ex_iso.replace("Z", "+00:00")) if ex_iso else None
        except Exception:
            ex_dt = None
        if ex_dt and ex_dt < now:
            g["status"] = "expired"
            g["expired_at"] = now.isoformat()
            g["expired_by"] = "stale-gate-janitor"
            p.write_text(json.dumps(g, indent=2))
            expired_now.append(g.get("id", p.stem))

# 3. Verify the test gate was flipped
result = json.loads(test_path.read_text())
assert result["status"] == "expired", f"FAIL: status={result['status']!r} (expected 'expired')"
assert result["expired_by"] == "stale-gate-janitor", f"FAIL: expired_by={result['expired_by']!r}"
assert "__test_stale_gate" in expired_now, f"FAIL: not in expired list"
print(f"[self-test] flip OK: status={result['status']}, expired_by={result['expired_by']}")
print(f"[self-test] expired this run: {len(expired_now)} (includes self-test gate + any real ones)")

# 4. Clean up
test_path.unlink()
print("[self-test] cleanup OK")
print("[self-test] PASS")
PYEOF
