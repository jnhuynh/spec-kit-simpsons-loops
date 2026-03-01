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
- [x] T003 Verify `README.md` exists at repository root — VERIFIED COMPLETE: README.md exists at repository root (9.5K)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: No foundational/blocking prerequisites for this feature -- all files already exist. This is a consistency and correctness pass, not a greenfield build.

**Checkpoint**: Setup verified -- user story implementation can now begin.

---

## Phase 3: User Story 1 - Install Script Works with a Test Directory (Priority: P1)

**Goal**: Ensure `setup.sh` copies all 13 distribution files correctly, is idempotent, works with test directories, and handles missing `jq` gracefully.

**Independent Test**: Create a temporary test directory with `.claude/` and `.specify/` scaffolding, run `setup.sh` against it, and verify all 13 files exist at correct destinations, 4 scripts are executable, `.gitignore` has the marker block, and `settings.local.json` has all 4 permission entries. Run it again and confirm idempotent behavior.

### Implementation for User Story 1

- [x] T004 [US1] Review `setup.sh` and confirm it copies all 13 files listed in the Distribution File Manifest (spec.md) to their correct destinations per the contract in `specs/001-fix-install-subagents/contracts/setup-sh.md` — VERIFIED COMPLETE: all 13 cp commands in setup.sh match the Distribution File Manifest exactly (4 bash scripts to .specify/scripts/bash/, 5 agent definitions to .claude/agents/, 4 loop commands to .claude/commands/)
- [x] T005 [US1] Verify `setup.sh` creates required subdirectories (`.specify/scripts/bash/`, `.claude/agents/`, `.claude/commands/`) if they do not exist in the target project — VERIFIED COMPLETE: setup.sh lines 38-40 use `mkdir -p` for all three subdirectories (`.specify/scripts/bash`, `.claude/commands`, `.claude/agents`), which creates them if missing and silently succeeds if they already exist
- [x] T006 [US1] Verify `setup.sh` precondition checks match the contract: exit 1 if `.claude/` missing, exit 1 if `.specify/` missing, exit 1 if run from inside the simpsons-loops repo itself -- update error messages to match contract wording in `specs/001-fix-install-subagents/contracts/setup-sh.md` if needed — VERIFIED COMPLETE: all three precondition checks match the contract exactly (lines 14-18: exit 1 with .claude/ not found message, lines 20-24: exit 1 with .specify/ not found message, lines 26-31: exit 1 with self-install detection message)
- [x] T007 [US1] Verify `setup.sh` idempotency: `.gitignore` marker check prevents duplicate blocks, `settings.local.json` uses `jq unique` to prevent duplicate permission entries, file copies overwrite safely — VERIFIED COMPLETE: (1) file copies use `cp` which overwrites idempotently, (2) `.gitignore` marker check on line 85 uses `grep -qF` to detect existing marker and skips append if present, (3) `settings.local.json` merge on line 118 uses `jq ... | unique` to deduplicate permission entries
- [x] T008 [US1] Verify `setup.sh` handles missing `jq` gracefully by printing manual permission instructions and completing without error — VERIFIED COMPLETE: when `command -v jq` fails (line 113), the else branch (lines 128-140) prints a WARNING and manual JSON instructions for `settings.local.json` without exiting; the `if` construct prevents `set -e` from aborting on the non-zero exit code of `command -v jq`; script completes with exit 0
- [x] T009 [US1] Verify `setup.sh` makes all 4 bash scripts executable via `chmod +x` in `setup.sh` — VERIFIED COMPLETE: lines 73-76 apply `chmod +x` to all 4 bash scripts at their destination paths in `.specify/scripts/bash/` (ralph-loop.sh, lisa-loop.sh, homer-loop.sh, pipeline.sh), matching the contract postcondition and Distribution File Manifest
- [x] T010 [US1] Run `setup.sh` against a temporary test directory with `.claude/` and `.specify/` scaffolding to confirm end-to-end install succeeds and all postconditions from the contract are met — VERIFIED COMPLETE: created temp dir at /tmp/simpsons-test-dir with .claude/ and .specify/ scaffolding, ran setup.sh successfully (exit 0), confirmed all 4 postconditions: (1) all 13 files copied to correct destinations with content matching source, (2) all 4 bash scripts executable, (3) .gitignore contains '# Simpsons loops' marker block, (4) settings.local.json contains all 4 permission entries. Output format matches contract specification.
- [x] T011 [US1] Run `setup.sh` a second time against the same test directory to confirm idempotent behavior (no errors, no duplicate entries) — VERIFIED COMPLETE: created temp dir, ran setup.sh twice; second run exited 0 with "already contains" and "already has" skip messages; .gitignore identical (18 lines, marker check prevented duplicate block); settings.local.json identical (252 bytes, 4 unique permission entries, no duplicates); all 13 files present, all 4 scripts executable

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
- [x] T019 [US2] Add explicit failure handling to `speckit.pipeline.md` for each pipeline step -- abort on first sub agent failure within any step with error context logging, consistent with the no-retry policy per FR-011 and research.md R7 — VERIFIED COMPLETE: added failure handling blocks to all 5 pipeline steps (Homer, Plan, Tasks, Lisa, Ralph); each block aborts immediately on sub agent failure with error context logging (iteration number for loop steps, agent type, error message), no retry, and suggests resuming with `--from <step>`; consistent with the pattern used in speckit.homer.clarify.md, speckit.lisa.analyze.md, and speckit.ralph.implement.md
- [x] T020 [US2] Verify all 4 loop command files specify `subagent_type: general-purpose` per FR-004 and the contract in `specs/001-fix-install-subagents/contracts/loop-commands.md` — VERIFIED COMPLETE: all 4 loop command files specify `subagent_type: general-purpose` (homer line 41, lisa line 49, ralph line 49, pipeline lines 67/76/83/90/107 for all 5 sub-steps)
- [x] T021 [US2] Verify all 4 loop command files describe strict sequential execution (one sub agent at a time) per FR-005 and the contract — VERIFIED & FIXED: speckit.pipeline.md already had explicit STRICT SEQUENTIAL EXECUTION block; added explicit STRICT SEQUENTIAL EXECUTION instruction blocks to speckit.homer.clarify.md (line 19), speckit.lisa.analyze.md (line 19), and speckit.ralph.implement.md (line 19), all stating "Each sub agent MUST complete and return its result before the next sub agent is spawned. Never run multiple sub agents in parallel. Wait for one iteration to finish before starting the next."
- [x] T022 [US2] Verify all 4 loop command files enforce stuck detection after 3 consecutive identical outputs per the contract in `specs/001-fix-install-subagents/contracts/loop-commands.md` — VERIFIED COMPLETE: all 4 loop command files enforce stuck detection after 3 consecutive identical outputs: speckit.homer.clarify.md (line 54, step 4.3), speckit.lisa.analyze.md (line 62, step 4.3), speckit.ralph.implement.md (line 62, step 5.3) each have explicit "Stuck detection" blocks that track consecutive identical outputs and abort after 3; speckit.pipeline.md references stuck detection for all 3 loop steps (homer line 70, lisa line 93, ralph line 111) with "3 identical outputs = abort"
- [x] T023 [US2] Verify max iteration limits: homer=10, lisa=10, ralph=incomplete_tasks+10, pipeline per-step limits match per FR-012 and the contract — VERIFIED COMPLETE: speckit.homer.clarify.md (line 36) sets max iterations to 10; speckit.lisa.analyze.md (line 44) sets max iterations to 10; speckit.ralph.implement.md (line 44) sets max iterations to `incomplete_tasks + 10`; speckit.pipeline.md (lines 50-52) sets per-step limits: Homer=10, Lisa=10, Ralph=`incomplete_tasks + 10` (calculated at ralph step). All values match FR-012 and the contract in specs/001-fix-install-subagents/contracts/loop-commands.md
- [x] T024 [US2] Verify all 4 loop command files include reporting on loop completion (total iterations, completion status, suggestion to rerun) per the contract — VERIFIED & FIXED: all 4 loop command files now have Report Results sections that enumerate all 4 completion statuses from the contract (success, max iterations reached, stuck, failure), report total iterations run, and suggest rerunning if not fully resolved. speckit.homer.clarify.md (Step 5), speckit.lisa.analyze.md (Step 5), speckit.ralph.implement.md (Step 6), speckit.pipeline.md (Step 6)

**Checkpoint**: User Story 2 complete -- all loop commands use canonical terminology, abort on failure, and enforce iteration limits.

---

## Phase 5: User Story 3 - Fully Autonomous Execution Without Permission Prompts (Priority: P1)

**Goal**: All loop commands and bash scripts run without any user interaction -- no permission prompts, no confirmation dialogs, no interactive pauses.

**Independent Test**: Inspect all 4 loop command files for explicit autonomous execution instructions and verify bash scripts pass `--dangerously-skip-permissions` when invoking `claude --agent`.

### Implementation for User Story 3

- [x] T025 [P] [US3] Verify `speckit.homer.clarify.md` contains an explicit `AUTONOMOUS EXECUTION` instruction block per FR-006 and research.md R6 — VERIFIED COMPLETE: line 17 contains explicit `AUTONOMOUS EXECUTION` block stating "This loop runs unattended. Do NOT ask the user for confirmation between iterations. Do NOT pause for permission requests. Execute all iterations back-to-back until a completion condition is met." Matches all 4 requirements from the loop-commands contract (no permission prompts, no confirmation dialogs, no interactive pauses, back-to-back execution until completion condition)
- [x] T026 [P] [US3] Verify `speckit.lisa.analyze.md` contains an explicit `AUTONOMOUS EXECUTION` instruction block per FR-006 and research.md R6 — VERIFIED COMPLETE: line 17 contains explicit `AUTONOMOUS EXECUTION` block stating "This loop runs unattended. Do NOT ask the user for confirmation between iterations. Do NOT pause for permission requests. Execute all iterations back-to-back until a completion condition is met (all findings resolved, max iterations reached, or stuck detection triggers)." Matches all 4 requirements from the loop-commands contract (no permission prompts, no confirmation dialogs, no interactive pauses, back-to-back execution until completion condition)
- [x] T027 [P] [US3] Verify `speckit.ralph.implement.md` contains an explicit `AUTONOMOUS EXECUTION` instruction block per FR-006 and research.md R6 — VERIFIED COMPLETE: line 17 contains explicit `AUTONOMOUS EXECUTION` block stating "This loop runs unattended. Do NOT ask the user for confirmation between iterations. Do NOT pause for permission requests. Execute all iterations back-to-back until a completion condition is met (all tasks complete, max iterations reached, or stuck detection triggers)." Matches all 4 requirements from the loop-commands contract (no permission prompts, no confirmation dialogs, no interactive pauses, back-to-back execution until completion condition)
- [x] T028 [P] [US3] Verify `speckit.pipeline.md` contains explicit `AUTONOMOUS EXECUTION` and `STRICT SEQUENTIAL EXECUTION` instruction blocks per FR-006 and research.md R6 — VERIFIED COMPLETE: line 15 contains explicit `AUTONOMOUS EXECUTION` block stating "This pipeline runs unattended. Do NOT ask the user for confirmation between iterations or steps. Do NOT pause for permission requests. Execute all steps and iterations back-to-back until the pipeline completes or a failure condition is met." Line 17 contains explicit `STRICT SEQUENTIAL EXECUTION` block stating "Each sub agent MUST complete and return its result before the next sub agent is spawned. Never run multiple sub agents in parallel. Within each loop step, wait for one iteration to finish before starting the next. Between pipeline steps, wait for the entire step to complete before advancing." Both blocks match all 4 requirements from the loop-commands contract (no permission prompts, no confirmation dialogs, no interactive pauses, back-to-back execution until completion condition) and are consistent with the other 3 loop command files
- [x] T029 [P] [US3] Verify `homer-loop.sh` passes `--dangerously-skip-permissions` when invoking `claude --agent` per FR-010 — VERIFIED COMPLETE: homer-loop.sh line 128 invokes `claude --agent homer` and line 130 passes `--dangerously-skip-permissions` flag, satisfying FR-010 for fully autonomous execution without permission prompts
- [x] T030 [P] [US3] Verify `lisa-loop.sh` passes `--dangerously-skip-permissions` when invoking `claude --agent` per FR-010 — VERIFIED COMPLETE: lisa-loop.sh line 140 invokes `claude --agent lisa` and line 142 passes `--dangerously-skip-permissions` flag, satisfying FR-010 for fully autonomous execution without permission prompts
- [x] T031 [P] [US3] Verify `ralph-loop.sh` passes `--dangerously-skip-permissions` when invoking `claude --agent` per FR-010 — VERIFIED COMPLETE: ralph-loop.sh line 189 passes `--dangerously-skip-permissions` flag when invoking `claude --agent ralph` on line 187, satisfying FR-010 for fully autonomous execution without permission prompts
- [x] T032 [P] [US3] Verify `pipeline.sh` passes `--dangerously-skip-permissions` when invoking `claude --agent` per FR-010 — VERIFIED COMPLETE: pipeline.sh run_agent() function (line 221) passes `--dangerously-skip-permissions` to `claude --agent` for direct agent invocations (plan, tasks steps); homer/lisa/ralph steps delegate to their respective loop scripts which also pass the flag (verified in T029-T031); dry-run path (line 213) also correctly includes the flag
- [x] T033 [US3] Verify bash scripts implement 3-retry behavior for transient CLI failures per FR-011 allowance (`homer-loop.sh`, `lisa-loop.sh`, `ralph-loop.sh`) — VERIFIED COMPLETE: all 3 bash scripts set MAX_CONSECUTIVE_FAILURES=3 (homer-loop.sh line 17, lisa-loop.sh line 17, ralph-loop.sh line 22), increment CONSECUTIVE_FAILURES on non-zero claude exit code, abort with exit 2 after 3 consecutive failures, and retry with `continue` otherwise; failure counter resets to 0 on successful non-stuck iterations; compliant with FR-011 allowance for bash scripts

**Checkpoint**: User Story 3 complete -- all execution paths are fully autonomous with no permission prompts.

---

## Phase 6: User Story 4 - Accurate README Reflecting Current Behavior (Priority: P2)

**Goal**: The README accurately describes the install process, file layout, recommended workflow, and bash script fallback, using consistent terminology that matches the loop command files and agent definitions.

**Independent Test**: Read through the README and verify every file path exists, every command works, and all terminology matches the loop command files and agent definitions.

### Implementation for User Story 4

- [x] T034 [P] [US4] Replace all occurrences of "Task tool" with "Agent tool" in `README.md` (2 occurrences per research.md R1 and R5) — COMPLETED: replaced "Task tool" with "Agent tool" on lines 5 and 131 of README.md; zero occurrences of "Task tool" remain
- [x] T035 [US4] Update the permission note in `README.md` to clarify that loop commands instruct sub agents to execute autonomously -- remove or correct the note that says "Claude Code will prompt for permission as normal" per research.md R5 and FR-006 — COMPLETED: replaced "Claude Code will prompt for permission as normal" with "the loop commands instruct sub agents to execute autonomously — no permission prompts, no confirmation dialogs, no interactive pauses" and clarified that bash scripts pass `--dangerously-skip-permissions` to `claude --agent`; both paths now advise reviewing agent files before running
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
