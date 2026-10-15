#!/usr/bin/env bash
# setup-readme-sync — a project continuity pack for THIS repo (dogfood).

# Invariant: what setup.sh installs and what the README install table lists
# are the same set. One PROJECT_GATE finding per path found on one side only.
# Contract: .specify/marge/README.md (review stage, diff-scoped).
set -euo pipefail

root="${SPECKIT_REPO_ROOT:-$(pwd)}"
setup="$root/setup.sh"
readme="$root/README.md"

# Only relevant when this diff touches setup.sh or README.md.
case "${SPECKIT_DIFF_FILES:-}" in
  *setup.sh*|*README.md*) ;;
  *) exit 0 ;;
esac
[ -f "$setup" ] && [ -f "$readme" ] || exit 0

# Ship-source paths setup.sh reads: every "$SCRIPT_DIR/..." on a cp or for line,
# or the templates/setup.sh call, cut at the first variable or glob. A loop over
# a directory yields the directory (trailing slash).
setup_paths=$(grep -E '^\s*(cp |for |"\$SCRIPT_DIR/)' "$setup" \
  | grep -oE '\$SCRIPT_DIR/[A-Za-z0-9_./-]+' | sed 's#^\$SCRIPT_DIR/##' | sort -u)

# Paths in the first column of the README install table. A later entry in a
# row may be cut to its last segments, as the table spells it.
readme_paths=$(sed -n '/^<details>/,/^<\/details>/p' "$readme" \
  | grep -E '^\| `' | cut -d'|' -f2 | grep -oE '`[^`]+`' | tr -d '`' | sort -u)

# Does the table entry R describe the setup.sh path S?
related() {  # $1 = R (table entry), $2 = S (setup.sh path)
  local r="$1" s="$2"
  [ "$r" = "$s" ] && return 0
  case "$s" in */"$r") return 0 ;; esac                  # R abbreviated: run-gates.sh
  # shellcheck disable=SC2254  # R is a glob on purpose
  case "$s" in $r|*/$r) return 0 ;; esac                 # R is a glob: claude-agents/*.md
  case "$s" in
    templates/setup.sh) case "$r" in templates/*) return 0 ;; esac ;;   # it installs templates/*
    */) case "$r" in "$s"*) return 0 ;; esac                           # S is a directory R lives in
        case "$s" in */"${r%/*}"/) return 0 ;; esac ;;                 # ... spelled by its last dir
  esac
  return 1
}

emit() {  # $1=file  $2=issue
  cat <<YAML
- file: $1:0
  severity: MEDIUM
  confidence: 90
  pack: project/$(basename "$0")
  rule: setup-readme-sync
  issue: "$2"
  fix: "keep setup.sh and the README install table in sync"
  tags: [PROJECT_GATE]
YAML
}

while IFS= read -r s; do
  [ -n "$s" ] || continue
  found=0
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    if related "$r" "$s"; then found=1; break; fi
  done <<<"$readme_paths"
  [ "$found" = 1 ] || emit README.md "setup.sh installs $s but the README install table does not list it"
done <<<"$setup_paths"

while IFS= read -r r; do
  [ -n "$r" ] || continue
  found=0
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    if related "$r" "$s"; then found=1; break; fi
  done <<<"$setup_paths"
  [ "$found" = 1 ] || emit setup.sh "the README install table lists $r but setup.sh does not install it"
done <<<"$readme_paths"

exit 0
