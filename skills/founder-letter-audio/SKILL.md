---
name: founder-letter-audio
owner_agent: content
description: Renders a Cooper-edited founder letter to MP3 via ElevenLabs TTS. Voice-gate + scrubber HARD before any cloud call. Pinned voice Sarah (EXAVITQu4vr4xnSDxMaL), model eleven_multilingual_v2. Tracks usage against the 10K-char free-tier monthly cap.
trigger: manual, after `founder-letter-publish` ships the letter to site/letters/
---

# founder-letter-audio

Audio counterpart to founder-letter-publish. See SOUL.md for the voice picker and quota tracking shape.

## Manual run

```bash
bash ~/.openclaw/skills/founder-letter-audio/run.sh data/founder-letters/2026-05-draft.md
```

## Required env

- `ELEVENLABS_API_KEY` set in `~/Library/LaunchAgents/ai.hermes.gateway.plist` (since cont-5)

## Outputs

- `site/audio/founder-letter-<YYYY-MM>.mp3` — TTS-rendered audio (typical 800-char letter ≈ 60-90 sec, 600-900 KB)
- Source `<letter>.md` gets a `🎧 Listen: /audio/founder-letter-<YYYY-MM>.mp3` line prepended after the H1
- `data/voice/elevenlabs_usage.json` updated with the month's cumulative chars

## Status codes

`STATUS=ok mp3=... chars=N quota_remaining=N` / `STATUS=blocked reason=...` / `STATUS=error reason=...`
