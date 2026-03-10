# Tasks: Fix Pipeline and Loop Command Delegation

**Input**: Design documents from `/specs/003-fix-pipeline-delegation/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md

**Tests**: No test tasks included — the spec does not request TDD for this feature (markdown command files are not unit-testable).

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Command files (working copy)**: `.claude/commands/speckit.<name>.md`
- **Command files (upstream source)**: `speckit.<name>.md`
- **Command files (global)**: `~/.openclaw/.claude/commands/speckit.<name>.md`
- **Utility scripts (read-only)**: `.specify/scripts/bash/check-prerequisites.sh`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Audit current command files to establish baseline for modifications

- [x] T001 Read all 4 command files in `.claude/commands/` to capture current content and identify stuck detection pattern, script existence check presence, and argument handling: `.claude/commands/speckit.pipeline.md`, `.claude/commands/speckit.homer.clarify.md`, `.claude/commands/speckit.lisa.analyze.md`, `.claude/commands/speckit.ralph.implement.md`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: No foundational phase needed — there are no shared infrastructure changes to make before user story work. All changes are direct modifications to existing command files.

**Checkpoint**: Proceed directly to user story phases.

---

## Phase 3: User Story 1 - Full Pipeline Runs to Completion (Priority: P1)

**Goal**: Ensure `/speckit.pipeline` orchestrates all 6 phases (specify, homer, plan, tasks, lisa, ralph) via Agent tool sub-agents without stopping prematurely.

**Independent Test**: Invoke `/speckit.pipeline` in a project with utility scripts installed and verify all 6 steps execute sequentially, producing spec.md, plan.md, tasks.md, and implementation changes.

### Implementation for User Story 1

- [x] T002 [US1] Add utility script existence check to `.claude/commands/speckit.pipeline.md` — verify `.specify/scripts/bash/check-prerequisites.sh` exists before execution, display actionable error with remediation instructions if missing (FR-002, FR-003)
- [x] T003 [US1] Update stuck detection in `.claude/commands/speckit.pipeline.md` from output-hash comparison (3-iteration threshold) to git diff-based detection (2-iteration threshold) per FR-007 — before each loop sub-agent, record `PRE_ITERATION_SHA=$(git rev-parse HEAD)`; after sub-agent returns, check `git diff $PRE_ITERATION_SHA --stat` for file changes and check output for completion promise tag; increment consecutive_stuck_count when no diff AND no promise tag; abort when count reaches 2
- [x] T004 [US1] Verify pipeline step sequencing in `.claude/commands/speckit.pipeline.md` — confirm the command orchestrates all 6 phases (specify -> homer -> plan -> tasks -> lisa -> ralph) via Agent tool sub-agents per FR-009, with loop phases using the same iteration pattern as standalone loop commands per FR-008
- [x] T004b [US1] Verify auto-detection of starting step in `.claude/commands/speckit.pipeline.md` — confirm the command implements the auto-detection logic from US1 Acceptance Scenario 2: if `tasks.md` exists with some `- [x]` completed tasks, start at ralph; if `tasks.md` exists with no completed tasks, start at lisa; if `plan.md` exists but no `tasks.md`, start at tasks; if `spec.md` exists but no `plan.md`, start at homer; if no `spec.md` but `--description` is provided, start at specify (FR-009, SC-001)

**Checkpoint**: Pipeline command should orchestrate all 6 phases end-to-end with correct auto-detection of starting step.

---

## Phase 4: User Story 2 - Loop Commands Run All Iterations (Priority: P1)

**Goal**: Ensure standalone loop commands (`/speckit.homer.clarify`, `/speckit.lisa.analyze`, `/speckit.ralph.implement`) iterate via Agent tool sub-agents until completion condition is met.

**Independent Test**: Invoke each loop command in a project with findings/tasks to resolve and verify multiple iterations execute until a completion condition is met.

### Implementation for User Story 2

- [x] T005 [P] [US2] Add utility script existence check to `.claude/commands/speckit.homer.clarify.md` — verify `.specify/scripts/bash/check-prerequisites.sh` exists before execution, display actionable error with remediation instructions if missing (FR-002, FR-003)
- [x] T006 [P] [US2] Add utility script existence check to `.claude/commands/speckit.lisa.analyze.md` — verify `.specify/scripts/bash/check-prerequisites.sh` exists before execution, display actionable error with remediation instructions if missing (FR-002, FR-003)
- [x] T007 [P] [US2] Add utility script existence check to `.claude/commands/speckit.ralph.implement.md` — verify `.specify/scripts/bash/check-prerequisites.sh` exists before execution, display actionable error with remediation instructions if missing (FR-002, FR-003)
- [x] T008 [P] [US2] Update stuck detection in `.claude/commands/speckit.homer.clarify.md` from output-hash comparison (3-iteration threshold) to git diff-based detection (2-iteration threshold) per FR-007 — before each sub-agent, record `PRE_ITERATION_SHA=$(git rev-parse HEAD)`; after sub-agent returns, check `git diff $PRE_ITERATION_SHA --stat` for changes; increment consecutive_stuck_count when no diff AND no promise tag; abort when count reaches 2
- [ ] T009 [P] [US2] Update stuck detection in `.claude/commands/speckit.lisa.analyze.md` from output-hash comparison (3-iteration threshold) to git diff-based detection (2-iteration threshold) per FR-007 — before each sub-agent, record `PRE_ITERATION_SHA=$(git rev-parse HEAD)`; after sub-agent returns, check `git diff $PRE_ITERATION_SHA --stat` for changes; increment consecutive_stuck_count when no diff AND no promise tag; abort when count reaches 2
- [ ] T010 [P] [US2] Update stuck detection in `.claude/commands/speckit.ralph.implement.md` from output-hash comparison (3-iteration threshold) to git diff-based detection (2-iteration threshold) per FR-007 — before each sub-agent, record `PRE_ITERATION_SHA=$(git rev-parse HEAD)`; after sub-agent returns, check `git diff $PRE_ITERATION_SHA --stat` for changes; increment consecutive_stuck_count when no diff AND no promise tag; abort when count reaches 2
- [ ] T011 [US2] Verify all 3 loop commands use the same Agent tool loop pattern (one sub-agent per iteration) as defined in FR-008 — confirm unified orchestration pattern across `.claude/commands/speckit.homer.clarify.md`, `.claude/commands/speckit.lisa.analyze.md`, `.claude/commands/speckit.ralph.implement.md`

**Checkpoint**: All 3 loop commands should iterate reliably with git diff-based stuck detection.

---

## Phase 5: User Story 3 - Helpful Error When Script Missing (Priority: P2)

**Goal**: All 4 commands display a clear error message with remediation instructions when utility scripts are not found, with no partial execution.

**Independent Test**: Invoke each command in a project without utility scripts and verify the error message appears with setup instructions.

### Implementation for User Story 3

- [ ] T012 [US3] Verify error messages in all 4 command files are actionable — each must explain that `.specify/scripts/bash/check-prerequisites.sh` is missing and instruct the user to run setup; confirm no partial execution occurs after the error (FR-003, SC-004). Files: `.claude/commands/speckit.pipeline.md`, `.claude/commands/speckit.homer.clarify.md`, `.claude/commands/speckit.lisa.analyze.md`, `.claude/commands/speckit.ralph.implement.md`

**Checkpoint**: Error messages are clear and actionable across all 4 commands.

---

## Phase 6: User Story 4 - Arguments Pass Through Correctly (Priority: P2)

**Goal**: All 4 commands correctly interpret user-provided arguments (spec-dir, max-iterations, --from for pipeline).

**Independent Test**: Run `/speckit.homer.clarify specs/003-fix-pipeline-delegation 5` and verify spec-dir and max-iterations are applied correctly.

### Implementation for User Story 4

- [ ] T013 [US4] Verify argument parsing in `.claude/commands/speckit.pipeline.md` — confirm `--from`, `spec-dir`, and `--description` arguments are correctly interpreted from `$ARGUMENTS` and applied to orchestration (FR-004, SC-003)
- [ ] T014 [P] [US4] Verify argument parsing in `.claude/commands/speckit.homer.clarify.md` — confirm `spec-dir` and `max-iterations` arguments are correctly interpreted from `$ARGUMENTS` (FR-004, SC-003)
- [ ] T015 [P] [US4] Verify argument parsing in `.claude/commands/speckit.lisa.analyze.md` — confirm `spec-dir` and `max-iterations` arguments are correctly interpreted from `$ARGUMENTS` (FR-004, SC-003)
- [ ] T016 [P] [US4] Verify argument parsing in `.claude/commands/speckit.ralph.implement.md` — confirm `spec-dir` and `max-iterations` arguments are correctly interpreted from `$ARGUMENTS` (FR-004, SC-003)

**Checkpoint**: All argument combinations work correctly across all 4 commands.

---

## Phase 7: User Story 5 - All File Copies Stay in Sync (Priority: P3)

**Goal**: Each command file is identical across all 3 locations (repo root, `.claude/commands/`, `~/.openclaw/.claude/commands/`).

**Independent Test**: Run `diff` across all 3 locations for each of the 4 command files.

### Implementation for User Story 5

- [ ] T017 [P] [US5] Sync `speckit.pipeline.md` across all 3 locations (repo root `speckit.pipeline.md`, `.claude/commands/speckit.pipeline.md`, global `~/.openclaw/.claude/commands/speckit.pipeline.md`); verify all 3 copies are byte-identical with `diff` (FR-006, SC-005)
- [ ] T018 [P] [US5] Sync `speckit.homer.clarify.md` across all 3 locations (repo root `speckit.homer.clarify.md`, `.claude/commands/speckit.homer.clarify.md`, global `~/.openclaw/.claude/commands/speckit.homer.clarify.md`); verify all 3 copies are byte-identical with `diff` (FR-006, SC-005)
- [ ] T019 [P] [US5] Sync `speckit.lisa.analyze.md` across all 3 locations (repo root `speckit.lisa.analyze.md`, `.claude/commands/speckit.lisa.analyze.md`, global `~/.openclaw/.claude/commands/speckit.lisa.analyze.md`); verify all 3 copies are byte-identical with `diff` (FR-006, SC-005)
- [ ] T020 [P] [US5] Sync `speckit.ralph.implement.md` across all 3 locations (repo root `speckit.ralph.implement.md`, `.claude/commands/speckit.ralph.implement.md`, global `~/.openclaw/.claude/commands/speckit.ralph.implement.md`); verify all 3 copies are byte-identical with `diff` (FR-006, SC-005)

**Checkpoint**: All 12 files (4 commands x 3 locations) are byte-identical.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Final validation across all commands

- [ ] T021 Verify unified orchestration pattern (SC-006) — confirm that `/speckit.pipeline` loop phases and standalone loop commands use the identical Agent tool loop pattern and bash utility calls by comparing the orchestration sections across all 4 command files
- [ ] T022 Run quickstart.md validation — execute the verification commands from `specs/003-fix-pipeline-delegation/quickstart.md` to confirm sync checks pass and commands are functional
- [ ] T023 [Edge Case] Verify non-zero bash utility exit handling — confirm all 4 command files propagate errors when `check-prerequisites.sh` exits with non-zero status (e.g., missing feature dir, invalid branch), reporting the failure to the user and stopping iteration rather than continuing silently
- [ ] T024 [Edge Case] Verify missing agent file handling — confirm that when agent files (e.g., `homer.md`, `lisa.md`, `ralph.md`) are missing, the Agent tool sub-agent failure is detected by the orchestrator and reported as an error to the user
- [ ] T025 [Edge Case] Verify non-executable utility scripts work — confirm all 4 commands invoke utility scripts via `bash <script>` (not `./<script>`), ensuring execution succeeds even when scripts lack the executable permission bit
- [ ] T026 Verify result reporting (FR-005) — confirm all 4 command files report the result of execution (success or failure) back to the user after orchestration completes, including loop completion reason (all findings resolved, all tasks complete, max iterations reached, stuck, or error). Files: `.claude/commands/speckit.pipeline.md`, `.claude/commands/speckit.homer.clarify.md`, `.claude/commands/speckit.lisa.analyze.md`, `.claude/commands/speckit.ralph.implement.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Skipped — no shared infrastructure needed
- **US1 Pipeline (Phase 3)**: Depends on Phase 1 (audit)
- **US2 Loop Commands (Phase 4)**: Depends on Phase 1 (audit); independent from Phase 3
- **US3 Error Messages (Phase 5)**: Depends on Phases 3 and 4 (existence checks added there)
- **US4 Arguments (Phase 6)**: Depends on Phases 3 and 4 (command files updated there)
- **US5 File Sync (Phase 7)**: Depends on ALL prior phases (sync happens after all modifications)
- **Polish (Phase 8)**: Depends on Phase 7

### User Story Dependencies

- **US1 (P1)**: Can start after Phase 1 — no dependencies on other stories
- **US2 (P1)**: Can start after Phase 1 — independent from US1 (different files)
- **US3 (P2)**: Depends on US1 and US2 (error checks are added during those phases)
- **US4 (P2)**: Depends on US1 and US2 (argument parsing verified after command updates)
- **US5 (P3)**: Depends on US1, US2, US3, US4 (sync happens after all modifications are complete)

### Within Each User Story

- Existence check before stuck detection update
- Stuck detection update before verification
- All modifications before file sync

### Parallel Opportunities

- T005, T006, T007 can run in parallel (different command files)
- T008, T009, T010 can run in parallel (different command files)
- T014, T015, T016 can run in parallel (different command files)
- T017, T018, T019, T020 can run in parallel (different command files, independent copy operations)
- US1 and US2 can run in parallel (pipeline vs loop commands are separate files)

---

## Parallel Example: User Story 2

```text
# Launch all existence checks in parallel (different files):
T005: Add script existence check to speckit.homer.clarify.md
T006: Add script existence check to speckit.lisa.analyze.md
T007: Add script existence check to speckit.ralph.implement.md

# Then launch all stuck detection updates in parallel (different files):
T008: Update stuck detection in speckit.homer.clarify.md
T009: Update stuck detection in speckit.lisa.analyze.md
T010: Update stuck detection in speckit.ralph.implement.md
```

---

## Implementation Strategy

### MVP First (User Stories 1 + 2)

1. Complete Phase 1: Audit current command files
2. Complete Phase 3: Fix pipeline command (US1)
3. Complete Phase 4: Fix loop commands (US2)
4. **STOP and VALIDATE**: Invoke `/speckit.pipeline` and individual loop commands to verify end-to-end execution
5. Complete Phase 7: Sync all file copies (US5)

### Incremental Delivery

1. Phase 1 (Audit) -> Understand current state
2. Phase 3 (US1) -> Pipeline runs all 6 phases -> Validate
3. Phase 4 (US2) -> Loop commands iterate correctly -> Validate
4. Phase 5 (US3) -> Error messages are actionable -> Validate
5. Phase 6 (US4) -> Arguments work correctly -> Validate
6. Phase 7 (US5) -> All file copies synced -> Validate with `diff`
7. Phase 8 (Polish) -> Final cross-cutting validation

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story is independently completable and testable
- Commit after each task or logical group
- Repo root is the upstream source for command files (per spec File Locations); `.claude/commands/` is the active working copy; all 3 locations must be byte-identical after sync (FR-006)
- Bash utility scripts are out-of-scope for modification (called as-is)
- Agent files are out-of-scope for modification (read by sub-agents)
