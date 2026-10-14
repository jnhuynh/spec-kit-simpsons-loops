#!/usr/bin/env bash
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

# ── Task 2: YAML flattener ──────────────────────────────────────────────────

# shellcheck source=../speckit-standards.sh
source "$ENGINE"

flat=$(yaml_flatten "$FIXTURES/damage-levels.yml"); rc=$?
check_rc "fixture damage-levels flattens" "$rc" 0
check_eq "fixture damage-levels line count" "$(wc -l <<<"$flat" | tr -d ' ')" "48"
check_eq "five levels" "$(grep -c '^levels\.[0-9]*\.name' <<<"$flat")" "5"
check_has "folded reviewer joined with spaces" "$flat" "levels.2.reviewer${TAB}Read all of it. This is the feature. Send it back if a sentence needs decoding."
check_has "folded question inside a sequence item" "$flat" "levels.0.checklist.2.question${TAB}Who can reach this? Can a secret, a card number or personal data end up in a log, a response or an unencrypted column?"
check_has "path-scoped question paths" "$flat" "levels.0.checklist.2.paths.1${TAB}app/models/user.rb"
check_has "plain scalar question" "$flat" "levels.0.checklist.3.question${TAB}Does this change what a member is told or agrees to?"
check_has "double-quoted glob unquoted" "$flat" "levels.3.paths.5${TAB}.*"
check_has "quoted star glob unquoted" "$flat" "levels.3.paths.6${TAB}*.yml"
check_has "comment between list items skipped" "$flat" "levels.0.checklist.2.paths.0${TAB}app/policies/**/*"
check_lacks "empty inline list emits nothing" "$flat" "levels.4.checklist"
check_has "aliases parsed" "$flat" "aliases.0.to${TAB}app/services/"

flat=$(yaml_flatten "$FIXTURES/lexicon.yml"); rc=$?
check_rc "fixture lexicon flattens" "$rc" 0
check_eq "fixture lexicon line count" "$(wc -l <<<"$flat" | tr -d ' ')" "43"
check_has "single-quoted pattern unquoted" "$flat" "banned.0.pattern${TAB}underwrit[[:alnum:]_]*"
check_has "unless list" "$flat" "prefer.0.unless.1${TAB}consumer (product|app|codebase|side|flow)"
check_has "inline list items" "$flat" "invented_phrases.nouns.7${TAB}facade"
check_has "inline list of suffixes" "$flat" "invented_phrases.compound_suffixes.3${TAB}driven"
check_eq "cfg_get reads one scalar" "$(cfg_get <(printf '%s\n' "$flat") banned.0.use)" "risk assessment"
check_eq "cfg_list reads a sequence in order" "$(cfg_list <(printf '%s\n' "$flat") known_terms | paste -sd, -)" "Jack Henry,User Story,Success Criteria,Plain Summary,Eastern Time"

tmp=$(mktemp -d)
printf 'a:\n\t- b\n' > "$tmp/tab.yml"
flat=$(yaml_flatten "$tmp/tab.yml" 2>"$tmp/err"); rc=$?
check_rc "tab indentation exits 2" "$rc" 2
check_has "tab error names the line" "$(cat "$tmp/err")" "$tmp/tab.yml:2: unsupported YAML: tab indentation"
printf 'a: &x 1\n' > "$tmp/anchor.yml"
yaml_flatten "$tmp/anchor.yml" >/dev/null 2>&1; rc=$?
check_rc "anchor exits 2" "$rc" 2
printf 'a: |\n  text\n' > "$tmp/literal.yml"
yaml_flatten "$tmp/literal.yml" >/dev/null 2>&1; rc=$?
check_rc "literal block exits 2" "$rc" 2
printf 'k: [a, "b c", d]\nq: "say \\"hi\\""\ns: '"'"'it'"'"''"'"'s'"'"'\nf: >-\n  one\n\n  two\n' > "$tmp/ok.yml"
flat=$(yaml_flatten "$tmp/ok.yml"); rc=$?
check_rc "escapes and folds parse" "$rc" 0
check_has "inline list with quoted item" "$flat" "k.1${TAB}b c"
check_has "escaped double quotes" "$flat" "q${TAB}say \"hi\""
check_has "doubled single quote" "$flat" "s${TAB}it's"
check_has "fold skips blank lines" "$flat" "f${TAB}one two"
rm -rf "$tmp"

echo
if [[ "$failures" -eq 0 ]]; then
  echo "ALL TESTS PASSED"
else
  echo "$failures TEST(S) FAILED"
  exit 1
fi
