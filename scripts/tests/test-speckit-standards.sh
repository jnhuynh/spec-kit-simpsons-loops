#!/usr/bin/env bash
# shellcheck disable=SC2034  # file-level: TAB is used from the Task 2 cases on; remove then
# Tests for scripts/speckit-standards.sh. Run from anywhere:
#   bash scripts/tests/test-speckit-standards.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$HERE/../speckit-standards.sh"
FIXTURES="$HERE/fixtures/standards"
SEEDS="$HERE/../../specify-marge/config"
failures=0
TAB=$'\t'

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; failures=$((failures + 1)); }
check_eq() { if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1 (got: $2, want: $3)"; fi; }
check_rc() { if [[ "$2" -eq "$3" ]]; then pass "$1"; else fail "$1 (rc=$2, want $3)"; fi; }
check_has() { if grep -qF -- "$3" <<<"$2"; then pass "$1"; else fail "$1 (missing: $3; got: ${2:0:300})"; fi; }
check_lacks() { if grep -qF -- "$3" <<<"$2"; then fail "$1 (unexpected: $3)"; else pass "$1"; fi; }

# A sandbox repo: `main` holds one commit; the work happens on branch `work`.
# $1 = which config to install: fixtures (the condensed Reset files), seeds
# (the shipped templates), or none.
make_repo() {
  sandbox=$(mktemp -d)
  cd "$sandbox" || exit 1
  git init -q -b main 2>/dev/null || { git init -q && git checkout -q -b main; }
  git config user.email test@test
  git config user.name tester
  mkdir -p .specify/marge/config
  case "$1" in
    fixtures) cp "$FIXTURES/damage-levels.yml" "$FIXTURES/lexicon.yml" .specify/marge/config/ ;;
    seeds) cp "$SEEDS/damage-levels.yml" "$SEEDS/lexicon.yml" .specify/marge/config/ ;;
  esac
  printf 'base\n' > base.txt
  git add -A
  git commit -qm init
  git checkout -qb work
}
cleanup() { cd / && rm -rf "$sandbox"; }
commit_all() { git add -A && git commit -qm "${1:-change}"; }
engine() { out=$(bash "$ENGINE" "$@" 2>"$sandbox/err.txt"); rc=$?; err=$(cat "$sandbox/err.txt"); }

# ── Task 1: CLI and silence without config ──────────────────────────────────

make_repo fixtures
engine
check_rc "no mode is a usage error" "$rc" 2
engine --base main --only bogus
check_rc "unknown --only group exits 2" "$rc" 2
check_has "unknown group is named" "$err" "bogus"
engine --base main --format xml
check_rc "unknown format exits 2" "$rc" 2
engine --base main --body-file does-not-exist.md
check_rc "missing body file exits 2" "$rc" 2
cleanup

make_repo none
printf 'x\n' > x.txt; commit_all
engine --base main
check_rc "no damage-levels.yml exits 0" "$rc" 0
check_eq "no damage-levels.yml prints nothing" "$out" ""
cleanup

make_repo fixtures
engine --base main
check_rc "clean change set exits 0" "$rc" 0
check_has "clean change set says so" "$out" "No findings."
cleanup

echo
if [[ "$failures" -eq 0 ]]; then
  echo "ALL TESTS PASSED"
else
  echo "$failures TEST(S) FAILED"
  exit 1
fi
