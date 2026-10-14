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
