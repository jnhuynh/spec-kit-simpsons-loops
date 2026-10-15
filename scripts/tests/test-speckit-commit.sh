#!/usr/bin/env bash
# Tests for scripts/speckit-commit.sh. Run from anywhere: bash scripts/tests/test-speckit-commit.sh
set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/speckit-commit.sh"
failures=0

# Each test runs in a fresh sandbox: a work clone with a local bare origin so
# pushes succeed without touching any real remote.
make_sandbox() { # $1 = branch name ("" = detached HEAD)
  sandbox=$(mktemp -d)
  git init -q --bare "$sandbox/origin.git"
  git clone -q "$sandbox/origin.git" "$sandbox/work" 2>/dev/null
  cd "$sandbox/work" || exit 1
  git config user.email test@test
  git config user.name tester
  git commit -q --allow-empty -m init
  git push -q origin HEAD:main
  if [[ -n "$1" ]]; then
    git checkout -q "$1" 2>/dev/null || git checkout -qb "$1"
    git push -qu origin "$1"
  else
    git checkout -q --detach HEAD
  fi
}

cleanup_sandbox() { cd / && rm -rf "$sandbox"; }

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; failures=$((failures + 1)); }
check_eq() { # $1 desc, $2 actual, $3 expected
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1 (got: $2, want: $3)"; fi
}
check_zero() { if [[ "$2" -eq 0 ]]; then pass "$1"; else fail "$1 (rc=$2)"; fi; }
check_nonzero() { if [[ "$2" -ne 0 ]]; then pass "$1"; else fail "$1 (rc=0)"; fi; }

# 1. Conforming branch: commits with derived subject and pushes.
make_sandbox "c31c-feat-billing-overhaul"
touch file.txt
rc=0; bash "$SCRIPT" "test msg" >/dev/null 2>&1 || rc=$?
check_zero "conforming branch exits 0" "$rc"
check_eq "subject derived from branch" "$(git log -1 --format=%s)" "feat(billing-overhaul): [c31c] test msg"
check_eq "commit pushed to origin" "$(git rev-parse origin/c31c-feat-billing-overhaul)" "$(git rev-parse HEAD)"
cleanup_sandbox

# 2. Type override.
make_sandbox "c31c-feat-billing-overhaul"
touch file.txt
bash "$SCRIPT" "polish pass" chore >/dev/null 2>&1
check_eq "type override respected" "$(git log -1 --format=%s)" "chore(billing-overhaul): [c31c] polish pass"
cleanup_sandbox

# 3. Non-conforming branch (no dashes): must refuse before committing.
make_sandbox "main"
touch file.txt
before=$(git rev-parse HEAD)
rc=0; bash "$SCRIPT" "should not land" >/dev/null 2>&1 || rc=$?
check_nonzero "non-conforming branch exits non-zero" "$rc"
check_eq "non-conforming branch creates no commit" "$(git rev-parse HEAD)" "$before"
cleanup_sandbox

# 4. Two-segment branch (empty scope): must refuse.
make_sandbox "fix-thing"
touch file.txt
before=$(git rev-parse HEAD)
rc=0; bash "$SCRIPT" "should not land" >/dev/null 2>&1 || rc=$?
check_nonzero "two-segment branch exits non-zero" "$rc"
check_eq "two-segment branch creates no commit" "$(git rev-parse HEAD)" "$before"
cleanup_sandbox

# 5. Detached HEAD: must refuse before committing.
make_sandbox ""
touch file.txt
before=$(git rev-parse HEAD)
rc=0; bash "$SCRIPT" "should not land" >/dev/null 2>&1 || rc=$?
check_nonzero "detached HEAD exits non-zero" "$rc"
check_eq "detached HEAD creates no commit" "$(git rev-parse HEAD)" "$before"
cleanup_sandbox

# 6. Nothing to commit but local commit unpushed: still pushes.
make_sandbox "c31c-feat-billing-overhaul"
git commit -q --allow-empty -m "feat(billing-overhaul): [c31c] stranded"
rc=0; bash "$SCRIPT" "noop" >/dev/null 2>&1 || rc=$?
check_zero "nothing-to-commit exits 0" "$rc"
check_eq "stranded commit still pushed" "$(git rev-parse origin/c31c-feat-billing-overhaul)" "$(git rev-parse HEAD)"
cleanup_sandbox

# 7. specs/ and code changed together: planning artifacts land in their own
#    `docs` commit before the code commit, and both are pushed.
make_sandbox "c31c-feat-billing-overhaul"
mkdir -p specs/c31c-feat-billing-overhaul
echo plan > specs/c31c-feat-billing-overhaul/plan.md
touch file.txt
rc=0; bash "$SCRIPT" "add billing plan" >/dev/null 2>&1 || rc=$?
check_zero "specs+code exits 0" "$rc"
check_eq "code commit is HEAD" "$(git log -1 --format=%s)" "feat(billing-overhaul): [c31c] add billing plan"
check_eq "docs commit precedes it" "$(git log -1 --format=%s HEAD~1)" "docs(billing-overhaul): [c31c] add billing plan"
check_eq "docs commit holds only specs/" "$(git show --format= --name-only HEAD~1)" "specs/c31c-feat-billing-overhaul/plan.md"
check_eq "code commit holds only code" "$(git show --format= --name-only HEAD)" "file.txt"
check_eq "both commits pushed" "$(git rev-parse origin/c31c-feat-billing-overhaul)" "$(git rev-parse HEAD)"
cleanup_sandbox

# 8. specs/ only: a single docs commit, nothing else, still pushed.
make_sandbox "c31c-feat-billing-overhaul"
mkdir -p specs/c31c-feat-billing-overhaul
echo spec > specs/c31c-feat-billing-overhaul/spec.md
before=$(git rev-parse HEAD)
rc=0; bash "$SCRIPT" "write spec" >/dev/null 2>&1 || rc=$?
check_zero "specs-only exits 0" "$rc"
check_eq "specs-only makes one docs commit" "$(git log -1 --format=%s)" "docs(billing-overhaul): [c31c] write spec"
check_eq "specs-only makes exactly one commit" "$(git rev-parse HEAD~1)" "$before"
check_eq "specs-only commit pushed" "$(git rev-parse origin/c31c-feat-billing-overhaul)" "$(git rev-parse HEAD)"
cleanup_sandbox

echo
if [[ "$failures" -eq 0 ]]; then
  echo "ALL TESTS PASSED"
else
  echo "$failures TEST(S) FAILED"
  exit 1
fi
