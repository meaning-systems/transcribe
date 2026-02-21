---
name: transcribe
description: Transcribe audio files to text using Parakeet v3 CoreML (local, fast, 25 European languages). Use when the user has audio files they want transcribed, wants to extract text from podcasts or interviews, or asks to "transcribe" or "convert audio to text".
disable-model-invocation: true
allowed-tools: Bash
argument-hint: "[audio-file-or-directory]"
metadata:
  author: neno
  version: "1.0"
license: MIT
compatibility: macOS 14+ with Apple Silicon. Requires Xcode Command Line Tools for first-time build.
---

# Transcribe Audio

Local speech-to-text using NVIDIA Parakeet TDT 0.6B via CoreML on Apple Silicon.
Powered by [FluidAudio](https://github.com/FluidInference/FluidAudio). Same engine as VoiceInk.app.

## First-time setup

If transcription fails with "Not installed", run:
```bash
~/.claude/bin/transcribe setup
```
This builds the Swift tools from FluidAudio and downloads the default model (~5 min).

## Instructions

### Single file (print to conversation)
```bash
~/.claude/bin/transcribe "$ARGUMENTS"
```

### Single file (save to disk)
```bash
~/.claude/bin/transcribe "$ARGUMENTS" "<output-dir>"
```
Saves `.txt` and `.json` (with timestamps + confidence) to output directory.

### Directory (bulk)
```bash
~/.claude/bin/transcribe "$ARGUMENTS"
```
Transcribes all audio files, saves `.txt` + `.json` alongside originals.

### Model selection
```bash
~/.claude/bin/transcribe --model v2 "$ARGUMENTS"
```

### Model management
```bash
~/.claude/bin/transcribe models
~/.claude/bin/transcribe install v3
~/.claude/bin/transcribe install v2
```

## Models

| Version | Languages | Notes |
|---------|-----------|-------|
| **v3** (default) | 25 European | Best quality, recommended |
| v2 | English-focused | Smaller, faster |

## Supported Formats

wav, mp3, m4a, aac, flac, ogg, opus, aiff, caf, mp4, mov, webm

## Requirements

- macOS 14+ (Apple Silicon recommended, Intel works slower)
- Xcode Command Line Tools (for first-time build)
- ~500MB disk (model + binaries)

## Examples

```
/transcribe recording.mp3
/transcribe ~/Desktop/interviews/
/transcribe podcast.m4a ./transcripts/
/transcribe --model v2 english-only.wav
```
