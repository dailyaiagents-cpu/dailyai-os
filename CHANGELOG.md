# Changelog

All notable changes to the Daily AI Agents OS skill bundle.

## [1.0.0] — 2026-05-01

Initial release. 10 skills shipped.

- `session-keeper` — daily browser-session audit
- `delegation-orchestrator` — fault-tree help routing
- `hermes-inbox-router` — multi-channel inbound aggregation
- `outreach-paced` — Reddit/forum outreach pacing with anti-self-promo gate
- `model-warmth-keeper` — local LLM auto-recovery
- `launchd-drift-recovery` — daily launchd plist health audit
- `ship-log-draft` — Friday 7-day aggregation
- `skill-registry-sync` — auto-wire `owner_agent`
- `voice-gate` — public-output quality scoring
- `public-content-scrubber` — financial-leak hard gate

Bundle format:

- `skills/<name>/SKILL.md` — frontmatter + description
- `skills/<name>/run.sh` — executable bash, idempotent
- Top-level `LICENSE` (MIT), `README.md`, `INSTALL.md`, `CHANGELOG.md`
- CI workflow at `.github/workflows/test.yml` validates skill structure

## How upgrades work

- New skill: gets a row in this changelog, lands in `skills/<name>/`
- Skill rename: deprecation note here, old name kept as a symlink for one minor version
- Breaking change to a skill's contract (env vars, output format): bumps the minor version, called out here
