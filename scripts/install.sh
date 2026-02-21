#!/bin/bash
# Install the transcribe skill for Claude Code
set -euo pipefail

SKILL_DIR="$HOME/.claude/skills/transcribe"
BIN_DIR="$HOME/.claude/bin"

echo "Installing transcribe skill..."

# Copy skill directory
mkdir -p "$SKILL_DIR"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cp "$SCRIPT_DIR/SKILL.md" "$SKILL_DIR/"

# Install the CLI wrapper
mkdir -p "$BIN_DIR"
cp "$SCRIPT_DIR/scripts/transcribe.sh" "$BIN_DIR/transcribe"
chmod +x "$BIN_DIR/transcribe"

echo ""
echo "Installed:"
echo "  Skill:  $SKILL_DIR/SKILL.md"
echo "  CLI:    $BIN_DIR/transcribe"
echo ""
echo "Next: open Claude Code and run"
echo "  /transcribe setup"
echo ""
echo "This builds the Swift transcription engine (~5 min, one-time)."
