---
name: founder-letter-audio
owner_agent: content
owns: ElevenLabs TTS rendering of edited founder letters. Voice-gate + scrubber HARD before any cloud call. Free-tier quota tracking in data/voice/elevenlabs_usage.json.
---

# founder-letter-audio

The audio counterpart to the cont-6 `founder-letter-publish` skill. Takes an edited founder-letter Markdown file, validates it through both quality gates, strips Markdown formatting, sends to ElevenLabs TTS, saves the resulting MP3 to `site/audio/`, and prepends a "🎧 Listen" link to the source Markdown.

## Why audio matters here

A founder letter is the most personal public artifact the company ships. Reading it aloud increases trust (the founder's voice carries texture that prose can't), accessibility (commute, kitchen, gym audiences), and reach (podcast app discovery without us running a podcast). For monthly cadence + ~800 char letters, the cost is trivial — well within free tier for 12 letters/year.

## Pipeline

1. **Input validation.** Refuse to render audio if the source still contains `_(Cooper writes ...)_` placeholders (cont-6 sentinel pattern).
2. **Voice-gate HARD.** Score must be ≥ 70 (the standard for public surfaces). Audio is permanent on the customer's device — it CANNOT be retroactively pulled.
3. **Public-content scrubber HARD.** No financial figures, no customer counts, no kalshi-profile URLs, no MRR mentions in the spoken audio. Scrubber failure = block.
4. **Markdown strip.** Headers, links, bold, code, horizontal rules, blockquotes, and HTML tags removed. Output is clean prose.
5. **ElevenLabs TTS.** POST to `https://api.elevenlabs.io/v1/text-to-speech/<voice_id>` with model `eleven_multilingual_v2`. Voice ID pinned to **Sarah** (`EXAVITQu4vr4xnSDxMaL`) — see Voice picker below for the rationale and the swap procedure.
6. **Quota tracking.** Each call appends `{date, chars, voice_id}` to `data/voice/elevenlabs_usage.json`. The skill refuses new generations when cumulative chars in the current month exceed `MONTHLY_CHAR_LIMIT` (default 9500, leaving 500-char headroom under the 10,000 free-tier monthly cap). Failure mode: `STATUS=error reason=quota-exhausted`.
7. **Output.** MP3 saved to `site/audio/founder-letter-<YYYY-MM>.mp3`. Listen link prepended to the source Markdown after the H1 line.

## Voice picker

Default: **Sarah** (`EXAVITQu4vr4xnSDxMaL`) — "Mature, Reassuring, Confident" per ElevenLabs's own description. Female, en_US, neutral pace, fits the "operator's letter" register.

Swap candidates from the available premade voice library:

| Voice ID | Name | Description (per ElevenLabs) |
|---|---|---|
| `EXAVITQu4vr4xnSDxMaL` | Sarah | Mature, Reassuring, Confident *(current default)* |
| `JBFqnCBsd6RMkjVDRZzb` | George | Warm, Captivating Storyteller |
| `cjVigY5qzO86Huf0OWal` | Eric | Smooth, Trustworthy |
| `nPczCjzI2devNBz1zQrb` | Brian | Deep, Resonant and Comforting |
| `iP95p4xoKVk53GoZ742B` | Chris | Charming, Down-to-Earth |
| `XrExE9yKIg1WjnnlVkGX` | Matilda | Knowledgable, Professional |

To swap: edit `~/.openclaw/skills/founder-letter-audio/run.sh` and change the `DEFAULT_VOICE_ID` value. Re-render the next letter. Cooper picks via ear (sample each candidate on https://elevenlabs.io/voice-lab) — there's no objectively right voice, only the one that matches the brand register.

The Rachel voice (`21m00Tcm4TlvDq8ikWAM`) Cooper named in the cont-11 prompt is not available in this account's voice library — only the listed premade voices respond to TTS calls under the current API key.

## Quota tracking

`data/voice/elevenlabs_usage.json` shape:

```json
{
  "month": "2026-05",
  "chars_this_month": 1247,
  "monthly_limit": 9500,
  "renders": [
    {"date": "2026-05-01", "voice_id": "EXAVITQu4vr4xnSDxMaL", "chars": 1247, "letter": "data/founder-letters/2026-05-draft.md"}
  ]
}
```

The free tier resets at the start of each calendar month. The skill auto-rolls the month + zeroes the counter when the current date crosses into a new month.

## Failure modes (P9 — fail loud)

- `ELEVENLABS_API_KEY` missing → `STATUS=error reason=elevenlabs-key-missing`. The Hermes plist already has it (cont-5).
- ElevenLabs API returns 4xx → `STATUS=error reason=elevenlabs-http-NNN`.
- ElevenLabs API returns 5xx → `STATUS=error reason=elevenlabs-http-NNN` (treat as transient; Cooper retries manually).
- Quota exhausted → `STATUS=error reason=quota-exhausted chars_used=N limit=M`. Cooper top-ups paid tier to continue.
- Voice-gate < 70 → `STATUS=blocked reason=voice-gate-failed score=N`.
- Scrubber non-clean → `STATUS=blocked reason=scrubber-failed inspect=...`.
- Cooper's placeholders present → `STATUS=blocked reason=letter-has-placeholders`.

## Status codes

- `STATUS=ok mp3=site/audio/founder-letter-2026-05.mp3 chars=812 quota_remaining=8688`
- `STATUS=blocked reason=voice-gate-failed|scrubber-failed|letter-has-placeholders ...`
- `STATUS=error reason=elevenlabs-http-NNN|quota-exhausted|...`
