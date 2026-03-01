# Tasks: Fix Install Script, Sub Agent Consistency, and README

**Input**: Design documents from `/specs/001-fix-install-subagents/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Tests**: No test tasks included -- tests were not explicitly requested in the feature specification.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

This is a flat distribution repository. All source files live at the root level. The `agents/` subdirectory holds agent definitions. There is no `src/` or `tests/` directory.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Verify project structure and ensure all expected source files exist before making changes

- [x] T001 Verify all 13 distribution source files exist at repository root per the Distribution File Manifest in spec.md (4 bash scripts: `homer-loop.sh`, `lisa-loop.sh`, `ralph-loop.sh`, `pipeline.sh`; 5 agent definitions in `agents/`: `homer.md`, `lisa.md`, `ralph.md`, `plan.md`, `tasks.md`; 4 loop commands: `speckit.homer.clarify.md`, `speckit.lisa.analyze.md`, `speckit.ralph.implement.md`, `speckit.pipeline.md`)
- [x] T002 Verify `setup.sh` exists at repository root and review its current structure against the contract in `specs/001-fix-install-subagents/contracts/setup-sh.md` — VERIFIED COMPLETE: setup.sh exists, all preconditions match contract (exit 1 for missing .claude/, missing .specify/, self-install), copies all 13 files, chmod +x on 4 scripts, .gitignore marker check, jq-based settings.local.json with unique, graceful jq-missing fallback, output format matches contract
- [ ] T003 Verify `README.md` exists at repository root

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: No foundational/blocking prerequisites for this feature -- all files already exist. This is a consistency and correctness pass, not a greenfield build.

**Checkpoint**: Setup verified -- user story implementation can now begin.

---

## Phase 3: User Story 1 - Install Script Works with a Test Directory (Priority: P1)

**Goal**: Ensure `setup.sh` copies all 13 distribution files correctly, is idempotent, works with test directories, and handles missing `jq` gracefully.

**Independent Test**: Create a temporary test directory with `.claude/` and `.specify/` scaffolding, run `setup.sh` against it, and verify all 13 files exist at correct destinations, 4 scripts are executable, `.gitignore` has the marker block, and `settings.local.json` has all 4 permission entries. Run it again and confirm idempotent behavior.

### Implementation for User Story 1

- [ ] T004 [US1] Review `setup.sh` and confirm it copies all 13 files listed in the Distribution File Manifest (spec.md) to their correct destinations per the contract in `specs/001-fix-install-subagents/contracts/setup-sh.md`
- [ ] T005 [US1] Verify `setup.sh` creates required subdirectories (`.specify/scripts/bash/`, `.claude/agents/`, `.claude/commands/`) if they do not exist in the target project
- [ ] T006 [US1] Verify `setup.sh` precondition checks match the contract: exit 1 if `.claude/` missing, exit 1 if `.specify/` missing, exit 1 if run from inside the simpsons-loops repo itself -- update error messages to match contract wording in `specs/001-fix-install-subagents/contracts/setup-sh.md` if needed
- [ ] T007 [US1] Verify `setup.sh` idempotency: `.gitignore` marker check prevents duplicate blocks, `settings.local.json` uses `jq unique` to prevent duplicate permission entries, file copies overwrite safely
- [ ] T008 [US1] Verify `setup.sh` handles missing `jq` gracefully by printing manual permission instructions and completing without error
- [ ] T009 [US1] Verify `setup.sh` makes all 4 bash scripts executable via `chmod +x` in `setup.sh`
- [ ] T010 [US1] Run `setup.sh` against a temporary test directory with `.claude/` and `.specify/` scaffolding to confirm end-to-end install succeeds and all postconditions from the contract are met
- [ ] T011 [US1] Run `setup.sh` a second time against the same test directory to confirm idempotent behavior (no errors, no duplicate entries)

**Checkpoint**: User Story 1 complete -- `setup.sh` works reliably with test directories and is idempotent.

---

## Phase 4: User Story 2 - Loop Commands Use Sub Agents with Sequential Execution (Priority: P1)

**Goal**: All 4 loop command files use the Agent tool (not "Task tool") with `subagent_type: general-purpose`, enforce strict sequential execution, handle failures by aborting immediately (no retry), enforce stuck detection after 3 identical outputs, and enforce a maximum iteration limit.

**Independent Test**: Inspect all 4 loop command files and confirm they reference "Agent tool" (not "Task tool"), specify `subagent_type: general-purpose`, describe sequential execution, abort on first sub agent failure, and enforce their max iteration limits per the contract.

### Implementation for User Story 2

- [x] T012 [P] [US2] Replace all occurrences of "Task tool" with "Agent tool" in `speckit.homer.clarify.md` (2 occurrences per research.md R1) — VERIFIED COMPLETE: source file already uses "Agent tool" throughout
- [x] T013 [P] [US2] Replace all occurrences of "Task tool" with "Agent tool" in `speckit.lisa.analyze.md` (2 occurrences per research.md R1) — VERIFIED COMPLETE: source file already uses "Agent tool" throughout
- [x] T014 [P] [US2] Replace all occurrences of "Task tool" with "Agent tool" in `speckit.ralph.implement.md` (2 occurrences per research.md R1) — VERIFIED COMPLETE: source file already uses "Agent tool" throughout
- [x] T015 [P] [US2] Replace all occurrences of "Task tool" and "Task tool call" with "Agent tool" and "Agent tool call" in `speckit.pipeline.md` (3 occurrences per research.md R1) — VERIFIED COMPLETE: source file already uses "Agent tool" throughout
- [x] T016 [P] [US2] Update failure handling in `speckit.homer.clarify.md` to abort immediately on sub agent failure with no retry -- replace "Abort after 3 consecutive failures" with immediate abort and error context logging (iteration number, agent type, error message) per FR-011 and contract `specs/001-fix-install-subagents/contracts/loop-commands.md` — VERIFIED COMPLETE: source file already uses immediate abort with error context logging and no retry
- [x] T017 [P] [US2] Update failure handling in `speckit.lisa.analyze.md` to abort immediately on sub agent failure with no retry -- replace "Abort after 3 consecutive failures" with immediate abort and error context logging (iteration number, agent type, error message) per FR-011 and contract `specs/001-fix-install-subagents/contracts/loop-commands.md` — VERIFIED COMPLETE: source file already uses immediate abort with error context logging and no retry
- [x] T018 [P] [US2] Update failure handling in `speckit.ralph.implement.md` to abort immediately on sub agent failure with no retry -- replace "Abort after 3 consecutive failures" with immediate abort and error context logging (iteration number, agent type, error message) per FR-011 and contract `specs/001-fix-install-subagents/contracts/loop-commands.md` — VERIFIED COMPLETE: source file already uses immediate abort with error context logging and no retry
- [ ] T019 [US2] Add explicit failure handling to `speckit.pipeline.md` for each pipeline step -- abort on first sub agent failure within any step with error context logging, consistent with the no-retry policy per FR-011 and research.md R7
- [ ] T020 [US2] Verify all 4 loop command files specify `subagent_type: general-purpose` per FR-004 and the contract in `specs/001-fix-install-subagents/contracts/loop-commands.md`
- [ ] T021 [US2] Verify all 4 loop command files describe strict sequential execution (one sub agent at a time) per FR-005 and the contract
- [ ] T022 [US2] Verify all 4 loop command files enforce stuck detection after 3 consecutive identical outputs per the contract in `specs/001-fix-install-subagents/contracts/loop-commands.md`
- [ ] T023 [US2] Verify max iteration limits: homer=10, lisa=10, ralph=incomplete_tasks+10, pipeline per-step limits match per FR-012 and the contract
- [ ] T024 [US2] Verify all 4 loop command files include reporting on loop completion (total iterations, completion status, suggestion to rerun) per the contract

**Checkpoint**: User Story 2 complete -- all loop commands use canonical terminology, abort on failure, and enforce iteration limits.

---

## Phase 5: User Story 3 - Fully Autonomous Execution Without Permission Prompts (Priority: P1)

**Goal**: All loop commands and bash scripts run without any user interaction -- no permission prompts, no confirmation dialogs, no interactive pauses.

**Independent Test**: Inspect all 4 loop command files for explicit autonomous execution instructions and verify bash scripts pass `--dangerously-skip-permissions` when invoking `claude --agent`.

### Implementation for User Story 3

- [ ] T025 [P] [US3] Verify `speckit.homer.clarify.md` contains an explicit `AUTONOMOUS EXECUTION` instruction block per FR-006 and research.md R6
- [ ] T026 [P] [US3] Verify `speckit.lisa.analyze.md` contains an explicit `AUTONOMOUS EXECUTION` instruction block per FR-006 and research.md R6
- [ ] T027 [P] [US3] Verify `speckit.ralph.implement.md` contains an explicit `AUTONOMOUS EXECUTION` instruction block per FR-006 and research.md R6
- [ ] T028 [P] [US3] Verify `speckit.pipeline.md` contains explicit `AUTONOMOUS EXECUTION` and `STRICT SEQUENTIAL EXECUTION` instruction blocks per FR-006 and research.md R6
- [ ] T029 [P] [US3] Verify `homer-loop.sh` passes `--dangerously-skip-permissions` when invoking `claude --agent` per FR-010
- [ ] T030 [P] [US3] Verify `lisa-loop.sh` passes `--dangerously-skip-permissions` when invoking `claude --agent` per FR-010
- [ ] T031 [P] [US3] Verify `ralph-loop.sh` passes `--dangerously-skip-permissions` when invoking `claude --agent` per FR-010
- [ ] T032 [P] [US3] Verify `pipeline.sh` passes `--dangerously-skip-permissions` when invoking `claude --agent` per FR-010
- [ ] T033 [US3] Verify bash scripts implement 3-retry behavior for transient CLI failures per FR-011 allowance (`homer-loop.sh`, `lisa-loop.sh`, `ralph-loop.sh`)

**Checkpoint**: User Story 3 complete -- all execution paths are fully autonomous with no permission prompts.

---

## Phase 6: User Story 4 - Accurate README Reflecting Current Behavior (Priority: P2)

**Goal**: The README accurately describes the install process, file layout, recommended workflow, and bash script fallback, using consistent terminology that matches the loop command files and agent definitions.

**Independent Test**: Read through the README and verify every file path exists, every command works, and all terminology matches the loop command files and agent definitions.

### Implementation for User Story 4

- [ ] T034 [P] [US4] Replace all occurrences of "Task tool" with "Agent tool" in `README.md` (2 occurrences per research.md R1 and R5)
- [ ] T035 [US4] Update the permission note in `README.md` to clarify that loop commands instruct sub agents to execute autonomously -- remove or correct the note that says "Claude Code will prompt for permission as normal" per research.md R5 and FR-006
- [ ] T036 [US4] Verify all file paths referenced in `README.md` correspond to actual files in the repository per FR-007 and SC-005
- [ ] T037 [US4] Verify `README.md` describes the recommended workflow (slash commands with sub agents) and the bash script fallback accurately per FR-007
- [ ] T038 [US4] Verify terminology in `README.md` is consistent with loop command files and agent definitions -- use the Terminology Map from data-model.md Entity 4 as the reference per FR-008 and FR-009
- [ ] T039 [US4] Verify `README.md` describes the 13 distribution files and their correct destinations per the Distribution File Manifest in spec.md

**Checkpoint**: User Story 4 complete -- README is accurate and terminology-consistent.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Final validation across all files to confirm cross-cutting consistency

- [ ] T040 Run a global search across all `.md` files at repository root and in `agents/` for the deprecated term "Task tool" and confirm zero occurrences remain per FR-008 and FR-009
- [ ] T041 Run a global search across all `.md` files for any other deprecated synonyms from the Terminology Map (data-model.md Entity 4): "child agent" used as a synonym for "sub agent", "loop script" used to describe loop commands (not bash scripts)
- [ ] T042 Verify all 4 bash loop scripts (`homer-loop.sh`, `lisa-loop.sh`, `ralph-loop.sh`, `pipeline.sh`) are unchanged except for any bug fixes -- bash scripts should NOT have "Task tool" -> "Agent tool" replacements since they are shell scripts, not Markdown
- [ ] T043 Run the quickstart verification checklist from `specs/001-fix-install-subagents/quickstart.md` to confirm all 7 verification items pass
- [ ] T044 Validate all success criteria from spec.md are met: SC-001 through SC-007

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies -- can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion -- no blocking tasks in this feature
- **User Story 1 (Phase 3)**: Can start after Setup -- independent of other stories
- **User Story 2 (Phase 4)**: Can start after Setup -- independent of other stories
- **User Story 3 (Phase 5)**: Can start after Setup -- independent of other stories
- **User Story 4 (Phase 6)**: Should start after US2 completes (US2 changes terminology in loop commands; US4 must ensure README matches)
- **Polish (Phase 7)**: Depends on ALL user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Independent -- modifies `setup.sh` only
- **User Story 2 (P1)**: Independent -- modifies loop command files only (`speckit.*.md`)
- **User Story 3 (P1)**: Independent -- verifies loop commands and bash scripts for autonomous execution
- **User Story 4 (P2)**: Depends on US2 completion -- README terminology must match updated loop command files

### Within Each User Story

- Verification tasks can run in parallel (marked [P])
- Update tasks for different files can run in parallel (marked [P])
- Verification tasks that depend on updates must run after updates complete

### Parallel Opportunities

- **Phase 1**: T001, T002, T003 can run in parallel
- **Phase 3 (US1)**: T004-T009 can run sequentially; T010-T011 must run after T004-T009
- **Phase 4 (US2)**: T012-T015 can run in parallel (terminology fixes in different files); T016-T018 can run in parallel (failure handling in different files); T019 after T015; T020-T024 after all updates
- **Phase 5 (US3)**: T025-T032 can ALL run in parallel (different files); T033 after T029-T031
- **Phase 6 (US4)**: T034 can start immediately; T035-T039 after T034
- **Phase 7**: T040-T044 must run after all user stories complete

---

## Parallel Example: User Story 2

```
# Launch all terminology fixes in parallel (different files):
Task: T012 "Replace Task tool -> Agent tool in speckit.homer.clarify.md"
Task: T013 "Replace Task tool -> Agent tool in speckit.lisa.analyze.md"
Task: T014 "Replace Task tool -> Agent tool in speckit.ralph.implement.md"
Task: T015 "Replace Task tool -> Agent tool in speckit.pipeline.md"

# Launch all failure handling updates in parallel (different files):
Task: T016 "Update failure handling in speckit.homer.clarify.md"
Task: T017 "Update failure handling in speckit.lisa.analyze.md"
Task: T018 "Update failure handling in speckit.ralph.implement.md"
```

---

## Implementation Strategy

### MVP First (User Story 1 + User Story 2)

1. Complete Phase 1: Setup verification
2. Complete Phase 3: User Story 1 (setup.sh validation)
3. Complete Phase 4: User Story 2 (loop command consistency)
4. **STOP and VALIDATE**: Run quickstart verification checklist items 1-4
5. These two stories deliver the highest-priority fixes

### Incremental Delivery

1. Phase 1: Setup verification
2. User Story 1: Install script validated and working
3. User Story 2: Loop commands consistent and correct
4. User Story 3: Autonomous execution verified
5. User Story 4: README updated and accurate
6. Phase 7: Cross-cutting validation confirms everything is consistent

### Suggested MVP Scope

User Stories 1 and 2 (both P1) are the minimum viable delivery -- they fix the install script and loop command consistency, which are the core distribution and execution mechanisms.

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- This feature is a consistency/correctness pass -- no new functionality is added
- Total tasks: 44
- Tasks per user story: US1=8, US2=13, US3=9, US4=6, Setup=3, Polish=5
