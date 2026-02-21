# Transcribe Skill

This repo is a Claude Code skill for local audio transcription.

## Structure

```
transcribe/
├── SKILL.md                # Skill definition (loaded by Claude Code)
├── CLAUDE.md               # This file
├── README.md               # User-facing docs
└── scripts/
    ├── install.sh          # Copies SKILL.md + CLI to ~/.claude/
    └── transcribe.sh       # CLI wrapper (setup, transcribe, model management)
```

## How it works

1. `install.sh` copies `SKILL.md` to `~/.claude/skills/transcribe/` and `transcribe.sh` to `~/.claude/bin/transcribe`
2. `transcribe setup` generates inline Swift source using FluidAudio as a dependency, builds two binaries (`parakeet-transcribe` and `parakeet-modelctl`), and downloads the default model
3. Transcription runs via CoreML on Apple Neural Engine — no network needed after setup

## Key paths after install

| What | Where |
|------|-------|
| Skill definition | `~/.claude/skills/transcribe/SKILL.md` |
| CLI wrapper | `~/.claude/bin/transcribe` |
| Built binaries | `~/.claude/bin/parakeet/` |
| Swift build cache | `~/.claude/cache/parakeet-build/` |
| Models | `~/Library/Application Support/FluidAudio/Models/` |

## Conventions

- The CLI emits NDJSON events to stdout during batch transcription for progress tracking
- Single-file mode prints plain text to stdout (no JSON wrapper)
- All user-facing messages go to stderr via `info()`
- The `--model` flag accepts `v2` or `v3`
