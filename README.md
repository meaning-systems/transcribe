# transcribe

Local audio transcription for [Claude Code](https://claude.ai/code) using NVIDIA Parakeet TDT 0.6B via CoreML on Apple Silicon.

Same engine as [VoiceInk.app](https://voiceink.app). Powered by [FluidAudio](https://github.com/FluidInference/FluidAudio).

- 25 European languages
- ~0.3x real-time (60s audio transcribes in ~18s)
- Runs entirely on-device via Apple Neural Engine
- No API keys, no internet needed after setup

## Install

```bash
git clone https://github.com/meaning-systems/transcribe ~/.claude/skills/transcribe
bash ~/.claude/skills/transcribe/scripts/install.sh
```

Then in Claude Code, run the one-time setup (~5 min):

```
/transcribe setup
```

This builds two Swift binaries from FluidAudio and downloads the Parakeet v3 model from HuggingFace.

## Usage

### Single file

Print transcript to the conversation:

```
/transcribe recording.mp3
```

Save transcript to disk (creates `.txt` and `.json` with timestamps):

```
/transcribe interview.m4a ./transcripts/
```

### Batch (entire directory)

Transcribe all audio files in a directory — outputs `.txt` + `.json` alongside each original:

```
/transcribe ~/Desktop/interviews/
```

Save all transcripts to a separate output directory:

```
/transcribe ~/Desktop/interviews/ ./output/
```

### Model selection

Use v2 (English-focused, smaller/faster) instead of v3 (default, 25 languages):

```
/transcribe --model v2 english-podcast.wav
```

### Model management

```
/transcribe models              # list installed models
/transcribe install v2           # download v2
/transcribe install v3           # download v3
```

## Supported formats

wav, mp3, m4a, aac, flac, ogg, opus, aiff, caf, mp4, mov, webm

## Requirements

- macOS 14+
- Apple Silicon (recommended) or Intel
- Xcode Command Line Tools (`xcode-select --install`)
- ~500MB disk (model + binaries)

## Models

| Version | Languages | Size | Notes |
|---------|-----------|------|-------|
| **v3** (default) | 25 European | ~400MB | Best quality |
| v2 | English-focused | ~200MB | Faster, smaller |

## License

MIT
