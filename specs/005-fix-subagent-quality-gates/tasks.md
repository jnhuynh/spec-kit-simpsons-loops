# Tasks: Fix Subagent Delegation and Quality Gate Consolidation

**Input**: Design documents from `/specs/005-fix-subagent-quality-gates/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, quickstart.md

**Tests**: No test framework — shellcheck serves as the quality gate. No test tasks generated.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story. US4 (Bash Script Removal) is addressed by Setup and Foundational phases since its work is prerequisite to all other stories.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup

**Purpose**: Delete bash script fallbacks — prerequisite for directory reorganization

- [x] T001 Delete root-level bash script fallbacks: `pipeline.sh`, `homer-loop.sh`, `lisa-loop.sh`, `ralph-loop.sh`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Reorganize source directories and update the installer script. MUST complete before any command file modifications.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete — command files must be in their new locations first.

- [ ] T002 [P] Rename `agents/` directory to `claude-agents/` using `git mv agents claude-agents`
- [ ] T003 [P] Create `speckit-commands/` directory and move root-level command files into it using `git mv`: `speckit.pipeline.md`, `speckit.homer.clarify.md`, `speckit.lisa.analyze.md`, `speckit.ralph.implement.md`
- [ ] T004 Update `setup.sh` — change source directories from `agents/` to `claude-agents/` and from root-level `speckit.*.md` to `speckit-commands/` for `.claude/commands/` installation; add cleanup logic to remove stale bash scripts (`pipeline.sh`, `homer-loop.sh`, `lisa-loop.sh`, `ralph-loop.sh`) from `.specify/scripts/bash/` and remove their corresponding `Bash(.specify/scripts/bash/...)` permission entries from `.claude/settings.local.json` using `jq`; stop installing bash loop scripts entirely

**Checkpoint**: Directory reorganization complete — command files are at `speckit-commands/speckit.*.md`, agent files are at `claude-agents/*.md`, `setup.sh` installs from new locations

---

## Phase 3: User Story 1 — Pipeline Spawns Subagents for Every Step (Priority: P1) 🎯 MVP

**Goal**: The pipeline command spawns a fresh, isolated subagent (via Agent tool) for each pipeline step and loop iteration — zero inline executions.

**Independent Test**: Run `/speckit.pipeline` on a feature and confirm each step shows as a separate Agent tool invocation in the Claude Code UI, not inline execution within the orchestrator's context.

### Implementation for User Story 1

- [ ] T005 [US1] Update `speckit-commands/speckit.pipeline.md` — remove all references to `--quality-gates` CLI flag and `QUALITY_GATES` environment variable override; update homer and lisa iteration defaults from current values to 30; update ralph phase iteration calculation from hardcoded 20 to `incomplete_tasks + 10` (count `- [ ]` lines in tasks.md); add quality gate file validation for the ralph phase (check `.specify/quality-gates.sh` exists and contains non-empty executable content via `test -f` and `grep -v '^\s*#' | grep -v '^\s*$' | head -1`); verify stuck detection threshold is 2 consecutive iterations for all loop phases (FR-013); verify all subagent spawning instructions use Agent tool with `subagent_type: general-purpose` and include the feature directory path in each prompt

**Checkpoint**: Pipeline command updated — spawns subagents with correct iteration defaults, quality gate validation, and no CLI/env override references

---

## Phase 4: User Story 2 — Standalone Loop Commands Spawn Subagents (Priority: P1)

**Goal**: Each standalone loop command (`/speckit.homer.clarify`, `/speckit.lisa.analyze`, `/speckit.ralph.implement`) spawns a fresh subagent per iteration with isolated context.

**Independent Test**: Run `/speckit.homer.clarify` on a feature with only `spec.md` (no plan.md) and confirm it starts successfully with each iteration as a separate subagent invocation.

### Implementation for User Story 2

- [ ] T006 [P] [US2] Update `speckit-commands/speckit.homer.clarify.md` — update default max iterations to 30 (FR-011); switch prerequisite check from `check-prerequisites.sh --json` to `check-prerequisites.sh --json --paths-only` (FR-019); replace full artifact validation with spec.md-only existence check using `test -f "$FEATURE_DIR/spec.md"` (FR-019, FR-020); verify stuck detection threshold is 2 consecutive iterations (FR-013); verify subagent spawning instructions use Agent tool with `subagent_type: general-purpose`
- [ ] T007 [P] [US2] Update `speckit-commands/speckit.lisa.analyze.md` — update default max iterations to 30 (FR-011); verify stuck detection threshold is 2 consecutive iterations (FR-013); verify subagent spawning instructions use Agent tool with `subagent_type: general-purpose`
- [ ] T008 [US2] Update `speckit-commands/speckit.ralph.implement.md` — verify max iterations uses `incomplete_tasks + 10` (FR-012); add quality gate file validation step before execution: check `.specify/quality-gates.sh` exists (`test -f`) and contains non-empty executable content (`grep -v '^\s*#' .specify/quality-gates.sh | grep -v '^\s*$' | head -1`); abort with clear error if validation fails (FR-010); verify stuck detection threshold is 2 consecutive iterations (FR-013); verify subagent spawning instructions use Agent tool with `subagent_type: general-purpose`

**Checkpoint**: All three standalone loop commands updated — homer runs without plan.md, iteration defaults are 30, ralph validates quality gates file

---

## Phase 5: User Story 3 — Quality Gates Use Only quality-gates.sh (Priority: P2)

**Goal**: `.specify/quality-gates.sh` is the sole mechanism for defining quality gates — no CLI arguments, no environment variables, no alternative resolution paths.

**Independent Test**: Search all command files for `--quality-gates`, `QUALITY_GATES`, or `resolve_quality_gates` — zero matches should be found. Homer and lisa command files should contain zero quality gate references.

### Implementation for User Story 3

- [ ] T009 [US3] Audit and clean all files in `speckit-commands/` — search for and remove any remaining references to `--quality-gates` CLI flag, `QUALITY_GATES` environment variable, or `resolve_quality_gates` function; verify `speckit-commands/speckit.homer.clarify.md` and `speckit-commands/speckit.lisa.analyze.md` contain zero quality gate references; verify `speckit-commands/speckit.ralph.implement.md` and `speckit-commands/speckit.pipeline.md` reference only `.specify/quality-gates.sh` as sole source

**Checkpoint**: Quality gate consolidation verified — single source of truth confirmed across all command files

---

## Phase 6: User Story 4 — Bash Script Fallbacks Removed (Priority: P2)

**Goal**: Root-level bash scripts are deleted, `setup.sh` stops installing them and cleans up stale copies from existing installations.

**Independent Test**: Confirm `pipeline.sh`, `homer-loop.sh`, `lisa-loop.sh`, `ralph-loop.sh` do not exist at root level; confirm `setup.sh` removes stale copies from `.specify/scripts/bash/` and their permissions from `.claude/settings.local.json`.

> **Note**: All implementation work for US4 is completed in Phase 1 (T001 — file deletion) and Phase 2 (T004 — setup.sh cleanup logic). This phase verifies completeness.

### Implementation for User Story 4

- [ ] T010 [US4] Verify bash script removal — confirm `pipeline.sh`, `homer-loop.sh`, `lisa-loop.sh`, `ralph-loop.sh` do not exist at root level; confirm `setup.sh` contains no references to installing these scripts; confirm `setup.sh` cleanup logic removes stale copies from `.specify/scripts/bash/` and removes their `Bash(...)` permission entries from `.claude/settings.local.json`; fix any gaps found

**Checkpoint**: Bash script fallbacks fully removed — sole invocation path is Claude Code command files

---

## Phase 7: User Story 5 — README Reflects Architecture and Configuration Changes (Priority: P2)

**Goal**: README accurately reflects the current architecture: Claude Code command files as the sole invocation path, subagent delegation, quality gates from `.specify/quality-gates.sh` only, updated iteration defaults, and stuck detection threshold.

**Independent Test**: Read the README and confirm: no references to `--quality-gates` flag, `QUALITY_GATES` env var, or bash script invocation; iteration defaults show 30 for homer/lisa; stuck detection says "two consecutive iterations"; two mermaid diagrams render in the Architecture section.

### Implementation for User Story 5

- [ ] T011 [US5] Update `README.md` — remove all references to `pipeline.sh`, `homer-loop.sh`, `lisa-loop.sh`, `ralph-loop.sh`, and bash script invocation (FR-014); remove all references to `--quality-gates` CLI flag and `QUALITY_GATES` environment variable (FR-014); update iteration defaults table to show 30 for homer/lisa and `incomplete_tasks + 10` for ralph (FR-015); add new "Architecture" section with two mermaid diagrams: (1) pipeline flow showing sequential steps with subagent spawning per step/iteration (specify → homer loop → plan → tasks → lisa loop → ralph loop), (2) standalone loop iteration lifecycle showing orchestrator → spawn subagent → check completion/stuck → next iteration or exit (FR-016); consolidate "Customization > Quality gates" section to document `.specify/quality-gates.sh` as single source with no override mechanisms (FR-017); update stuck detection description to "two consecutive iterations" (FR-018)

**Checkpoint**: README fully updated — accurate architecture documentation with diagrams, corrected defaults, no stale references

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Final validation across all changes

- [ ] T012 [P] Run `shellcheck` on `setup.sh` and all scripts in `.specify/scripts/bash/` — fix any errors or warnings
- [ ] T013 Run quickstart.md verification checklist against the implemented changes in `specs/005-fix-subagent-quality-gates/quickstart.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 (bash scripts must be deleted before directory reorganization)
  - T002 and T003 can run in parallel (different directories)
  - T004 depends on T002 and T003 (setup.sh must reference final directory names)
- **US1 (Phase 3)**: Depends on Phase 2 (pipeline command must be at new location)
- **US2 (Phase 4)**: Depends on Phase 2 (loop commands must be at new locations)
  - US1 and US2 CAN run in parallel (different files)
- **US3 (Phase 5)**: Depends on US1 and US2 (audit runs after all command file changes)
- **US4 (Phase 6)**: Depends on Phase 1 and Phase 2 (verification of earlier work)
  - US4 CAN run in parallel with US3
- **US5 (Phase 7)**: Depends on US1–US4 (README must reflect final state)
- **Polish (Phase 8)**: Depends on all previous phases

### User Story Dependencies

- **US1 (P1)**: Depends on Foundational only — can start after Phase 2
- **US2 (P1)**: Depends on Foundational only — can start after Phase 2, parallel with US1
- **US3 (P2)**: Depends on US1 + US2 (verification of their changes)
- **US4 (P2)**: Depends on Phase 1 + Phase 2 (verification of earlier changes), parallel with US3
- **US5 (P2)**: Depends on US1–US4 (README must document final state)

### Within Each User Story

- Core command file modifications before verification tasks
- Quality gate validation logic before sweep/audit
- All command files complete before README documentation

### Parallel Opportunities

- T002 and T003 can run in parallel (different directories)
- T006 and T007 can run in parallel (different command files)
- T008 can run in parallel with T006/T007 (different file, though not marked [P] due to shared QG validation pattern with T005)
- US1 (Phase 3) and US2 (Phase 4) can run in parallel (different files)
- US3 (Phase 5) and US4 (Phase 6) can run in parallel

---

## Parallel Example: User Story 2

```text
# Launch homer and lisa updates together (different files, no dependencies):
Task T006: "Update speckit-commands/speckit.homer.clarify.md — iterations to 30, --paths-only prereqs, spec.md-only validation"
Task T007: "Update speckit-commands/speckit.lisa.analyze.md — iterations to 30"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (delete bash scripts)
2. Complete Phase 2: Foundational (reorganize dirs, update setup.sh)
3. Complete Phase 3: User Story 1 (pipeline command)
4. **STOP and VALIDATE**: Test pipeline spawns subagents correctly
5. Proceed to remaining stories

### Incremental Delivery

1. Phase 1 + Phase 2 → Foundation ready
2. Add US1 → Pipeline works with subagents → Validate (MVP!)
3. Add US2 → Standalone loops work with subagents → Validate
4. Add US3 → Quality gates consolidated → Validate
5. Add US4 → Bash script removal verified → Validate
6. Add US5 → README updated → Validate
7. Polish → Final validation

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- US4 (Bash Script Removal) implementation is in Setup + Foundational phases; US4 phase is verification only
- No test tasks generated — shellcheck is the quality gate per plan.md
- All command file edits target `speckit-commands/` (source files), not `.claude/commands/` (installed copies)
- Agent files in `claude-agents/` require NO content changes per plan.md
