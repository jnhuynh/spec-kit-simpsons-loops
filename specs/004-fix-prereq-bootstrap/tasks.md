# Tasks: Fix Prerequisite Bootstrap Ordering

**Input**: Design documents from `/specs/004-fix-prereq-bootstrap/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, quickstart.md

**Tests**: No test tasks generated — the spec uses manual pipeline execution tests and shellcheck for validation, not a unit test framework.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2)
- Include exact file paths in descriptions

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Verify the current state and understand the code that needs modification

- [ ] T001 Read and understand the current `resolve_feature_dir()` function in `.specify/scripts/bash/pipeline.sh` (lines 302-345) and the current Step 1 resolution logic in `.claude/commands/speckit.pipeline.md` (line 89)
- [ ] T002 Read and understand the `--paths-only` flag behavior in `.specify/scripts/bash/check-prerequisites.sh` (lines 86-101) to confirm it returns paths without validation

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: No foundational tasks needed — this is a targeted bug fix on existing files with no shared infrastructure to build

**Checkpoint**: Setup complete — user story implementation can now begin

---

## Phase 3: User Story 1 — Run Full Pipeline from Description (Priority: P1)

**Goal**: Enable the pipeline to start from the `specify` step without requiring a pre-existing spec directory, spec.md, or plan.md. This is the core broken workflow.

**Independent Test**: Run `pipeline.sh --from specify --description "Test feature" --dry-run` from the main branch and verify it resolves the feature directory and proceeds without prerequisite errors.

### Implementation for User Story 1

- [ ] T003 [US1] Add bootstrap fallback to `resolve_feature_dir()` in `.specify/scripts/bash/pipeline.sh` — after the `for dir in ... done` loop and exact-match check in `resolve_feature_dir()`, before the final error message, add: if no directory was found but `FROM_STEP=specify` or `DESCRIPTION` is non-empty, construct and return `specs/<branch-name>` without requiring the directory to exist. Additionally, when on `main` branch (or `HEAD`) and bootstrapping is active, treat the `resolve_feature_dir()` failure as non-fatal — allow the pipeline to proceed with an empty `FEATURE_DIR` so that the specify step's agent (via `create-new-feature.sh`) can create the branch and directory first, after which `FEATURE_DIR` is resolved
- [ ] T004 [US1] Copy the updated `.specify/scripts/bash/pipeline.sh` to the root-level `pipeline.sh` to keep them in sync
- [ ] T005 [US1] Update Step 1 in `.claude/commands/speckit.pipeline.md` (line 89) to use `check-prerequisites.sh --json --paths-only` instead of `check-prerequisites.sh --json` when `--from specify` is set or `--description` is provided and no `spec-dir` argument is given
- [ ] T006 [US1] Copy the updated `.claude/commands/speckit.pipeline.md` to the root-level `speckit.pipeline.md` to keep them in sync
- [ ] T007 [US1] Verify the fix by running `bash .specify/scripts/bash/pipeline.sh --from specify --description "Test feature" --dry-run` and confirming it resolves the feature directory without errors

**Checkpoint**: At this point, the pipeline can start from `specify` with a description and resolve the feature directory without prerequisite errors

---

## Phase 4: User Story 2 — Pipeline Prerequisite Checks Skip Validation for Early Steps (Priority: P2)

**Goal**: Ensure the prerequisite checking system uses path-only resolution for early steps and full validation for later steps, so that the `specify` step can create artifacts that later steps depend on.

**Independent Test**: Invoke `check-prerequisites.sh --json --paths-only` when no spec directory exists and verify it returns path information without errors. Then invoke `check-prerequisites.sh --json` when spec directory and plan.md exist and verify full validation still works.

### Implementation for User Story 2

- [ ] T008 [US2] Verify that the `--paths-only` flag in `.specify/scripts/bash/check-prerequisites.sh` already returns path information without validation errors when the spec directory does not exist (READ ONLY — no modification to this file)
- [ ] T009 [US2] Verify that existing prerequisite validation in `.claude/commands/speckit.pipeline.md` Step 2 (lines 92-98) correctly handles the case where spec.md does not exist and `--from specify` or `--description` is provided (READ ONLY — no modification needed if logic is correct)
- [ ] T010 [US2] Verify that downstream callers (`.claude/commands/speckit.homer.clarify.md`, `.claude/commands/speckit.lisa.analyze.md`, `.claude/commands/speckit.ralph.implement.md`) still use `--json` with full validation and are unaffected by the changes (READ ONLY — no modification to these files)
- [ ] T011 [US2] Run `bash .specify/scripts/bash/pipeline.sh --dry-run` from the `004-fix-prereq-bootstrap` branch (where spec.md exists) and verify it auto-detects the starting step correctly with no regressions

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
- **User Story 1 (Phase 3)**: Depends on Setup (Phase 1) — implements the core fix
- **User Story 2 (Phase 4)**: Depends on User Story 1 (Phase 3) — verifies the fix works correctly for stage-aware validation
- **Polish (Phase 5)**: Depends on both user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Setup — core implementation changes
- **User Story 2 (P2)**: Depends on US1 completion — verification that changes work correctly across all pipeline stages

### Within Each User Story

- Read/understand before modifying
- Modify source files before syncing root copies
- Sync root copies before verification
- Verification last

### Parallel Opportunities

- T003 and T005 can run in parallel [P] — they modify different files (pipeline.sh vs speckit.pipeline.md)
- T004 and T006 can run in parallel [P] — they sync different files
- T008, T009, T010 can all run in parallel [P] — they are read-only verification tasks on different files
- T012, T013, T014 can all run in parallel [P] — they are independent validation checks

---

## Parallel Example: User Story 1

```bash
# Launch pipeline.sh and speckit.pipeline.md changes together:
Task: "Add bootstrap fallback to resolve_feature_dir() in .specify/scripts/bash/pipeline.sh"
Task: "Update Step 1 in .claude/commands/speckit.pipeline.md to use --paths-only for bootstrap"

# Launch root-level syncs together (after source changes):
Task: "Copy updated pipeline.sh to root-level pipeline.sh"
Task: "Copy updated speckit.pipeline.md to root-level speckit.pipeline.md"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (understand existing code)
2. Complete Phase 3: User Story 1 (core fix)
3. **STOP and VALIDATE**: Run dry-run pipeline test
4. Deploy/demo if ready

### Incremental Delivery

1. Complete Setup → Understand current codebase
2. Add User Story 1 → Fix bootstrap ordering → Verify dry-run (MVP!)
3. Add User Story 2 → Verify stage-aware validation → Confirm no regressions
4. Polish → shellcheck, sync validation, quickstart verification

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- **Constraint**: Do NOT modify `check-prerequisites.sh` internals or `create-new-feature.sh` behavior (explicitly out of scope)
- Only 2 files need code changes (plus their root-level copies): `pipeline.sh` and `speckit.pipeline.md`
