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
  echo "       Run this script from the root of a project with a .claude/ directory."
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

# ── 0b. Deploy CLAUDE.md and constitution.md ─────────────────────────
"$SCRIPT_DIR/templates/setup.sh" init "$PROJECT_DIR"

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

# ── 1. Clean up stale bash scripts ────────────────────────────────
# Remove previously-installed bash loop scripts and their permissions.
# Idempotent — safe to run on fresh installations.

STALE_SCRIPTS=(
  "pipeline.sh"
  "homer-loop.sh"
  "lisa-loop.sh"
  "ralph-loop.sh"
)

stale_removed=false
for script in "${STALE_SCRIPTS[@]}"; do
  stale_path="$PROJECT_DIR/.specify/scripts/bash/$script"
  if [[ -f "$stale_path" ]]; then
    rm "$stale_path"
    echo "  Removed stale script: .specify/scripts/bash/$script"
    stale_removed=true
  fi
done
if ! $stale_removed; then
  echo "  No stale bash scripts to remove"
fi

# Remove stale Bash(...) permission entries from settings.local.json
SETTINGS="$PROJECT_DIR/.claude/settings.local.json"

if [[ -f "$SETTINGS" ]] && command -v jq &>/dev/null; then
  # Check if any stale permission entries exist
  has_stale_perms=false
  for script in "${STALE_SCRIPTS[@]}"; do
    if grep -qF "Bash(.specify/scripts/bash/$script" "$SETTINGS"; then
      has_stale_perms=true
      break
    fi
  done

  if $has_stale_perms; then
    tmp=$(mktemp)
    jq '
      .permissions.allow = (
        .permissions.allow // [] |
        map(select(
          (test("Bash\\(\\.specify/scripts/bash/pipeline\\.sh") |not) and
          (test("Bash\\(\\.specify/scripts/bash/homer-loop\\.sh") | not) and
          (test("Bash\\(\\.specify/scripts/bash/lisa-loop\\.sh") | not) and
          (test("Bash\\(\\.specify/scripts/bash/ralph-loop\\.sh") | not)
        ))
      )
    ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
    echo "  Removed stale bash script permissions from .claude/settings.local.json"
  fi
fi

# ── 2. Copy files ───────────────────────────────────────────────────

mkdir -p "$PROJECT_DIR/.claude/commands"
mkdir -p "$PROJECT_DIR/.claude/agents"

cp "$SCRIPT_DIR/claude-agents/homer.md"                         "$PROJECT_DIR/.claude/agents/homer.md"
cp "$SCRIPT_DIR/claude-agents/lisa.md"                          "$PROJECT_DIR/.claude/agents/lisa.md"
cp "$SCRIPT_DIR/claude-agents/marge.md"                         "$PROJECT_DIR/.claude/agents/marge.md"
cp "$SCRIPT_DIR/claude-agents/ralph.md"                         "$PROJECT_DIR/.claude/agents/ralph.md"
cp "$SCRIPT_DIR/claude-agents/phaser.md"                        "$PROJECT_DIR/.claude/agents/phaser.md"
cp "$SCRIPT_DIR/claude-agents/plan.md"                          "$PROJECT_DIR/.claude/agents/plan.md"
cp "$SCRIPT_DIR/claude-agents/tasks.md"                         "$PROJECT_DIR/.claude/agents/tasks.md"
cp "$SCRIPT_DIR/claude-agents/specify.md"                       "$PROJECT_DIR/.claude/agents/specify.md"
cp "$SCRIPT_DIR/speckit-commands/speckit.ralph.implement.md"    "$PROJECT_DIR/.claude/commands/speckit.ralph.implement.md"
cp "$SCRIPT_DIR/speckit-commands/speckit.lisa.analyze.md"       "$PROJECT_DIR/.claude/commands/speckit.lisa.analyze.md"
cp "$SCRIPT_DIR/speckit-commands/speckit.homer.clarify.md"      "$PROJECT_DIR/.claude/commands/speckit.homer.clarify.md"
cp "$SCRIPT_DIR/speckit-commands/speckit.marge.review.md"       "$PROJECT_DIR/.claude/commands/speckit.marge.review.md"
cp "$SCRIPT_DIR/speckit-commands/speckit.review.md"             "$PROJECT_DIR/.claude/commands/speckit.review.md"
cp "$SCRIPT_DIR/speckit-commands/speckit.pipeline.md"           "$PROJECT_DIR/.claude/commands/speckit.pipeline.md"
cp "$SCRIPT_DIR/speckit-commands/speckit.phaser.md"             "$PROJECT_DIR/.claude/commands/speckit.phaser.md"
cp "$SCRIPT_DIR/speckit-commands/speckit.flavor.init.md"        "$PROJECT_DIR/.claude/commands/speckit.flavor.init.md"

echo "  Copied files:"
echo "    .claude/agents/homer.md"
echo "    .claude/agents/lisa.md"
echo "    .claude/agents/marge.md"
echo "    .claude/agents/ralph.md"
echo "    .claude/agents/phaser.md"
echo "    .claude/agents/plan.md"
echo "    .claude/agents/tasks.md"
echo "    .claude/agents/specify.md"
echo "    .claude/commands/speckit.ralph.implement.md"
echo "    .claude/commands/speckit.lisa.analyze.md"
echo "    .claude/commands/speckit.homer.clarify.md"
echo "    .claude/commands/speckit.marge.review.md"
echo "    .claude/commands/speckit.review.md"
echo "    .claude/commands/speckit.pipeline.md"
echo "    .claude/commands/speckit.phaser.md"
echo "    .claude/commands/speckit.flavor.init.md"

# ── 2a. Install phaser/ entry points (R-017, D-015) ─────────────────
# The phaser engine is shipped as a Ruby toolkit under $SCRIPT_DIR/phaser/.
# Target projects access it via a `phaser/` symlink at the project root so
# the documented invocation path `phaser/bin/phaser-flavor-init` (and the
# other phaser bins) resolves. Idempotent: an existing correct symlink is
# left alone; a stale link is replaced; a real `phaser/` directory in the
# target is preserved with a warning.

PHASER_LINK="$PROJECT_DIR/phaser"
PHASER_SOURCE="$SCRIPT_DIR/phaser"

# Ensure the source-of-truth entry point is executable (git on some
# filesystems may not preserve the bit).
chmod +x "$PHASER_SOURCE/bin/phaser-flavor-init"

if [[ -L "$PHASER_LINK" ]]; then
  current_target="$(readlink "$PHASER_LINK")"
  if [[ "$current_target" == "$PHASER_SOURCE" ]]; then
    echo "  phaser/ symlink already points to $PHASER_SOURCE — skipped"
  else
    rm "$PHASER_LINK"
    ln -s "$PHASER_SOURCE" "$PHASER_LINK"
    echo "  Updated phaser/ symlink → $PHASER_SOURCE"
  fi
elif [[ -e "$PHASER_LINK" ]]; then
  echo "  WARNING: $PHASER_LINK exists and is not a symlink — leaving untouched."
  echo "           The phaser entry points may not resolve from $PROJECT_DIR/phaser/bin/."
else
  ln -s "$PHASER_SOURCE" "$PHASER_LINK"
  echo "  Created phaser/ symlink → $PHASER_SOURCE"
fi

# ── 2b. Seed Marge review packs ─────────────────────────────────────
# Baseline packs ship with the template. Copy each baseline file to
# .specify/marge/checks/ only if it does not already exist — this
# preserves any consumer customizations while still bootstrapping
# fresh installs. Consumer-added packs (files with different names)
# are never touched.

MARGE_CHECKS_DIR="$PROJECT_DIR/.specify/marge/checks"
mkdir -p "$MARGE_CHECKS_DIR"

marge_seeded=false
for pack in "$SCRIPT_DIR/.specify/marge/checks/"*.md; do
  [[ -f "$pack" ]] || continue
  pack_name=$(basename "$pack")
  target="$MARGE_CHECKS_DIR/$pack_name"
  if [[ -f "$target" ]]; then
    echo "  .specify/marge/checks/$pack_name already exists — skipped"
  else
    cp "$pack" "$target"
    echo "  Seeded .specify/marge/checks/$pack_name"
    marge_seeded=true
  fi
done

if ! $marge_seeded; then
  echo "  All Marge review packs already present"
fi

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

echo ""
echo "Done! Run /speckit.pipeline for the full end-to-end workflow, or use individual loops:"
echo "  /speckit.ralph.implement  /speckit.lisa.analyze  /speckit.homer.clarify  /speckit.marge.review"
