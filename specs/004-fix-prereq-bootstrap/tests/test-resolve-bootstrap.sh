#!/usr/bin/env bash
# test-resolve-bootstrap.sh
#
# Asserts that resolve_feature_dir() in pipeline.sh returns a valid path
# (exit 0) when FROM_STEP=specify and no spec directory exists for the
# current branch.
#
# This test extracts resolve_feature_dir() from pipeline.sh and evaluates
# it in an isolated subshell with controlled variables.
#
# Expected: FAILS against unfixed code (resolve_feature_dir errors out),
#           PASSES after the bootstrap fallback is added.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
PIPELINE_SH="$REPO_ROOT/.specify/scripts/bash/pipeline.sh"

PASS=0
FAIL=0

assert_eq() {
    local description="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        echo "  PASS: $description"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $description (expected='$expected', actual='$actual')"
        FAIL=$((FAIL + 1))
    fi
}

assert_exit_zero() {
    local description="$1"
    shift
    local output exit_code=0
    output=$("$@" 2>/dev/null) || exit_code=$?
    if [[ $exit_code -eq 0 ]]; then
        echo "  PASS: $description (exit=0, output='$output')"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $description (exit=$exit_code, output='$output')"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== Test: resolve_feature_dir bootstrap fallback ==="
echo ""

# Extract the resolve_feature_dir function body from pipeline.sh using sed
FUNC_BODY=$(sed -n '/^resolve_feature_dir()/,/^}/p' "$PIPELINE_SH")

if [[ -z "$FUNC_BODY" ]]; then
    echo "FAIL: Could not extract resolve_feature_dir() from $PIPELINE_SH"
    exit 1
fi

# Test 1: On a feature branch with FROM_STEP=specify, DESCRIPTION set,
# and no spec directory, resolve_feature_dir should succeed (exit 0)
# and return a path like specs/<branch>.
echo "Test 1: Feature branch + FROM_STEP=specify + no spec dir -> should resolve"

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
echo "  Current branch: $CURRENT_BRANCH"

# Create a temp dir to simulate a repo root with no matching spec dir
TEMP_ROOT=$(mktemp -d)
mkdir -p "$TEMP_ROOT/specs"
# Do NOT create specs/$CURRENT_BRANCH -- that's the point

RESULT=$(
    # Set up the isolated environment
    REPO_ROOT="$TEMP_ROOT"
    SPEC_DIR_ARG=""
    FROM_STEP="specify"
    DESCRIPTION="test feature"
    RED=""
    GREEN=""
    NC=""

    # Define the function and call it
    eval "$FUNC_BODY"
    resolve_feature_dir
) 2>/dev/null
EXIT_CODE=$?

# Clean up temp dir
rm -rf "$TEMP_ROOT"

assert_eq "resolve_feature_dir exits 0 when FROM_STEP=specify on feature branch" "0" "$EXIT_CODE"

if [[ -n "$RESULT" ]]; then
    echo "  INFO: Resolved path: '$RESULT'"
    # Should contain specs/ and the branch name
    if [[ "$RESULT" == specs/* ]]; then
        echo "  PASS: Path starts with specs/"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Path does not start with specs/ (got '$RESULT')"
        FAIL=$((FAIL + 1))
    fi
else
    echo "  FAIL: resolve_feature_dir returned empty string"
    FAIL=$((FAIL + 1))
fi

# Test 2: On main/HEAD branch with FROM_STEP=specify and DESCRIPTION set,
# resolve_feature_dir should succeed (exit 0) and return an empty string.
# This covers spec.md Edge Case 2 and T003b (main branch bootstrap).
echo "Test 2: Main branch + FROM_STEP=specify + DESCRIPTION set -> should return empty string with exit 0"

TEMP_ROOT=$(mktemp -d)
mkdir -p "$TEMP_ROOT/specs"

RESULT=$(
    REPO_ROOT="$TEMP_ROOT"
    SPEC_DIR_ARG=""
    FROM_STEP="specify"
    DESCRIPTION="test feature"
    RED=""
    GREEN=""
    NC=""

    # Override git to simulate being on 'main' branch
    git() { echo "main"; }
    export -f git

    eval "$FUNC_BODY"
    resolve_feature_dir
) 2>/dev/null
EXIT_CODE=$?

rm -rf "$TEMP_ROOT"

assert_eq "resolve_feature_dir exits 0 when FROM_STEP=specify on main branch" "0" "$EXIT_CODE"

if [[ -z "$RESULT" ]]; then
    echo "  PASS: Returns empty string on main branch (non-fatal, specify step will create branch)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Expected empty string on main branch, got '$RESULT'"
    FAIL=$((FAIL + 1))
fi

# Test 3: On main/HEAD branch WITHOUT bootstrapping flags, resolve_feature_dir
# should fail (exit non-zero). This ensures the error path is preserved.
echo "Test 3: Main branch + no FROM_STEP + no DESCRIPTION -> should fail"

TEMP_ROOT=$(mktemp -d)
mkdir -p "$TEMP_ROOT/specs"

RESULT=$(
    REPO_ROOT="$TEMP_ROOT"
    SPEC_DIR_ARG=""
    FROM_STEP=""
    DESCRIPTION=""
    RED=""
    GREEN=""
    NC=""

    git() { echo "main"; }
    export -f git

    eval "$FUNC_BODY"
    resolve_feature_dir
) 2>/dev/null
EXIT_CODE=$?

rm -rf "$TEMP_ROOT"

assert_eq "resolve_feature_dir exits non-zero on main branch without bootstrap flags" "1" "$EXIT_CODE"

# Summary
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
exit 0
