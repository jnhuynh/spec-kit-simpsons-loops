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

# ── 0. Quality gate file (never overwrite) ──────────────────────────
# MUST run before file copies so we can inspect the target's existing
# Ralph command file for custom quality gates before it gets overwritten.

QUALITY_GATE_FILE="$PROJECT_DIR/.specify/quality-gates.sh"
RALPH_CMD_FILE="$PROJECT_DIR/.claude/commands/speckit.ralph.implement.md"
SENTINEL="# SPECKIT_DEFAULT_QUALITY_GATE"

if [[ -f "$QUALITY_GATE_FILE" ]]; then
  echo "  Quality gate file already exists — skipped"
else
  # Determine content: placeholder or extracted custom gates
  qg_content=""

  if [[ -f "$RALPH_CMD_FILE" ]] && ! grep -qF "$SENTINEL" "$RALPH_CMD_FILE"; then
    # Sentinel is absent → custom quality gates → extract code block from
    # the "### Step 3: Extract Quality Gates" section
    extracted=$(awk '
      /^### Step 3: Extract Quality Gates/ { found_section=1; next }
      found_section && /^```bash/ { in_block=1; next }
      in_block && /^```/ { exit }
      in_block { print }
    ' "$RALPH_CMD_FILE")

    if [[ -n "$extracted" ]]; then
      qg_content="$(printf '#!/usr/bin/env bash\n%s\n' "$extracted")"
      echo "  Extracted custom quality gates from Ralph command file"
    fi
  fi

  # If nothing was extracted (no file, sentinel present, or empty block),
  # create the placeholder
  if [[ -z "$qg_content" ]]; then
    qg_content='#!/usr/bin/env bash
# SPECKIT_DEFAULT_QUALITY_GATE
#
# Quality Gates Configuration
# ──────────────────────────────────────────────────────────────
# Add your project'\''s quality gate commands below.
# These commands run after each implementation step to verify code quality.
#
# Examples:
#   npm test && npm run lint
#   pytest && ruff check .
#   cargo test && cargo clippy
#   shellcheck *.sh
#
# This file is sourced by the pipeline and Ralph loop scripts.
# It must exit 0 for quality gates to pass.
# ──────────────────────────────────────────────────────────────

echo "ERROR: Quality gates not configured."
echo "Edit .specify/quality-gates.sh with your project'\''s quality gate commands."
exit 1'
    echo "  Created placeholder quality gate file"
  fi

  # Atomic write: temp file → mv
  tmp=$(mktemp)
  printf '%s\n' "$qg_content" > "$tmp"
  chmod +x "$tmp"
  mv "$tmp" "$QUALITY_GATE_FILE"
fi

# ── 1. Copy files ───────────────────────────────────────────────────

mkdir -p "$PROJECT_DIR/.specify/scripts/bash"
mkdir -p "$PROJECT_DIR/.claude/commands"
mkdir -p "$PROJECT_DIR/.claude/agents"

cp "$SCRIPT_DIR/ralph-loop.sh"              "$PROJECT_DIR/.specify/scripts/bash/ralph-loop.sh"
cp "$SCRIPT_DIR/lisa-loop.sh"               "$PROJECT_DIR/.specify/scripts/bash/lisa-loop.sh"
cp "$SCRIPT_DIR/homer-loop.sh"              "$PROJECT_DIR/.specify/scripts/bash/homer-loop.sh"
cp "$SCRIPT_DIR/pipeline.sh"                "$PROJECT_DIR/.specify/scripts/bash/pipeline.sh"
cp "$SCRIPT_DIR/agents/homer.md"            "$PROJECT_DIR/.claude/agents/homer.md"
cp "$SCRIPT_DIR/agents/lisa.md"             "$PROJECT_DIR/.claude/agents/lisa.md"
cp "$SCRIPT_DIR/agents/ralph.md"            "$PROJECT_DIR/.claude/agents/ralph.md"
cp "$SCRIPT_DIR/agents/plan.md"             "$PROJECT_DIR/.claude/agents/plan.md"
cp "$SCRIPT_DIR/agents/tasks.md"            "$PROJECT_DIR/.claude/agents/tasks.md"
cp "$SCRIPT_DIR/agents/specify.md"          "$PROJECT_DIR/.claude/agents/specify.md"
cp "$SCRIPT_DIR/speckit.ralph.implement.md" "$PROJECT_DIR/.claude/commands/speckit.ralph.implement.md"
cp "$SCRIPT_DIR/speckit.lisa.analyze.md"    "$PROJECT_DIR/.claude/commands/speckit.lisa.analyze.md"
cp "$SCRIPT_DIR/speckit.homer.clarify.md"   "$PROJECT_DIR/.claude/commands/speckit.homer.clarify.md"
cp "$SCRIPT_DIR/speckit.pipeline.md"        "$PROJECT_DIR/.claude/commands/speckit.pipeline.md"

echo "  Copied files:"
echo "    .specify/scripts/bash/ralph-loop.sh"
echo "    .specify/scripts/bash/lisa-loop.sh"
echo "    .specify/scripts/bash/homer-loop.sh"
echo "    .specify/scripts/bash/pipeline.sh"
echo "    .claude/agents/homer.md"
echo "    .claude/agents/lisa.md"
echo "    .claude/agents/ralph.md"
echo "    .claude/agents/plan.md"
echo "    .claude/agents/tasks.md"
echo "    .claude/agents/specify.md"
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
