#!/usr/bin/env bash
# test-phase-spec-references.sh
#
# Contract test for the reference-based phase child spec model.
#
# Child specs must POINT AT the parent spec rather than duplicate its user
# stories, requirements, entities, and success criteria. This test asserts the
# ship-source markdown encodes that contract:
#
#   - speckit-split generates pointer-only children (Inherited Scope table,
#     FR-P{N}-### phase-local namespace) and no longer copies parent prose
#   - the duplication-driven reconciliation machinery (baseline regeneration,
#     section-by-section manual-edit detection, <!-- CONFLICT --> markers) is gone
#   - the reconcile pipeline step targets the PARENT spec for drift, not the child
#   - homer / premortem / phase skip on child specs
#   - plan / tasks / lisa / ralph / marge / pr-review tell their sub agents to resolve the parent first
#
# Expected: FAILS against the duplication model, PASSES after the reference
#           model lands.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

SPLIT="$REPO_ROOT/speckit-skills/speckit-split/SKILL.md"
STEPS="$REPO_ROOT/speckit-skills/speckit-pipeline/reference/steps"
PIPELINE="$REPO_ROOT/speckit-skills/speckit-pipeline/SKILL.md"
README="$REPO_ROOT/README.md"

PASS=0
FAIL=0

# assert_contains <label> <file> <extended-regex>
assert_contains() {
    local label="$1" file="$2" pattern="$3"
    if grep -Eq -- "$pattern" "$file"; then
        echo "  PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $label"
        echo "        expected $(basename "$(dirname "$file")")/$(basename "$file") to match: $pattern"
        FAIL=$((FAIL + 1))
    fi
}

# assert_absent <label> <file> <extended-regex>
assert_absent() {
    local label="$1" file="$2" pattern="$3"
    if grep -Eq -- "$pattern" "$file"; then
        echo "  FAIL: $label"
        echo "        expected $(basename "$(dirname "$file")")/$(basename "$file") NOT to match: $pattern"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS: $label"
        PASS=$((PASS + 1))
    fi
}

echo "=== Test: reference-based phase child specs ==="
echo ""

echo "Group 1: speckit-split emits pointer-only child specs"
assert_contains "child spec declares an Inherited Scope section" "$SPLIT" '## Inherited Scope'
assert_contains "child spec marks the parent authoritative" "$SPLIT" 'Parent Spec.*AUTHORITATIVE|AUTHORITATIVE'
assert_contains "child spec carries the read-the-parent directive" "$SPLIT" 'phase view, not a standalone spec'
assert_contains "phase-local requirements use the FR-P{N} namespace" "$SPLIT" 'FR-P\{N\}-'
assert_contains "phase-local success criteria use the SC-P{N} namespace" "$SPLIT" 'SC-P\{N\}-'
assert_contains "child spec records phase entry/exit state" "$SPLIT" '## Phase Boundary'
assert_absent "no instruction to copy parent story prose" "$SPLIT" 'Copy the full user story content'
assert_absent "no self-contained/independence requirement" "$SPLIT" 'self-contained|Independence requirement'
echo ""

echo "Group 2: duplication-driven reconciliation is deleted"
assert_absent "no conflict markers in split" "$SPLIT" 'CONFLICT'
assert_absent "no baseline regeneration in split" "$SPLIT" 'Generate the baseline|the .baseline.'
assert_absent "no section-by-section manual-edit detection" "$SPLIT" 'Detect manual edits'
assert_absent "no conflict markers in the reconcile step" "$STEPS/reconcile.md" 'CONFLICT'
echo ""

echo "Group 3: reconcile targets the parent spec for drift"
assert_contains "reconcile detects spec-vs-shipped drift" "$STEPS/reconcile.md" '[Dd]rift'
assert_contains "reconcile writes to the parent spec" "$STEPS/reconcile.md" 'PARENT_DIR>/spec\.md|parent spec'
assert_absent "reconcile no longer re-runs /speckit-split" "$STEPS/reconcile.md" 'STEP_COMMAND: /speckit-split'
echo ""

echo "Group 4: homer / premortem / phase skip on child specs"
for step in homer premortem phase; do
    assert_contains "$step skips child specs" "$STEPS/$step.md" '\-\-p\{N\}\-'
done
echo ""

echo "Group 5: consumers resolve the parent before acting"
for step in plan tasks ralph; do
    assert_contains "$step step tells the sub agent to resolve Inherited Scope" \
        "$STEPS/$step.md" 'Inherited Scope'
done
assert_contains "lisa step resolves the parent for child specs" "$STEPS/lisa.md" 'Inherited Scope|parent spec'
assert_contains "marge step points reviewers at the parent" "$STEPS/marge.md" 'Inherited Scope|parent spec'
assert_contains "pr-review step points the PR reviewer at the parent" "$STEPS/pr-review.md" 'Inherited Scope'
echo ""

echo "Group 6: pipeline spine and docs describe the reference model"
assert_contains "pipeline spine states homer/premortem/phase never run on child specs" \
    "$PIPELINE" 'never run on child specs'
assert_contains "README documents references instead of duplication" \
    "$README" 'Inherited Scope'
echo ""

echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
