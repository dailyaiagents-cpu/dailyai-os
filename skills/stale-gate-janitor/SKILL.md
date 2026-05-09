---
name: stale-gate-janitor
description: Daily 04:00 CT housekeeping over data/approval-gates/. Expires pending past expires_at, archives gates >7 days old. Telegram only on change.
scheduled: cron 0 4 * * * America/Chicago via openclaw cron (agent=ops)
---

# stale-gate-janitor

## Why this exists

Active approval-gates dir accumulates resolved + expired entries that audit reads (hermes-daily-audit) keep tripping on. Today's session (2026-04-29) caught 3 stale Apr-28 gates Cooper had to mentally filter every morning. This skill removes that toll.

## Inputs

```json
{
  "dry_run": false,
  "test_telegram_chat_id": null
}
```

`dry_run=true` walks + classifies but doesn't write or Telegram.

`test_telegram_chat_id` (env var `TELEGRAM_TEST_CHAT_ID`) — if set, sends summary to that chat instead of Cooper's. Used by self-test to avoid pinging Cooper during ops verification.

## Procedure

### Step 1 — Walk + classify

```python
import json, datetime, pathlib, shutil, os, subprocess
home = pathlib.Path.home()
repo = home / "Dev/daily-ai-agent-os"
gates_dir = repo / "data/approval-gates"
archive_root = gates_dir / "archive"
now = datetime.datetime.now(datetime.timezone.utc)

if not gates_dir.exists():
    print("[stale-gate-janitor] no approval-gates dir; nothing to do")
    raise SystemExit(0)

ARCHIVE_AGE_S = 7 * 86400

expired_now = []
archived = []
errors = []

# Pass 1 — expire stale-pending gates
for p in gates_dir.glob("*.json"):
    if p.parent != gates_dir:  # skip archive subdir
        continue
    try:
        g = json.loads(p.read_text())
    except Exception as e:
        errors.append({"file": str(p), "err": f"parse: {e}"})
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

# Pass 2 — archive >7d files
for p in list(gates_dir.glob("*.json")):
    if p.parent != gates_dir:
        continue
    age_s = now.timestamp() - p.stat().st_mtime
    if age_s <= ARCHIVE_AGE_S:
        continue
    try:
        g = json.loads(p.read_text())
        ts = g.get("created_at") or g.get("expires_at") or now.isoformat()
        ym = ts[:7]  # YYYY-MM
    except Exception:
        ym = now.strftime("%Y-%m")
    bucket = archive_root / ym
    bucket.mkdir(parents=True, exist_ok=True)
    target = bucket / p.name
    shutil.move(str(p), str(target))
    archived.append(p.stem)

print(f"[stale-gate-janitor] expired={len(expired_now)} archived={len(archived)} errors={len(errors)}")
```

### Step 2 — Telegram summary (only on change)

```python
if (expired_now or archived) and not dry_run:
    chat_id = os.environ.get("TELEGRAM_TEST_CHAT_ID")  # for self-test
    msg = f"[gate-janitor] expired: {len(expired_now)}, archived: {len(archived)}"
    if errors:
        msg += f", parse-errors: {len(errors)}"
    args = ["python3.11", str(repo / "tools/notify/telegram_send.py"), "--text", msg]
    if chat_id:
        args.extend(["--chat-id", chat_id])
    subprocess.run(args, timeout=10, check=False)
    print(f"[stale-gate-janitor] telegram sent: {msg}")
elif not (expired_now or archived):
    print(f"[stale-gate-janitor] no changes — silent")
```

### Step 3 — Vault Activity log (always, for audit trail)

```python
date_str = now.strftime("%Y-%m-%d")
vault_path = home / f"Dev/daily-ai-agents-vault/Activity/gate-janitor-{date_str}.md"
vault_path.parent.mkdir(parents=True, exist_ok=True)
with open(vault_path, "a") as f:
    f.write(f"\n## {now.isoformat()}\n")
    f.write(f"- expired: {len(expired_now)} ({expired_now[:5]}{'...' if len(expired_now)>5 else ''})\n")
    f.write(f"- archived: {len(archived)} ({archived[:5]}{'...' if len(archived)>5 else ''})\n")
    if errors:
        f.write(f"- errors: {len(errors)} (see /tmp/stale-gate-janitor-errors.json)\n")
        pathlib.Path("/tmp/stale-gate-janitor-errors.json").write_text(json.dumps(errors, indent=2))
```

## Self-test

`skills/stale-gate-janitor/test.sh`:
1. Drop a fake gate at `/tmp/test-stale-gate.json` with `expires_at` in the past, `status="pending"`.
2. Symlink it into `data/approval-gates/__test_stale_gate.json` (or use a writable copy).
3. Run the skill's expire-pass logic.
4. Verify `status` flipped to `"expired"` and `expired_by="stale-gate-janitor"`.
5. Clean up.

## Composition

- Reads + writes: `data/approval-gates/*.json`, archive subdir.
- Writes: `~/Dev/daily-ai-agents-vault/Activity/gate-janitor-<date>.md`.
- Calls: `tools/notify/telegram_send.py` only on change.

## Hard rules

1. NEVER re-resolves a gate whose status is already approved/denied/expired.
2. Pending → expired ONLY when `expires_at < now`.
3. Archive ONLY by file mtime > 7 days, regardless of status.
4. Telegram silent on no-op.
5. Idempotent across invocations.
