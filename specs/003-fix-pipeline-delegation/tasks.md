# Tasks: Fix Pipeline and Loop Command Delegation

**Input**: Design documents from `specs/003-fix-pipeline-delegation/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md

**Tests**: No test tasks included — the spec does not request TDD and specifies manual verification via invocation and `diff`/`wc -l` checks.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Understand existing files and establish the delegation pattern

- [ ] T001 Read the current command files to understand existing structure: `speckit.pipeline.md`, `speckit.homer.clarify.md`, `speckit.lisa.analyze.md`, `speckit.ralph.implement.md`
- [ ] T002 Read the corresponding bash scripts to understand their CLI interfaces: `.specify/scripts/bash/pipeline.sh`, `.specify/scripts/bash/homer-loop.sh`, `.specify/scripts/bash/lisa-loop.sh`, `.specify/scripts/bash/ralph-loop.sh`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: No foundational phase needed — this feature rewrites existing files with no shared infrastructure to build first

**Checkpoint**: Setup complete — user story implementation can begin

---

## Phase 3: User Story 2 - Loop Commands Run All Iterations (Priority: P1)

**Goal**: Rewrite the 3 standalone loop commands (homer, lisa, ralph) to delegate to their bash scripts instead of reimplementing orchestration logic

**Independent Test**: Invoke each loop command and verify it delegates to the corresponding bash script. Check line counts with `wc -l` (must be <= 40 lines each).

### Implementation for User Story 2

- [ ] T003 [P] [US2] Rewrite `speckit.homer.clarify.md` to delegate to `.specify/scripts/bash/homer-loop.sh` — keep frontmatter description, add script existence check with error message, pass `$ARGUMENTS` through, use `run_in_background` for execution, report results. Must not exceed 40 lines.
- [ ] T004 [P] [US2] Rewrite `speckit.lisa.analyze.md` to delegate to `.specify/scripts/bash/lisa-loop.sh` — keep frontmatter description, add script existence check with error message, pass `$ARGUMENTS` through, use `run_in_background` for execution, report results. Must not exceed 40 lines.
- [ ] T005 [P] [US2] Rewrite `speckit.ralph.implement.md` to delegate to `.specify/scripts/bash/ralph-loop.sh` — keep frontmatter description, add script existence check with error message, pass `$ARGUMENTS` through, use `run_in_background` for execution, report results. Must not exceed 40 lines.

**Checkpoint**: All 3 standalone loop commands rewritten. Each should delegate to its bash script and stay within 40-line limit.

---

## Phase 4: User Story 1 - Full Pipeline Runs to Completion (Priority: P1)

**Goal**: Rewrite the pipeline command to delegate to `pipeline.sh` instead of reimplementing step sequencing and orchestration logic

**Independent Test**: Invoke `/speckit.pipeline --dry-run` and verify it delegates to `pipeline.sh`. Check line count with `wc -l` (must be <= 60 lines).

### Implementation for User Story 1

- [ ] T006 [US1] Rewrite `speckit.pipeline.md` to delegate to `.specify/scripts/bash/pipeline.sh` — keep frontmatter description, add script existence check with error message, pass `$ARGUMENTS` through, use `run_in_background` for execution, report results. Must not exceed 60 lines.

**Checkpoint**: Pipeline command rewritten. Should delegate to `pipeline.sh` and stay within 60-line limit.

---

## Phase 5: User Story 3 - Helpful Error When Script Missing (Priority: P2)

**Goal**: Ensure all 4 commands display a clear error message with remediation instructions when their bash script is not found

**Independent Test**: Verify each rewritten command file includes a script existence check (`[[ -f ... ]]`) and a clear error message instructing the user to run setup.

### Implementation for User Story 3

- [ ] T007 Verify all 4 rewritten command files (T003-T006) include script existence checks and actionable error messages — review each file for the pattern: check script exists, if not display error with setup instructions, exit without partial execution

**Checkpoint**: Error handling confirmed in all 4 commands.

---

## Phase 6: User Story 4 - Arguments Pass Through to Scripts (Priority: P2)

**Goal**: Ensure all 4 commands forward `$ARGUMENTS` to their bash scripts unchanged

**Independent Test**: Review each command file to confirm `$ARGUMENTS` is passed directly to the bash script invocation without modification.

### Implementation for User Story 4

- [ ] T008 Verify all 4 rewritten command files (T003-T006) pass `$ARGUMENTS` directly to their bash script invocations — confirm the delegation line uses `$ARGUMENTS` without wrapping, filtering, or modifying the arguments

**Checkpoint**: Argument pass-through confirmed in all 4 commands.

---

## Phase 7: User Story 5 - All File Copies Stay in Sync (Priority: P3)

**Goal**: Sync all 3 copies of each command file (repo root, `.claude/commands/`, `~/.openclaw/.claude/commands/`) so they are byte-identical

**Independent Test**: Run `diff` across all 3 locations for each of the 4 command files.

### Implementation for User Story 5

- [ ] T009 [P] [US5] Copy `speckit.homer.clarify.md` from repo root to `.claude/commands/speckit.homer.clarify.md` and `~/.openclaw/.claude/commands/speckit.homer.clarify.md`
- [ ] T010 [P] [US5] Copy `speckit.lisa.analyze.md` from repo root to `.claude/commands/speckit.lisa.analyze.md` and `~/.openclaw/.claude/commands/speckit.lisa.analyze.md`
- [ ] T011 [P] [US5] Copy `speckit.ralph.implement.md` from repo root to `.claude/commands/speckit.ralph.implement.md` and `~/.openclaw/.claude/commands/speckit.ralph.implement.md`
- [ ] T012 [P] [US5] Copy `speckit.pipeline.md` from repo root to `.claude/commands/speckit.pipeline.md` and `~/.openclaw/.claude/commands/speckit.pipeline.md`

**Checkpoint**: All 12 files (4 commands x 3 locations) are byte-identical.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Final validation across all commands

- [ ] T013 Run line count validation: `wc -l speckit.pipeline.md speckit.homer.clarify.md speckit.lisa.analyze.md speckit.ralph.implement.md` — pipeline <= 60, others <= 40
- [ ] T014 Run sync validation: `diff` each repo root file against its `.claude/commands/` and `~/.openclaw/.claude/commands/` copies (12 comparisons, all must show no differences)
- [ ] T015 Run quickstart.md validation scenarios from `specs/003-fix-pipeline-delegation/quickstart.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: N/A — no foundational tasks needed
- **User Story 2 (Phase 3)**: Depends on Setup — loop commands rewritten first since pipeline.sh calls the same loop scripts
- **User Story 1 (Phase 4)**: Depends on Setup — can run in parallel with Phase 3
- **User Story 3 (Phase 5)**: Depends on Phases 3 and 4 — verification of error handling in rewritten files
- **User Story 4 (Phase 6)**: Depends on Phases 3 and 4 — verification of argument pass-through in rewritten files
- **User Story 5 (Phase 7)**: Depends on Phases 3 and 4 — syncing requires final versions of all command files
- **Polish (Phase 8)**: Depends on Phase 7 — final validation after all files are in place

### User Story Dependencies

- **User Story 2 (P1)**: Can start after Setup — no dependencies on other stories
- **User Story 1 (P1)**: Can start after Setup — no dependencies on other stories (can run parallel with US2)
- **User Story 3 (P2)**: Verification step — depends on US1 and US2 completion
- **User Story 4 (P2)**: Verification step — depends on US1 and US2 completion
- **User Story 5 (P3)**: Sync step — depends on US1 and US2 completion (final file content must be settled)

### Within Each User Story

- Read existing files before rewriting
- Rewrite command file at repo root location
- Verify line count constraint
- Sync to other locations (Phase 7)

### Parallel Opportunities

- T003, T004, T005 can all run in parallel (different files, no dependencies)
- T006 can run in parallel with T003-T005 (different file)
- T009, T010, T011, T012 can all run in parallel (different files)

---

## Parallel Example: User Story 2

```bash
# Launch all loop command rewrites together (different files):
Task: "Rewrite speckit.homer.clarify.md to delegate to homer-loop.sh"
Task: "Rewrite speckit.lisa.analyze.md to delegate to lisa-loop.sh"
Task: "Rewrite speckit.ralph.implement.md to delegate to ralph-loop.sh"
```

## Parallel Example: User Story 5

```bash
# Launch all sync operations together (different files):
Task: "Copy speckit.homer.clarify.md to .claude/commands/ and ~/.openclaw/"
Task: "Copy speckit.lisa.analyze.md to .claude/commands/ and ~/.openclaw/"
Task: "Copy speckit.ralph.implement.md to .claude/commands/ and ~/.openclaw/"
Task: "Copy speckit.pipeline.md to .claude/commands/ and ~/.openclaw/"
```

---

## Implementation Strategy

### MVP First (User Stories 1 & 2)

1. Complete Phase 1: Setup (read existing files)
2. Complete Phase 3: Rewrite loop commands (T003-T005)
3. Complete Phase 4: Rewrite pipeline command (T006)
4. **STOP and VALIDATE**: Check line counts, verify delegation pattern
5. Proceed to sync and polish

### Incremental Delivery

1. Setup: Read existing files to understand current structure
2. Rewrite loop commands (homer, lisa, ralph) -> Verify line counts -> Test delegation
3. Rewrite pipeline command -> Verify line count -> Test delegation
4. Verify error handling and argument pass-through (US3, US4)
5. Sync all copies (US5) -> Verify with diff
6. Final validation (Polish)

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- US3 and US4 are verification-only phases — the error handling and argument pass-through are built into the rewrites in US1 and US2
- The bash scripts are NOT modified — only the 4 Markdown command files are rewritten
- Each command file exists in 3 locations (12 file writes total)
- Line count constraints are hard limits: loop commands <= 40 lines, pipeline <= 60 lines
