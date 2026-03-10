# Tasks: Fix Prerequisite Bootstrap Ordering

**Input**: Design documents from `/specs/004-fix-prereq-bootstrap/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, quickstart.md

**Tests**: Test-first tasks (T002a, T002b) write lightweight Bash assertion scripts that capture expected behavior before implementation. These scripts are executed after implementation (T007, T011) to verify correctness. This satisfies the constitution's test-first mandate without requiring an external test framework.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2)
- Include exact file paths in descriptions

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Verify the current state and understand the code that needs modification

- [x] T001 Read and understand the current `resolve_feature_dir()` function in `.specify/scripts/bash/pipeline.sh` (lines 302-345) and the current Step 1 resolution logic in `.claude/commands/speckit.pipeline.md` (line 89)
- [x] T002 Read and understand the `--paths-only` flag behavior in `.specify/scripts/bash/check-prerequisites.sh` (lines 86-101) to confirm it returns paths without validation

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: No foundational tasks needed — this is a targeted bug fix on existing files with no shared infrastructure to build

**Checkpoint**: Setup complete — user story implementation can now begin

---

## Phase 2b: Test-First — Write Assertion Scripts Before Implementation

**Purpose**: Satisfy the constitution's test-first development mandate (Section: Test-First Development). Write lightweight Bash assertion scripts that define expected behavior for the bootstrap fix. These scripts MUST be written and verified to FAIL against the current (unfixed) code before any implementation begins.

- [x] T002a Write a test script `specs/004-fix-prereq-bootstrap/tests/test-resolve-bootstrap.sh` that asserts `resolve_feature_dir()` returns a valid path (exit 0) when `FROM_STEP=specify` and no spec directory exists. Because `pipeline.sh` is not a sourceable library (it executes top-level code on source), the test script MUST extract the `resolve_feature_dir()` function body from `pipeline.sh` using `sed` and evaluate it in an isolated subshell with the required variables (`REPO_ROOT`, `SPEC_DIR_ARG=""`, `FROM_STEP=specify`, `DESCRIPTION="test"`, and color variables) pre-set. Alternatively, the test can invoke `pipeline.sh --from specify --description "test" --dry-run` as a subprocess and assert the feature directory resolution succeeds (similar to T002b but focused on the resolve step output). Verify this test FAILS against the current unfixed code (exit code != 0), confirming the bug exists.
- [x] T002b Write a test script `specs/004-fix-prereq-bootstrap/tests/test-pipeline-dry-run.sh` that asserts `pipeline.sh --from specify --description "Test feature" --dry-run` exits 0 and does not emit prerequisite errors to stderr. Verify this test FAILS against the current unfixed code, confirming the end-to-end bug exists.

**Checkpoint**: Test scripts exist and fail against the current code, proving the bug. Implementation may now begin.

---

## Phase 3: User Story 1 — Run Full Pipeline from Description (Priority: P1)

**Goal**: Enable the pipeline to start from the `specify` step without requiring a pre-existing spec directory, spec.md, or plan.md. This is the core broken workflow.

**Independent Test**: Run `pipeline.sh --from specify --description "Test feature" --dry-run` from the main branch and verify it resolves the feature directory and proceeds without prerequisite errors.

### Implementation for User Story 1

- [x] T003a [US1] Add bootstrap fallback to `resolve_feature_dir()` in `.specify/scripts/bash/pipeline.sh` — in the `resolve_feature_dir()` function, after the `for dir in ... done` loop and exact-match check, before the final error message: if no directory was found but `FROM_STEP=specify` or `DESCRIPTION` is non-empty AND the current branch is a feature branch (not `main` or `HEAD`), construct and return `specs/$branch` (using the full branch name, NOT prefix glob matching) without requiring the directory to exist. Note: `pipeline.sh` uses a 4-char alphanumeric prefix regex `^([a-z0-9]{4})-` while `common.sh` uses `^([0-9]{3})-`. Since all current branches use 3-digit numeric prefixes (e.g., `004-`), the 4-char regex glob loop in `resolve_feature_dir()` is effectively dead code — resolution always falls through to the exact-match check at line 338. The bootstrap fallback bypasses glob expansion entirely since no directory exists yet
- [x] T003b [US1] Handle the `main` branch bootstrap case in `resolve_feature_dir()` in `.specify/scripts/bash/pipeline.sh` — modify the early `main`/`HEAD` branch check (lines 321-324) so that when on `main` branch (or `HEAD`) and bootstrapping is active (`FROM_STEP=specify` or `DESCRIPTION` is non-empty), the function returns an empty string with a success exit code (instead of erroring out). This change is at lines 321-324 (the existing `main`/`HEAD` guard), NOT after the glob loop at lines 327-335. The pipeline proceeds with an empty `FEATURE_DIR` because the specify step's agent (via `create-new-feature.sh`) will create the feature branch and directory. The caller must check for an empty `FEATURE_DIR` and skip directory-dependent logic until after the specify step completes
- [x] T003c [US1] Add post-specify re-resolution to `pipeline.sh` — after the specify step completes and before subsequent steps (homer, plan, etc.) execute, the pipeline MUST re-call `resolve_feature_dir()` to obtain the now-valid `FEATURE_DIR` (since `create-new-feature.sh` will have created the branch and directory). This re-resolution ensures downstream steps receive a valid path for their prerequisite checks. This covers FR-004. **Error handling**: If re-resolution fails after the specify step (e.g., `create-new-feature.sh` created an unexpected branch name, or the directory was not created), the pipeline MUST abort with a clear error message indicating that the specify step completed but the feature directory could not be resolved — do NOT proceed to homer with an invalid or empty `FEATURE_DIR`
- [x] T004 [US1] Copy the updated `.specify/scripts/bash/pipeline.sh` to the root-level `pipeline.sh` to keep them in sync. **Known limitation**: The root-level copy has an incorrect `REPO_ROOT` derivation (`SCRIPT_DIR/../../..`) that resolves incorrectly when run from the repo root (it goes 3 levels up from the repo root instead of staying at the repo root). This is a pre-existing issue not introduced by this fix. A separate chore should convert the root-level copy to a thin wrapper that delegates to `.specify/scripts/bash/pipeline.sh`
- [x] T005 [US1] Update Step 1 in `.claude/commands/speckit.pipeline.md` (line 89) to conditionally resolve `FEATURE_DIR` when `--from specify` is set or `--description` is provided and no `spec-dir` argument is given. The logic MUST be: (1) determine if the current branch is a feature branch (matches `^[0-9]{3}-` pattern); (2) if on a feature branch, use `check-prerequisites.sh --json --paths-only` for path resolution without validation; (3) if on a non-feature branch (e.g., `main` or `HEAD`), skip `check-prerequisites.sh` entirely because `check_feature_branch()` in `common.sh` rejects non-feature branches before the `--paths-only` code path is reached — proceed with an empty/unresolved `FEATURE_DIR`; (4) in either case, treat resolution failure as non-fatal when bootstrapping and allow the specify step to proceed; (5) after the specify step completes in Step 5, re-run `check-prerequisites.sh --json` to obtain the now-valid `FEATURE_DIR` before passing it to subsequent steps (homer, plan, etc.) — this mirrors the post-specify re-resolution in T003c for pipeline.sh
- [x] T006 [US1] Copy the updated `.claude/commands/speckit.pipeline.md` to the root-level `speckit.pipeline.md` to keep them in sync (root-level copy is byte-identical; the same pre-existing path-derivation caveat from T004 applies to the shell script copy but not to this markdown file)
- [x] T007 [US1] Verify the fix by running the test scripts from T002a and T002b (`bash specs/004-fix-prereq-bootstrap/tests/test-resolve-bootstrap.sh` and `bash specs/004-fix-prereq-bootstrap/tests/test-pipeline-dry-run.sh`) and confirming both now PASS (exit 0). Additionally run `bash .specify/scripts/bash/pipeline.sh --from specify --description "Test feature" --dry-run` and confirm it resolves the feature directory without errors

**Checkpoint**: At this point, the pipeline can start from `specify` with a description and resolve the feature directory without prerequisite errors

---

## Phase 4: User Story 2 — Pipeline Prerequisite Checks Skip Validation for Early Steps (Priority: P2)

**Goal**: Ensure the prerequisite checking system uses path-only resolution for early steps and full validation for later steps, so that the `specify` step can create artifacts that later steps depend on.

**Independent Test**: Invoke `check-prerequisites.sh --json --paths-only` when no spec directory exists and verify it returns path information without errors. Then invoke `check-prerequisites.sh --json` when spec directory and plan.md exist and verify full validation still works.

### Implementation for User Story 2

- [x] T008 [US2] Verify that the `--paths-only` flag in `.specify/scripts/bash/check-prerequisites.sh` already returns path information without validation errors when the spec directory does not exist (READ ONLY — no modification to this file)
- [x] T009 [US2] Verify that existing prerequisite validation in `.claude/commands/speckit.pipeline.md` Step 2 (lines 92-98) correctly handles the case where spec.md does not exist and `--from specify` or `--description` is provided (READ ONLY — no modification needed if logic is correct)
- [x] T010 [US2] Verify that downstream callers (`.claude/commands/speckit.homer.clarify.md`, `.claude/commands/speckit.lisa.analyze.md`, `.claude/commands/speckit.ralph.implement.md`) still use `--json` with full validation and are unaffected by the changes (READ ONLY — no modification to these files)
- [x] T011 [US2] Run `bash .specify/scripts/bash/pipeline.sh --dry-run` from the `004-fix-prereq-bootstrap` branch (where spec.md exists) and verify it auto-detects the starting step correctly with no regressions. Additionally, write and run a regression assertion script `specs/004-fix-prereq-bootstrap/tests/test-existing-pipeline-no-regression.sh` that verifies: (1) `pipeline.sh --dry-run` exits 0 on a feature branch with existing artifacts, (2) prerequisite validation still detects genuinely missing artifacts — specifically: (a) running with `--from homer` when spec.md is absent produces a non-zero exit and a clear error message, (b) running with `--from plan` when spec.md is absent produces a non-zero exit and a clear error message, (c) running with `--from lisa` when tasks.md is absent produces a non-zero exit and a clear error message. This automated regression test covers FR-005 and SC-002/SC-004

**Checkpoint**: Prerequisite checks are stage-aware — early steps use path-only resolution, later steps use full validation

---

## Phase 5: Polish & Cross-Cutting Concerns

**Purpose**: Final validation across all modified files

- [ ] T012 Run shellcheck on `.specify/scripts/bash/pipeline.sh` to verify no new linting errors were introduced
- [ ] T013 Verify byte-identical sync between `.specify/scripts/bash/pipeline.sh` and root-level `pipeline.sh`
- [ ] T014 Verify byte-identical sync between `.claude/commands/speckit.pipeline.md` and root-level `speckit.pipeline.md`
- [ ] T015 Run quickstart.md verification scenarios from `specs/004-fix-prereq-bootstrap/quickstart.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: N/A — no foundational tasks
- **Test-First (Phase 2b)**: Depends on Setup (Phase 1) — writes assertion scripts that MUST fail before implementation
- **User Story 1 (Phase 3)**: Depends on Test-First (Phase 2b) — implements the core fix
- **User Story 2 (Phase 4)**: Depends on User Story 1 (Phase 3) — verifies the fix works correctly for stage-aware validation
- **Polish (Phase 5)**: Depends on both user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Test-First (Phase 2b) — core implementation changes
- **User Story 2 (P2)**: Depends on US1 completion — verification that changes work correctly across all pipeline stages

### Within Each User Story

- Read/understand before modifying
- Modify source files before syncing root copies
- Sync root copies before verification
- Verification last

### Parallel Opportunities

- T003a, T003b, and T003c are sequential within pipeline.sh (T003a and T003b modify resolve_feature_dir(), T003c adds re-resolution logic after the specify step)
- T003a/T003b/T003c and T005 can run in parallel [P] — they modify different files (pipeline.sh vs speckit.pipeline.md)
- T004 and T006 can run in parallel [P] — they sync different files
- T008, T009, T010 can all run in parallel [P] — they are read-only verification tasks on different files
- T012, T013, T014 can all run in parallel [P] — they are independent validation checks

---

## Parallel Example: User Story 1

```bash
# Launch pipeline.sh and speckit.pipeline.md changes together:
Task: "Add bootstrap fallback + main-branch handling + post-specify re-resolution in pipeline.sh (T003a, T003b, T003c)"
Task: "Update Step 1 in .claude/commands/speckit.pipeline.md to use --paths-only for bootstrap (T005)"

# Launch root-level syncs together (after source changes):
Task: "Copy updated pipeline.sh to root-level pipeline.sh"
Task: "Copy updated speckit.pipeline.md to root-level speckit.pipeline.md"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (understand existing code)
2. Complete Phase 2b: Test-First (write assertion scripts, verify they fail)
3. Complete Phase 3: User Story 1 (core fix)
4. **STOP and VALIDATE**: Run test scripts + dry-run pipeline test
5. Deploy/demo if ready

### Incremental Delivery

1. Complete Setup → Understand current codebase
2. Write test scripts → Verify they fail against unfixed code (test-first)
3. Add User Story 1 → Fix bootstrap ordering → Verify tests pass + dry-run (MVP!)
4. Add User Story 2 → Verify stage-aware validation → Confirm no regressions
5. Polish → shellcheck, sync validation, quickstart verification

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- **Constraint**: Do NOT modify `check-prerequisites.sh` internals or `create-new-feature.sh` behavior (explicitly out of scope)
- Only 2 files need code changes (plus their root-level copies): `pipeline.sh` and `speckit.pipeline.md`
