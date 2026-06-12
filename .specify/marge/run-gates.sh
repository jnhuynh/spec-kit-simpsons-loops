#!/usr/bin/env bash
# run-gates.sh — deterministic SpecKit script-pack runner.
#
# Discovers .specify/marge/project/*.sh (script packs), runs each under a timeout
# with the pack-contract environment exported, and emits the concatenated findings
# (a YAML sequence) on stdout. A pack that exits non-zero or times out yields ONE
# `pack-execution` meta-finding instead of aborting. ONLY findings go to stdout
# (diagnostics, if any, go to stderr). Contract: .specify/marge/README.md.
#
# Called by /speckit.review and /speckit.review.pr (SPECKIT_STAGE=review) and by
# the Lisa planning agent (SPECKIT_STAGE=planning). Callers set the stage-scoped
# env; this runner passes it through to each script pack unchanged.
set -euo pipefail

stage="${SPECKIT_STAGE:-review}"
repo_root="${SPECKIT_REPO_ROOT:-$(pwd)}"
diff_files="${SPECKIT_DIFF_FILES:-}"
base_ref="${SPECKIT_BASE_REF:-}"

# Review: derive the changed-file list from the base ref when the caller did not
# pass one explicitly (so callers need only supply a single ref, not a marshalled
# multi-line value). PR supplies its own `gh pr diff` list; planning supplies none.
if [ -z "$diff_files" ] && [ -n "$base_ref" ] && git -C "$repo_root" rev-parse --git-dir >/dev/null 2>&1; then
  if git -C "$repo_root" rev-parse --verify --quiet "$base_ref^{commit}" >/dev/null; then
    diff_files="$(git -C "$repo_root" diff --name-only "$base_ref"...HEAD 2>/dev/null || true)"
  else
    echo "run-gates.sh: base ref '$base_ref' did not resolve; diff-scoped packs see an empty changed-file list" >&2
  fi
fi

# Export the full contract env so each script pack (a grandchild process) inherits it.
export SPECKIT_STAGE="$stage"
export SPECKIT_REPO_ROOT="$repo_root"
export SPECKIT_DIFF_FILES="$diff_files"
export SPECKIT_BASE_REF="$base_ref"
export SPECKIT_FEATURE_DIR="${SPECKIT_FEATURE_DIR:-}"

packs_dir="$repo_root/.specify/marge/project"
[ -d "$packs_dir" ] || exit 0

# Script packs always run with the repo root as working directory, in every venue.
cd "$repo_root"

run_pack() {  # $1 = script-pack path; runs under a timeout, degrading where absent
  if command -v timeout >/dev/null 2>&1; then
    timeout 120 bash "$1"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout 120 bash "$1"
  else
    bash "$1"
  fi
}

errfile="$(mktemp)"
trap 'rm -f "$errfile"' EXIT

for pack in "$packs_dir"/*.sh; do
  [ -e "$pack" ] || continue          # literal-glob guard: no matches in dir
  name="$(basename "$pack")"

  # Planning runs only script packs that opt in. Capture the header to a variable
  # (no pipe) so a pipefail + `grep -q` early-exit SIGPIPE on `head` can't cause a
  # false skip of a marked pack.
  if [ "$stage" = "planning" ]; then
    header="$(head -n 20 "$pack" 2>/dev/null || true)"
    grep -qF '# speckit-stage: planning' <<<"$header" || continue
  fi

  # Capture pack stdout (findings) and stderr (diagnostics) separately; tolerate
  # a non-zero exit under `set -e` via the `|| rc=$?` test.
  rc=0
  out="$(run_pack "$pack" 2>"$errfile")" || rc=$?
  if [ "$rc" -eq 0 ]; then
    if [ -n "$out" ]; then printf '%s\n' "$out"; fi
  else
    # Strip quotes/backslashes so arbitrary stderr text cannot break the
    # double-quoted YAML scalar below.
    last_err="$(tail -n 1 "$errfile" 2>/dev/null | tr -d '\n\r"\\')"
    issue="script pack failed to run (exit $rc)"
    if [ -n "$last_err" ]; then issue="$issue: $last_err"; fi
    cat <<YAML
- file: .specify/marge/project/$name:0
  severity: LOW
  confidence: 100
  pack: project/$name
  rule: pack-execution
  issue: "$issue"
  tags: [PROJECT_GATE, NEEDS_HUMAN]
YAML
  fi
done

exit 0
