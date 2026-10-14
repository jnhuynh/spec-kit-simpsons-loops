# Standards Checks, Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a Bash engine that reports a change's damage level and its standards findings (PR shape, plain language, lexicon), wired into Marge and Lisa as a baseline script pack, installed and seeded by `setup.sh`.

**Architecture:** One script, `scripts/speckit-standards.sh`, reads two YAML config files through an awk flattener, builds a change set from git, extracts the prose a person reads, and runs each rule as a small awk program over that data. Findings go to a TSV file and are rendered as text, Marge YAML, or Stop-hook JSON. A seeded wrapper `baseline/standards.sh` calls the engine from `run-gates.sh`, which learns to run `baseline/*.sh`.

**Tech Stack:** Bash 4, awk (BSD and GNU), grep, sed, git, iconv. No Ruby, Python, jq, or yq. Tests are plain Bash in the style of `scripts/tests/test-speckit-commit.sh`.

**Spec:** `docs/superpowers/specs/2026-10-14-standards-checks-design.md` (sections 1, 2, 5, and the phase 1 row of section 6). Phases 2 and 3 get their own plans after this one ships.

## Global Constraints

- Ship-source only: edit `scripts/`, `specify-marge/`, `speckit-skills/`, `claude-agents/`, `templates/`, `setup.sh`, `README.md`. Never edit anything under `.specify/` or `.claude/` except this repo's own `.specify/quality-gates.sh`.
- Bash 4 and standard Unix utilities only. Every awk program must run on macOS awk (version 20200816) and GNU awk: no `gensub`, no `IGNORECASE`, no `match(s, r, arr)`, no `\s`, no `{n,m}` intervals.
- Exit codes are the contract: `0` clean or advice, `1` a finding blocks, `2` the engine could not run.
- Rule names, severities, and blocking are fixed by the spec's rule table (section 1.3). Finding `pack:` is always `baseline/standards.sh`. Findings never carry `PROJECT_GATE`.
- Config file names are `.specify/marge/config/damage-levels.yml` and `.specify/marge/config/lexicon.yml`. Absent `damage-levels.yml` means print nothing and exit 0.
- Patterns in `lexicon.yml` are POSIX ERE matched against the lowercased line; the engine adds word-boundary guards. Globs in `damage-levels.yml`: `*` stops at `/`, `**` crosses directories.
- Commit format: `type(scope): [9cad] description`, one logical change per commit, never push. Every commit ends with the two attribution lines the session gives.
- Quality gate before every commit: `bash .specify/quality-gates.sh` (shellcheck at warning severity) and `bash scripts/tests/test-speckit-standards.sh` both green.

## Review Focus

Inputs the spec implies but no rule test would otherwise exercise. Each has a test in the task named.

1. A changed path containing a space or a UTF-8 character must flow through `files.tsv`, the damage level, and the text output unchanged (Task 3 tests `collect_change_set` with `app/services/naïve dir/x.rb`).
2. An added Markdown line inside a code fence that was opened *before* the diff (the fence is unchanged context) must not be treated as prose (Task 3, "fence opened in context").
3. A `--body-file` whose ids sit inside inline code or a URL must not block; the same id as prose must (Task 5).
4. A lexicon pattern that matches a word at the very start or very end of a line must still be found, and a pattern that would match inside a longer word must not (Task 8, "boundaries").
5. A `damage-levels.yml` with a `default_level` that names no level, or an unsupported YAML construct, must exit 2 with the file and line, never produce a verdict (Task 2 and Task 4).

---

### Task 1: Test harness, fixtures, and the engine skeleton

**Files:**
- Create: `scripts/speckit-standards.sh`
- Create: `scripts/tests/test-speckit-standards.sh`
- Create: `scripts/tests/fixtures/standards/damage-levels.yml`
- Create: `scripts/tests/fixtures/standards/lexicon.yml`

**Interfaces:**
- Produces: the CLI (`parse_args`), the globals `MODE`, `BASE_REF`, `DIR`, `BODY_FILE`, `ONLY`, `BLOCKING_ONLY`, `FORMAT`, `WORK`, the helpers `fail_to_run`, `usage`, `want GROUP`, and stub functions `yaml_flatten`, `collect_change_set`, `collect_prose`, `assess_damage`, `run_rules`, `render` that later tasks replace. The script can be sourced: `main` runs only when executed.
- Produces for tests: `make_repo fixtures|seeds|none`, `cleanup`, `engine ARGS...` (sets `out` and `rc`), `check_eq`, `check_rc`, `check_has`, `check_lacks`, `pass`, `fail`.

- [ ] **Step 1: Write the fixtures**

`scripts/tests/fixtures/standards/damage-levels.yml`:

```yaml
# Fixture: a condensed copy of Reset's damage-levels.yml, keeping every YAML
# feature the parser must handle: folded scalars, path-scoped questions,
# quoted globs, comments between list items, blank lines.
default_level: member-facing

aliases:
  - from: app/jobs/
    to: app/services/

unit_dirs:
  - app/services/*
  - app/models/*.rb

boundaries:
  - app/services/reset_*/**
  - app/jobs/reset_*/**

levels:
  - name: money and trust
    reviewer: >-
      Read every line. Work the checklist.
    checklist:
      - What happens if this runs twice?
      - What happens if it fails halfway through?
      - question: >-
          Who can reach this? Can a secret, a card number or personal data end
          up in a log, a response or an unencrypted column?
        paths:
          # Sign-in, sessions, and who may act.
          - app/policies/**/*
          - app/models/user.rb
      - question: Does this change what a member is told or agrees to?
        paths:
          - app/views/static_pages/*_agreement.html.erb
    paths:
      - app/services/repayment_instances/**/*
      - app/services/risk_assessments/**/*
      - app/services/reset_synctera/**/*
      - db/migrate/**/*
      - app/models/partner.rb

  - name: member-facing
    reviewer: >-
      Read every hunk. Confirm the author's screenshot or live check.
    checklist:
      - Does the screenshot or live check match what the code does?
    paths:
      - app/services/**/*
      - app/jobs/**/*
      - app/models/**/*
      - app/views/**/*

  - name: specification
    reviewer: >-
      Read all of it. This is the feature. Send it back if a sentence needs
      decoding.
    checklist:
      - Can you say in two sentences what a member gets when this ships?
    paths:
      - specs/**/*

  - name: internal
    reviewer: Skim. Look closely at the one hunk the author flagged.
    checklist:
      - Does the flagged hunk do what the description says?
    paths:
      - app/services/notifications/**/*
      - script/**/*
      - lib/**/*
      - config/**/*
      - .specify/**/*
      - ".*"
      - "*.yml"
      - Procfile*

  - name: no runtime effect
    reviewer: >-
      Approve. Nobody is expected to read this line by line.
    checklist: []
    paths:
      - docs/**/*
      - spec/**/*
      - "**/*.md"
```

`scripts/tests/fixtures/standards/lexicon.yml`:

```yaml
# Fixture: a condensed copy of Reset's lexicon.yml in the shipped ERE dialect.
banned:
  - pattern: 'underwrit[[:alnum:]_]*'
    use: risk assessment
    why: Reset does not do this.
  - pattern: 'borrowers?'
    use: member

prefer:
  - pattern: 'consumers?'
    use: member
    why: >-
      Vendor-speak for the person using Reset. Warns, not blocks, because the
      word has other senses.
    unless:
      - 'to-consumer'
      - 'consumer (product|app|codebase|side|flow)'
  - pattern: 'customers?'
    use: member
  - pattern: 'compensation'
    use: income

soft_verbs:
  - pattern: 'utili[sz][[:alnum:]_]+'
    use: use
  - pattern: 'leverag[[:alnum:]_]+'
    use: use
  - pattern: 'ensur[[:alnum:]_]+'
    use: check, make sure
  - pattern: 'surfac(e|es|ed|ing) (the|a|an|to|it|them|this|that)'
    use: show

invented_phrases:
  nouns: [seam, surface, layer, boundary, mechanism, harness, lever, facade]
  compound_suffixes: [neutral, agnostic, aware, driven]
  allowed:
    - test harness
    - attack surface

exempt_paths:
  - docs/standards/lexicon.md
  - .specify/marge/config/lexicon.yml

known_terms:
  - Jack Henry
  - User Story
  - Success Criteria
  - Plain Summary
  - Eastern Time
```

- [ ] **Step 2: Write the test harness with the first four cases**

`scripts/tests/test-speckit-standards.sh`:

```bash
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

echo
if [[ "$failures" -eq 0 ]]; then
  echo "ALL TESTS PASSED"
else
  echo "$failures TEST(S) FAILED"
  exit 1
fi
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `bash scripts/tests/test-speckit-standards.sh`
Expected: every case `FAIL` (the engine does not exist; `bash` exits 127), ending with `TEST(S) FAILED`.

- [ ] **Step 4: Write the engine skeleton**

`scripts/speckit-standards.sh`:

```bash
#!/usr/bin/env bash
# speckit-standards.sh — deterministic standards checks over a change set:
# damage level, PR shape, plain language, lexicon.
#
#   speckit-standards.sh --base origin/main                      # Marge, /speckit-pr: the branch diff
#   speckit-standards.sh --working-tree                          # the Stop hook: uncommitted work
#   speckit-standards.sh --dir specs/1a2b-feat-x                 # Lisa: what the branch changed under a spec dir
#   speckit-standards.sh --base origin/main --body-file body.md  # the branch and a draft description
#
# Exit 0 clean or advice only, 1 a finding blocks, 2 the engine could not run.
# Config: .specify/marge/config/damage-levels.yml (required; absent = silent exit 0)
# and .specify/marge/config/lexicon.yml (absent = lexicon rules skipped).
# Rules and config format: README.md "Standards checks". Pack contract: .specify/marge/README.md.
set -uo pipefail

CONFIG_DIR=".specify/marge/config"
PACK_LABEL="baseline/standards.sh"
ALL_GROUPS="lexicon plain-language pr-shape unrated-path"
MAX_WORDS=25
MAX_COMMENT_LINES=4
SUMMARY_MAX_WORDS=150
MAX_HOOK_REASONS=8
TAB=$'\t'

MODE=""
BASE_REF=""
DIR=""
BODY_FILE=""
ONLY="$ALL_GROUPS"
BLOCKING_ONLY=0
FORMAT=text
WORK=""

usage() {
  cat >&2 <<'EOF'
usage: speckit-standards.sh (--base REF | --working-tree | --dir PATH [--base REF])
                            [--body-file FILE] [--only GROUP[,GROUP...]]
                            [--blocking-only] [--format text|marge|hook]
groups: lexicon, plain-language, pr-shape, unrated-path
EOF
  exit 2
}

fail_to_run() { echo "speckit-standards: $*" >&2; exit 2; }

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --base) [[ $# -ge 2 ]] || usage; BASE_REF="$2"; [[ -n "$MODE" ]] || MODE=base; shift 2 ;;
      --working-tree) MODE=working-tree; shift ;;
      --dir) [[ $# -ge 2 ]] || usage; DIR="${2%/}"; MODE=dir; shift 2 ;;
      --body-file) [[ $# -ge 2 ]] || usage; BODY_FILE="$2"; shift 2 ;;
      --only) [[ $# -ge 2 ]] || usage; ONLY="${2//,/ }"; shift 2 ;;
      --blocking-only) BLOCKING_ONLY=1; shift ;;
      --format) [[ $# -ge 2 ]] || usage; FORMAT="$2"; shift 2 ;;
      *) usage ;;
    esac
  done
  [[ -n "$MODE" ]] || usage
  case "$FORMAT" in text|marge|hook) ;; *) usage ;; esac
  local group
  for group in $ONLY; do
    [[ " $ALL_GROUPS " == *" $group "* ]] || fail_to_run "unknown group: $group (choose from ${ALL_GROUPS// /, })"
  done
  [[ -z "$BODY_FILE" || -r "$BODY_FILE" ]] || fail_to_run "cannot read body file: $BODY_FILE"
}

want() { [[ " $ONLY " == *" $1 "* ]]; }

# ── Stubs replaced by later tasks ──────────────────────────────────────────
yaml_flatten() { :; }
collect_change_set() { :; }
collect_prose() { :; }
assess_damage() { :; }
run_rules() { :; }
render() { [[ "$FORMAT" == text ]] && echo "No findings."; exit 0; }

main() {
  parse_args "$@"
  local root
  root=$(git rev-parse --show-toplevel 2>/dev/null) || fail_to_run "not inside a git work tree"
  cd "$root" || fail_to_run "cannot enter $root"
  [[ -f "$CONFIG_DIR/damage-levels.yml" ]] || exit 0
  WORK=$(mktemp -d) || fail_to_run "mktemp failed"
  trap 'rm -rf "$WORK"' EXIT
  yaml_flatten "$CONFIG_DIR/damage-levels.yml" > "$WORK/dl.tsv" || exit 2
  if [[ -f "$CONFIG_DIR/lexicon.yml" ]]; then
    yaml_flatten "$CONFIG_DIR/lexicon.yml" > "$WORK/lx.tsv" || exit 2
  fi
  : > "$WORK/findings.tsv"
  collect_change_set
  collect_prose
  assess_damage
  run_rules
  render
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bash scripts/tests/test-speckit-standards.sh`
Expected: `ALL TESTS PASSED`.

Run: `shellcheck --severity=warning scripts/speckit-standards.sh scripts/tests/test-speckit-standards.sh`
Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add scripts/speckit-standards.sh scripts/tests/test-speckit-standards.sh scripts/tests/fixtures/standards/
git commit -m "feat(standards): [9cad] engine skeleton, CLI, and test harness"
```

---

### Task 2: YAML flattener

**Files:**
- Modify: `scripts/speckit-standards.sh` (replace the `yaml_flatten` stub)
- Test: `scripts/tests/test-speckit-standards.sh`

**Interfaces:**
- Produces: `yaml_flatten FILE` prints one `keypath<TAB>value` line per scalar, where a sequence item's key path ends in its zero-based index (`levels.0.checklist.2.paths.1`). Exit 2 with `FILE:LINE: unsupported YAML: reason` on stderr for anything outside the subset. Also `cfg_get FLAT KEY` (one scalar) and `cfg_list FLAT PREFIX` (the values `PREFIX.0`, `PREFIX.1`, ... in order).

- [ ] **Step 1: Add the failing tests**

Insert before the `echo` / `ALL TESTS PASSED` block:

```bash
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash scripts/tests/test-speckit-standards.sh 2>&1 | grep -c FAIL`
Expected: a number above 20 (every Task 2 case fails: the stub prints nothing and `cfg_get` does not exist).

- [ ] **Step 3: Replace the `yaml_flatten` stub**

Delete the line `yaml_flatten() { :; }` and put this in its place:

```bash
# ── YAML subset → "keypath<TAB>value" ──────────────────────────────────────
# Two-space indentation; `key: value`, `key:` with a nested block, `- item`,
# `- key: value` opening a mapping; plain, 'single', "double" or >- folded
# scalars; inline lists [a, b]; # comments. Anything else exits 2.
AWK_FLATTEN=$(cat <<'AWK'
function die(msg) { printf("%s:%d: unsupported YAML: %s\n", FILENAME, FNR, msg) > "/dev/stderr"; exit 2 }
function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
function joinpath(a, b) { return (a == "" ? b : a "." b) }
function unquote(s) {
  s = trim(s)
  if (s ~ /^"/) {
    if (s !~ /"[[:space:]]*(#.*)?$/) die("unterminated double quote")
    sub(/^"/, "", s); sub(/"[[:space:]]*(#.*)?$/, "", s)
    gsub(/\\"/, "\"", s); gsub(/\\\\/, "\\", s)
    return s
  }
  if (s ~ /^'/) {
    if (s !~ /'[[:space:]]*(#.*)?$/) die("unterminated single quote")
    sub(/^'/, "", s); sub(/'[[:space:]]*(#.*)?$/, "", s)
    gsub(/''/, "'", s)
    return s
  }
  sub(/[[:space:]]+#.*$/, "", s)
  return trim(s)
}
function emit_list(keypath, text,   inner, parts, k, m) {
  inner = trim(text); sub(/^\[/, "", inner); sub(/\][[:space:]]*(#.*)?$/, "", inner)
  if (trim(inner) == "") return
  m = split(inner, parts, ",")
  for (k = 1; k <= m; k++) print keypath "." (k - 1) "\t" unquote(parts[k])
}
function handle_key(text, col,   key, rest) {
  key = text; sub(/:.*$/, "", key)
  rest = text; sub(/^[^:]*:/, "", rest); rest = trim(rest)
  pend[depth] = ""
  if (rest == "") { pend[depth] = key; return }
  if (rest == ">-" || rest == ">") { folding = joinpath(path[depth], key); foldind = col; foldbuf = ""; return }
  if (rest ~ /^[|]/) die("literal block scalars are not supported")
  if (rest ~ /^\[/) { emit_list(joinpath(path[depth], key), rest); return }
  if (rest ~ /^[{&*]/) die("flow mappings, anchors and aliases are not supported")
  print joinpath(path[depth], key) "\t" unquote(rest)
}
BEGIN { depth = 0; ind[0] = 0; path[0] = ""; kind[0] = "m"; pend[0] = ""; folding = "" }
{
  line = $0
  if (line ~ /^[[:space:]]*\t/) die("tab indentation")
  if (folding != "") {
    if (line ~ /^[[:space:]]*$/) next
    n = match(line, /[^ ]/) - 1
    if (n > foldind) { foldbuf = (foldbuf == "" ? trim(line) : foldbuf " " trim(line)); next }
    print folding "\t" foldbuf; folding = ""; foldbuf = ""
  }
  if (line ~ /^[[:space:]]*$/ || line ~ /^[[:space:]]*#/) next
  n = match(line, /[^ ]/) - 1
  rest = substr(line, n + 1)
  if (rest ~ /^- / || rest == "-") {
    while (ind[depth] > n) depth--
    if (!(kind[depth] == "s" && ind[depth] == n)) {
      if (kind[depth] != "m" || pend[depth] == "" || ind[depth] > n) die("sequence item without a key")
      depth++; ind[depth] = n; kind[depth] = "s"; path[depth] = joinpath(path[depth-1], pend[depth-1]); pend[depth] = ""
      pend[depth-1] = ""; count[path[depth]] = 0
    }
    item = trim(substr(rest, 3))
    i = count[path[depth]]++
    itempath = path[depth] "." i
    if (item ~ /^[A-Za-z_][A-Za-z0-9_-]*:([[:space:]]|$)/) {
      depth++; ind[depth] = n + 2; kind[depth] = "m"; path[depth] = itempath; pend[depth] = ""
      handle_key(item, n + 2)
    } else if (item ~ /^\[/) {
      emit_list(itempath, item)
    } else {
      print itempath "\t" unquote(item)
    }
    next
  }
  if (rest ~ /^[A-Za-z_][A-Za-z0-9_-]*:([[:space:]]|$)/) {
    while (ind[depth] > n || (ind[depth] == n && kind[depth] == "s")) depth--
    if (kind[depth] != "m") die("key inside a sequence")
    if (ind[depth] < n) {
      if (pend[depth] == "") die("bad indentation")
      depth++; ind[depth] = n; kind[depth] = "m"; path[depth] = joinpath(path[depth-1], pend[depth-1]); pend[depth] = ""
      pend[depth-1] = ""
    } else if (ind[depth] != n) die("bad indentation")
    handle_key(rest, n)
    next
  }
  die("unrecognized line")
}
END { if (folding != "") print folding "\t" foldbuf }
AWK
)

yaml_flatten() { awk "$AWK_FLATTEN" "$1"; }

# cfg_get FLAT KEY → the scalar at KEY; cfg_list FLAT PREFIX → PREFIX.0, PREFIX.1, ... in order.
cfg_get() { awk -F'\t' -v k="$2" '$1 == k { print substr($0, length($1) + 2); exit }' "$1"; }
cfg_list() {
  awk -F'\t' -v p="$2" 'index($1, p ".") == 1 && substr($1, length(p) + 2) ~ /^[0-9]+$/ { print substr($0, length($1) + 2) }' "$1"
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash scripts/tests/test-speckit-standards.sh`
Expected: `ALL TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add scripts/speckit-standards.sh scripts/tests/test-speckit-standards.sh
git commit -m "feat(standards): [9cad] YAML subset flattener"
```

---

### Task 3: Change set and prose extraction

**Files:**
- Modify: `scripts/speckit-standards.sh` (replace the `collect_change_set` and `collect_prose` stubs)
- Test: `scripts/tests/test-speckit-standards.sh`

**Interfaces:**
- Produces: `$WORK/files.tsv` (`path<TAB>status<TAB>kind`, status one of `A M D R`, kind one of `prose comment none`), `$WORK/added.tsv` (`path<TAB>line<TAB>text` for every added line), `$WORK/prose.tsv` (same shape, only the lines a person reads, comment prefixes stripped), and `prose_of PATH` printing `line<TAB>text` for one file. Uses the globals `MODE`, `BASE_REF`, `DIR`, `WORK`.

- [ ] **Step 1: Add the failing tests**

Insert before the `echo` / `ALL TESTS PASSED` block:

```bash
# ── Task 3: change set and prose ────────────────────────────────────────────

# Drive the collectors directly: the engine is sourced, so set its globals.
make_repo fixtures
git checkout -q main
mkdir -p "app/services/naïve dir" docs
printf 'old\n' > "app/services/naïve dir/x.rb"
printf 'x1\nx2\nx3\nx4\nx5\nx6\nx7\nx8\nx9\nx10\n' > old.rb
printf 'Intro.\n\n```\nfenced before\n' > docs/open.md
commit_all "seed"
git checkout -q work
git merge -q main
printf 'base\nB1\nB2\n' > base.txt
git mv old.rb new.rb
printf 'x1\n# why one\n# why two\nx2\nx3\nx4\nx5\nx6\nx7\nx8\nx9\nx10\n' > new.rb
printf 'new\n' > "app/services/naïve dir/x.rb"
printf 'Intro.\n\n```\nfenced before\nadded inside fence\n```\nAfter `code` and https://x.y/z link.\n' > docs/open.md
printf '# Spec\n\nText `code` here.\n\n```sh\necho inside fence\n```\nTail.\n' > spec.md
commit_all "work"
WORK=$(mktemp -d); MODE=base; BASE_REF=main
collect_change_set
check_has "modified file listed" "$(cat "$WORK/files.tsv")" "base.txt${TAB}M${TAB}none"
check_has "rename keeps the new path" "$(cat "$WORK/files.tsv")" "new.rb${TAB}R${TAB}comment"
check_has "unicode and space path survive" "$(cat "$WORK/files.tsv")" "app/services/naïve dir/x.rb${TAB}M${TAB}comment"
check_has "markdown is prose" "$(cat "$WORK/files.tsv")" "spec.md${TAB}A${TAB}prose"
check_has "added line numbered from the hunk" "$(cat "$WORK/added.tsv")" "base.txt${TAB}2${TAB}B1"
check_has "second added line follows" "$(cat "$WORK/added.tsv")" "base.txt${TAB}3${TAB}B2"
check_has "rename contributes only its added lines" "$(cat "$WORK/added.tsv")" "new.rb${TAB}2${TAB}# why one"
check_lacks "unchanged rename line not added" "$(cat "$WORK/added.tsv")" "new.rb${TAB}1${TAB}x1"
collect_prose
check_has "comment prefix stripped" "$(cat "$WORK/prose.tsv")" "new.rb${TAB}3${TAB}why two"
check_lacks "code line is not prose" "$(cat "$WORK/prose.tsv")" "new.rb${TAB}4"
check_has "markdown outside fences is prose" "$(cat "$WORK/prose.tsv")" "spec.md${TAB}3${TAB}Text \`code\` here."
check_lacks "fenced markdown is not prose" "$(cat "$WORK/prose.tsv")" "echo inside fence"
check_lacks "fence opened in context still fences" "$(cat "$WORK/prose.tsv")" "added inside fence"
check_has "line after the fence closes is prose" "$(cat "$WORK/prose.tsv")" "docs/open.md${TAB}7${TAB}After"
check_eq "prose_of prints one file" "$(prose_of new.rb | paste -sd'|' -)" "2${TAB}why one|3${TAB}why two"
rm -rf "$WORK"; cleanup

make_repo fixtures
printf 'untracked prose line.\n' > notes.md
printf '\x00\x01\x02' > blob.bin
printf 'base\nmore\n' > base.txt
WORK=$(mktemp -d); MODE=working-tree; BASE_REF=""
collect_change_set
check_has "working tree sees the uncommitted edit" "$(cat "$WORK/added.tsv")" "base.txt${TAB}2${TAB}more"
check_has "untracked file is added" "$(cat "$WORK/files.tsv")" "notes.md${TAB}A${TAB}prose"
check_has "untracked lines all added" "$(cat "$WORK/added.tsv")" "notes.md${TAB}1${TAB}untracked prose line."
check_has "binary untracked file keeps its path" "$(cat "$WORK/files.tsv")" "blob.bin${TAB}A${TAB}none"
check_lacks "binary untracked file carries no lines" "$(cat "$WORK/added.tsv")" "blob.bin"
rm -rf "$WORK"
mkdir -p specs/9cad-feat-x
printf '# Spec\n' > specs/9cad-feat-x/spec.md
WORK=$(mktemp -d); MODE=dir; DIR=specs/9cad-feat-x; BASE_REF=main
collect_change_set
check_has "dir mode sees the untracked spec" "$(cat "$WORK/files.tsv")" "specs/9cad-feat-x/spec.md${TAB}A${TAB}prose"
check_lacks "dir mode ignores files outside the dir" "$(cat "$WORK/files.tsv")" "base.txt"
rm -rf "$WORK"; cleanup
MODE=""; DIR=""; BASE_REF=""
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash scripts/tests/test-speckit-standards.sh 2>&1 | grep -c FAIL`
Expected: a number above 20.

- [ ] **Step 3: Replace the `collect_change_set` and `collect_prose` stubs**

Delete the two lines `collect_change_set() { :; }` and `collect_prose() { :; }` and put this in their place:

```bash
# ── Change set ─────────────────────────────────────────────────────────────
# git diff -U0 -M on stdin → "path<TAB>line<TAB>text" for every added line.
AWK_DIFF_ADDED=$(cat <<'AWK'
/^diff --git / { path = ""; inhunk = 0; next }
/^\+\+\+ / { if ($0 !~ /^\+\+\+ \/dev\/null/) path = substr($0, 7); next }
/^--- / { next }
/^@@ / { match($0, /\+[0-9]+/); cur = substr($0, RSTART + 1, RLENGTH - 1) + 0; inhunk = 1; next }
/^Binary files / { next }
/^\\ No newline/ { next }
inhunk && /^\+/ { if (path != "") print path "\t" cur "\t" substr($0, 2); cur++; next }
inhunk && /^-/ { next }
AWK
)

# prose | comment | none, by extension.
kind_of() {
  case "${1##*.}" in
    md|markdown|txt) echo prose ;;
    rb|rake|py|sh|bash|zsh|yml|yaml|toml|ts|tsx|js|jsx|mjs|cjs|go|rs|java|kt|swift|c|h|cc|cpp|cs|scala) echo comment ;;
    *) echo none ;;
  esac
}

comment_prefix() {
  case "${1##*.}" in
    rb|rake|py|sh|bash|zsh|yml|yaml|toml) echo '^[[:space:]]*#[[:space:]]?' ;;
    *) echo '^[[:space:]]*//[[:space:]]?' ;;
  esac
}

# A file the engine may read line by line: known kind, on disk, at most 1 MB, valid UTF-8.
readable_text() {
  [[ "$(kind_of "$1")" != none && -f "$1" ]] || return 1
  [[ $(( $(wc -c < "$1") )) -le 1000000 ]] || return 1
  iconv -f UTF-8 -t UTF-8 "$1" >/dev/null 2>&1
}

merge_base() { git merge-base "${BASE_REF:-origin/main}" HEAD 2>/dev/null || echo HEAD; }

# Writes $WORK/files.tsv (path, status, kind) and $WORK/added.tsv (path, line, text).
collect_change_set() {
  local -a diff_args
  case "$MODE" in
    base) diff_args=("$BASE_REF...HEAD") ;;
    working-tree) diff_args=(HEAD) ;;
    dir) diff_args=("$(merge_base)" -- "$DIR") ;;
  esac
  git -c core.quotePath=false diff --name-status -M "${diff_args[@]}" > "$WORK/name-status.txt" 2>"$WORK/git-err.txt" \
    || fail_to_run "git diff failed: $(tail -n 1 "$WORK/git-err.txt")"
  : > "$WORK/files.tsv"
  local status p1 p2 path
  while IFS="$TAB" read -r status p1 p2; do
    [[ -n "$status" ]] || continue
    path="${p2:-$p1}"
    printf '%s\t%s\t%s\n' "$path" "${status:0:1}" "$(kind_of "$path")" >> "$WORK/files.tsv"
  done < "$WORK/name-status.txt"
  git -c core.quotePath=false diff -U0 -M "${diff_args[@]}" 2>/dev/null | awk "$AWK_DIFF_ADDED" > "$WORK/added.tsv"
  if [[ "$MODE" != base ]]; then
    local -a ls_args=(ls-files --others --exclude-standard)
    [[ "$MODE" == dir ]] && ls_args+=(-- "$DIR")
    git -c core.quotePath=false "${ls_args[@]}" | while IFS= read -r path; do
      printf '%s\tA\t%s\n' "$path" "$(kind_of "$path")" >> "$WORK/files.tsv"
      readable_text "$path" && awk -v p="$path" '{ print p "\t" NR "\t" $0 }' "$path" >> "$WORK/added.tsv"
    done
  fi
  return 0
}

# ── Prose: the added lines a person reads ──────────────────────────────────
# -v mode=md|comment [-v prefix=REGEX] [-v disk=FILE]; input: added lines of ONE
# file as "path<TAB>line<TAB>text"; output: "line<TAB>text". For Markdown, fence
# state comes from the whole file on disk when every added line agrees with it.
AWK_PROSE=$(cat <<'AWK'
BEGIN { FS = "\t" }
{ n++; ln[n] = $2; tx[n] = $0; sub(/^[^\t]*\t[^\t]*\t/, "", tx[n]) }
END {
  if (mode == "comment") {
    for (k = 1; k <= n; k++) if (tx[k] ~ prefix) { t = tx[k]; sub(prefix, "", t); sub(/[[:space:]]+$/, "", t); print ln[k] "\t" t }
    exit
  }
  usedisk = 0
  if (disk != "") {
    usedisk = 1; d = 0
    while ((getline line < disk) > 0) dl[++d] = line
    close(disk)
    for (k = 1; k <= n; k++) if (!(ln[k] in dl) || dl[ln[k]] != tx[k]) { usedisk = 0; break }
  }
  if (usedisk) { inside = 0; for (k = 1; k <= d; k++) { if (dl[k] ~ /^[[:space:]]*```/) { inside = !inside; fenced[k] = 1 } else if (inside) fenced[k] = 1 } }
  else { inside = 0; for (k = 1; k <= n; k++) { if (tx[k] ~ /^[[:space:]]*```/) { inside = !inside; fenced[ln[k]] = 1 } else if (inside) fenced[ln[k]] = 1 } }
  for (k = 1; k <= n; k++) if (!(ln[k] in fenced)) print ln[k] "\t" tx[k]
}
AWK
)

collect_prose() {
  : > "$WORK/prose.tsv"
  local path status kind disk
  while IFS="$TAB" read -r path status kind; do
    [[ "$kind" != none ]] || continue
    awk -F'\t' -v p="$path" '$1 == p' "$WORK/added.tsv" > "$WORK/one.tsv"
    [[ -s "$WORK/one.tsv" ]] || continue
    if [[ "$kind" == prose ]]; then
      disk=""; [[ -f "$path" ]] && disk="$path"
      awk -v mode=md -v disk="$disk" "$AWK_PROSE" "$WORK/one.tsv"
    else
      awk -v mode=comment -v prefix="$(comment_prefix "$path")" "$AWK_PROSE" "$WORK/one.tsv"
    fi | awk -F'\t' -v p="$path" '{ print p "\t" $0 }' >> "$WORK/prose.tsv"
  done < "$WORK/files.tsv"
  return 0
}

prose_of() { awk -F'\t' -v p="$1" '$1 == p { print $2 "\t" substr($0, length($1) + length($2) + 3) }' "$WORK/prose.tsv"; }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash scripts/tests/test-speckit-standards.sh`
Expected: `ALL TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add scripts/speckit-standards.sh scripts/tests/test-speckit-standards.sh
git commit -m "feat(standards): [9cad] change set and prose extraction"
```

---

### Task 4: Damage level assessment and the text header

**Files:**
- Modify: `scripts/speckit-standards.sh` (replace the `assess_damage` stub; add `AWK_GLOB`, `level_header`; make `render` print the header)
- Test: `scripts/tests/test-speckit-standards.sh`

**Interfaces:**
- Produces: `AWK_GLOB` (awk source defining `glob_to_ere(g)` and `specificity(g)`, prepended to every awk program that matches globs), `$WORK/level.tsv` with lines `LEVEL<TAB>name<TAB>reviewer`, `PATH<TAB>path<TAB>level<TAB>winning-pattern`, `BY<TAB>path`, `ASK<TAB>question`, and `level_header` printing the three-part text header. Exit 2 when `default_level` names no level.

- [ ] **Step 1: Add the failing tests**

Insert before the `echo` / `ALL TESTS PASSED` block:

```bash
# ── Task 4: damage level ────────────────────────────────────────────────────

make_repo fixtures
mkdir -p app/models
printf 'class User; end\n' > app/models/user.rb
commit_all
engine --base main
check_rc "path-scoped question: exit 0 with no findings" "$rc" 0
check_has "level from an exact path" "$out" "Damage level: money and trust (set by app/models/user.rb)"
check_has "reviewer line follows" "$out" "Read every line. Work the checklist."
check_has "plain question asked" "$out" "  - What happens if this runs twice?"
check_has "path-scoped question asked when its path is touched" "$out" "  - Who can reach this?"
check_lacks "other path-scoped question not asked" "$out" "told or agrees to"
cleanup

make_repo fixtures
mkdir -p app/services/repayment_instances docs
printf 'x\n' > app/services/repayment_instances/pay.rb
printf 'y\n' > docs/a.md
commit_all
engine --base main
check_has "path-scoped question skipped when untouched" "$out" "Damage level: money and trust (set by app/services/repayment_instances/pay.rb)"
check_lacks "untouched path-scoped question" "$out" "Who can reach this?"
cleanup

make_repo fixtures
mkdir -p app/jobs/repayment_instances
printf 'x\n' > app/jobs/repayment_instances/run_job.rb
commit_all
engine --base main
check_has "alias inherits the service directory level" "$out" "Damage level: money and trust (set by app/jobs/repayment_instances/run_job.rb)"
cleanup

make_repo fixtures
mkdir -p app/services/notifications
printf 'x\n' > app/services/notifications/mailer.rb
printf 'x\n' > Gemfile
printf 'x\n' > .rubocop.yml
commit_all
engine --base main
check_has "most specific pattern wins over the catch-all" "$out" "Damage level: member-facing (set by Gemfile)"
cleanup

make_repo fixtures
mkdir -p docs
printf 'a\n' > docs/a.md; printf 'b\n' > docs/b.md; printf 'c\n' > docs/c.md; printf 'd\n' > docs/d.md
commit_all
engine --base main
check_has "more than three files are summarized" "$out" "Damage level: no runtime effect (set by docs/a.md, docs/b.md, docs/c.md and 1 more)"
check_has "a level with an empty checklist prints only its reviewer line" "$out" "Approve. Nobody is expected to read this line by line."
cleanup

make_repo fixtures
engine --base main
check_has "empty change set is the least serious level" "$out" "Damage level: no runtime effect (nothing in this change raises it)"
cleanup

make_repo fixtures
sed -i.bak 's/^default_level: member-facing/default_level: nowhere/' .specify/marge/config/damage-levels.yml && rm .specify/marge/config/damage-levels.yml.bak
engine --base main
check_rc "default_level naming no level exits 2" "$rc" 2
check_has "default_level error is explained" "$err" "default_level"
cleanup
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash scripts/tests/test-speckit-standards.sh 2>&1 | grep -c FAIL`
Expected: a number above 12.

- [ ] **Step 3: Add `AWK_GLOB`, replace the `assess_damage` stub, add `level_header`, and extend `render`**

Insert this block directly above the `# ── Change set` comment (so `AWK_GLOB` is defined before anything uses it):

```bash
# ── Globs ──────────────────────────────────────────────────────────────────
# Shell globs → ERE: `**/` crosses directories, `*` and `?` stop at `/`.
# Prepended to every awk program that matches paths.
AWK_GLOB=$(cat <<'AWK'
function glob_to_ere(g,   out, c, k, n) {
  out = ""; n = length(g)
  for (k = 1; k <= n; k++) {
    c = substr(g, k, 1)
    if (c == "*") {
      if (substr(g, k, 3) == "**/") { out = out "(.*/)?"; k += 2 }
      else if (substr(g, k, 2) == "**") { out = out ".*"; k += 1 }
      else out = out "[^/]*"
    } else if (c == "?") out = out "[^/]"
    else if (c ~ /[.+(){}\[\]|^$\\]/) out = out "\\" c
    else out = out c
  }
  return "^" out "$"
}
function specificity(g,   t) { t = g; gsub(/[*?\[\]{}]/, "", t); return length(t) }
AWK
)
```

Delete the line `assess_damage() { :; }` and put this in its place:

```bash
# ── Damage level ───────────────────────────────────────────────────────────
# -v cfg=flattened damage-levels; stdin: one changed path per line.
# Output: LEVEL name reviewer; PATH path level pattern; BY path; ASK question.
AWK_LEVEL="$AWK_GLOB"$'\n'"$(cat <<'AWK'
BEGIN {
  FS = "\t"
  while ((getline line < cfg) > 0) {
    split(line, kv, "\t"); key = kv[1]; val = substr(line, length(key) + 2)
    if (key == "default_level") deflevel = val
    else if (key ~ /^levels\.[0-9]+\.name$/) { split(key, p, "."); lname[p[2]] = val; nlevels = (p[2] + 1 > nlevels ? p[2] + 1 : nlevels) }
    else if (key ~ /^levels\.[0-9]+\.reviewer$/) { split(key, p, "."); lrev[p[2]] = val }
    else if (key ~ /^levels\.[0-9]+\.paths\.[0-9]+$/) { split(key, p, "."); np++; pat[np] = val; plev[np] = p[2] }
    else if (key ~ /^levels\.[0-9]+\.checklist\.[0-9]+$/) { split(key, p, "."); q = p[2] "." p[4]; qtext[q] = val; qn[p[2]]++; qorder[p[2], qn[p[2]]] = q }
    else if (key ~ /^levels\.[0-9]+\.checklist\.[0-9]+\.question$/) { split(key, p, "."); q = p[2] "." p[4]; qtext[q] = val; qn[p[2]]++; qorder[p[2], qn[p[2]]] = q }
    else if (key ~ /^levels\.[0-9]+\.checklist\.[0-9]+\.paths\.[0-9]+$/) { split(key, p, "."); q = p[2] "." p[4]; qpn[q]++; qpat[q, qpn[q]] = val; np++; pat[np] = val; plev[np] = p[2] }
    else if (key ~ /^aliases\.[0-9]+\.from$/) { split(key, p, "."); afrom[p[2]] = val; na = (p[2] + 1 > na ? p[2] + 1 : na) }
    else if (key ~ /^aliases\.[0-9]+\.to$/) { split(key, p, "."); ato[p[2]] = val }
  }
  close(cfg)
  if (nlevels == 0) { print "damage-levels.yml lists no levels" > "/dev/stderr"; exit 2 }
  for (k = 1; k <= np; k++) { pere[k] = glob_to_ere(pat[k]); pspec[k] = specificity(pat[k]) }
  defidx = -1
  for (k = 0; k < nlevels; k++) if (lname[k] == deflevel) defidx = k
  if (defidx < 0) { print "damage-levels.yml: default_level \"" deflevel "\" names no level" > "/dev/stderr"; exit 2 }
}
function rank(li) { return nlevels - li }
function candidates(path, cand,   k, c) {
  c = 1; cand[1] = path
  for (k = 0; k < na; k++) if (index(path, afrom[k]) == 1) { c++; cand[c] = ato[k] substr(path, length(afrom[k]) + 1) }
  return c
}
function level_for(path,   cand, c, k, j, best, bs, br) {
  c = candidates(path, cand); best = -1; bs = -1; br = -1; WIN_PATTERN = ""
  for (j = 1; j <= c; j++) for (k = 1; k <= np; k++) if (cand[j] ~ pere[k]) {
    if (pspec[k] > bs || (pspec[k] == bs && rank(plev[k]) > br)) { bs = pspec[k]; br = rank(plev[k]); best = plev[k]; WIN_PATTERN = pat[k] }
  }
  return (best < 0 ? defidx : best)
}
{ paths[++n] = $0 }
END {
  if (nlevels == 0 || defidx < 0) exit 2
  top = -1
  for (k = 1; k <= n; k++) { lv = level_for(paths[k]); plv[k] = lv; ppat[k] = WIN_PATTERN; if (top < 0 || rank(lv) > rank(top)) top = lv }
  if (n == 0) top = nlevels - 1
  print "LEVEL\t" lname[top] "\t" lrev[top]
  for (k = 1; k <= n; k++) { print "PATH\t" paths[k] "\t" lname[plv[k]] "\t" ppat[k]; if (plv[k] == top) print "BY\t" paths[k] }
  for (k = 1; k <= qn[top]; k++) {
    q = qorder[top, k]; asked = (qpn[q] == 0)
    for (j = 1; j <= qpn[q] && !asked; j++) { re = glob_to_ere(qpat[q, j]); for (m = 1; m <= n && !asked; m++) { c = candidates(paths[m], cand); for (x = 1; x <= c; x++) if (cand[x] ~ re) asked = 1 } }
    if (asked) print "ASK\t" qtext[q]
  }
}
AWK
)"

assess_damage() {
  cut -f1 "$WORK/files.tsv" | awk -v cfg="$WORK/dl.tsv" "$AWK_LEVEL" > "$WORK/level.tsv" || fail_to_run "cannot assess the damage level (see above)"
}

# The level, what set it, the reviewer line, and the checklist, for --format text.
level_header() {
  [[ -s "$WORK/level.tsv" ]] || return 0
  local name reviewer set_by count
  name=$(awk -F'\t' '$1 == "LEVEL" { print $2; exit }' "$WORK/level.tsv")
  reviewer=$(awk -F'\t' '$1 == "LEVEL" { print $3; exit }' "$WORK/level.tsv")
  count=$(awk -F'\t' '$1 == "BY"' "$WORK/level.tsv" | wc -l | tr -d ' ')
  if [[ "$count" -eq 0 ]]; then
    set_by="nothing in this change raises it"
  else
    set_by="set by $(awk -F'\t' '$1 == "BY" { print $2 }' "$WORK/level.tsv" | head -n 3 | paste -sd, - | sed 's/,/, /g')"
    [[ "$count" -gt 3 ]] && set_by="$set_by and $((count - 3)) more"
  fi
  echo "Damage level: $name ($set_by)"
  echo "$reviewer"
  awk -F'\t' '$1 == "ASK" { print "  - " $2 }' "$WORK/level.tsv"
}
```

Replace the `render` stub line `render() { [[ "$FORMAT" == text ]] && echo "No findings."; exit 0; }` with:

```bash
render() {
  if [[ "$FORMAT" == text ]]; then level_header; echo "No findings."; fi
  exit 0
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash scripts/tests/test-speckit-standards.sh`
Expected: `ALL TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add scripts/speckit-standards.sh scripts/tests/test-speckit-standards.sh
git commit -m "feat(standards): [9cad] damage level assessment and text header"
```

---

### Task 5: Findings pipeline, output formats, and `requirement-id-in-body`

**Files:**
- Modify: `scripts/speckit-standards.sh` (add `emit`, the three renderers, replace `render` and `run_rules`, add `rule_requirement_ids`)
- Test: `scripts/tests/test-speckit-standards.sh`

**Interfaces:**
- Produces: `emit BLOCK SEV FILE LINE RULE ISSUE FIX [TAGS]` where BLOCK is `1` or `0`, SEV is `HIGH|MEDIUM|LOW`, TAGS is `NEEDS_HUMAN` or empty; appends to `$WORK/findings.tsv` with columns `brank srank file line sev rule issue fix tags`. `render` sorts, filters for `--blocking-only`, prints in the chosen format, and exits 1 when any finding blocks. `run_rules` calls each rule group guarded by `want`.

- [ ] **Step 1: Add the failing tests**

Insert before the `echo` / `ALL TESTS PASSED` block:

```bash
# ── Task 5: formats and requirement-id-in-body ──────────────────────────────

make_repo fixtures
printf 'Implements FR-001 and SC-P1-003 for US2; see `FR-009` and https://x.y/FR-010 and NFR-2.\n' > body.md
engine --base main --body-file body.md
check_rc "requirement id in the body blocks" "$rc" 1
check_has "ids listed once each, sorted" "$out" "BLOCK HIGH   PULL_REQUEST:0  requirement-id-in-body: the description leans on requirement ids: FR-001, NFR-2, SC-P1-003, US2"
check_lacks "id inside inline code ignored" "$out" "FR-009"
check_lacks "id inside a URL ignored" "$out" "FR-010"
printf 'FR-001,FR-002\n' > body2.md
engine --base main --body-file body2.md
check_has "adjacent ids both found" "$out" "FR-001, FR-002"
printf 'A reviewer can read this without the spec.\n' > clean.md
engine --base main --body-file clean.md
check_rc "clean body exits 0" "$rc" 0
engine --base main --body-file body.md --format marge
check_rc "marge format still exits 1" "$rc" 1
check_has "marge file line" "$out" "- file: PULL_REQUEST:0"
check_has "marge severity" "$out" "  severity: HIGH"
check_has "marge pack label" "$out" "  pack: baseline/standards.sh"
check_has "marge rule" "$out" "  rule: requirement-id-in-body"
check_has "marge empty tags" "$out" "  tags: []"
check_has "marge quoted issue" "$out" '  issue: "the description leans on requirement ids: FR-001, NFR-2, SC-P1-003, US2"'
engine --base main --body-file clean.md --format marge
check_eq "marge prints nothing when clean" "$out" ""
engine --base main --body-file body.md --format hook
check_has "hook decision" "$out" '{"decision":"block","reason":"A standards check blocks this change. Fix these before finishing:\nPULL_REQUEST:0  requirement-id-in-body: the description leans on requirement ids: FR-001, NFR-2, SC-P1-003, US2"}'
engine --base main --body-file clean.md --format hook
check_eq "hook prints nothing when clean" "$out" ""
engine --base main --body-file body.md --only lexicon
check_rc "--only without pr-shape skips the body rule" "$rc" 0
check_has "--only without pr-shape reports clean" "$out" "No findings."
cleanup

# Escaping: a quote and a backslash inside a finding survive both formats.
make_repo fixtures
printf 'See FR-001 "quoted" and back\\slash.\n' > body.md
engine --base main --body-file body.md --format marge
check_has "marge escapes nothing in the id list" "$out" '  issue: "the description leans on requirement ids: FR-001"'
cleanup
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash scripts/tests/test-speckit-standards.sh 2>&1 | grep -c FAIL`
Expected: a number above 14.

- [ ] **Step 3: Add the findings pipeline and the first rule**

Delete the lines `run_rules() { :; }` and the whole `render()` function, and put this in their place:

```bash
# ── Findings ───────────────────────────────────────────────────────────────
# emit BLOCK(1|0) SEV FILE LINE RULE ISSUE FIX [TAGS]
emit() {
  local block="$1" sev="$2" file="$3" line="$4" rule="$5" issue="$6" fix="$7" tags="${8:-}"
  local brank=1 srank=3
  [[ "$block" == 1 ]] && brank=0
  case "$sev" in HIGH) srank=0 ;; MEDIUM) srank=1 ;; LOW) srank=2 ;; esac
  issue="${issue//$TAB/ }"
  fix="${fix//$TAB/ }"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$brank" "$srank" "$file" "$line" "$sev" "$rule" "$issue" "$fix" "$tags" >> "$WORK/findings.tsv"
}

yaml_escape() { local s="${1//\\/\\\\}"; printf '%s' "${s//\"/\\\"}"; }
json_escape() { local s="${1//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//$'\n'/\\n}"; s="${s//$'\t'/\\t}"; printf '%s' "$s"; }

render_text() {
  level_header
  if [[ ! -s "$1" ]]; then echo "No findings."; return 0; fi
  awk -F'\t' '{ printf("%s%-6s %s:%s  %s: %s\n", ($1 == 0 ? "BLOCK " : ""), $5, $3, $4, $6, $7) }' "$1"
}

render_marge() {
  [[ -s "$1" ]] || return 0
  local _b _s file line sev rule issue fix tags
  while IFS="$TAB" read -r _b _s file line sev rule issue fix tags; do
    printf -- '- file: %s:%s\n  severity: %s\n  confidence: 95\n  pack: %s\n  rule: %s\n  issue: "%s"\n  fix: "%s"\n  tags: [%s]\n' \
      "$file" "$line" "$sev" "$PACK_LABEL" "$rule" "$(yaml_escape "$issue")" "$(yaml_escape "$fix")" "$tags"
  done < "$1"
}

render_hook() {
  grep -q "^0$TAB" "$1" || return 0
  local reasons
  reasons=$(grep "^0$TAB" "$1" | head -n "$MAX_HOOK_REASONS" | awk -F'\t' '{ printf("%s%s:%s  %s: %s", (NR > 1 ? "\n" : ""), $3, $4, $6, $7) }')
  printf '{"decision":"block","reason":"A standards check blocks this change. Fix these before finishing:\\n%s"}\n' "$(json_escape "$reasons")"
}

render() {
  sort -t "$TAB" -k1,1n -k2,2n -k3,3 -k4,4n "$WORK/findings.tsv" > "$WORK/sorted.tsv"
  local blocking=0
  grep -q "^0$TAB" "$WORK/sorted.tsv" && blocking=1
  if [[ "$BLOCKING_ONLY" == 1 ]]; then
    grep "^0$TAB" "$WORK/sorted.tsv" > "$WORK/shown.tsv" || true
  else
    cp "$WORK/sorted.tsv" "$WORK/shown.tsv"
  fi
  case "$FORMAT" in
    text) render_text "$WORK/shown.tsv" ;;
    marge) render_marge "$WORK/shown.tsv" ;;
    hook) render_hook "$WORK/shown.tsv" ;;
  esac
  exit "$blocking"
}

# ── Rules: pr-shape ────────────────────────────────────────────────────────
# Requirement ids in prose, outside inline code and URLs. Consecutive ids share
# their separator, so the loop keeps the trailing guard character for the next match.
AWK_REQUIREMENT_IDS=$(cat <<'AWK'
{
  text = $0; gsub(/`[^`]*`/, " ", text); gsub(/https?:\/\/[^[:space:]]+/, " ", text)
  rest = text
  while (match(rest, /(^|[^[:alnum:]_])(FR|NFR|SR|SC|CHK|AS|US)-?(P[0-9]+-)?[0-9]+([^[:alnum:]_]|$)/)) {
    id = substr(rest, RSTART, RLENGTH); sub(/^[^[:alnum:]_]/, "", id); sub(/[^[:alnum:]_]$/, "", id)
    if (!(id in seen)) { seen[id] = 1; print id }
    rest = substr(rest, RSTART + RLENGTH - 1)
    if (RLENGTH <= 1) break
  }
}
AWK
)

rule_requirement_ids() {
  [[ -n "$BODY_FILE" ]] || return 0
  local ids
  ids=$(awk "$AWK_REQUIREMENT_IDS" "$BODY_FILE" | sort -u | paste -sd, - | sed 's/,/, /g')
  [[ -n "$ids" ]] || return 0
  emit 1 HIGH PULL_REQUEST 0 requirement-id-in-body "the description leans on requirement ids: $ids" \
    "say what changes in words a reviewer can read without opening the spec; link the spec once"
}

run_rules() {
  if want pr-shape; then
    rule_requirement_ids
  fi
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash scripts/tests/test-speckit-standards.sh`
Expected: `ALL TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add scripts/speckit-standards.sh scripts/tests/test-speckit-standards.sh
git commit -m "feat(standards): [9cad] findings pipeline, three output formats, requirement ids in the body"
```

---

### Task 6: `specs-mixed-with-code`, `many-boundaries`, `plain-summary-missing`, `plain-summary-too-long`

**Files:**
- Modify: `scripts/speckit-standards.sh` (add three rule functions and `AWK_BOUNDARIES`; extend `run_rules`)
- Test: `scripts/tests/test-speckit-standards.sh`

**Interfaces:**
- Consumes: `emit`, `$WORK/files.tsv`, `$WORK/added.tsv`, `$WORK/dl.tsv`, `AWK_GLOB`.
- Produces: `rule_specs_mixed`, `rule_many_boundaries`, `rule_plain_summary`.

- [ ] **Step 1: Add the failing tests**

Insert before the `echo` / `ALL TESTS PASSED` block:

```bash
# ── Task 6: PR shape ────────────────────────────────────────────────────────

make_repo fixtures
mkdir -p specs/9cad-feat-x app
printf '# Spec\n\n## Plain summary\n\nShort.\n' > specs/9cad-feat-x/spec.md
printf 'x\n' > app/x.rb
commit_all
engine --base main
check_rc "specs mixed with code is advice" "$rc" 0
check_has "specs mixed with code finding" "$out" "MEDIUM specs/9cad-feat-x/spec.md:0  specs-mixed-with-code: this change edits specs/ and application code together"
engine --base main --format marge
check_has "specs mixed with code needs a human" "$out" "  tags: [NEEDS_HUMAN]"
cleanup

make_repo fixtures
mkdir -p specs/9cad-feat-x docs
printf '# Spec\n\n## Plain summary\n\nShort.\n' > specs/9cad-feat-x/spec.md
printf 'notes\n' > docs/notes.md
commit_all
engine --base main
check_lacks "specs with docs only is not mixed" "$out" "specs-mixed-with-code"
cleanup

make_repo fixtures
mkdir -p app/services/reset_plaid app/jobs/reset_pave app/services/reset_x
printf 'a\n' > app/services/reset_plaid/a.rb
printf 'b\n' > app/services/reset_plaid/b.rb
printf 'j\n' > app/jobs/reset_pave/j.rb
commit_all
engine --base main
check_has "two boundaries reported once" "$out" "MEDIUM PULL_REQUEST:0  many-boundaries: touches 2 boundaries: reset_pave, reset_plaid"
cleanup

make_repo fixtures
mkdir -p app/services/reset_plaid
printf 'a\n' > app/services/reset_plaid/a.rb
commit_all
engine --base main
check_lacks "one boundary is fine" "$out" "many-boundaries"
cleanup

make_repo fixtures
mkdir -p specs/9cad-feat-x
printf '# Spec\n\n## User Scenarios\n\nText.\n' > specs/9cad-feat-x/spec.md
commit_all
engine --base main
check_rc "missing plain summary blocks" "$rc" 1
check_has "missing plain summary finding" "$out" 'BLOCK HIGH   specs/9cad-feat-x/spec.md:1  plain-summary-missing: a new spec must open with a "## Plain summary" section'
cleanup

make_repo fixtures
mkdir -p specs/9cad-feat-x
{ printf '# Spec\n\n## Plain summary\n\n'; for _ in $(seq 1 151); do printf 'word '; done; printf '\n\n## Next\n\nMore.\n'; } > specs/9cad-feat-x/spec.md
commit_all
engine --base main
check_rc "long plain summary blocks" "$rc" 1
check_has "long plain summary finding at the heading line" "$out" "BLOCK HIGH   specs/9cad-feat-x/spec.md:3  plain-summary-too-long: the plain summary is 151 words; the limit is 150"
cleanup

make_repo fixtures
mkdir -p specs/9cad-feat-x
printf '# Spec\n\n## Plain Summary *(mandatory)*\n\nWho, what, and what goes wrong.\n\n## Next\n' > specs/9cad-feat-x/spec.md
commit_all
engine --base main
check_lacks "case-insensitive heading with suffix passes" "$out" "plain-summary"
printf '# Spec\n\n## Plain Summary\n\nEdited later.\n' > specs/9cad-feat-x/spec.md
commit_all
engine --base HEAD~1
check_lacks "an existing spec is never checked for a summary" "$out" "plain-summary"
cleanup
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash scripts/tests/test-speckit-standards.sh 2>&1 | grep -c FAIL`
Expected: at least 8.

- [ ] **Step 3: Add the three rules**

Insert directly above `run_rules()`:

```bash
rule_specs_mixed() {
  local spec code
  spec=$(awk -F'\t' '$1 ~ /^specs\// { print $1; exit }' "$WORK/files.tsv")
  [[ -n "$spec" ]] || return 0
  code=$(awk -F'\t' '$1 !~ /^(specs|docs)\// && $1 !~ /\.(md|markdown|txt)$/ { print $1; exit }' "$WORK/files.tsv")
  [[ -n "$code" ]] || return 0
  emit 0 MEDIUM "$spec" 0 specs-mixed-with-code "this change edits specs/ and application code together" \
    "open a separate pull request for the specs/ changes so the code can be read on its own" NEEDS_HUMAN
}

# -v cfg=flattened damage-levels; stdin: changed paths → distinct boundary names.
# A boundary glob's first wildcard segment names the boundary.
AWK_BOUNDARIES="$AWK_GLOB"$'\n'"$(cat <<'AWK'
BEGIN {
  FS = "\t"
  while ((getline l < cfg) > 0) {
    split(l, kv, "\t")
    if (kv[1] ~ /^boundaries\.[0-9]+$/) {
      nb++; bre[nb] = glob_to_ere(kv[2]); m = split(kv[2], seg, "/"); bseg[nb] = 0
      for (k = 1; k <= m; k++) if (seg[k] ~ /[*?]/) { bseg[nb] = k; break }
    }
  }
  close(cfg)
}
{ for (b = 1; b <= nb; b++) if (bseg[b] > 0 && $0 ~ bre[b]) { split($0, ps, "/"); if (!(ps[bseg[b]] in seen)) { seen[ps[bseg[b]]] = 1; print ps[bseg[b]] } } }
AWK
)"

rule_many_boundaries() {
  local names count
  names=$(cut -f1 "$WORK/files.tsv" | awk -v cfg="$WORK/dl.tsv" "$AWK_BOUNDARIES" | sort)
  count=$(grep -c . <<<"$names" 2>/dev/null || true)
  [[ "${count:-0}" -ge 2 ]] || return 0
  emit 0 MEDIUM PULL_REQUEST 0 many-boundaries "touches $count boundaries: $(paste -sd, - <<<"$names" | sed 's/,/, /g')" \
    "read each boundary on its own; split the change if the work in one does not need the others" NEEDS_HUMAN
}

# A new specs/*/spec.md opens with "## Plain summary" of at most SUMMARY_MAX_WORDS words.
AWK_PLAIN_SUMMARY=$(cat <<'AWK'
BEGIN { FS = "\t" }
$1 == p { n++; ln[n] = $2; tx[n] = substr($0, length($1) + length($2) + 3) }
END {
  start = 0
  for (k = 1; k <= n; k++) if (tolower(tx[k]) ~ /^##[[:space:]]+plain summary/) { start = k; break }
  if (!start) { print "missing\t1\t0"; exit }
  words = 0
  for (k = start + 1; k <= n && tx[k] !~ /^#+[[:space:]]/; k++) {
    t = tx[k]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", t)
    if (t != "") words += split(t, w, /[[:space:]]+/)
  }
  print (words > max ? "long" : "ok") "\t" ln[start] "\t" words
}
AWK
)

rule_plain_summary() {
  local path status kind verdict line words
  while IFS="$TAB" read -r path status kind; do
    [[ "$status" == A && "$path" =~ ^specs/[^/]+/spec\.md$ ]] || continue
    IFS="$TAB" read -r verdict line words < <(awk -v p="$path" -v max="$SUMMARY_MAX_WORDS" "$AWK_PLAIN_SUMMARY" "$WORK/added.tsv")
    case "$verdict" in
      missing) emit 1 HIGH "$path" 1 plain-summary-missing 'a new spec must open with a "## Plain summary" section' \
                 "add \"## Plain summary\" ($SUMMARY_MAX_WORDS words or fewer) before the first user story" ;;
      long) emit 1 HIGH "$path" "$line" plain-summary-too-long "the plain summary is $words words; the limit is $SUMMARY_MAX_WORDS" \
              "cut it to the three questions: who is this for, what changes for them, what goes wrong if it is wrong" ;;
    esac
  done < "$WORK/files.tsv"
}
```

Replace the body of `run_rules` so it reads:

```bash
run_rules() {
  if want pr-shape; then
    rule_requirement_ids
    rule_specs_mixed
    rule_many_boundaries
    rule_plain_summary
  fi
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash scripts/tests/test-speckit-standards.sh`
Expected: `ALL TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add scripts/speckit-standards.sh scripts/tests/test-speckit-standards.sh
git commit -m "feat(standards): [9cad] PR shape rules"
```

---

### Task 7: `long-sentence` and `long-comment`

**Files:**
- Modify: `scripts/speckit-standards.sh` (add `AWK_SENTENCES`, two rule functions; extend `run_rules`)
- Test: `scripts/tests/test-speckit-standards.sh`

**Interfaces:**
- Consumes: `prose_of`, `$WORK/files.tsv`, `emit`, `MAX_WORDS`, `MAX_COMMENT_LINES`.
- Produces: `rule_long_sentence`, `rule_long_comment`.

- [ ] **Step 1: Add the failing tests**

Insert before the `echo` / `ALL TESTS PASSED` block:

```bash
# ── Task 7: plain language ──────────────────────────────────────────────────

make_repo fixtures
mkdir -p docs
{
  printf '# Title\n\n'
  printf 'One two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty twenty-one twenty-two twenty-three twenty-four twenty-five twenty-six.\n\n'
  printf 'Short first. One two three four five six seven eight nine ten eleven twelve thirteen\nfourteen fifteen sixteen seventeen eighteen nineteen twenty twenty-one twenty-two twenty-three twenty-four twenty-five twenty-six twenty-seven.\n\n'
  printf '```\none two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty twenty-one twenty-two twenty-three twenty-four twenty-five twenty-six.\n```\n\n'
  printf '| one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty twenty-one twenty-two twenty-three twenty-four twenty-five twenty-six |\n\n'
  printf -- '- A list item with [a link](https://example.com/x) and `code` stays short.\n'
} > docs/long.md
commit_all
engine --base main
check_rc "long sentences are advice" "$rc" 0
check_has "26-word sentence flagged with its count" "$out" "MEDIUM docs/long.md:3  long-sentence: 26 words: \"One two three four five six seven eight nine ten eleven twelve thirtee…\""
check_has "sentence wrapped over two lines reported on its own line" "$out" "MEDIUM docs/long.md:5  long-sentence: 27 words:"
check_lacks "fenced code is not a sentence" "$out" "docs/long.md:9"
check_lacks "table row is not a sentence" "$out" "docs/long.md:12"
check_eq "exactly two long sentences" "$(grep -c 'long-sentence' <<<"$out")" "2"
engine --base main --format marge
check_has "long sentence has a fix" "$out" '  fix: "split it; aim for 15 words, never more than 25"'
cleanup

make_repo fixtures
printf 'x = 1\n# one\n# two\n# three\n# four\n# five\ny = 2\n# a\n# b\n# c\n# d\n' > code.rb
printf 'let x = 1;\n// one\n// two\n// three\n// four\n// five\n' > code.ts
commit_all
engine --base main
check_has "five hash comment lines flagged at the first" "$out" "MEDIUM code.rb:2  long-comment: 5 lines of comment in a row"
check_lacks "four comment lines are fine" "$out" "code.rb:8"
check_has "slash comments count too" "$out" "MEDIUM code.ts:2  long-comment: 5 lines of comment in a row"
cleanup
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash scripts/tests/test-speckit-standards.sh 2>&1 | grep -c FAIL`
Expected: at least 6.

- [ ] **Step 3: Add the two rules**

Insert directly above `run_rules()`:

```bash
# ── Rules: plain-language ──────────────────────────────────────────────────
# input: "line<TAB>text" prose lines of one file → "line<TAB>words<TAB>excerpt"
# for every sentence over `max` words. Sentences live in the paragraph, not the
# line: consecutive lines up to a blank, a heading, a list item, a table row, or a quote.
AWK_SENTENCES=$(cat <<'AWK'
BEGIN { FS = "\t" }
{ n++; ln[n] = $1; tx[n] = substr($0, length($1) + 2) }
function strip_md(t,   s) {
  gsub(/`[^`]*`/, "CODE", t)
  gsub(/https?:\/\/[^[:space:]]+/, "URL", t)
  while (match(t, /\[[^\]]*\]\([^)]*\)/)) { s = substr(t, RSTART, RLENGTH); sub(/^\[/, "", s); sub(/\]\(.*$/, "", s); t = substr(t, 1, RSTART - 1) s substr(t, RSTART + RLENGTH) }
  gsub(/<!--[^>]*-->/, "", t)
  gsub(/\*\*|__|\*|_/, "", t)
  return t
}
function flush(first, text,   rest, pos, words, w, sentence, nl, before, excerpt, parts) {
  text = strip_md(text); rest = text; pos = 0
  while (rest != "") {
    if (match(rest, /[.!?]["')]*[[:space:]]+/)) { sentence = substr(rest, 1, RSTART + RLENGTH - 1); rest = substr(rest, RSTART + RLENGTH) }
    else { sentence = rest; rest = "" }
    before = substr(text, 1, pos); nl = gsub(/\n/, "", before)
    pos += length(sentence)
    w = sentence; gsub(/\n/, " ", w); gsub(/^[[:space:]]+|[[:space:]]+$/, "", w)
    if (w == "") continue
    words = split(w, parts, /[[:space:]]+/)
    if (words > max) { excerpt = substr(w, 1, 70); gsub(/\t/, " ", excerpt); printf("%d\t%d\t%s\n", first + nl, words, excerpt) }
  }
}
END {
  first = 0; buf = ""
  for (k = 1; k <= n; k++) {
    t = tx[k]
    blank = (t ~ /^[[:space:]]*$/); blockstart = (t ~ /^[[:space:]]*(#|[-*+][[:space:]]|[0-9]+\.[[:space:]]|\||>)/)
    broken = (k > 1 && (ln[k] != ln[k-1] + 1 || blank || blockstart || tx[k-1] ~ /^[[:space:]]*#/ || tx[k-1] ~ /^[[:space:]]*$/))
    if (broken && buf != "") { flush(first, buf); buf = "" }
    if (blank) continue
    if (t ~ /^[[:space:]]*\|/) continue
    hdr = t; if (sub(/^[[:space:]]*#+[[:space:]]*/, "", hdr)) t = hdr
    lst = t; if (sub(/^[[:space:]]*([-*+]|[0-9]+\.)[[:space:]]+/, "", lst)) t = lst
    if (buf == "") { first = ln[k]; buf = t } else buf = buf "\n" t
  }
  if (buf != "") flush(first, buf)
}
AWK
)

rule_long_sentence() {
  local path status kind line words excerpt
  while IFS="$TAB" read -r path status kind; do
    [[ "$kind" != none ]] || continue
    while IFS="$TAB" read -r line words excerpt; do
      emit 0 MEDIUM "$path" "$line" long-sentence "$words words: \"$excerpt…\"" "split it; aim for 15 words, never more than $MAX_WORDS"
    done < <(prose_of "$path" | awk -v max="$MAX_WORDS" "$AWK_SENTENCES")
  done < "$WORK/files.tsv"
}

rule_long_comment() {
  local path status kind start run
  while IFS="$TAB" read -r path status kind; do
    [[ "$kind" == comment ]] || continue
    while IFS="$TAB" read -r start run; do
      emit 0 MEDIUM "$path" "$start" long-comment "$run lines of comment in a row" "say why in one or two sentences; link the source for the rest"
    done < <(prose_of "$path" | awk -F'\t' -v max="$MAX_COMMENT_LINES" '
      { if (n && $1 == last + 1) run++; else { if (run > max) print start "\t" run; run = 1; start = $1 } last = $1; n = 1 }
      END { if (run > max) print start "\t" run }')
  done < "$WORK/files.tsv"
}
```

Extend `run_rules` with a second group, after the `pr-shape` block:

```bash
  if want plain-language; then
    rule_long_sentence
    rule_long_comment
  fi
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash scripts/tests/test-speckit-standards.sh`
Expected: `ALL TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add scripts/speckit-standards.sh scripts/tests/test-speckit-standards.sh
git commit -m "feat(standards): [9cad] long sentence and long comment rules"
```

---

### Task 8: Lexicon rules

**Files:**
- Modify: `scripts/speckit-standards.sh` (add `AWK_LEXICON`, `lexicon_exempt`, `rule_lexicon`; extend `run_rules`)
- Test: `scripts/tests/test-speckit-standards.sh`

**Interfaces:**
- Consumes: `$WORK/lx.tsv`, `prose_of`, `AWK_GLOB`, `emit`.
- Produces: `rule_lexicon` emitting `lexicon-banned`, `lexicon-prefer`, `plain-verb`, `invented-phrase`, `lexicon-new-term`.

- [ ] **Step 1: Add the failing tests**

Insert before the `echo` / `ALL TESTS PASSED` block:

```bash
# ── Task 8: lexicon ─────────────────────────────────────────────────────────

make_repo fixtures
mkdir -p specs/9cad-feat-x docs/standards
{
  printf '# Spec\n\n## Plain summary\n\nShort.\n\n'
  printf 'Underwriting starts here. Consumers pay today.\n'
  printf 'The direct-to-consumer flow and the consumer app are fine.\n'
  printf 'We utilize the vendor-neutral seam and the dispatch surface, never the attack surface or the surface.\n'
  printf 'The Risk Engine Service runs nightly. Nightly Job runs too. User Story 3 stays known.\n'
  printf 'customers\n'
  printf 'Borrower\n'
  printf 'The `underwriting` module and https://underwriting.example are never scanned.\n'
  printf '## Underwriting Heading Words\n'
  printf '| Underwriting | table |\n'
  printf 'subcustomers and borrowership stay.\n'
} > specs/9cad-feat-x/spec.md
printf 'underwriting is allowed here\n' > docs/standards/lexicon.md
commit_all
engine --base main
check_rc "a banned word blocks" "$rc" 1
check_has "banned word with its reason" "$out" 'BLOCK HIGH   specs/9cad-feat-x/spec.md:7  lexicon-banned: "Underwriting" — say "risk assessment". Reset does not do this.'
check_has "preferred word" "$out" 'MEDIUM specs/9cad-feat-x/spec.md:7  lexicon-prefer: "Consumers" — say "member".'
check_lacks "unless suppresses the whole line" "$out" "spec.md:8  lexicon-prefer"
check_has "plain verb" "$out" 'LOW    specs/9cad-feat-x/spec.md:9  plain-verb: "utilize" — say "use".'
check_has "compound invented phrase once" "$out" 'MEDIUM specs/9cad-feat-x/spec.md:9  invented-phrase: "vendor-neutral seam" is built from generic words.'
check_eq "invented phrase reported once per line" "$(grep -c 'vendor-neutral seam' <<<"$out")" "1"
check_has "modifier plus generic noun" "$out" '"dispatch surface" is built from generic words.'
check_lacks "allowed phrase" "$out" '"attack surface"'
check_lacks "noun after an article" "$out" '"the surface"'
check_has "new Title Case term" "$out" 'LOW    specs/9cad-feat-x/spec.md:10  lexicon-new-term: "Risk Engine Service" looks like a new term.'
check_lacks "sentence-start capital drops its first word" "$out" '"Nightly Job"'
check_lacks "known term" "$out" '"User Story"'
check_has "whole-line match at line start" "$out" 'specs/9cad-feat-x/spec.md:11  lexicon-prefer: "customers" — say "member".'
check_has "whole-line match at line end" "$out" 'specs/9cad-feat-x/spec.md:12  lexicon-banned: "Borrower" — say "member".'
check_lacks "inline code and URLs are never scanned" "$out" "spec.md:13"
check_has "headings are scanned for words" "$out" 'spec.md:14  lexicon-banned: "Underwriting"'
check_lacks "headings are not new terms" "$out" '"Underwriting Heading Words"'
check_has "table cells are scanned for words" "$out" 'spec.md:15  lexicon-banned: "Underwriting"'
check_lacks "a pattern never matches inside a longer word" "$out" "spec.md:16"
check_lacks "exempt path never scanned" "$out" "docs/standards/lexicon.md"
engine --base main --format marge
check_has "new term needs a human" "$out" "  rule: lexicon-new-term"
check_has "marge escapes quotes in the issue" "$out" '  issue: "\"Underwriting\" — say \"risk assessment\". Reset does not do this."'
check_has "new term fix names the config" "$out" '  fix: "add it to known_terms in .specify/marge/config/lexicon.yml in this change, or write it in plain lower-case words"'
cleanup

make_repo fixtures
printf 'Underwriting in a comment is found too.\n' > note.txt
printf 'x\n# underwriting here\n' > code.rb
commit_all
engine --base main
check_has "txt prose scanned" "$out" "note.txt:1  lexicon-banned"
check_has "comment scanned" "$out" "code.rb:2  lexicon-banned"
rm .specify/marge/config/lexicon.yml
commit_all "drop lexicon"
engine --base HEAD~1
check_rc "without lexicon.yml nothing blocks" "$rc" 0
check_lacks "without lexicon.yml no lexicon findings" "$out" "lexicon-"
cleanup
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash scripts/tests/test-speckit-standards.sh 2>&1 | grep -c FAIL`
Expected: at least 14.

- [ ] **Step 3: Add the lexicon rule**

Insert directly above `run_rules()`:

```bash
# ── Rules: lexicon ─────────────────────────────────────────────────────────
# -v cfg=flattened lexicon -v status=A|M|D|R -v path=PATH; stdin: "line<TAB>text"
# prose lines of one file. Output: "line<TAB>group<TAB>word<TAB>use<TAB>why"
# for banned/prefer/soft_verbs, "line<TAB>invented<TAB>phrase", "line<TAB>newterm<TAB>phrase".
AWK_LEXICON="$AWK_GLOB"$'\n'"$(cat <<'AWK'
BEGIN {
  FS = "\t"
  NOTMOD = " the a an this that each every any no its their our your one per to and or not then also must may can will would should could we it they you "
  while ((getline l < cfg) > 0) {
    split(l, kv, "\t"); key = kv[1]; val = substr(l, length(key) + 2)
    if (key ~ /^(banned|prefer|soft_verbs)\.[0-9]+\.(pattern|use|why)$/) {
      split(key, p, "."); id = p[1] "." p[2]
      if (!(id in rid)) { rid[id] = ++nr; rgroup[nr] = p[1] }
      k = rid[id]
      if (p[3] == "pattern") rpat[k] = val; else if (p[3] == "use") ruse[k] = val; else rwhy[k] = val
    }
    else if (key ~ /^(banned|prefer|soft_verbs)\.[0-9]+\.unless\.[0-9]+$/) {
      split(key, p, "."); id = p[1] "." p[2]
      if (!(id in rid)) { rid[id] = ++nr; rgroup[nr] = p[1] }
      k = rid[id]; nun[k]++; runless[k, nun[k]] = tolower(val)
    }
    else if (key ~ /^invented_phrases\.nouns\.[0-9]+$/) nouns = (nouns == "" ? val : nouns "|" val)
    else if (key ~ /^invented_phrases\.compound_suffixes\.[0-9]+$/) sufs = (sufs == "" ? val : sufs "|" val)
    else if (key ~ /^invented_phrases\.allowed\.[0-9]+$/) allowed[tolower(val)] = 1
    else if (key ~ /^known_terms\.[0-9]+$/) known[val] = 1
  }
  close(cfg)
  for (k = 1; k <= nr; k++) rre[k] = "(^|[^[:alnum:]_])(" tolower(rpat[k]) ")([^[:alnum:]_]|$)"
  if (nouns != "") nounre = "(^|[^[:alnum:]_-])[a-z][a-z0-9_-]*[[:space:]]+(" nouns ")s?([^[:alnum:]_]|$)"
  if (sufs != "") sufre = "(^|[^[:alnum:]_-])[a-z]+-(" sufs ")[[:space:]]+[a-z]+([^[:alnum:]_]|$)"
}
function word_of(s) { sub(/^[^[:alnum:]_]/, "", s); sub(/[^[:alnum:]_]$/, "", s); return s }
function allowed_phrase(ph,   l) { l = tolower(ph); if (l in allowed) return 1; sub(/s$/, "", l); return (l in allowed) }
function report_phrase(ln, ph) { if (!((ln, ph) in rep)) { rep[ln, ph] = 1; print ln "\tinvented\t" ph } }
{
  ln = $1; text = substr($0, length($1) + 2); gsub(/`[^`]*`/, " ", text); gsub(/https?:\/\/[^[:space:]]+/, " ", text)
  low = tolower(text)
  for (k = 1; k <= nr; k++) {
    if (match(low, rre[k])) {
      skip = 0; for (u = 1; u <= nun[k]; u++) if (low ~ runless[k, u]) skip = 1
      if (skip) continue
      w = word_of(substr(text, RSTART, RLENGTH))
      print ln "\t" rgroup[k] "\t" w "\t" ruse[k] "\t" rwhy[k]
    }
  }
  rest = low
  while (nounre != "" && match(rest, nounre)) {
    ph = word_of(substr(rest, RSTART, RLENGTH)); rest = substr(rest, RSTART + RLENGTH - 1)
    mod = ph; sub(/[[:space:]].*$/, "", mod)
    if (index(NOTMOD, " " mod " ") == 0 && !allowed_phrase(ph)) report_phrase(ln, ph)
    if (RLENGTH <= 1) break
  }
  rest = low
  while (sufre != "" && match(rest, sufre)) {
    ph = word_of(substr(rest, RSTART, RLENGTH)); rest = substr(rest, RSTART + RLENGTH - 1)
    if (!allowed_phrase(ph)) report_phrase(ln, ph)
    if (RLENGTH <= 1) break
  }
  if (status == "A" && path ~ /^specs\// && text !~ /^[[:space:]]*(#|\|)/) {
    rest = text; off = 0
    while (match(rest, /[A-Z][a-z]+( [A-Z][a-z]+)+/)) {
      ph = substr(rest, RSTART, RLENGTH); pre = substr(text, 1, off + RSTART - 1)
      nw = split(ph, pw, " ")
      if (nw > 4) ph = pw[1] " " pw[2] " " pw[3] " " pw[4]
      if (!(ph in known)) {
        if (pre ~ /(^|[.!?][[:space:]]+|["'(\[])$/ || pre ~ /^[[:space:]]*([-*+]|[0-9]+\.)[[:space:]]+$/) sub(/^[A-Za-z]+ ?/, "", ph)
        if (index(ph, " ") > 0 && !(ph in known) && !(ph in seen)) { seen[ph] = 1; print ln "\tnewterm\t" ph }
      }
      off += RSTART + RLENGTH - 1; rest = substr(rest, RSTART + RLENGTH)
    }
  }
}
AWK
)"

lexicon_exempt() {
  awk -F'\t' -v p="$1" "$AWK_GLOB"$'\n''$1 ~ /^exempt_paths\.[0-9]+$/ && p ~ glob_to_ere(substr($0, length($1) + 2)) { found = 1; exit } END { exit !found }' "$WORK/lx.tsv"
}

rule_lexicon() {
  [[ -f "$WORK/lx.tsv" ]] || return 0
  local path status kind line group word use why
  while IFS="$TAB" read -r path status kind; do
    [[ "$kind" != none ]] || continue
    lexicon_exempt "$path" && continue
    while IFS="$TAB" read -r line group word use why; do
      case "$group" in
        banned) emit 1 HIGH "$path" "$line" lexicon-banned "\"$word\" — say \"$use\".${why:+ $why}" "say \"$use\"" ;;
        prefer) emit 0 MEDIUM "$path" "$line" lexicon-prefer "\"$word\" — say \"$use\".${why:+ $why}" "say \"$use\"" ;;
        soft_verbs) emit 0 LOW "$path" "$line" plain-verb "\"$word\" — say \"$use\".${why:+ $why}" "say \"$use\"" ;;
        invented) emit 0 MEDIUM "$path" "$line" invented-phrase "\"$word\" is built from generic words." \
                    "name the thing — the class, the endpoint, the table, or the vendor's own word" ;;
        newterm) emit 0 LOW "$path" "$line" lexicon-new-term "\"$word\" looks like a new term." \
                   "add it to known_terms in $CONFIG_DIR/lexicon.yml in this change, or write it in plain lower-case words" NEEDS_HUMAN ;;
      esac
    done < <(prose_of "$path" | awk -v cfg="$WORK/lx.tsv" -v status="$status" -v path="$path" "$AWK_LEXICON")
  done < "$WORK/files.tsv"
}
```

Extend `run_rules` with a third group:

```bash
  if want lexicon; then
    rule_lexicon
  fi
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash scripts/tests/test-speckit-standards.sh`
Expected: `ALL TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add scripts/speckit-standards.sh scripts/tests/test-speckit-standards.sh
git commit -m "feat(standards): [9cad] lexicon rules"
```

---

### Task 9: `unrated-path`

**Files:**
- Modify: `scripts/speckit-standards.sh` (add `AWK_UNRATED`, `rule_unrated_path`; extend `run_rules`)
- Test: `scripts/tests/test-speckit-standards.sh`

**Interfaces:**
- Consumes: `$WORK/dl.tsv` (`unit_dirs`), `$WORK/level.tsv` (`PATH` lines), `$WORK/files.tsv`, `AWK_GLOB`, `emit`.
- Produces: `rule_unrated_path`.

- [ ] **Step 1: Add the failing tests**

Insert before the `echo` / `ALL TESTS PASSED` block:

```bash
# ── Task 9: unrated-path ────────────────────────────────────────────────────

make_repo fixtures
mkdir -p app/services/reset_visa app/services/repayment_instances app/models lib
printf 'a\n' > app/services/reset_visa/a.rb
printf 'b\n' > app/services/reset_visa/b.rb
printf 'n\n' > app/services/repayment_instances/new.rb
printf 't\n' > app/models/thing.rb
printf 'p\n' > app/models/partner.rb
printf 'l\n' > lib/x.rb
commit_all
engine --base main
check_has "new directory rated only by the catch-all" "$out" "MEDIUM app/services/reset_visa/:0  unrated-path: new directory, rated member-facing only by app/services/**/*"
check_eq "directory reported once" "$(grep -c 'app/services/reset_visa/' <<<"$out")" "1"
check_has "new model file rated only by the catch-all" "$out" "MEDIUM app/models/thing.rb:0  unrated-path: new file, rated member-facing only by app/models/**/*"
check_lacks "directory with its own pattern is rated" "$out" "repayment_instances/:0"
check_lacks "file with its own pattern is rated" "$out" "partner.rb:0"
check_lacks "path outside unit_dirs is ignored" "$out" "lib/x.rb"
engine --base main --format marge
check_has "unrated path needs a human" "$out" "  rule: unrated-path"
cleanup

make_repo fixtures
mkdir -p app/services/reset_visa
printf 'old\n' > app/services/reset_visa/old.rb
commit_all "existing unit"
printf 'b\n' > app/services/reset_visa/b.rb
commit_all
engine --base HEAD~1
check_lacks "a file added to an existing directory is not a new unit" "$out" "unrated-path"
cleanup
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash scripts/tests/test-speckit-standards.sh 2>&1 | grep -c FAIL`
Expected: at least 3.

- [ ] **Step 3: Add the rule**

Insert directly above `run_rules()`:

```bash
# ── Rules: unrated-path ────────────────────────────────────────────────────
# -v cfg=flattened damage-levels -v levels=level.tsv; stdin: "path<TAB>status".
# Output: "UNIT<TAB>unit<TAB>dir|file<TAB>level<TAB>pattern" for an added file whose
# unit (per unit_dirs) is rated only by a pattern above the unit, or by the default.
AWK_UNRATED="$AWK_GLOB"$'\n'"$(cat <<'AWK'
function literal_prefix(g) { sub(/[*?].*$/, "", g); return g }
BEGIN {
  FS = "\t"
  while ((getline l < cfg) > 0) { split(l, kv, "\t"); if (kv[1] ~ /^unit_dirs\.[0-9]+$/) { nu++; ure[nu] = glob_to_ere(kv[2]); useg[nu] = split(kv[2], tmp, "/") } }
  close(cfg)
  while ((getline l < levels) > 0) { split(l, kv, "\t"); if (kv[1] == "PATH") { plevel[kv[2]] = kv[3]; ppat[kv[2]] = kv[4] } }
  close(levels)
}
$2 == "A" {
  path = $1; n = split(path, seg, "/")
  for (u = 1; u <= nu; u++) {
    if (useg[u] > n) continue
    prefix = seg[1]; for (k = 2; k <= useg[u]; k++) prefix = prefix "/" seg[k]
    if (prefix !~ ure[u]) continue
    unit = prefix; kind = (useg[u] < n ? "dir" : "file")
    pat = ppat[path]
    if (pat == "") catchall = 1
    else { lp = literal_prefix(pat); sub(/\/$/, "", lp); catchall = (lp != unit && index(unit, lp "/") == 1) }
    if (catchall && !(unit in reported)) { reported[unit] = 1; print "UNIT\t" unit "\t" kind "\t" plevel[path] "\t" pat }
    break
  }
}
AWK
)"

rule_unrated_path() {
  local _u unit kind level pattern what file f new
  awk -F'\t' '$2 == "A" { print $1 }' "$WORK/files.tsv" > "$WORK/added-paths.txt"
  while IFS="$TAB" read -r _u unit kind level pattern; do
    if [[ "$kind" == dir ]]; then
      new=1
      while IFS= read -r f; do
        grep -qxF -- "$f" "$WORK/added-paths.txt" || { new=0; break; }
      done < <(find "$unit" -type f 2>/dev/null)
      [[ "$new" == 1 ]] || continue
      what="new directory"; file="$unit/"
    else
      what="new file"; file="$unit"
    fi
    emit 0 MEDIUM "$file" 0 unrated-path "$what, rated $level only by ${pattern:-the default level}" \
      "decide its level in $CONFIG_DIR/damage-levels.yml: list it under a more serious level if a mistake there would do more damage than \"$level\" implies" NEEDS_HUMAN
  done < <(cut -f1,2 "$WORK/files.tsv" | awk -v cfg="$WORK/dl.tsv" -v levels="$WORK/level.tsv" "$AWK_UNRATED")
}
```

Extend `run_rules` with the last group:

```bash
  if want unrated-path; then
    rule_unrated_path
  fi
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash scripts/tests/test-speckit-standards.sh`
Expected: `ALL TESTS PASSED`.

Run: `bash .specify/quality-gates.sh`
Expected: no shellcheck output, exit 0.

- [ ] **Step 5: Commit**

```bash
git add scripts/speckit-standards.sh scripts/tests/test-speckit-standards.sh
git commit -m "feat(standards): [9cad] unrated-path rule"
```

---

### Task 10: Baseline wrapper and the runner's baseline loop

**Files:**
- Create: `specify-marge/baseline/standards.sh`
- Modify: `specify-marge/run-gates.sh:38-39` and `:57-85` (the pack loop)
- Create: `scripts/tests/test-run-gates.sh`

**Interfaces:**
- Consumes: the engine CLI from Tasks 1 to 9 and the runner env (`SPECKIT_STAGE`, `SPECKIT_REPO_ROOT`, `SPECKIT_BASE_REF`, `SPECKIT_DIFF_FILES`, `SPECKIT_FEATURE_DIR`).
- Produces: `run-gates.sh` runs `baseline/*.sh` before `project/*.sh`; a failed baseline pack yields `pack: baseline/<name>` with `tags: [NEEDS_HUMAN]`. `baseline/standards.sh` emits the engine's `--format marge` output, opts into planning, and refuses a checkout that disagrees with `SPECKIT_DIFF_FILES`.

- [ ] **Step 1: Write the failing runner tests**

`scripts/tests/test-run-gates.sh`:

```bash
#!/usr/bin/env bash
# Tests for specify-marge/run-gates.sh and specify-marge/baseline/standards.sh.
# Run from anywhere: bash scripts/tests/test-run-gates.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="$HERE/../../specify-marge/run-gates.sh"
WRAPPER="$HERE/../../specify-marge/baseline/standards.sh"
ENGINE="$HERE/../speckit-standards.sh"
FIXTURES="$HERE/fixtures/standards"
failures=0

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; failures=$((failures + 1)); }
check_rc() { if [[ "$2" -eq "$3" ]]; then pass "$1"; else fail "$1 (rc=$2, want $3)"; fi; }
check_has() { if grep -qF -- "$3" <<<"$2"; then pass "$1"; else fail "$1 (missing: $3; got: ${2:0:300})"; fi; }
check_lacks() { if grep -qF -- "$3" <<<"$2"; then fail "$1 (unexpected: $3)"; else pass "$1"; fi; }
check_before() { # $1 desc, $2 text, $3 first, $4 second
  local a b
  a=$(grep -nF -- "$3" <<<"$2" | head -n 1 | cut -d: -f1); b=$(grep -nF -- "$4" <<<"$2" | head -n 1 | cut -d: -f1)
  if [[ -n "$a" && -n "$b" && "$a" -lt "$b" ]]; then pass "$1"; else fail "$1 ($3 at ${a:-none}, $4 at ${b:-none})"; fi
}

make_repo() {
  sandbox=$(mktemp -d)
  cd "$sandbox" || exit 1
  git init -q -b main 2>/dev/null || { git init -q && git checkout -q -b main; }
  git config user.email test@test
  git config user.name tester
  mkdir -p .specify/marge/baseline .specify/marge/project .specify/marge/config .specify/scripts/bash
  cp "$RUNNER" .specify/marge/run-gates.sh
  printf 'base\n' > base.txt
  git add -A; git commit -qm init
  git checkout -qb work
}
cleanup() { cd / && rm -rf "$sandbox"; }
finding() { # $1 pack label, $2 rule
  printf -- '- file: x.rb:1\n  severity: LOW\n  confidence: 100\n  pack: %s\n  rule: %s\n  issue: "i"\n  tags: []\n' "$1" "$2"
}

# 1. Baseline script packs run first, then project packs.
make_repo
printf '#!/usr/bin/env bash\nprintf -- "- file: x.rb:1\\n  severity: LOW\\n  confidence: 100\\n  pack: baseline/one.sh\\n  rule: base-rule\\n  issue: \\"b\\"\\n  tags: []\\n"\n' > .specify/marge/baseline/one.sh
printf '#!/usr/bin/env bash\nprintf -- "- file: y.rb:1\\n  severity: LOW\\n  confidence: 100\\n  pack: project/two.sh\\n  rule: proj-rule\\n  issue: \\"p\\"\\n  tags: [PROJECT_GATE]\\n"\n' > .specify/marge/project/two.sh
out=$(SPECKIT_BASE_REF=main SPECKIT_REPO_ROOT="$PWD" bash .specify/marge/run-gates.sh 2>/dev/null); rc=$?
check_rc "runner exits 0" "$rc" 0
check_has "baseline pack ran" "$out" "rule: base-rule"
check_has "project pack ran" "$out" "rule: proj-rule"
check_before "baseline findings come first" "$out" "rule: base-rule" "rule: proj-rule"
cleanup

# 2. A failing baseline pack yields a baseline meta-finding without PROJECT_GATE.
make_repo
printf '#!/usr/bin/env bash\necho boom >&2\nexit 3\n' > .specify/marge/baseline/bad.sh
printf '#!/usr/bin/env bash\nexit 3\n' > .specify/marge/project/worse.sh
out=$(SPECKIT_BASE_REF=main SPECKIT_REPO_ROOT="$PWD" bash .specify/marge/run-gates.sh 2>/dev/null)
check_has "baseline meta-finding labelled by origin" "$out" "pack: baseline/bad.sh"
check_has "baseline meta-finding file" "$out" "- file: .specify/marge/baseline/bad.sh:0"
check_has "baseline meta-finding tags" "$out" "tags: [NEEDS_HUMAN]"
check_has "baseline meta-finding carries stderr" "$out" "script pack failed to run (exit 3): boom"
check_has "project meta-finding keeps PROJECT_GATE" "$out" "tags: [PROJECT_GATE, NEEDS_HUMAN]"
cleanup

# 3. Planning stage runs only opted-in packs, from both directories.
make_repo
printf '#!/usr/bin/env bash\n# speckit-stage: planning\n' > .specify/marge/baseline/plan.sh
cat >> .specify/marge/baseline/plan.sh <<'EOF'
printf -- "- file: spec.md:1\n  severity: LOW\n  confidence: 100\n  pack: baseline/plan.sh\n  rule: planning-rule\n  issue: \"p\"\n  tags: []\n"
EOF
printf '#!/usr/bin/env bash\nprintf -- "- file: x.rb:1\\n  severity: LOW\\n  confidence: 100\\n  pack: baseline/review.sh\\n  rule: review-only\\n  issue: \\"r\\"\\n  tags: []\\n"\n' > .specify/marge/baseline/review.sh
out=$(SPECKIT_STAGE=planning SPECKIT_FEATURE_DIR=specs/x SPECKIT_REPO_ROOT="$PWD" bash .specify/marge/run-gates.sh 2>/dev/null)
check_has "planning runs the opted-in baseline pack" "$out" "rule: planning-rule"
check_lacks "planning skips a review-only baseline pack" "$out" "rule: review-only"
cleanup

# 4. The shipped wrapper: review stage emits engine findings in marge format.
make_repo
cp "$WRAPPER" .specify/marge/baseline/standards.sh
cp "$ENGINE" .specify/scripts/bash/speckit-standards.sh; chmod +x .specify/scripts/bash/speckit-standards.sh
cp "$FIXTURES/damage-levels.yml" "$FIXTURES/lexicon.yml" .specify/marge/config/
printf 'Underwriting here.\n' > note.txt
git add -A; git commit -qm change
out=$(SPECKIT_BASE_REF=main SPECKIT_REPO_ROOT="$PWD" bash .specify/marge/run-gates.sh 2>/dev/null); rc=$?
check_rc "wrapper run exits 0 even with a blocking finding" "$rc" 0
check_has "wrapper emits the engine finding" "$out" "rule: lexicon-banned"
check_has "wrapper finding carries the pack label" "$out" "pack: baseline/standards.sh"
check_lacks "wrapper never emits PROJECT_GATE" "$out" "PROJECT_GATE"
cleanup

# 5. The wrapper refuses a checkout that disagrees with the pull request's file list.
make_repo
cp "$WRAPPER" .specify/marge/baseline/standards.sh
cp "$ENGINE" .specify/scripts/bash/speckit-standards.sh; chmod +x .specify/scripts/bash/speckit-standards.sh
cp "$FIXTURES/damage-levels.yml" .specify/marge/config/
printf 'x\n' > note.txt
git add -A; git commit -qm change
out=$(SPECKIT_BASE_REF=main SPECKIT_DIFF_FILES="other.rb" SPECKIT_REPO_ROOT="$PWD" bash .specify/marge/run-gates.sh 2>/dev/null)
check_has "mismatched checkout is a pack-execution finding" "$out" "pack: baseline/standards.sh"
check_has "mismatched checkout explains itself" "$out" "the checkout is not the pull request head"
cleanup

# 6. The wrapper is silent without the engine, and runs --dir at planning.
make_repo
cp "$WRAPPER" .specify/marge/baseline/standards.sh
out=$(SPECKIT_BASE_REF=main SPECKIT_REPO_ROOT="$PWD" bash .specify/marge/run-gates.sh 2>/dev/null); rc=$?
check_rc "no engine: exit 0" "$rc" 0
check_lacks "no engine: no findings" "$out" "pack:"
cp "$ENGINE" .specify/scripts/bash/speckit-standards.sh; chmod +x .specify/scripts/bash/speckit-standards.sh
cp "$FIXTURES/damage-levels.yml" "$FIXTURES/lexicon.yml" .specify/marge/config/
mkdir -p specs/9cad-feat-x
printf '# Spec\n\n## User Scenarios\n\nUnderwriting.\n' > specs/9cad-feat-x/spec.md
out=$(SPECKIT_STAGE=planning SPECKIT_FEATURE_DIR=specs/9cad-feat-x SPECKIT_BASE_REF=main SPECKIT_REPO_ROOT="$PWD" bash .specify/marge/run-gates.sh 2>/dev/null)
check_has "planning sees the untracked spec" "$out" "rule: plain-summary-missing"
check_has "planning runs the lexicon group" "$out" "rule: lexicon-banned"
cleanup

echo
if [[ "$failures" -eq 0 ]]; then
  echo "ALL TESTS PASSED"
else
  echo "$failures TEST(S) FAILED"
  exit 1
fi
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash scripts/tests/test-run-gates.sh 2>&1 | grep -c FAIL`
Expected: at least 12 (no baseline loop; no wrapper file).

- [ ] **Step 3: Change the runner**

In `specify-marge/run-gates.sh`, replace lines 38 and 39:

```bash
packs_dir="$repo_root/.specify/marge/project"
[ -d "$packs_dir" ] || exit 0
```

with:

```bash
# Baseline script packs (shipped, seeded once) run first; project packs after.
baseline_dir="$repo_root/.specify/marge/baseline"
project_dir="$repo_root/.specify/marge/project"
[ -d "$baseline_dir" ] || [ -d "$project_dir" ] || exit 0
```

Update the header comment on line 4 to read `# Discovers .specify/marge/baseline/*.sh and .specify/marge/project/*.sh (script packs), runs each under a timeout`.

Replace the pack loop (from `for pack in "$packs_dir"/*.sh; do` through its closing `done`) with:

```bash
run_packs_in() {  # $1 = directory, $2 = origin label (baseline|project)
  local dir="$1" origin="$2" pack name header rc out last_err issue tags
  [ -d "$dir" ] || return 0
  if [ "$origin" = baseline ]; then tags="NEEDS_HUMAN"; else tags="PROJECT_GATE, NEEDS_HUMAN"; fi
  for pack in "$dir"/*.sh; do
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
- file: .specify/marge/$origin/$name:0
  severity: LOW
  confidence: 100
  pack: $origin/$name
  rule: pack-execution
  issue: "$issue"
  tags: [$tags]
YAML
    fi
  done
}

run_packs_in "$baseline_dir" baseline
run_packs_in "$project_dir" project
```

Keep the final `exit 0`.

- [ ] **Step 4: Write the wrapper**

`specify-marge/baseline/standards.sh`:

```bash
#!/usr/bin/env bash
# Runs the shipped standards engine (damage level, lexicon, plain language,
# PR shape) as a baseline script pack. Edit --only to tune; delete to opt out.
# Seeded once by setup.sh; updates never touch it. Contract: .specify/marge/README.md.
# speckit-stage: planning
set -uo pipefail

engine=".specify/scripts/bash/speckit-standards.sh"
[ -x "$engine" ] || exit 0
base="${SPECKIT_BASE_REF:-origin/main}"

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
```

Run: `chmod +x specify-marge/baseline/standards.sh`

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bash scripts/tests/test-run-gates.sh`
Expected: `ALL TESTS PASSED`.

Run: `bash scripts/tests/test-speckit-standards.sh && shellcheck --severity=warning specify-marge/run-gates.sh specify-marge/baseline/standards.sh scripts/tests/test-run-gates.sh`
Expected: `ALL TESTS PASSED`, no shellcheck output.

- [ ] **Step 6: Commit**

```bash
git add specify-marge/run-gates.sh specify-marge/baseline/standards.sh scripts/tests/test-run-gates.sh
git commit -m "feat(marge): [9cad] baseline script packs and the shipped standards wrapper"
```

---

### Task 11: Seeds, `setup.sh`, and this repo's quality gate

**Files:**
- Create: `specify-marge/config/damage-levels.yml`
- Create: `specify-marge/config/lexicon.yml`
- Modify: `setup.sh` (engine copy, baseline `*.sh` seeding, config seeding, echo lines)
- Create: `scripts/tests/test-setup-standards.sh`
- Modify: `.specify/quality-gates.sh`

**Interfaces:**
- Produces: a consumer running `setup.sh` gets `.specify/scripts/bash/speckit-standards.sh` (overwritten, executable), `.specify/marge/baseline/standards.sh` (seeded once, executable), `.specify/marge/config/damage-levels.yml` and `lexicon.yml` (seeded once). The seeds parse with the engine and leave a fresh repo clean.

- [ ] **Step 1: Write the failing setup test**

`scripts/tests/test-setup-standards.sh`:

```bash
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

printf '# mine\n' > .specify/marge/baseline/standards.sh
printf '# mine\n' > .specify/marge/config/lexicon.yml
printf '# old engine\n' > .specify/scripts/bash/speckit-standards.sh
bash "$REPO/setup.sh" >/dev/null 2>&1
check_eq "wrapper preserved on re-install" "$(cat .specify/marge/baseline/standards.sh)" "# mine"
check_eq "lexicon preserved on re-install" "$(cat .specify/marge/config/lexicon.yml)" "# mine"
check_eq "engine refreshed on re-install" "$(head -n 1 .specify/scripts/bash/speckit-standards.sh)" "#!/usr/bin/env bash"

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

echo
if [[ "$failures" -eq 0 ]]; then echo "ALL TESTS PASSED"; else echo "$failures TEST(S) FAILED"; exit 1; fi
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash scripts/tests/test-setup-standards.sh 2>&1 | grep -c FAIL`
Expected: at least 5.

- [ ] **Step 3: Write the seeds**

`specify-marge/config/damage-levels.yml`:

```yaml
# How much damage a mistake could do, decided by which files changed.
# Read by .specify/scripts/bash/speckit-standards.sh. Guide: README.md "Standards checks".
#
# A file gets the level of the most specific pattern it matches (a tie goes to
# the more serious level). A change gets the highest level of any file in it.
# A path that matches nothing gets `default_level`. Levels are listed from most
# to least serious. The level says how hard to look, not how big the change is:
# a large change with no runtime effect is a skim, a one-line change to a
# payment calculator is not.
#
# `reviewer` and `checklist` go into the pull request description. A checklist
# entry is a question, or a `question` with `paths`: asked only when the change
# touches one of them. Those paths belong to the level too.
#
# Patterns are shell globs: `*` stops at `/`, `**` crosses directories. Quote a
# pattern that starts with `.` or `*`. Out of the box only specification,
# internal, and no-runtime-effect paths are set; everything else is
# user-facing until you list your critical paths under `critical`.

default_level: user-facing

# A path under `from` is also matched as if it lived under `to`, so a job can
# inherit its service directory's level. Example:
#   - from: app/jobs/
#     to: app/services/
aliases: []

# Places where a new directory or file deserves a level of its own. A new unit
# rated only by a catch-all pattern is reported (unrated-path) so someone decides.
# Example:
#   - app/services/*
#   - app/models/*.rb
unit_dirs: []

# Globs whose first wildcard segment names a boundary: a vendor integration, a
# bounded context. A change touching two or more is reported (many-boundaries).
# Example:
#   - app/services/vendor_*/**
boundaries: []

levels:
  - name: critical
    reviewer: >-
      Read every line. Work the checklist.
    checklist:
      - What happens if this runs twice?
      - What happens if it fails halfway through?
      - Can a user see or change data that is not theirs?
      - Is the migration reversible? Does it lock a large table?
      - Is the failure path tested, not just the happy path?
      - question: >-
          Who can reach this? Can a secret, a credential or personal data end
          up in a log, a response or an unencrypted column?
        paths: []
        # Sign-in, sessions, permissions, secrets, encrypted columns, for example:
        #   - app/policies/**/*
        #   - config/initializers/**/*
      - question: >-
          Does this change what a user is told or agrees to? Should users who
          accepted the old version accept again?
        paths: []
        # Disclosures, terms, agreements, for example:
        #   - app/views/legal/**/*
    paths: []
    # Code that moves money or data of record, decides who may act, or stores
    # secrets or personal data, for example:
    #   - db/migrate/**/*
    #   - app/services/payments/**/*

  - name: user-facing
    reviewer: >-
      Read every hunk. Confirm the author's screenshot or live check.
    checklist:
      - Does the screenshot or live check match what the code does?
      - What does a user see when a dependency fails?
      - Does the change alter what an existing user already sees?
    paths: []
    # Everything a user can see or do; often the whole application tree:
    #   - src/**/*
    #   - app/**/*

  - name: specification
    reviewer: >-
      Read all of it. This is the feature. Send it back if a sentence needs
      decoding.
    checklist:
      - Can you say in two sentences what a user or an operator gets when this ships?
      - Is there a phrase built from generic words where the thing has a name?
      - Is there a word the lexicon and the code do not use?
      - Did any sentence need a second read?
    paths:
      - specs/**/*

  - name: internal
    reviewer: >-
      Skim. Look closely at the one hunk the author flagged in "Where to look".
    checklist:
      - Does the flagged hunk do what the description says?
    paths:
      - .specify/**/*
      - .claude/**/*
      - .github/**/*
      - ".*"
      # Staff tools, metrics, scripts, deploy tooling, for example:
      #   - script/**/*
      #   - app/services/metrics/**/*

  - name: no runtime effect
    reviewer: >-
      Approve. Nobody is expected to read this line by line.
    checklist: []
    paths:
      - docs/**/*
      - "**/*.md"
      # Test-only directories, for example:
      #   - test/**/*
      #   - spec/**/*
```

`specify-marge/config/lexicon.yml`:

```yaml
# The words this project uses, machine half. Read by
# .specify/scripts/bash/speckit-standards.sh, which scans ADDED prose only:
# Markdown outside code fences, and comment lines in code. Identifiers are
# never scanned. Patterns are POSIX extended regular expressions matched
# case-insensitively at word boundaries (the engine adds the boundaries; never
# write \b). No lookaround: `unless` lists patterns that, when any matches the
# same line, suppress the entry for that line.
#
#   banned            blocks: the Stop hook and Marge treat it as a must-fix.
#   prefer            warns. The canonical word is preferred; the other has real uses.
#   soft_verbs        warns. Filler verbs with a plain replacement.
#   invented_phrases  warns. Generic words chained into a term that names nothing.
#   known_terms       Title Case phrases that are not new terms (headings, products).
#   exempt_paths      files never scanned (the lexicon has to name the words it bans).

banned: []
#   - pattern: 'underwrit[[:alnum:]_]*'
#     use: risk assessment
#     why: We do not do this.

prefer: []
#   - pattern: 'customers?'
#     use: member
#     why: One word for the person.
#     unless:
#       - 'customer_state'

soft_verbs:
  - pattern: 'utili[sz][[:alnum:]_]+'
    use: use
  - pattern: 'leverag[[:alnum:]_]+'
    use: use
  - pattern: 'facilitat[[:alnum:]_]+'
    use: let, help
  - pattern: 'materiali[sz][[:alnum:]_]+'
    use: build, write
  - pattern: 'ensur[[:alnum:]_]+'
    use: check, make sure
  - pattern: 'perform(s|ed|ing)? validation'
    use: check
  - pattern: 'provid[[:alnum:]_]+ the ability to'
    use: let
  - pattern: 'surfac(e|es|ed|ing) (the|a|an|to|it|them|this|that)'
    use: show

# Phrases built from generic words instead of the name of the thing. Any word
# before one of these nouns is flagged, and so is any "<word>-neutral",
# "-agnostic", ... before a noun. A listed noun after an article, or on its
# own, is not. Warns; never blocks: the check cannot know the right name.
invented_phrases:
  nouns: [seam, surface, layer, boundary, primitive, fabric, substrate, plane, mechanism, machinery, scaffold, scaffolding, shim, harness, lever, indirection, facade, touchpoint, affordance, construct, topology, chokepoint]
  compound_suffixes: [neutral, agnostic, aware, driven, centric, oriented]
  allowed:
    - test harness
    - attack surface

exempt_paths:
  - .specify/marge/config/lexicon.yml
  - .specify/marge/README.md

known_terms:
  - User Story
  - User Scenarios
  - Success Criteria
  - Functional Requirements
  - Key Entities
  - Edge Cases
  - Plain Summary
  - Acceptance Scenarios
  - Independent Test
  - Pull Request Plan
  - Phase Boundary
  - Inherited Scope
  - Minimum Viable Product
```

- [ ] **Step 4: Change `setup.sh`**

After the commit-helper copy block (the lines ending `chmod +x "$PROJECT_DIR/.specify/scripts/bash/speckit-commit.sh"`), add:

```bash
# Standards engine (Pattern A: OVERWRITE). The baseline wrapper that calls it and
# the two config files it reads are seeded once, below, so consumer edits survive.
cp "$SCRIPT_DIR/scripts/speckit-standards.sh" "$PROJECT_DIR/.specify/scripts/bash/speckit-standards.sh"
chmod +x "$PROJECT_DIR/.specify/scripts/bash/speckit-standards.sh"
```

In the `echo "  Copied files:"` list, after `echo "    .specify/scripts/bash/speckit-commit.sh"`, add:

```bash
echo "    .specify/scripts/bash/speckit-standards.sh"
```

In section `2b. Seed Marge baseline packs`, change the loop header `for pack in "$SCRIPT_DIR/specify-marge/baseline/"*.md; do` to `for pack in "$SCRIPT_DIR/specify-marge/baseline/"*.md "$SCRIPT_DIR/specify-marge/baseline/"*.sh; do`, and after the line `cp "$pack" "$target"` inside it add:

```bash
    [[ "$pack" == *.sh ]] && chmod +x "$target"
```

Update that section's leading comment from `Baseline packs ship from the non-hidden source dir specify-marge/baseline/.` to `Baseline packs (prose *.md and the one shipped script pack, standards.sh) ship from the non-hidden source dir specify-marge/baseline/.`

In section `2c`, after the two `cp` lines for the READMEs, add:

```bash
# Standards config data: seeded once, never overwritten (consumer-owned data).
for seed in damage-levels.yml lexicon.yml; do
  if [[ -f "$PROJECT_DIR/.specify/marge/config/$seed" ]]; then
    echo "  .specify/marge/config/$seed already exists — skipped"
  else
    cp "$SCRIPT_DIR/specify-marge/config/$seed" "$PROJECT_DIR/.specify/marge/config/$seed"
    echo "  Seeded .specify/marge/config/$seed"
  fi
done
```

- [ ] **Step 5: Extend this repo's quality gate**

Replace `.specify/quality-gates.sh` with:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Collect shell files that actually exist
files=()
for pattern in *.sh scripts/*.sh scripts/tests/*.sh specify-marge/*.sh specify-marge/baseline/*.sh .specify/scripts/bash/*.sh .specify/marge/*.sh .specify/marge/project/*.sh; do
  for f in $pattern; do
    [ -f "$f" ] && files+=("$f")
  done
done

if [ ${#files[@]} -eq 0 ]; then
  echo "No shell files found to check"
  exit 0
fi

shellcheck --severity=warning "${files[@]}"

for t in scripts/tests/test-*.sh; do
  [ -f "$t" ] || continue
  bash "$t" >/dev/null || { echo "FAIL: $t"; bash "$t" | grep '^FAIL'; exit 1; }
done
```

- [ ] **Step 6: Run everything to verify it passes**

Run: `bash scripts/tests/test-setup-standards.sh`
Expected: `ALL TESTS PASSED`.

Run: `bash .specify/quality-gates.sh`
Expected: no output, exit 0 (shellcheck clean, all three test files green).

- [ ] **Step 7: Commit**

```bash
git add specify-marge/config/damage-levels.yml specify-marge/config/lexicon.yml setup.sh scripts/tests/test-setup-standards.sh .specify/quality-gates.sh
git commit -m "feat(setup): [9cad] install the standards engine, seed the wrapper and config"
```

---

### Task 12: Documentation

**Files:**
- Modify: `README.md` (install table, Customization)
- Modify: `specify-marge/README.md` (glossary, layout, script pack contract)
- Modify: `specify-marge/config/README.md`
- Modify: `speckit-skills/speckit-review/reference/pack-execution.md` (section 3)
- Modify: `claude-agents/lisa.md` (Phase 1 step 1), `claude-agents/marge.md` (File Paths)
- Modify: `speckit-skills/speckit-review-pr/SKILL.md` (Step 5 note)
- Modify: `templates/CLAUDE.md` (Speckit section)

**Interfaces:** none; prose only. Every claim below must match the shipped behaviour of Tasks 1 to 11.

- [ ] **Step 1: README.md**

In the install table, after the row `| `scripts/speckit-commit.sh` | `.specify/scripts/bash/` | overwritten |`, add:

```markdown
| `scripts/speckit-standards.sh` | `.specify/scripts/bash/` | overwritten (the standards engine) |
| `specify-marge/baseline/standards.sh` | `.specify/marge/baseline/` | **preserved** — the wrapper that runs the engine; edit `--only` or delete to opt out |
| `specify-marge/config/damage-levels.yml`, `config/lexicon.yml` | `.specify/marge/config/` | **preserved** — your damage levels and your words |
```

In the sentence after the table that begins `To do it manually,`, change `` `chmod +x` the two `.sh` files `` to `` `chmod +x` the four `.sh` files ``.

Before `### Dogfooding this repo`, add:

```markdown
### Standards checks

Marge and Lisa also run a deterministic engine, `.specify/scripts/bash/speckit-standards.sh`, through the seeded baseline script pack `standards.sh`. It reports three things about a change:

- **Damage level.** `config/damage-levels.yml` maps paths to levels, most to least serious: `critical`, `user-facing`, `specification`, `internal`, `no runtime effect`. A file takes the most specific matching pattern, a change takes its highest file, and each level carries a reviewer line and a checklist. The level is a floor: raise it in the PR description when it understates the risk, never lower it. Fill in the `paths:` lists for your tree; the seed only rates specs, dotfiles, docs, and Markdown.
- **PR shape.** A requirement id (`FR-001`, `US2`) in a PR description, a new `specs/*/spec.md` without a `## Plain summary` of 150 words or fewer, and a banned word all **block**: Marge must fix them and the engine exits 1. Specs mixed with code, a change spanning two `boundaries:`, and a new unit under `unit_dirs:` rated only by a catch-all are advice for a person (`NEEDS_HUMAN`).
- **Plain language.** Sentences over 25 words, more than 4 comment lines in a row, filler verbs, invented phrases (`vendor-neutral seam`), and Title Case terms a new spec coins are advice. Words live in `config/lexicon.yml`: `banned`, `prefer`, `soft_verbs`, `invented_phrases`, `known_terms`, `exempt_paths`. Patterns are POSIX ERE, matched case-insensitively at word boundaries, with `unless:` instead of lookaround.

Run it yourself from the repo root:

```bash
bash .specify/scripts/bash/speckit-standards.sh --base origin/main            # the branch
bash .specify/scripts/bash/speckit-standards.sh --working-tree                # uncommitted work
bash .specify/scripts/bash/speckit-standards.sh --dir specs/1a2b-feat-x       # one spec directory
bash .specify/scripts/bash/speckit-standards.sh --base origin/main --body-file pr.md --format marge
```

Exit 0 is clean or advice, 1 means a finding blocks, 2 means the engine could not run. `--only lexicon,plain-language,pr-shape,unrated-path` picks groups; `--blocking-only` hides advice; `--format hook` emits the Claude Code Stop-hook JSON. If `damage-levels.yml` is absent the engine prints nothing and exits 0; if `lexicon.yml` is absent only the lexicon rules are skipped. The wrapper opts into Lisa's planning stage with the `lexicon`, `plain-language`, and `pr-shape` groups against the spec directory.
```

- [ ] **Step 2: `specify-marge/README.md`**

In the glossary's **origin** bullet, change `` `baseline/` (shipped, generic code-quality) `` to `` `baseline/` (shipped: generic code-quality prose packs and the one shipped script pack, `standards.sh`) ``.

In the Layout table, change the `baseline/` row's "Holds" cell to: `` shipped prose packs (`security.md`, `concurrency.md`, …) and the shipped standards script pack (`standards.sh`, a wrapper around `.specify/scripts/bash/speckit-standards.sh`). Findings never carry `PROJECT_GATE`. `` and the `config/` row's "Holds" cell to: `` `*.yml` / `*.json` data read by config-backed prose packs in `project/`, plus the seeded `damage-levels.yml` and `lexicon.yml` the standards engine reads ``.

Change the `run-gates.sh` row's "Holds" cell to `` the runner that executes every `baseline/*.sh` and `project/*.sh` script pack ``.

In "Script pack contract", change the first sentence `The shipped runner `.specify/marge/run-gates.sh` discovers every `*.sh` in `project/` and runs each under a ~120s timeout` to `The shipped runner `.specify/marge/run-gates.sh` discovers every `*.sh` in `baseline/` (run first) and `project/` and runs each under a ~120s timeout`.

In the same section's "Exit code" bullets, change `the runner records one `LOW` / `NEEDS_HUMAN` meta-finding (`rule: pack-execution`)` to `the runner records one `LOW` meta-finding (`rule: pack-execution`, `pack: <origin>/<name>`), tagged `[PROJECT_GATE, NEEDS_HUMAN]` for a project pack and `[NEEDS_HUMAN]` for a baseline pack`.

In the "Output (stdout)" bullets, change `Always include `PROJECT_GATE` in `tags`.` to `A project pack always includes `PROJECT_GATE` in `tags`; the baseline standards pack never does.`

- [ ] **Step 3: `specify-marge/config/README.md`**

Append:

```markdown

Two files are seeded here by `setup.sh` and read by the standards engine (`.specify/scripts/bash/speckit-standards.sh`, run by `../baseline/standards.sh`): `damage-levels.yml` (levels, reviewer lines, checklists, `aliases`, `unit_dirs`, `boundaries`) and `lexicon.yml` (`banned`, `prefer`, `soft_verbs`, `invented_phrases`, `known_terms`, `exempt_paths`). They are yours: updates never overwrite them. Delete `damage-levels.yml` and the engine goes silent.
```

- [ ] **Step 4: `speckit-skills/speckit-review/reference/pack-execution.md`**

Replace the first paragraph of section `## 3. Run script packs` with:

```markdown
**Script packs** are deterministic checks: `.specify/marge/baseline/standards.sh` (shipped; runs the standards engine for the damage level, PR shape, plain language, and lexicon) and project continuity checks under `.specify/marge/project/*.sh`. All are executed by the shipped runner `.specify/marge/run-gates.sh` (contract: `.specify/marge/README.md`), baseline first. The runner discovers the script packs, applies the per-pack timeout, exports the contract env, and emits findings — or one `pack-execution` meta-finding per failed pack — on stdout; it never aborts.
```

In the same section, change `each item already carries `pack: project/<name>` and `PROJECT_GATE`` to `each item already carries its `pack:` label (`baseline/standards.sh` or `project/<name>`); project items carry `PROJECT_GATE`, baseline items never do`, and change `If `.specify/marge/project/` is absent the runner prints nothing — script packs are optional` to `If neither directory holds a `*.sh` the runner prints nothing — script packs are optional`.

- [ ] **Step 5: `claude-agents/lisa.md` and `claude-agents/marge.md`**

In `lisa.md` Phase 1 step 1, change `It discovers `.specify/marge/project/*.sh` and runs ONLY packs that opt in` to `It discovers `.specify/marge/baseline/*.sh` and `.specify/marge/project/*.sh` and runs ONLY packs that opt in`, and change `Treat stdout as findings (each tagged `PROJECT_GATE`;` to `Treat stdout as findings (project items tagged `PROJECT_GATE`, baseline items untagged;`.

In `marge.md` File Paths, change the line `- Baseline review packs: `.specify/marge/baseline/*.md`` to `- Baseline review packs: `.specify/marge/baseline/*.md` (prose) and `.specify/marge/baseline/standards.sh` (the standards engine wrapper; findings untagged)`.

- [ ] **Step 6: `speckit-skills/speckit-review-pr/SKILL.md`**

After the paragraph in Step 5 that begins `Findings from `one-way-doors.md` and `concurrency.md` packs`, add:

```markdown
Findings from the shipped standards pack (`pack: baseline/standards.sh`) follow the ordinary rule: only those tagged `NEEDS_HUMAN` (`specs-mixed-with-code`, `many-boundaries`, `unrated-path`, `lexicon-new-term`) are posted. The rest are mechanical and Marge has already fixed them.
```

- [ ] **Step 7: `templates/CLAUDE.md`**

In the `## Speckit` section, after the **Marge (review)** bullet, add:

```markdown
- **Standards checks** → Marge and Lisa run `.specify/scripts/bash/speckit-standards.sh` through the baseline pack `standards.sh`: damage level from `.specify/marge/config/damage-levels.yml`, PR shape, plain language, and the words in `config/lexicon.yml`. A banned word, a requirement id in a PR description, or a new spec without a `## Plain summary` blocks; the level is a floor an agent never lowers
```

- [ ] **Step 8: Verify and commit**

Run: `bash .specify/quality-gates.sh`
Expected: exit 0.

Run: `grep -rn 'project/\*\.sh' speckit-skills claude-agents specify-marge README.md | grep -v 'baseline'`
Expected: no line that describes script packs as living only under `project/` (lines that merely name the project directory are fine).

```bash
git add README.md specify-marge/README.md specify-marge/config/README.md speckit-skills/speckit-review/reference/pack-execution.md claude-agents/lisa.md claude-agents/marge.md speckit-skills/speckit-review-pr/SKILL.md templates/CLAUDE.md
git commit -m "docs(standards): [9cad] document the standards engine, wrapper, and config"
```

---

## Done when

- `bash .specify/quality-gates.sh` exits 0 on the branch.
- In a scratch consumer repo with `.claude/` and `.specify/`, `bash <repo>/setup.sh` installs the engine, seeds the wrapper and both config files, and `bash .specify/scripts/bash/speckit-standards.sh --base origin/main` prints a `Damage level:` header.
- Phase 2 (`/speckit-pr`, Ralph hint, specify-step instruction) and phase 3 (Stop hook) each get their own plan from the same spec.
