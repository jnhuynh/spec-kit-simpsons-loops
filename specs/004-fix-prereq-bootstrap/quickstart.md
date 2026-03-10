# Quickstart: Fix Prerequisite Bootstrap Ordering

## What Changed

Two files need modifications (plus their root-level copies kept in sync):

1. **`pipeline.sh`** -- `resolve_feature_dir()` gains a bootstrap fallback
2. **`speckit.pipeline.md`** -- Step 1 uses `--paths-only` when bootstrapping

## Change 1: `pipeline.sh` — `resolve_feature_dir()`

**File**: `.specify/scripts/bash/pipeline.sh` (and root copy `pipeline.sh`)

**Current behavior**: When no `spec-dir` argument is provided and auto-detecting from branch, the function requires a matching directory to exist in `specs/`. If none exists, it errors out.

**New behavior**: When no matching directory exists AND the pipeline is bootstrapping (`FROM_STEP=specify` or `DESCRIPTION` is non-empty), construct a prospective path `specs/<branch-name>` from the current branch without requiring the directory to exist. This allows the specify step to create the directory.

**Key constraint**: The `FROM_STEP` and `DESCRIPTION` variables are set before `resolve_feature_dir()` is called (argument parsing happens first), so they are available for the bootstrap check.

**Location in code**: After the branch auto-detect loop (around line 335), before the final error message (line 343). Add a check: if no directory was found but bootstrapping is active, construct and return the path.

## Change 2: `speckit.pipeline.md` — Step 1 feature dir resolution

**File**: `.claude/commands/speckit.pipeline.md` (and root copy `speckit.pipeline.md`)

**Current behavior**: Step 1 (line 89) always runs `check-prerequisites.sh --json` for auto-detection, which triggers full validation (requires feature dir + plan.md to exist).

**New behavior**: When `--from specify` is set or `--description` is provided and no `spec-dir` argument is given, the logic MUST first check the current branch type: (1) if on a feature branch (matches `^[0-9]{3}-` pattern), use `check-prerequisites.sh --json --paths-only` for path resolution without validation; (2) if on a non-feature branch (e.g., `main` or `HEAD`), skip `check-prerequisites.sh` entirely because `check_feature_branch()` in `common.sh` rejects non-feature branches before the `--paths-only` code path is reached — proceed with an empty/unresolved `FEATURE_DIR`. In either case, treat resolution failure as non-fatal when bootstrapping and allow the specify step to proceed. After the specify step completes, re-run `check-prerequisites.sh --json` to obtain the now-valid `FEATURE_DIR` for subsequent steps.

**Location in code**: Step 1, the paragraph starting "If no `spec-dir` is provided" (line 89). Add conditional logic for the bootstrap case.

## Verification

After making these changes, verify with:

```bash
# Test 1: pipeline.sh dry-run from specify (no spec dir exists)
git checkout main
.specify/scripts/bash/pipeline.sh --from specify --description "Test feature" --dry-run

# Test 2: Normal pipeline still works (spec dir exists)
git checkout 004-fix-prereq-bootstrap
.specify/scripts/bash/pipeline.sh --dry-run
```

## Files Modified

| File | Change |
|------|--------|
| `.specify/scripts/bash/pipeline.sh` | `resolve_feature_dir()` bootstrap fallback |
| `pipeline.sh` | Root copy kept in sync |
| `.claude/commands/speckit.pipeline.md` | Step 1 conditional `--paths-only` |
| `speckit.pipeline.md` | Root copy kept in sync |
