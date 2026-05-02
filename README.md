# Daily AI Agents OS

> Autonomous AI company runtime for solo founders.
> Built in public, run privately, documented openly.

This repo ships the 10-skill public bundle for the Starter tier of Daily AI Agents OS — a runtime that turns one Mac into an autonomous AI company you operate by Telegram.

The brain is `Hermes`. The arms are `OpenClaw` specialists. This bundle is the first layer of skills they execute, written in bash + jq + curl, all readable in 60 seconds per skill.

## Install

```
curl -sf https://usedailyai.com/install.sh | bash
```

The installer runs 9 checks: `Darwin arm64`, ≥ 16 GB RAM, Hermes present, OpenClaw present, license valid, bundle synced, symlinked into `~/.openclaw/skills/dai-os-bundle`, smoke-test, and gateway-ready prompt. A license key is required — set `DAI_OS_LICENSE_KEY` in your env, or paste it when prompted.

## What's in the bundle (10 skills)

| Skill | What it does |
|---|---|
| `session-keeper` | Daily browser-session audit at 09:00 — keeps long-lived logins alive on a schedule. |
| `delegation-orchestrator` | Cross-agent fault-tree help routing with a 60-second daemon tick. |
| `hermes-inbox-router` | Multi-channel inbound aggregation across Telegram, email, Slack. |
| `outreach-paced` | Reddit and forum outreach pacing with the anti-self-promo gate at Step 3.5. |
| `model-warmth-keeper` | Local LLM auto-recovery on Ollama (`http://127.0.0.1:11434`) and LM Studio. |
| `launchd-drift-recovery` | Daily macOS launchd plist health audit at 06:00. |
| `ship-log-draft` | Friday 17:00 CT 7-day aggregation of git, postmortems, auto-skills, ops notes. |
| `skill-registry-sync` | Auto-wire `owner_agent` for every new SKILL.md the runtime discovers. |
| `voice-gate` | Public-output quality scoring against a `VOICE.md` reference. |
| `public-content-scrubber` | Hard gate against financial-data leaks in any public-bound text. |

Each skill is a directory with `SKILL.md` (frontmatter + description), `run.sh` (executable bash), `INSTALL.md` (env vars + smoke), and `EXAMPLES.md` (1-2 sanitized real outputs).

## Tiers

| Tier | Price | What's included |
|---|---|---|
| Starter | $99/mo | 1 user, this 10-skill bundle, Discord access |
| Team | $499/mo | Unlimited users, full 200+ skill library, monthly office hours with Cooper |

Buy at https://usedailyai.com/os.

## What you bring

This OS runs on your hardware. Bring:

- A Mac with macOS 14+ on Apple Silicon (M1, M2, or M3) and ≥ 16 GB RAM
- A free Telegram bot token from `@BotFather` (2 minutes)
- A ChatGPT Plus or Pro subscription — Hermes routes through Codex OAuth
- Optional: a Stripe account for the e-commerce skills
- Optional: a GitHub PAT for the dev-loop skills

## What this is, what this isn't

It is: 12 working skills, an install script, a runtime contract, and a CI workflow that validates every skill on every push. Honest, opinionated, evolving.

It isn't: a hosted SaaS. It isn't a guarantee that any particular skill produces a measurable business outcome on your stack. It isn't a replacement for understanding what your agents are doing — every skill is auditable bash, every output passes through `voice-gate` and `public-content-scrubber` you can read.

If a skill produces output that looks wrong, the source is in `skills/<name>/run.sh` and you can fix it yourself. That's the deal at the Starter tier.

## Honest disclaimers

- Outputs are not guaranteed. Skills produce drafts; you decide what ships.
- Costs are yours to manage. Local model inference is free; cloud LLM calls and Stripe transaction fees are not.
- Compatibility is best-effort. Hermes 0.11.x and OpenClaw 2026.4+ are independent projects with their own release cadences. We pin known-good versions; major upstream changes may briefly break.

## Updates and support

- Newest skills land here weekly. Watch the `CHANGELOG.md` for the running list.
- Discord (invite arrives in your activation email) is the primary support channel.
- Bug reports: GitHub issues are read; reply volume varies.
- Pro and Team tiers get email + priority Discord.

## License

MIT. Use the bundle as you want. Attribution appreciated, not required.

---

_Daily AI Agents · An autonomous AI-native solo founder operating system._
