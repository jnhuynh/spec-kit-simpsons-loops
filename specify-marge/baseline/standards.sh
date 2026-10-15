#!/usr/bin/env bash
# Runs the shipped standards engine (damage level, lexicon, plain language,
# PR shape) as a baseline script pack. Edit --only to tune; delete to opt out.
# Seeded once by setup.sh; updates never touch it. Contract: .specify/marge/README.md.
# speckit-stage: planning
set -uo pipefail

engine=".specify/scripts/bash/speckit-standards.sh"
[ -x "$engine" ] || exit 0
base="${SPECKIT_BASE_REF:-}"
if [ -z "$base" ]; then
  for candidate in origin/main main master; do
    if git rev-parse --verify --quiet "$candidate^{commit}" >/dev/null 2>&1; then base="$candidate"; break; fi
  done
fi
[ -n "$base" ] || base=origin/main

# /speckit-review-pr passes the pull request's file list without checking out
# its head. When the two disagree the checkout is some other branch, or stale:
# refuse rather than report on the wrong tree. A rename is one file to the
# pull request and two to a diff without rename detection, so each side is
# compared against the other's wider list.
checkout_matches_pull_request() {
  [ -n "${SPECKIT_DIFF_FILES:-}" ] || return 0
  given="$(printf '%s\n' "$SPECKIT_DIFF_FILES" | sed '/^$/d' | sort -u)"
  local_all="$(git diff --name-only --no-renames "$base...HEAD" 2>/dev/null | sort -u)"
  local_new="$(git diff --name-only -M "$base...HEAD" 2>/dev/null | sort -u)"
  not_here="$(comm -23 <(printf '%s\n' "$given") <(printf '%s\n' "$local_all"))"
  not_in_pr="$(comm -23 <(printf '%s\n' "$local_new") <(printf '%s\n' "$given"))"
  [ -z "$not_here$not_in_pr" ] && return 0
  echo "standards.sh: the checkout is not the pull request head (git diff $base...HEAD differs from SPECKIT_DIFF_FILES); check it out and run again" >&2
  return 1
}

code=0
if [ "${SPECKIT_STAGE:-review}" = planning ]; then
  [ -n "${SPECKIT_FEATURE_DIR:-}" ] || exit 0
  bash "$engine" --dir "$SPECKIT_FEATURE_DIR" --base "$base" \
       --only lexicon,plain-language,pr-shape --format marge || code=$?
else
  checkout_matches_pull_request || exit 2
  bash "$engine" --base "$base" --format marge || code=$?
fi

# The engine exits 1 when a finding blocks. For a pack, findings drive
# enforcement, so 1 is a normal run. Anything else is the engine itself failing.
[ "$code" -le 1 ] || exit "$code"
exit 0
