# Standards Checks, Phase 3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the Claude Code Stop hook that sends an interactive session back once when a blocking standards finding sits in its uncommitted work, with `setup.sh` installing the hook and registering it in `.claude/settings.json` one time.

**Architecture:** One ship-source script, `scripts/speckit-standards-stop.sh`, installed to `.claude/hooks/` (overwritten). It reads the hook JSON from stdin, bails out silently on every doubt, and otherwise runs the phase 1 engine with `--working-tree --blocking-only --only lexicon,pr-shape --format hook`, printing the engine's `{"decision":"block",...}` object when the engine exits 1. `setup.sh` copies the script and, on the install that first creates it, merges the `Stop` entry with `jq`; afterwards it only reports. Tests are plain Bash sandboxes.

**Tech Stack:** Bash (must run on macOS `/bin/bash` 3.2), `jq` when present with a `sed` fallback, git. Tests in the style of `scripts/tests/test-run-gates.sh`.

**Spec:** `docs/superpowers/specs/2026-10-14-standards-checks-design.md` (section 4, the Stop-hook lines of 5.1 and 5.2, the `test-speckit-standards-stop.sh` paragraph of 5.3, and the phase 3 row of section 6). Phases 1 and 2 shipped on `9cad-feat-standards-checks` and `9cad-feat-speckit-pr`; this plan stacks on them as `9cad-feat-standards-stop-hook`.

## Global Constraints

- Ship-source only: edit `scripts/`, `scripts/tests/`, `setup.sh`, `README.md`, `templates/CLAUDE.md`, and this repo's own `.gitignore`. Never edit anything under `.specify/` or `.claude/`.
- The hook fails open: every exit code is `0`; the only output ever printed is the engine's hook JSON, and only when the engine exited `1` with non-empty output.
- The engine command is fixed: `.specify/scripts/bash/speckit-standards.sh --working-tree --blocking-only --only lexicon,pr-shape --format hook`, run from the repo root. `plain-language` is left out.
- The settings entry is exactly `{"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/speckit-standards-stop.sh", "timeout": 30}]}]}}`, merged into `.claude/settings.json` atomically (temp file, `mv`), other keys untouched, the file created when absent. It is merged only when the hook script did not exist before this run, `jq` is available, and no `Stop` command in the file already contains `speckit-standards-stop.sh`. Otherwise the snippet is printed.
- Bash 3.2: no `declare -A`, no `${var,,}`, no `read -d ''` inside `$( )`, no `mapfile`.
- Commit format: `type(scope): [9cad] description`, one logical change per commit, never push. Every commit ends with the two attribution lines the session gives.
- Quality gate before every commit: `bash .specify/quality-gates.sh` green (shellcheck at warning severity over `scripts/*.sh` and `scripts/tests/*.sh`, then every `scripts/tests/test-*.sh`).

## Review Focus

Inputs the spec implies that would hurt a person if the hook got them wrong. Each has a test in Task 1 or Task 2.

1. `stop_hook_active: true` with a blocking finding present must stay silent, or the session loops forever (Task 1, "stop_hook_active true is silent").
2. Hook JSON without `cwd` must fall back to `CLAUDE_PROJECT_DIR`, then to the current directory, so a hook run from elsewhere still finds the repo (Task 1, "no cwd falls back to CLAUDE_PROJECT_DIR").
3. Without `jq` the two keys are read with `sed`, and the block JSON is still produced; with `jq` present, malformed input is silent (Task 1, "without jq" and "malformed JSON is silent").
4. A consumer who deleted the `Stop` entry to opt out must not get it back on re-install, even though the hook script is refreshed (Task 2, "entry not re-added when the hook existed").
5. A pre-existing `.claude/settings.json` with permissions and another `Stop` hook keeps both and gains the entry once (Task 2, "existing settings preserved").

---

### Task 1: The hook script and its tests

**Files:**
- Create: `scripts/speckit-standards-stop.sh`
- Create: `scripts/tests/test-speckit-standards-stop.sh`

**Interfaces:**
- Consumes: `scripts/speckit-standards.sh` (`--working-tree --blocking-only --only lexicon,pr-shape --format hook`; exit `1` with a `{"decision":"block","reason":"..."}` line when something blocks, `0` silent when clean, `2` when it cannot run); fixtures `scripts/tests/fixtures/standards/{damage-levels.yml,lexicon.yml}` (the lexicon bans `underwrit[[:alnum:]_]*`).
- Produces: `scripts/speckit-standards-stop.sh`, which Task 2 installs; the test helper `path_without_jq`, which Task 2 copies.

- [ ] **Step 1: Write the failing tests**

Create `scripts/tests/test-speckit-standards-stop.sh`:

```bash
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash scripts/tests/test-speckit-standards-stop.sh 2>&1 | grep -c '^FAIL'`
Expected: `9` or more. Every `check_has` fails because the hook does not exist (`bash` prints an error to stderr, `out` is empty); the `check_silent` and `check_rc` checks pass by accident, which is why the block cases are the ones that prove the script.

- [ ] **Step 3: Write the hook**

Create `scripts/speckit-standards-stop.sh`:

```bash
#!/usr/bin/env bash
# Claude Code Stop hook. When an interactive session tries to finish with a
# blocking standards finding in its uncommitted work, this sends it back once
# with the reason. setup.sh installs it to .claude/hooks/ and registers it under
# "Stop" in .claude/settings.json; delete that entry to opt out.
#
# Fails open: every exit is 0, and anything unexpected means no opinion, never a
# stuck session. Only the last step prints.
set -u

input=$(cat 2>/dev/null) || exit 0
[ -n "$input" ] || exit 0

# The two keys this hook reads: jq when it is installed (input it cannot parse
# is no opinion), else sed on each key.
if command -v jq >/dev/null 2>&1; then
  parsed=$(printf '%s' "$input" | jq -r '[(.cwd // ""), (.stop_hook_active // false | tostring)] | join("\n")' 2>/dev/null) || exit 0
  cwd=${parsed%%$'\n'*}
  active=${parsed#*$'\n'}
else
  cwd=$(printf '%s' "$input" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
  active=$(printf '%s' "$input" | sed -n 's/.*"stop_hook_active"[[:space:]]*:[[:space:]]*\([a-z]*\).*/\1/p' | head -n 1)
fi

# Claude is already continuing because of this hook. Never loop.
[ "$active" != true ] || exit 0

for dir in "$cwd" "${CLAUDE_PROJECT_DIR:-}" .; do
  [ -n "$dir" ] || continue
  if cd "$dir" 2>/dev/null; then break; fi
done
root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$root" 2>/dev/null || exit 0

engine=.specify/scripts/bash/speckit-standards.sh
[ -x "$engine" ] || exit 0
[ -n "$(git status --porcelain --untracked-files=all 2>/dev/null)" ] || exit 0

# plain-language is advice and the slow group; the blocking rules live in
# lexicon and pr-shape.
out=$(bash "$engine" --working-tree --blocking-only --only lexicon,pr-shape --format hook 2>/dev/null)
rc=$?
if [ "$rc" -eq 1 ] && [ -n "$out" ]; then
  printf '%s\n' "$out"
fi
exit 0
```

Then `chmod +x scripts/speckit-standards-stop.sh`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash scripts/tests/test-speckit-standards-stop.sh 2>&1 | tail -n 3`
Expected: `ALL TESTS PASSED`.

- [ ] **Step 5: Run the hook under macOS bash 3.2**

Run: `/bin/bash scripts/tests/test-speckit-standards-stop.sh 2>&1 | tail -n 1`
Expected: `ALL TESTS PASSED` (the test and the hook both run under `/bin/bash` 3.2 because `bash` inside the test resolves through `PATH`; this step pins the test file itself. Also run the hook directly: `printf '{"cwd":"/","stop_hook_active":false}' | /bin/bash scripts/speckit-standards-stop.sh; echo rc=$?` prints only `rc=0`.)

- [ ] **Step 6: Run the quality gate and commit**

Run: `bash .specify/quality-gates.sh 2>&1 | tail -n 3`
Expected: exit 0.

```bash
git add scripts/speckit-standards-stop.sh scripts/tests/test-speckit-standards-stop.sh
git commit -m "feat(standards): [9cad] Stop hook sends a session back when a standards check blocks its uncommitted work"
```

---

### Task 2: `setup.sh` installs the hook and registers it once

**Files:**
- Modify: `setup.sh` (after the `echo "    .specify/scripts/bash/speckit-standards.sh"` line, about line 259)
- Modify: `scripts/tests/test-setup-standards.sh`
- Modify: `.gitignore` (this repo's own; after the `.claude/skills/` line)

**Interfaces:**
- Consumes: `scripts/speckit-standards-stop.sh` from Task 1; the `path_without_jq` helper from Task 1's test (copied, not sourced).
- Produces: the installed hook at `.claude/hooks/speckit-standards-stop.sh` and the `Stop` entry in `.claude/settings.json`.

- [ ] **Step 1: Write the failing tests**

In `scripts/tests/test-setup-standards.sh`, add after the `check_file "lexicon seeded" ...` line:

```bash
check_exec "stop hook installed and executable" .claude/hooks/speckit-standards-stop.sh
check_eq "stop hook registered once" "$(jq '.hooks.Stop | length' .claude/settings.json 2>/dev/null)" 1
check_eq "stop hook command" "$(jq -r '.hooks.Stop[0].hooks[0].command' .claude/settings.json 2>/dev/null)" '$CLAUDE_PROJECT_DIR/.claude/hooks/speckit-standards-stop.sh'
check_eq "stop hook timeout" "$(jq '.hooks.Stop[0].hooks[0].timeout' .claude/settings.json 2>/dev/null)" 30
```

After the `printf '# old engine\n' > .specify/scripts/bash/speckit-standards.sh` line, add:

```bash
printf '# old hook\n' > .claude/hooks/speckit-standards-stop.sh
jq 'del(.hooks)' .claude/settings.json > settings.tmp && mv settings.tmp .claude/settings.json   # the consumer opted out
```

After the `check_eq "engine refreshed on re-install" ...` line, add:

```bash
check_eq "hook refreshed on re-install" "$(head -n 1 .claude/hooks/speckit-standards-stop.sh)" "#!/usr/bin/env bash"
check_eq "entry not re-added when the hook existed" "$(jq '.hooks.Stop // [] | length' .claude/settings.json)" 0
```

Before the final `echo` / summary block, add three sandboxes:

```bash
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash scripts/tests/test-setup-standards.sh 2>&1 | grep -c '^FAIL'`
Expected: `14` or more (every new check except "settings.json left alone" and "settings.json not written", which pass before the feature exists).

- [ ] **Step 3: Add the hook install and the settings merge to `setup.sh`**

After the line `echo "    .specify/scripts/bash/speckit-standards.sh"`, insert:

```bash

# ── 2a. Stop hook ───────────────────────────────────────────────────
# The hook script is framework code (Pattern A: OVERWRITE). Its Stop entry in
# .claude/settings.json is merged once, on the install that first creates the
# script, so a consumer who deletes the entry has opted out for good.
HOOK_REL=".claude/hooks/speckit-standards-stop.sh"
HOOK_DEST="$PROJECT_DIR/$HOOK_REL"
HOOK_CMD='$CLAUDE_PROJECT_DIR/.claude/hooks/speckit-standards-stop.sh'
PROJECT_SETTINGS="$PROJECT_DIR/.claude/settings.json"
hook_existed=false
[[ -f "$HOOK_DEST" ]] && hook_existed=true
mkdir -p "$PROJECT_DIR/.claude/hooks"
cp "$SCRIPT_DIR/scripts/speckit-standards-stop.sh" "$HOOK_DEST"
chmod +x "$HOOK_DEST"
echo "    $HOOK_REL"

print_hook_snippet() {
  echo "  To be sent back when a standards check blocks uncommitted work, add this Stop hook to .claude/settings.json:"
  echo '    {"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/speckit-standards-stop.sh", "timeout": 30}]}]}}'
}

if [[ -f "$PROJECT_SETTINGS" ]] && grep -qF 'speckit-standards-stop.sh' "$PROJECT_SETTINGS"; then
  echo "  Stop hook already registered in .claude/settings.json"
elif ! $hook_existed && command -v jq &>/dev/null; then
  [[ -f "$PROJECT_SETTINGS" ]] || echo '{}' > "$PROJECT_SETTINGS"
  tmp=$(mktemp)
  if jq --arg cmd "$HOOK_CMD" '.hooks.Stop = ((.hooks.Stop // []) + [{hooks: [{type: "command", command: $cmd, timeout: 30}]}])' "$PROJECT_SETTINGS" > "$tmp" 2>/dev/null; then
    mv "$tmp" "$PROJECT_SETTINGS"
    echo "  Registered the Stop hook in .claude/settings.json"
  else
    rm -f "$tmp"
    print_hook_snippet
  fi
else
  print_hook_snippet
fi
```

- [ ] **Step 4: Ignore the dogfood copy in this repo**

In `.gitignore`, after the `.claude/skills/` line, add `.claude/hooks/` (a `setup.sh --self` run writes the hook there, and installed copies are never committed in this repo).

- [ ] **Step 5: Run the test to verify it passes**

Run: `bash scripts/tests/test-setup-standards.sh 2>&1 | tail -n 3`
Expected: `ALL TESTS PASSED`.

- [ ] **Step 6: Run the quality gate and commit**

Run: `bash .specify/quality-gates.sh 2>&1 | tail -n 3`
Expected: exit 0.

```bash
git add setup.sh scripts/tests/test-setup-standards.sh .gitignore
git commit -m "feat(setup): [9cad] install the Stop hook and register it in settings.json once"
```

---

### Task 3: Documentation

**Files:**
- Modify: `README.md` (install table, line 108 area; `### Standards checks`, after the `Run it yourself` block's closing paragraph)
- Modify: `templates/CLAUDE.md:55`

**Interfaces:**
- Consumes: the hook and the settings entry from Tasks 1 and 2.
- Produces: nothing.

- [ ] **Step 1: README install table**

After the row for `specify-marge/config/damage-levels.yml`, add:

```markdown
| `scripts/speckit-standards-stop.sh` | `.claude/hooks/` | overwritten (the Stop hook); its `Stop` entry in `.claude/settings.json` is added once — delete the entry to opt out |
```

- [ ] **Step 2: README standards section**

After the paragraph that begins `Exit 0 is clean or advice, 1 means a finding blocks`, add:

```markdown
**Stop hook.** `setup.sh` installs `.claude/hooks/speckit-standards-stop.sh` and, on the install that first creates it, registers it under `Stop` in `.claude/settings.json` (with `jq`; without `jq` it prints the entry for you to add). When an interactive session tries to finish with a blocking finding in its uncommitted work — a banned word, a new spec without its plain summary — the hook sends the session back once with the reason. It runs only the `lexicon` and `pr-shape` groups, so advice never interrupts anyone, and it fails open: any error means no opinion. Delete the `Stop` entry to opt out; `setup.sh` never adds it again.
```

- [ ] **Step 3: templates/CLAUDE.md**

Line 55 ends `` `/speckit-pr` writes the pull request description with the level and its checklist ``. Append:

```markdown
; the Stop hook (`.claude/hooks/speckit-standards-stop.sh`) sends an interactive session back once when a blocking finding sits in its uncommitted work
```

- [ ] **Step 4: Run the quality gate and commit**

Run: `bash .specify/quality-gates.sh 2>&1 | tail -n 3`
Expected: exit 0.

```bash
git add README.md templates/CLAUDE.md
git commit -m "docs(standards): [9cad] document the Stop hook"
```
