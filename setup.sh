#!/usr/bin/env bash
set -euo pipefail

# ─── Simpsons Loops installer ───────────────────────────────────────
# Run from the ROOT of your target project:
#   bash <path-to-simpsons-loops>/setup.sh
#
# To install into itself for dogfooding:
#   bash setup.sh --self
# ─────────────────────────────────────────────────────────────────────

SELF_INSTALL=false
while [[ $# -gt 0 && "$1" == --* ]]; do
  case "$1" in
    --self) SELF_INSTALL=true; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

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

if [[ "$SCRIPT_DIR" == "$PROJECT_DIR" && "$SELF_INSTALL" != true ]]; then
  echo "ERROR: You are running setup.sh from inside the simpsons-loops repo itself."
  echo "       cd into your target project first, then run:"
  echo "         bash $SCRIPT_DIR/setup.sh"
  echo ""
  echo "       To install into itself for dogfooding, use:"
  echo "         bash setup.sh --self"
  exit 1
fi

echo "Installing Simpsons Loops into: $PROJECT_DIR"
echo ""

# ── 0b. Deploy CLAUDE.md and constitution.md ─────────────────────────
# Skip for self-install — the repo has its own CLAUDE.md and constitution
if [[ "$SELF_INSTALL" != true ]]; then
  "$SCRIPT_DIR/templates/setup.sh" init "$PROJECT_DIR"
fi

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

# ── 0c. Fast quality gate file (never overwrite) ────────────────────
QUALITY_GATE_FAST_FILE="$PROJECT_DIR/.specify/quality-gates-fast.sh"

if [[ -f "$QUALITY_GATE_FAST_FILE" ]]; then
  echo "  Fast quality gate file already exists — skipped"
else
  qg_fast_content='#!/usr/bin/env bash
# SPECKIT_DEFAULT_QUALITY_GATE_FAST
#
# Fast Quality Gates Configuration (per-iteration)
# ──────────────────────────────────────────────────────────────
# This is the SCOPED version that runs per iteration during ralph and marge.
# It should check only CHANGED files for fast feedback.
# The full gate (.specify/quality-gates.sh) runs once after loop completion.
#
# Examples:
#   npm test --changed && npx eslint $(git diff --name-only --diff-filter=d HEAD -- "*.ts" "*.tsx")
#   rspec $(git diff --name-only --diff-filter=d HEAD -- "*_spec.rb") && rubocop $(git diff --name-only --diff-filter=d HEAD -- "*.rb")
#   pytest $(git diff --name-only --diff-filter=d HEAD -- "test_*.py")
#
# This file is optional. If absent, the full gate is used per iteration instead.
# It must exit 0 for quality gates to pass.
# ──────────────────────────────────────────────────────────────

echo "ERROR: Fast quality gates not configured."
echo "Edit .specify/quality-gates-fast.sh with scoped quality gate commands."
echo "Or delete this file to fall back to the full gate per iteration."
exit 1'

  tmp=$(mktemp)
  printf '%s\n' "$qg_fast_content" > "$tmp"
  chmod +x "$tmp"
  mv "$tmp" "$QUALITY_GATE_FAST_FILE"
  echo "  Created placeholder fast quality gate file"
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
cp "$SCRIPT_DIR/claude-agents/plan.md"                          "$PROJECT_DIR/.claude/agents/plan.md"
cp "$SCRIPT_DIR/claude-agents/tasks.md"                         "$PROJECT_DIR/.claude/agents/tasks.md"
cp "$SCRIPT_DIR/claude-agents/specify.md"                       "$PROJECT_DIR/.claude/agents/specify.md"
cp "$SCRIPT_DIR/claude-agents/loop-orchestrator.md"             "$PROJECT_DIR/.claude/agents/loop-orchestrator.md"
cp "$SCRIPT_DIR/speckit-commands/speckit.ralph.implement.md"    "$PROJECT_DIR/.claude/commands/speckit.ralph.implement.md"
cp "$SCRIPT_DIR/speckit-commands/speckit.lisa.analyze.md"       "$PROJECT_DIR/.claude/commands/speckit.lisa.analyze.md"
cp "$SCRIPT_DIR/speckit-commands/speckit.homer.clarify.md"      "$PROJECT_DIR/.claude/commands/speckit.homer.clarify.md"
cp "$SCRIPT_DIR/speckit-commands/speckit.marge.review.md"       "$PROJECT_DIR/.claude/commands/speckit.marge.review.md"
cp "$SCRIPT_DIR/speckit-commands/speckit.review.md"             "$PROJECT_DIR/.claude/commands/speckit.review.md"
cp "$SCRIPT_DIR/speckit-commands/speckit.pipeline.md"           "$PROJECT_DIR/.claude/commands/speckit.pipeline.md"
cp "$SCRIPT_DIR/speckit-commands/speckit.brainstorm.md"        "$PROJECT_DIR/.claude/commands/speckit.brainstorm.md"
cp "$SCRIPT_DIR/speckit-commands/speckit.review.pr.md"        "$PROJECT_DIR/.claude/commands/speckit.review.pr.md"
cp "$SCRIPT_DIR/speckit-commands/speckit.phase.md"            "$PROJECT_DIR/.claude/commands/speckit.phase.md"
cp "$SCRIPT_DIR/speckit-commands/speckit.split.md"            "$PROJECT_DIR/.claude/commands/speckit.split.md"
cp "$SCRIPT_DIR/claude-agents/phase.md"                       "$PROJECT_DIR/.claude/agents/phase.md"
cp "$SCRIPT_DIR/claude-agents/split.md"                       "$PROJECT_DIR/.claude/agents/split.md"
cp "$SCRIPT_DIR/claude-agents/reconcile.md"                   "$PROJECT_DIR/.claude/agents/reconcile.md"

# Framework runner for project script packs (Pattern A: OVERWRITE, like the
# agent/command copies above). It lives under .specify/marge/ next to the
# consumer-owned project/, but is framework code, so it is always refreshed —
# the project/*.sh script packs themselves are authored per repo and preserved.
mkdir -p "$PROJECT_DIR/.specify/marge"
cp "$SCRIPT_DIR/specify-marge/run-gates.sh" "$PROJECT_DIR/.specify/marge/run-gates.sh"
chmod +x "$PROJECT_DIR/.specify/marge/run-gates.sh"

echo "  Copied files:"
echo "    .claude/agents/homer.md"
echo "    .claude/agents/lisa.md"
echo "    .claude/agents/marge.md"
echo "    .claude/agents/ralph.md"
echo "    .claude/agents/plan.md"
echo "    .claude/agents/tasks.md"
echo "    .claude/agents/specify.md"
echo "    .claude/agents/loop-orchestrator.md"
echo "    .claude/commands/speckit.ralph.implement.md"
echo "    .claude/commands/speckit.lisa.analyze.md"
echo "    .claude/commands/speckit.homer.clarify.md"
echo "    .claude/commands/speckit.marge.review.md"
echo "    .claude/commands/speckit.review.md"
echo "    .claude/commands/speckit.pipeline.md"
echo "    .claude/commands/speckit.brainstorm.md"
echo "    .claude/commands/speckit.review.pr.md"
echo "    .claude/commands/speckit.phase.md"
echo "    .claude/commands/speckit.split.md"
echo "    .claude/agents/phase.md"
echo "    .claude/agents/split.md"
echo "    .claude/agents/reconcile.md"
echo "    .specify/marge/run-gates.sh"

# ── 2b-migrate. Migrate an older checks//gates/ layout ──────────────
# Earlier installs used .specify/marge/checks/ (prose packs) and
# .specify/marge/gates/ (script packs). The current layout splits by ORIGIN:
# baseline/ (shipped) and project/ (yours), with mode carried by the extension
# (.md prose, .sh script). Move any existing files into the new layout,
# preserving consumer customizations: shipped baseline names go to baseline/,
# everything else (consumer prose packs) and all old script packs go to project/.
MARGE_DIR="$PROJECT_DIR/.specify/marge"
if [[ -d "$MARGE_DIR/checks" || -d "$MARGE_DIR/gates" ]]; then
  mkdir -p "$MARGE_DIR/baseline" "$MARGE_DIR/project"

  baseline_names=" "
  for b in "$SCRIPT_DIR/specify-marge/baseline/"*.md; do
    [[ -f "$b" ]] && baseline_names+="$(basename "$b") "
  done

  if [[ -d "$MARGE_DIR/checks" ]]; then
    for f in "$MARGE_DIR/checks/"*.md; do
      [[ -f "$f" ]] || continue
      name=$(basename "$f")
      if [[ "$baseline_names" == *" $name "* ]]; then
        dest="$MARGE_DIR/baseline/$name"
      else
        dest="$MARGE_DIR/project/$name"
      fi
      if [[ -e "$dest" ]]; then rm -f "$f"; else mv "$f" "$dest"; fi
    done
  fi

  if [[ -d "$MARGE_DIR/gates" ]]; then
    for f in "$MARGE_DIR/gates/"*.sh; do
      [[ -f "$f" ]] || continue
      name=$(basename "$f")
      dest="$MARGE_DIR/project/$name"
      if [[ -e "$dest" ]]; then rm -f "$f"; else mv "$f" "$dest"; fi
    done
    rm -f "$MARGE_DIR/gates/README.md"   # old contract doc — superseded by .specify/marge/README.md
  fi

  rmdir "$MARGE_DIR/checks" "$MARGE_DIR/gates" 2>/dev/null || true
  echo "  Migrated existing .specify/marge/{checks,gates}/ into baseline//project/"
fi

# ── 2b. Seed Marge baseline packs ───────────────────────────────────
# Baseline packs ship from the non-hidden source dir specify-marge/baseline/.
# Copy each into the consumer's .specify/marge/baseline/ only if it does not
# already exist — preserving consumer customizations while bootstrapping fresh
# installs. Consumer-added packs go in project/ and are never touched here.
# (Source is non-hidden; setup never reads from the hidden .specify tree.)

MARGE_BASELINE_DIR="$PROJECT_DIR/.specify/marge/baseline"
mkdir -p "$MARGE_BASELINE_DIR"

marge_seeded=false
for pack in "$SCRIPT_DIR/specify-marge/baseline/"*.md; do
  [[ -f "$pack" ]] || continue
  pack_name=$(basename "$pack")
  target="$MARGE_BASELINE_DIR/$pack_name"
  if [[ -f "$target" ]]; then
    echo "  .specify/marge/baseline/$pack_name already exists — skipped"
  else
    cp "$pack" "$target"
    echo "  Seeded .specify/marge/baseline/$pack_name"
    marge_seeded=true
  fi
done

if ! $marge_seeded; then
  echo "  All Marge baseline packs already present"
fi

# ── 2c. Refresh Marge contract docs + scaffold project/ ─────────────
# The glossary + authoring contract (.specify/marge/README.md) and the config
# data note (config/README.md) are framework docs — always refreshed (Pattern A,
# like run-gates.sh above). The project/ dir is created empty: consumers author
# their own packs there (.md prose, .sh script); nothing generic ships into it.
mkdir -p "$PROJECT_DIR/.specify/marge/project" "$PROJECT_DIR/.specify/marge/config"
cp "$SCRIPT_DIR/specify-marge/README.md"        "$PROJECT_DIR/.specify/marge/README.md"
cp "$SCRIPT_DIR/specify-marge/config/README.md" "$PROJECT_DIR/.specify/marge/config/README.md"
echo "    .specify/marge/README.md"
echo "    .specify/marge/config/README.md"

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
