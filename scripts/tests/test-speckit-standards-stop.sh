#!/usr/bin/env bash
# Tests for scripts/speckit-standards-stop.sh, the Claude Code Stop hook.
# Run from anywhere: bash scripts/tests/test-speckit-standards-stop.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HERE/../speckit-standards-stop.sh"
ENGINE="$HERE/../speckit-standards.sh"
FIXTURES="$HERE/fixtures/standards"
failures=0

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; failures=$((failures + 1)); }
check_rc() { if [[ "$2" -eq "$3" ]]; then pass "$1"; else fail "$1 (rc=$2, want $3)"; fi; }
check_silent() { if [[ -z "$2" ]]; then pass "$1"; else fail "$1 (got: ${2:0:200})"; fi; }
check_has() { if grep -qF -- "$3" <<<"$2"; then pass "$1"; else fail "$1 (missing: $3; got: ${2:0:300})"; fi; }

# A consumer repo after setup.sh: the engine installed, the fixture config, one commit.
make_repo() {
  sandbox=$(mktemp -d)
  cd "$sandbox" || exit 1
  git init -q -b main 2>/dev/null || { git init -q && git checkout -q -b main; }
  git config user.email t@t; git config user.name t
  mkdir -p .specify/marge/config .specify/scripts/bash
  cp "$ENGINE" .specify/scripts/bash/speckit-standards.sh; chmod +x .specify/scripts/bash/speckit-standards.sh
  cp "$FIXTURES/damage-levels.yml" "$FIXTURES/lexicon.yml" .specify/marge/config/
  printf 'base\n' > base.txt
  git add -A; git commit -qm init
}
cleanup() { cd / && rm -rf "$sandbox"; }

# The hook JSON Claude Code sends, with the two keys the hook reads.
json() { printf '{"session_id":"s1","transcript_path":"/t","cwd":"%s","hook_event_name":"Stop","stop_hook_active":%s}' "$1" "$2"; }
# Run the hook from / with $1 on stdin, so only the JSON (or the env) can find the repo.
hook() { out=$(cd / && printf '%s' "$1" | bash "$HOOK" 2>/dev/null); rc=$?; }

# A PATH with every command on the current one except jq.
path_without_jq() {
  local shim dir f
  shim=$(mktemp -d)
  IFS=: read -r -a dirs <<<"$PATH"
  for dir in "${dirs[@]}"; do
    [[ -d "$dir" ]] || continue
    for f in "$dir"/*; do
      [[ -x "$f" && ! -d "$f" ]] || continue
      [[ "$(basename "$f")" == jq || -e "$shim/$(basename "$f")" ]] && continue
      ln -s "$f" "$shim/"
    done
  done
  printf '%s' "$shim"
}

# 1. A banned word in an untracked Markdown file blocks, with the reason.
make_repo
printf 'Underwriting here.\n' > note.md
hook "$(json "$sandbox" false)"
check_rc "block: exit 0" "$rc" 0
check_has "block: decision" "$out" '{"decision":"block"'
check_has "block: names the rule" "$out" 'lexicon-banned'
check_has "block: names the file and line" "$out" 'note.md:1'
check_has "block: explains itself" "$out" 'Fix these before finishing'

# 2. The same tree is silent once the hook already sent the session back.
hook "$(json "$sandbox" true)"
check_rc "stop_hook_active true: exit 0" "$rc" 0
check_silent "stop_hook_active true is silent" "$out"

# 3. Advice never blocks: a filler verb alone is silent.
printf 'We utilize things.\n' > note.md
hook "$(json "$sandbox" false)"
check_silent "advice only is silent" "$out"

# 4. A new spec without its plain summary blocks (the pr-shape group runs on untracked files).
mkdir -p specs/1a2b-feat-x
printf '# Spec\n\n## User Scenarios\n\nText.\n' > specs/1a2b-feat-x/spec.md
hook "$(json "$sandbox" false)"
check_has "plain-summary-missing blocks" "$out" 'plain-summary-missing'

# 5. A clean tree is silent.
git add -A; git commit -qm all
hook "$(json "$sandbox" false)"
check_rc "clean tree: exit 0" "$rc" 0
check_silent "clean tree is silent" "$out"

# 6. The engine failing to run (exit 2) is silent.
printf 'Underwriting here.\n' > note.md
printf 'levels:\n\t- name: broken\n' > .specify/marge/config/damage-levels.yml
hook "$(json "$sandbox" false)"
check_rc "engine exit 2: exit 0" "$rc" 0
check_silent "engine exit 2 is silent" "$out"
cp "$FIXTURES/damage-levels.yml" .specify/marge/config/

# 7. Malformed and empty input are silent.
hook '{"cwd": '
check_rc "malformed JSON: exit 0" "$rc" 0
check_silent "malformed JSON is silent" "$out"
hook ''
check_rc "empty input: exit 0" "$rc" 0
check_silent "empty input is silent" "$out"

# 8. No cwd in the JSON: CLAUDE_PROJECT_DIR finds the repo.
out=$(cd / && printf '{"stop_hook_active":false}' | CLAUDE_PROJECT_DIR="$sandbox" bash "$HOOK" 2>/dev/null); rc=$?
check_rc "no cwd: exit 0" "$rc" 0
check_has "no cwd falls back to CLAUDE_PROJECT_DIR" "$out" '{"decision":"block"'

# 9. Without jq, the two keys are read with sed.
shim=$(path_without_jq)
out=$(cd / && printf '%s' "$(json "$sandbox" false)" | PATH="$shim" bash "$HOOK" 2>/dev/null); rc=$?
check_rc "without jq: exit 0" "$rc" 0
check_has "without jq the block is still printed" "$out" 'lexicon-banned'
out=$(cd / && printf '%s' "$(json "$sandbox" true)" | PATH="$shim" bash "$HOOK" 2>/dev/null)
check_silent "without jq stop_hook_active true is silent" "$out"
rm -rf "$shim"

# 10. A missing engine is silent.
rm .specify/scripts/bash/speckit-standards.sh
hook "$(json "$sandbox" false)"
check_rc "missing engine: exit 0" "$rc" 0
check_silent "missing engine is silent" "$out"
cleanup

# 11. A cwd outside any git work tree is silent.
elsewhere=$(mktemp -d)
hook "$(json "$elsewhere" false)"
check_rc "not a work tree: exit 0" "$rc" 0
check_silent "not a work tree is silent" "$out"
rm -rf "$elsewhere"

echo
if [[ "$failures" -eq 0 ]]; then echo "ALL TESTS PASSED"; else echo "$failures TEST(S) FAILED"; exit 1; fi
