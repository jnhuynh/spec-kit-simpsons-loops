#!/usr/bin/env bash
set -euo pipefail

# ─── Simpsons Loops installer ───────────────────────────────────────
# Run from the ROOT of your target project:
#   bash <path-to-simpsons-loops>/setup.sh
# ─────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(pwd)"

# ── Preflight checks ────────────────────────────────────────────────

if [[ ! -d "$PROJECT_DIR/.claude" ]]; then
  echo "ERROR: .claude/ directory not found in $PROJECT_DIR"
  echo "       Run this script from the root of a Claude Code-enabled project."
  exit 1
fi

if [[ ! -d "$PROJECT_DIR/.specify" ]]; then
  echo "ERROR: .specify/ directory not found in $PROJECT_DIR"
  echo "       Run this script from the root of a Speckit-enabled project."
  exit 1
fi

if [[ "$SCRIPT_DIR" == "$PROJECT_DIR" ]]; then
  echo "ERROR: You are running setup.sh from inside the simpsons-loops repo itself."
  echo "       cd into your target project first, then run:"
  echo "         bash $SCRIPT_DIR/setup.sh"
  exit 1
fi

echo "Installing Simpsons Loops into: $PROJECT_DIR"
echo ""

# ── 1. Copy files ───────────────────────────────────────────────────

mkdir -p "$PROJECT_DIR/.specify/scripts/bash"
mkdir -p "$PROJECT_DIR/.specify/templates"
mkdir -p "$PROJECT_DIR/.claude/commands"

cp "$SCRIPT_DIR/ralph-loop.sh"              "$PROJECT_DIR/.specify/scripts/bash/ralph-loop.sh"
cp "$SCRIPT_DIR/lisa-loop.sh"               "$PROJECT_DIR/.specify/scripts/bash/lisa-loop.sh"
cp "$SCRIPT_DIR/homer-loop.sh"              "$PROJECT_DIR/.specify/scripts/bash/homer-loop.sh"
cp "$SCRIPT_DIR/pipeline.sh"                "$PROJECT_DIR/.specify/scripts/bash/pipeline.sh"
cp "$SCRIPT_DIR/ralph-prompt.template.md"   "$PROJECT_DIR/.specify/templates/ralph-prompt.template.md"
cp "$SCRIPT_DIR/lisa-prompt.template.md"    "$PROJECT_DIR/.specify/templates/lisa-prompt.template.md"
cp "$SCRIPT_DIR/homer-prompt.template.md"   "$PROJECT_DIR/.specify/templates/homer-prompt.template.md"
cp "$SCRIPT_DIR/speckit.ralph.implement.md" "$PROJECT_DIR/.claude/commands/speckit.ralph.implement.md"
cp "$SCRIPT_DIR/speckit.lisa.analyze.md"    "$PROJECT_DIR/.claude/commands/speckit.lisa.analyze.md"
cp "$SCRIPT_DIR/speckit.homer.clarify.md"   "$PROJECT_DIR/.claude/commands/speckit.homer.clarify.md"
cp "$SCRIPT_DIR/speckit.pipeline.md"        "$PROJECT_DIR/.claude/commands/speckit.pipeline.md"

echo "  Copied files:"
echo "    .specify/scripts/bash/ralph-loop.sh"
echo "    .specify/scripts/bash/lisa-loop.sh"
echo "    .specify/scripts/bash/homer-loop.sh"
echo "    .specify/scripts/bash/pipeline.sh"
echo "    .specify/templates/ralph-prompt.template.md"
echo "    .specify/templates/lisa-prompt.template.md"
echo "    .specify/templates/homer-prompt.template.md"
echo "    .claude/commands/speckit.ralph.implement.md"
echo "    .claude/commands/speckit.lisa.analyze.md"
echo "    .claude/commands/speckit.homer.clarify.md"
echo "    .claude/commands/speckit.pipeline.md"

# ── 2. Make scripts executable ──────────────────────────────────────

chmod +x "$PROJECT_DIR/.specify/scripts/bash/ralph-loop.sh"
chmod +x "$PROJECT_DIR/.specify/scripts/bash/lisa-loop.sh"
chmod +x "$PROJECT_DIR/.specify/scripts/bash/homer-loop.sh"
chmod +x "$PROJECT_DIR/.specify/scripts/bash/pipeline.sh"

echo "  Made scripts executable"

# ── 3. Update .gitignore ────────────────────────────────────────────

GITIGNORE="$PROJECT_DIR/.gitignore"
MARKER="# Simpsons loops"

if [[ -f "$GITIGNORE" ]] && grep -qF "$MARKER" "$GITIGNORE"; then
  echo "  .gitignore already contains Simpsons loops entries — skipped"
else
  {
    echo ""
    echo "$MARKER"
    cat "$SCRIPT_DIR/gitignore"
  } >> "$GITIGNORE"
  echo "  Appended entries to .gitignore"
fi

# ── 4. Update Claude Code permissions ───────────────────────────────

SETTINGS="$PROJECT_DIR/.claude/settings.local.json"
RALPH_PERM='Bash(.specify/scripts/bash/ralph-loop.sh*)'
LISA_PERM='Bash(.specify/scripts/bash/lisa-loop.sh*)'
HOMER_PERM='Bash(.specify/scripts/bash/homer-loop.sh*)'
PIPELINE_PERM='Bash(.specify/scripts/bash/pipeline.sh*)'

needs_update=false

if [[ ! -f "$SETTINGS" ]]; then
  needs_update=true
elif ! grep -qF "$RALPH_PERM" "$SETTINGS" || ! grep -qF "$LISA_PERM" "$SETTINGS" || ! grep -qF "$HOMER_PERM" "$SETTINGS" || ! grep -qF "$PIPELINE_PERM" "$SETTINGS"; then
  needs_update=true
fi

if $needs_update; then
  if command -v jq &>/dev/null; then
    if [[ -f "$SETTINGS" ]]; then
      # Merge into existing file
      tmp=$(mktemp)
      jq --arg r "$RALPH_PERM" --arg l "$LISA_PERM" --arg h "$HOMER_PERM" --arg p "$PIPELINE_PERM" '
        .permissions.allow = ((.permissions.allow // []) + [$r, $l, $h, $p] | unique)
      ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
    else
      # Create new file
      jq -n --arg r "$RALPH_PERM" --arg l "$LISA_PERM" --arg h "$HOMER_PERM" --arg p "$PIPELINE_PERM" '
        { permissions: { allow: [$r, $l, $h, $p] } }
      ' > "$SETTINGS"
    fi
    echo "  Updated .claude/settings.local.json"
  else
    echo ""
    echo "  WARNING: jq not found — could not update .claude/settings.local.json automatically."
    echo "  Add these entries manually to .claude/settings.local.json:"
    echo ""
    echo '    "permissions": {'
    echo '      "allow": ['
    echo "        \"$RALPH_PERM\","
    echo "        \"$LISA_PERM\","
    echo "        \"$HOMER_PERM\","
    echo "        \"$PIPELINE_PERM\""
    echo '      ]'
    echo '    }'
  fi
else
  echo "  .claude/settings.local.json already has script permissions — skipped"
fi

echo ""
echo "Done! Run /speckit.pipeline for the full end-to-end workflow, or use individual loops:"
echo "  /speckit.ralph.implement  /speckit.lisa.analyze  /speckit.homer.clarify"
