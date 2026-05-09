# voice-scrubber

Pre-publish scanner. Block text containing fabricated metrics, LLM-default hype phrases, or prompt-injection markers.

## Install

```bash
cp -r voice-scrubber/ /your/agents/lib/
```

## Use

```bash
bash voice-scrubber.sh --file draft-newsletter.md
bash voice-scrubber.sh --text "We're revolutionizing the unlock-value space."
```

Exit 0 = clean, exit 1 = blocked.

## Customize

Edit `banlist.txt`. One phrase per line, case-insensitive substring match. Add your team's voice exceptions.

## License

MIT.
