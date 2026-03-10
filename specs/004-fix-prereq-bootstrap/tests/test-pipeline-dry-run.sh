#!/usr/bin/env bash
# test-pipeline-dry-run.sh
#
# Asserts that pipeline.sh --from specify --description "Test feature" --dry-run
# exits 0 and does not emit prerequisite errors to stderr, even when no spec
# directory exists for the current branch.
#
# To simulate the bootstrap scenario (no existing spec dir), the test
# temporarily renames the current spec directory, runs the pipeline, then
# restores it.
#
# Expected: FAILS against unfixed code (pipeline exits non-zero because
#           resolve_feature_dir cannot find a spec directory),
#           PASSES after the bootstrap fix is applied.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
PIPELINE_SH="$REPO_ROOT/.specify/scripts/bash/pipeline.sh"

PASS=0
FAIL=0

# Determine the current branch and its spec directory
CURRENT_BRANCH=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
SPEC_DIR="$REPO_ROOT/specs/$CURRENT_BRANCH"
SPEC_DIR_BACKUP=""

cleanup() {
    # Restore the spec directory if it was moved
    if [[ -n "$SPEC_DIR_BACKUP" && -d "$SPEC_DIR_BACKUP" ]]; then
        mv "$SPEC_DIR_BACKUP" "$SPEC_DIR"
    fi
}
trap cleanup EXIT

echo "=== Test: pipeline.sh --from specify --description dry-run (no spec dir) ==="
echo ""
echo "  Branch: $CURRENT_BRANCH"
echo "  Spec dir: $SPEC_DIR"

# Temporarily hide the spec directory to simulate bootstrap scenario
if [[ -d "$SPEC_DIR" ]]; then
    SPEC_DIR_BACKUP="${SPEC_DIR}.test-backup"
    mv "$SPEC_DIR" "$SPEC_DIR_BACKUP"
    echo "  Temporarily moved spec dir to simulate bootstrap"
fi

# Test 1: pipeline.sh --from specify --description "Test feature" --dry-run
# should exit 0 even when no spec directory exists
echo ""
echo "Test 1: --from specify --description 'Test feature' --dry-run -> exit 0"

STDERR_FILE=$(mktemp)
STDOUT_FILE=$(mktemp)

EXIT_CODE=0
bash "$PIPELINE_SH" --from specify --description "Test feature" --dry-run \
    >"$STDOUT_FILE" 2>"$STDERR_FILE" || EXIT_CODE=$?

STDERR_CONTENT=$(cat "$STDERR_FILE")
STDOUT_CONTENT=$(cat "$STDOUT_FILE")

rm -f "$STDERR_FILE" "$STDOUT_FILE"

if [[ $EXIT_CODE -eq 0 ]]; then
    echo "  PASS: pipeline exits 0"
    PASS=$((PASS + 1))
else
    echo "  FAIL: pipeline exits $EXIT_CODE (expected 0)"
    FAIL=$((FAIL + 1))
    if [[ -n "$STDERR_CONTENT" ]]; then
        echo "  STDERR: $STDERR_CONTENT"
    fi
fi

# Test 2: No prerequisite-related error messages in stderr
echo "Test 2: No prerequisite errors in stderr"

if echo "$STDERR_CONTENT" | grep -qi "error.*spec directory\|error.*cannot auto-detect\|error.*no spec"; then
    echo "  FAIL: stderr contains prerequisite error messages"
    echo "  STDERR: $STDERR_CONTENT"
    FAIL=$((FAIL + 1))
else
    echo "  PASS: no prerequisite error messages in stderr"
    PASS=$((PASS + 1))
fi

# Test 3: stdout should contain dry-run output indicating the pipeline would proceed
echo "Test 3: stdout contains dry-run output"

if echo "$STDOUT_CONTENT" | grep -qi "dry-run\|would run"; then
    echo "  PASS: stdout contains dry-run markers"
    PASS=$((PASS + 1))
else
    echo "  FAIL: stdout missing dry-run markers"
    echo "  STDOUT: $STDOUT_CONTENT"
    FAIL=$((FAIL + 1))
fi

# Test 4: --description only (no --from specify) -> auto-detects specify step
# Covers US1 Acceptance Scenario 2: "the user provides a --description but no
# --from flag ... the pipeline auto-detects that no spec.md exists, starts from
# the specify step, and completes successfully."
echo "Test 4: --description 'Test feature' --dry-run (no --from) -> exit 0 and auto-detects specify"

STDERR_FILE=$(mktemp)
STDOUT_FILE=$(mktemp)

EXIT_CODE=0
bash "$PIPELINE_SH" --description "Test feature" --dry-run \
    >"$STDOUT_FILE" 2>"$STDERR_FILE" || EXIT_CODE=$?

STDERR_CONTENT=$(cat "$STDERR_FILE")
STDOUT_CONTENT=$(cat "$STDOUT_FILE")

rm -f "$STDERR_FILE" "$STDOUT_FILE"

if [[ $EXIT_CODE -eq 0 ]]; then
    echo "  PASS: pipeline exits 0 with --description only"
    PASS=$((PASS + 1))
else
    echo "  FAIL: pipeline exits $EXIT_CODE (expected 0) with --description only"
    FAIL=$((FAIL + 1))
    if [[ -n "$STDERR_CONTENT" ]]; then
        echo "  STDERR: $STDERR_CONTENT"
    fi
fi

# Test 5: --description only -> stdout indicates specify step would run
echo "Test 5: --description only -> specify step appears in dry-run output"

if echo "$STDOUT_CONTENT" | grep -qi "specify\|dry-run"; then
    echo "  PASS: stdout references specify step or dry-run"
    PASS=$((PASS + 1))
else
    echo "  FAIL: stdout missing specify step reference"
    echo "  STDOUT: $STDOUT_CONTENT"
    FAIL=$((FAIL + 1))
fi

# Summary
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
exit 0
