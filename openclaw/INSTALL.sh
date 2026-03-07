#!/usr/bin/env bash
#
# INSTALL.sh — Install OpenClaw skills (claude-runner, coding-agent) to ~/.openclaw/skills/
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="${OPENCLAW_SKILLS_DIR:-$HOME/.openclaw/skills}"

echo "=== OpenClaw Skills Installer ==="
echo ""
echo "Source:  $SCRIPT_DIR"
echo "Target:  $SKILLS_DIR"
echo ""

# --- Check dependencies ---

MISSING=""

if ! command -v tmux >/dev/null 2>&1; then
  MISSING="$MISSING tmux"
fi

if ! command -v claude >/dev/null 2>&1; then
  MISSING="$MISSING claude"
fi

if [[ -n "$MISSING" ]]; then
  echo "WARNING: Missing dependencies:$MISSING"
  echo "  - tmux: https://github.com/tmux/tmux (brew install tmux)"
  echo "  - claude: https://docs.anthropic.com/en/docs/claude-code"
  echo ""
  echo "Skills will be installed but won't work until dependencies are available."
  echo ""
fi

# --- Check for existing installations ---

for skill in claude-runner coding-agent; do
  if [[ -d "$SKILLS_DIR/$skill" ]]; then
    echo "NOTE: $skill already exists at $SKILLS_DIR/$skill"
    echo "  Existing files will be overwritten."
  fi
done
echo ""

# --- Install ---

mkdir -p "$SKILLS_DIR"

for skill in claude-runner coding-agent; do
  if [[ ! -d "$SCRIPT_DIR/$skill" ]]; then
    echo "ERROR: Source directory not found: $SCRIPT_DIR/$skill"
    exit 1
  fi

  echo "Installing $skill..."
  cp -r "$SCRIPT_DIR/$skill/" "$SKILLS_DIR/$skill/"
done

# Ensure runner.sh is executable
chmod +x "$SKILLS_DIR/claude-runner/runner.sh"

echo ""
echo "=== Installation Complete ==="
echo ""
echo "Installed skills:"
echo "  - claude-runner  ($SKILLS_DIR/claude-runner/)"
echo "  - coding-agent   ($SKILLS_DIR/coding-agent/)"
echo ""
echo "Next steps:"
echo "  1. Ensure tmux and claude CLI are installed"
echo "  2. For coding-agent: install Speckit (brew install specify-cli)"
echo "  3. For coding-agent: clone Simpsons Loops:"
echo "     git clone https://github.com/jnhuynh/spec-kit-simpsons-loops.git ~/Projects/spec-kit-simpsons-loops"
echo "  4. See openclaw/README.md for usage examples"
