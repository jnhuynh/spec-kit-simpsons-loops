#!/usr/bin/env bash
# Tests for the standards parts of setup.sh. Run from anywhere:
#   bash scripts/tests/test-setup-standards.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
failures=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; failures=$((failures + 1)); }
check_file() { if [[ -f "$2" ]]; then pass "$1"; else fail "$1 (missing $2)"; fi; }
check_exec() { if [[ -x "$2" ]]; then pass "$1"; else fail "$1 ($2 not executable)"; fi; }
check_eq() { if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1 (got: $2, want: $3)"; fi; }

consumer=$(mktemp -d)
cd "$consumer" || exit 1
git init -q
mkdir -p .claude .specify/memory .specify/scripts/bash
bash "$REPO/setup.sh" >/dev/null 2>&1; rc=$?
check_eq "setup.sh exits 0" "$rc" 0
check_exec "engine installed and executable" .specify/scripts/bash/speckit-standards.sh
check_exec "baseline wrapper seeded and executable" .specify/marge/baseline/standards.sh
check_file "damage-levels seeded" .specify/marge/config/damage-levels.yml
check_file "lexicon seeded" .specify/marge/config/lexicon.yml
check_exec "stop hook installed and executable" .claude/hooks/speckit-standards-stop.sh
check_eq "stop hook registered once" "$(jq '.hooks.Stop | length' .claude/settings.json 2>/dev/null)" 1
check_eq "stop hook command" "$(jq -r '.hooks.Stop[0].hooks[0].command' .claude/settings.json 2>/dev/null)" '"$CLAUDE_PROJECT_DIR"/.claude/hooks/speckit-standards-stop.sh'
check_eq "stop hook timeout" "$(jq '.hooks.Stop[0].hooks[0].timeout' .claude/settings.json 2>/dev/null)" 30
check_file "speckit-pr skill installed" .claude/skills/speckit-pr/SKILL.md
check_eq "speckit-pr skill is named" "$(sed -n 2p .claude/skills/speckit-pr/SKILL.md 2>/dev/null)" "name: speckit-pr"
for phrase in 'reads the local tree' 'change nothing' 'never push' 'Never lower' '--body-file' 'origin/<BRANCH>' 'Only a `PULL_REQUEST:0` line' 'damage-levels.yml' 'Recount' 'names a branch that is not the current branch' 'read-only' 'git fetch origin' 'no pull requests found' 'uncommitted changes are not in this description' 'MEDIUM specs/9cad-feat-x/spec.md:5' '## What changed' '## How much damage if it is wrong' '## Where to look' '## How it was verified' '## Links'; do
  if grep -qF -- "$phrase" .claude/skills/speckit-pr/SKILL.md 2>/dev/null; then pass "speckit-pr skill says: $phrase"; else fail "speckit-pr skill says: $phrase"; fi
done
for hinted in .claude/agents/ralph.md .claude/skills/speckit-ralph-implement/SKILL.md .claude/skills/speckit-pipeline/reference/steps/ralph.md; do
  if grep -qF 'Open it with /speckit-pr.' "$hinted" 2>/dev/null; then pass "Ralph hint in $hinted"; else fail "Ralph hint in $hinted"; fi
done
if grep -qF 'Open the spec with a "## Plain summary" section' .claude/skills/speckit-pipeline/reference/steps/specify.md 2>/dev/null; then pass "specify step asks for a plain summary"; else fail "specify step asks for a plain summary"; fi

printf '# mine\n' > .specify/marge/baseline/standards.sh
printf '# mine\n' > .specify/marge/config/lexicon.yml
printf '# old engine\n' > .specify/scripts/bash/speckit-standards.sh
printf '# old hook\n' > .claude/hooks/speckit-standards-stop.sh
jq 'del(.hooks)' .claude/settings.json > settings.tmp && mv settings.tmp .claude/settings.json   # the consumer opted out
bash "$REPO/setup.sh" >/dev/null 2>&1
check_eq "wrapper preserved on re-install" "$(cat .specify/marge/baseline/standards.sh)" "# mine"
check_eq "lexicon preserved on re-install" "$(cat .specify/marge/config/lexicon.yml)" "# mine"
check_eq "engine refreshed on re-install" "$(head -n 1 .specify/scripts/bash/speckit-standards.sh)" "#!/usr/bin/env bash"
check_eq "hook refreshed on re-install" "$(head -n 1 .claude/hooks/speckit-standards-stop.sh)" "#!/usr/bin/env bash"
check_eq "entry not re-added when the hook existed" "$(jq '.hooks.Stop // [] | length' .claude/settings.json)" 0

# The seeds parse and leave a fresh change clean.
cp "$REPO/specify-marge/config/lexicon.yml" .specify/marge/config/lexicon.yml
git add -A >/dev/null; git -c user.email=t@t -c user.name=t commit -qm init
git checkout -qb work
printf 'A short note.\n' > note.md
git add -A; git -c user.email=t@t -c user.name=t commit -qm note
out=$(bash .specify/scripts/bash/speckit-standards.sh --base "$(git rev-parse main 2>/dev/null || git rev-parse master)" 2>&1); rc=$?
check_eq "seeded config runs clean" "$rc" 0
check_eq "seeded default level" "$(head -n 1 <<<"$out")" "Damage level: no runtime effect (set by note.md)"
printf 'We utilize the dispatch surface.\n' > note.md
git add -A; git -c user.email=t@t -c user.name=t commit -qm words
out=$(bash .specify/scripts/bash/speckit-standards.sh --base "$(git rev-parse main 2>/dev/null || git rev-parse master)" 2>&1)
if grep -q 'plain-verb: "utilize"' <<<"$out" && grep -q 'invented-phrase: "dispatch surface"' <<<"$out"; then pass "seeded lexicon finds filler and invented phrases"; else fail "seeded lexicon rules (got: $out)"; fi
cd / && rm -rf "$consumer"

# The seeds themselves pass the shipped rules when they arrive as a change.
consumer=$(mktemp -d)
cd "$consumer" || exit 1
git init -q -b main 2>/dev/null || { git init -q && git checkout -q -b main; }
git config user.email t@t; git config user.name t
mkdir -p .specify/marge/config .specify/scripts/bash
cp "$REPO/scripts/speckit-standards.sh" .specify/scripts/bash/
printf 'base\n' > base.txt
git add -A; git commit -qm init
git checkout -qb work
cp "$REPO/specify-marge/config/damage-levels.yml" "$REPO/specify-marge/config/lexicon.yml" .specify/marge/config/
git add -A; git commit -qm seeds
out=$(bash .specify/scripts/bash/speckit-standards.sh --base main 2>&1); rc=$?
check_eq "seeds as a change exit 0" "$rc" 0
if grep -q 'No findings.' <<<"$out"; then pass "seeds as a change are clean"; else fail "seeds as a change are clean (got: $out)"; fi
cd / && rm -rf "$consumer"

# Existing settings keep their keys and other hooks, and gain the entry once.
consumer=$(mktemp -d)
cd "$consumer" || exit 1
git init -q
mkdir -p .claude .specify/memory .specify/scripts/bash
printf '{"permissions":{"allow":["Bash(ls:*)"]},"hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo other"}]}]}}\n' > .claude/settings.json
bash "$REPO/setup.sh" >/dev/null 2>&1
check_eq "existing settings preserved: permissions" "$(jq -r '.permissions.allow[0]' .claude/settings.json)" 'Bash(ls:*)'
check_eq "existing settings preserved: other Stop hook" "$(jq -r '.hooks.Stop[0].hooks[0].command' .claude/settings.json)" 'echo other'
check_eq "existing settings gain the entry" "$(jq '.hooks.Stop | length' .claude/settings.json)" 2
bash "$REPO/setup.sh" >/dev/null 2>&1
check_eq "entry not duplicated on re-install" "$(jq '.hooks.Stop | length' .claude/settings.json)" 2
cd / && rm -rf "$consumer"

# A hook that already existed with no entry: the snippet is printed, nothing merged.
consumer=$(mktemp -d)
cd "$consumer" || exit 1
git init -q
mkdir -p .claude/hooks .specify/memory .specify/scripts/bash
printf '# mine\n' > .claude/hooks/speckit-standards-stop.sh
out=$(bash "$REPO/setup.sh" 2>&1)
if grep -qF '"Stop"' <<<"$out"; then pass "pre-existing hook: snippet printed"; else fail "pre-existing hook: snippet printed (got: ${out:0:300})"; fi
if [[ -f .claude/settings.json ]]; then fail "pre-existing hook: settings.json left alone"; else pass "pre-existing hook: settings.json left alone"; fi
cd / && rm -rf "$consumer"

# Without jq: the hook is installed, the snippet is printed, settings.json is not written.
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
consumer=$(mktemp -d)
cd "$consumer" || exit 1
git init -q
mkdir -p .claude .specify/memory .specify/scripts/bash
shim=$(path_without_jq)
out=$(PATH="$shim" bash "$REPO/setup.sh" 2>&1); rc=$?
rm -rf "$shim"
check_eq "without jq: setup.sh exits 0" "$rc" 0
check_exec "without jq: hook still installed" .claude/hooks/speckit-standards-stop.sh
if grep -qF '"Stop"' <<<"$out"; then pass "without jq: snippet printed"; else fail "without jq: snippet printed (got: ${out:0:300})"; fi
if [[ -f .claude/settings.json ]]; then fail "without jq: settings.json not written"; else pass "without jq: settings.json not written"; fi
cd / && rm -rf "$consumer"

echo
if [[ "$failures" -eq 0 ]]; then echo "ALL TESTS PASSED"; else echo "$failures TEST(S) FAILED"; exit 1; fi
