#!/usr/bin/env bash
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
exit 1
