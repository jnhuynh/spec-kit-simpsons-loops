# Tasks: Stop-After Pipeline Parameter

**Input**: Design documents from `/specs/006-stop-after-param/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, quickstart.md

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: No new files or project initialization needed. This feature modifies a single existing file: `.claude/commands/speckit.pipeline.md`. Setup phase establishes the foundational argument parsing and step index mapping that all user stories depend on.

- [x] T001 Add `--stop-after <step>` argument parsing to Step 1 in `.claude/commands/speckit.pipeline.md` — parse alongside existing `--from`, `--description`, and `spec-dir` arguments; store value in `STOP_AFTER_STEP` variable; handle missing value error case (FR-001, FR-009)
- [x] T002 Add step index mapping (specify=0, homer=1, plan=2, tasks=3, lisa=4, ralph=5) after Step 3 in `.claude/commands/speckit.pipeline.md` for use in validation and execution plan computation (D-003)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Validation logic that MUST be in place before any execution-related user stories can be implemented safely.

- [x] T003 Add value validation after Step 3 in `.claude/commands/speckit.pipeline.md` — if `STOP_AFTER_STEP` is provided, verify it is one of the six valid step names; if invalid, display error listing valid options and stop before any steps execute (FR-006)
- [x] T004 Add range validation after Step 3 in `.claude/commands/speckit.pipeline.md` — if `STOP_AFTER_STEP` index is less than the starting step index, display error explaining that stop-after must not precede the from step and stop before any steps execute (FR-005)

**Checkpoint**: Argument parsing and validation are complete. Execution-related stories can now be implemented.

---

## Phase 3: User Story 1 — Stop pipeline after a specific step (Priority: P1)

**Goal**: Users can pass `--stop-after <step>` to halt the pipeline after the specified step completes, skipping all subsequent steps.

**Independent Test**: Invoke the pipeline with `--stop-after plan` and verify it completes the plan step but does not start the tasks step.

### Implementation for User Story 1

- [x] T005 [US1] Add execution plan announcement before Step 5 in `.claude/commands/speckit.pipeline.md` — output a line listing planned steps and the stop point (e.g., "Execution plan: specify -> homer -> plan. Stopping after: plan."); when `--stop-after` is not provided, show all steps from start to ralph without a "Stopping after" clause (FR-011, D-005)
- [x] T006 [US1] Add post-step stop check in Step 5 of `.claude/commands/speckit.pipeline.md` — after each step completes (whether it was executed or skipped because its artifact already existed), check if the current step matches `STOP_AFTER_STEP`; if it does, output explicit stop message ("Pipeline stopped after <step> per --stop-after parameter. Skipping: <remaining steps>.") and skip all remaining steps; ensure no further sub-agents are spawned. This includes the edge case where `--stop-after specify` is used but specify was skipped because spec.md exists — the pipeline must still stop and not continue to homer (FR-002, FR-010, D-004)
- [x] T007 [US1] Expand Step 6 completion report in `.claude/commands/speckit.pipeline.md` — list all six pipeline steps with per-step status: `executed`, `skipped` (step was not executed — either because its artifact already existed OR because the step falls before the `--from` starting step), or `stopped-by-param` (not executed due to `--stop-after`); when stopped early, indicate which step was the last executed (FR-008, D-006)
- [x] T008 [US1] Verify default behavior preservation in `.claude/commands/speckit.pipeline.md` — when `--stop-after` is not provided, ensure `STOP_AFTER_STEP` is empty/unset so all stop checks are no-ops and the pipeline behaves identically to the current implementation (FR-007)

**Checkpoint**: Core `--stop-after` functionality is complete. Users can stop the pipeline after any single step.

---

## Phase 4: User Story 2 — Combine --from and --stop-after for a step range (Priority: P2)

**Goal**: Users can combine `--from` and `--stop-after` to run only a specific range of pipeline steps.

**Independent Test**: Invoke the pipeline with `--from plan --stop-after tasks` on a feature with an existing spec.md and verify only the plan and tasks steps execute.

### Implementation for User Story 2

- [x] T009 [US2] Verify combined `--from` and `--stop-after` range execution in `.claude/commands/speckit.pipeline.md` — ensure that when both flags are provided, only steps in the inclusive range [from..stop-after] execute; verify the execution plan announcement correctly reflects the range; verify the completion report shows steps before `--from` as `skipped` and steps after `--stop-after` as `stopped-by-param` (FR-003)
- [x] T010 [US2] Verify single-step execution when `--from` equals `--stop-after` in `.claude/commands/speckit.pipeline.md` — ensure that `--from homer --stop-after homer` executes only the homer step (FR-004)

**Checkpoint**: Range-based execution works. Users can define precise step windows.

---

## Phase 5: User Story 3 — Validation and error reporting for invalid --stop-after values (Priority: P3)

**Goal**: Users receive clear error messages when providing invalid `--stop-after` values or logically impossible combinations with `--from`.

**Independent Test**: Pass invalid values and verify error output without any pipeline steps executing.

### Implementation for User Story 3

- [ ] T011 [US3] Verify error message for invalid step name in `.claude/commands/speckit.pipeline.md` — confirm that `--stop-after invalidstep` produces a clear error listing valid step names (specify, homer, plan, tasks, lisa, ralph) and does not execute any steps (FR-006)
- [ ] T012 [US3] Verify error message for impossible range in `.claude/commands/speckit.pipeline.md` — confirm that `--from tasks --stop-after plan` produces a clear error explaining that stop-after must not precede the from step, including the pipeline sequence, and does not execute any steps (FR-005)
- [ ] T013 [US3] Verify error message for missing value in `.claude/commands/speckit.pipeline.md` — confirm that `--stop-after` without a following step name produces an error indicating a step name is required (edge case from spec)

**Checkpoint**: All error paths produce clear, actionable messages before any steps execute.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Documentation updates and final verification across all stories.

- [ ] T014 Add `--stop-after` examples to the Examples section at the bottom of `.claude/commands/speckit.pipeline.md` — include examples from quickstart.md: `--stop-after plan`, `--from homer --stop-after tasks`, `--stop-after homer --from specify --description "Add feature X"`
- [ ] T015 Run quickstart.md verification checklist against the final implementation in `.claude/commands/speckit.pipeline.md` — verify all items in the Verification Checklist section of `specs/006-stop-after-param/quickstart.md` are satisfied

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion (T001, T002) — BLOCKS all user stories
- **User Story 1 (Phase 3)**: Depends on Foundational phase completion (T003, T004)
- **User Story 2 (Phase 4)**: Depends on User Story 1 completion (T005-T008) — range behavior relies on the core stop-after mechanism
- **User Story 3 (Phase 5)**: Depends on Foundational phase completion (T003, T004) — verifies validation already implemented
- **Polish (Phase 6)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) — no dependencies on other stories
- **User Story 2 (P2)**: Depends on User Story 1 — the combined range behavior requires the stop-after mechanism to exist
- **User Story 3 (P3)**: Can start after Foundational (Phase 2) — validates error paths implemented in Foundational phase; can run in parallel with User Story 1

### Within Each User Story

- Execution plan announcement (T005) before stop check logic (T006)
- Stop check logic (T006) before completion report (T007)
- Core behavior (T005-T007) before default behavior verification (T008)

### Parallel Opportunities

- T003 and T004 (Foundational validation tasks) can run in parallel — they add independent validation checks
- T011, T012, and T013 (User Story 3 verification tasks) can run in parallel — they verify independent error paths
- User Story 3 (Phase 5) can run in parallel with User Story 1 (Phase 3) since it only depends on Foundational phase

---

## Parallel Example: Foundational Phase

```bash
# These two validation tasks touch different concerns and can run in parallel:
Task: "T003 - Add value validation for --stop-after step name"
Task: "T004 - Add range validation for --from/--stop-after combination"
```

## Parallel Example: User Story 3

```bash
# All three verification tasks check independent error paths:
Task: "T011 - Verify error for invalid step name"
Task: "T012 - Verify error for impossible range"
Task: "T013 - Verify error for missing value"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001-T002) — argument parsing and index mapping
2. Complete Phase 2: Foundational (T003-T004) — validation guards
3. Complete Phase 3: User Story 1 (T005-T008) — core stop-after behavior
4. **STOP and VALIDATE**: Test `--stop-after plan` and verify default behavior unchanged
5. Deploy/demo if ready

### Incremental Delivery

1. Complete Setup + Foundational -> Argument parsing and validation ready
2. Add User Story 1 -> Core stop-after works -> Validate (MVP!)
3. Add User Story 2 -> Combined ranges work -> Validate
4. Add User Story 3 -> Error messages verified -> Validate
5. Polish -> Examples and checklist verification -> Complete

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- All changes target a single file: `.claude/commands/speckit.pipeline.md`
- No test tasks included (not explicitly requested in the spec; shellcheck and manual verification serve as quality gates)
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
