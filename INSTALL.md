# Install — Daily AI Agents OS

Full walkthrough. The one-liner at https://usedailyai.com/install.sh handles steps 1–8 automatically. This doc explains what each step does and how to recover if one fails.

## Prerequisites — 4 things

- macOS 14+ on Apple Silicon (M1 / M2 / M3 — Intel Macs not supported)
- ≥ 16 GB RAM (32+ recommended for Pro and Team workloads)
- ≥ 10 GB free disk for skills + Hermes + OpenClaw runtime
- A `DAI_OS_LICENSE_KEY` from your activation email (or set as an env var)

## Step-by-step (9 steps)

### 1. Verify hardware

```
sysctl -n hw.memsize | awk '{print int($1/1024/1024/1024)" GB"}'
uname -sm
```

Expect ≥ 16 GB and `Darwin arm64`. Anything else and the installer exits.

### 2. Install Hermes

```
curl -sf https://hermes-agent.nousresearch.com/install | bash
hermes --version    # expect 0.11.x or newer
```

### 3. Install OpenClaw

```
curl -sf https://openclaw.ai/install | bash
openclaw --version  # expect 2026.4 or newer
```

### 4. Verify your license

The installer hits `https://usedailyai.com/api/verify-license` with your key, expecting HTTP 200. To verify manually:

```
curl -sf -X POST https://usedailyai.com/api/verify-license \
  -H "Content-Type: application/json" \
  -d '{"license":"YOUR_KEY"}'
```

A valid response returns 200 with body `{"valid":true,"tier":"starter","expires":"..."}`. Invalid or expired keys return 401 and block the install.

### 5. Sync the skill bundle

```
mkdir -p ~/.dailyai-os && cd ~/.dailyai-os
git clone https://github.com/dailyaiagents-cpu/dailyai-os.git . 2>/dev/null || git pull
```

The clone runs once (~2 MB); after that `git pull` keeps the bundle current.

### 6. Point OpenClaw at the bundle

```
ln -sfn ~/.dailyai-os/skills ~/.openclaw/skills/dai-os-bundle
```

OpenClaw discovers `SKILL.md` files under `~/.openclaw/skills/*` automatically. The symlink keeps the bundle in sync without copying 12 directories every release.

### 7. Configure Hermes

Hermes needs a Telegram bot token (free, 2 minutes via `@BotFather`) and a Codex OAuth login.

```
hermes gateway setup
```

Walk through the 5 setup prompts. The gateway stores config at `~/.hermes/config.yaml`.

### 8. Smoke

```
hermes skills list | grep dai-os-bundle
```

Expect 12 skill names from this bundle. If 0 show, restart Hermes (step 9).

### 9. Start the runtime

```
hermes gateway start
```

Send a Telegram message to your bot. You should get a reply within 5 seconds.

## Recovery — 4 common failure modes

### 1. License verification fails

Confirm your activation email and copy the `DAI_OS_LICENSE_KEY` exactly — no surrounding whitespace, all 32 chars. Check status of `https://usedailyai.com/api/verify-license`; if down, email support@dailyaiagents.com.

### 2. Hermes or OpenClaw install fails

Both upstream projects ship their own install docs. Re-run their installers directly. Confirm Xcode Command Line Tools with `xcode-select --install` first — that fixes most install failures.

### 3. Skills don't appear (after step 8)

Verify the symlink with `ls -la ~/.openclaw/skills/dai-os-bundle`. Restart Hermes via `hermes gateway stop && hermes gateway start`. Confirm with `hermes skills list | wc -l` — expect 12+ rows.

### 4. Anything else

Discord (invite in your activation email) is the fastest support channel — typical reply within 2 hours during US business hours.

## Per-skill setup — 4 skills need env vars

Most of the 12 skills work out of the box. These 4 need configuration:

| Skill | Required env vars |
|---|---|
| `outreach-paced` | `REDDIT_USERNAME`, `REDDIT_PASSWORD`, `REDDIT_CLIENT_ID`, `REDDIT_CLIENT_SECRET` |
| `model-warmth-keeper` | `OLLAMA_HOST` (default `http://127.0.0.1:11434`) |
| `voice-gate` | Path to your `VOICE.md` (default `${REPO_ROOT}/VOICE.md`) |

Each skill's own `INSTALL.md` lists its 1-4 dependencies plus a single smoke command you copy-paste.
