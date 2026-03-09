# Tasks: Rerunnable Setup & End-to-End Pipeline

**Input**: Design documents from `/specs/002-feat-rerun-setup-pipeline/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/

**Tests**: This feature consists entirely of shell scripts and markdown command files. Per the constitution's test-first mandate, the test-first approach for shell scripts is: (1) `shellcheck` static analysis before committing any script change, and (2) functional validation against a test project per the quickstart checklist. Each phase includes shellcheck tasks that MUST pass before proceeding. Functional acceptance scenarios are validated at phase checkpoints.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Prepare the Ralph command template with sentinel marker, which is a prerequisite for both the setup.sh extraction logic and the file-based quality gate reading.

- [ ] T001 Add `# SPECKIT_DEFAULT_QUALITY_GATE` sentinel comment to the placeholder quality gate code block in `speckit.ralph.implement.md` and replace inline quality gate instructions with a reference to `.specify/quality-gates.sh`
- [ ] T002 Copy updated template to `.claude/commands/speckit.ralph.implement.md` to keep both copies in sync

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Implement the quality gate file creation and extraction logic in `setup.sh`, which MUST be complete before loop scripts can read from the file.

**CRITICAL**: No user story work (file reading in loops) can begin until setup.sh can create the quality gate file.

- [ ] T003 Add quality gate file creation logic to `setup.sh` after existing file copies: check if `.specify/quality-gates.sh` exists in target project, if not check Ralph command file for sentinel, create placeholder or extract custom gates accordingly, use atomic write (`mktemp` + `mv`), set executable permissions (`chmod +x`)
- [ ] T004 Validate `setup.sh` changes pass `shellcheck` linting

**Checkpoint**: `setup.sh` can now create/extract quality gate files on first run and re-run. Manual validation: fresh install creates placeholder, rerun preserves existing file, migration extracts custom gates.

---

## Phase 3: User Story 1 - Rerun setup.sh Without Losing Quality Gates (Priority: P1)

**Goal**: `setup.sh` safely reruns without overwriting existing quality gate configuration. All other files are updated to latest versions while `.specify/quality-gates.sh` is preserved.

**Independent Test**: Configure a quality gate file, rerun `setup.sh`, verify the quality gate file is unchanged while other files are updated.

### Implementation for User Story 1

- [ ] T005 [US1] Verify `setup.sh` never overwrites `.specify/quality-gates.sh` when it already exists by adding an existence check guard at the top of the quality gate creation section in `setup.sh`
- [ ] T006 [US1] Verify `setup.sh` detects the sentinel comment `# SPECKIT_DEFAULT_QUALITY_GATE` in the target project's `.claude/commands/speckit.ralph.implement.md` and creates a placeholder quality gate file when sentinel is present in `setup.sh`
- [ ] T007 [US1] Verify `setup.sh` extracts custom quality gates from the target project's `.claude/commands/speckit.ralph.implement.md` when sentinel is absent and writes them to `.specify/quality-gates.sh` in `setup.sh`
- [ ] T008 [US1] Verify `setup.sh` creates placeholder quality gate file on first-time installation (no existing Ralph command file) in `setup.sh`
- [ ] T009 [US1] Run `shellcheck setup.sh` and fix any linting errors

**Checkpoint**: `setup.sh` is fully idempotent. Quality gate file is created once, never overwritten. All four acceptance scenarios from US1 pass.

---

## Phase 4: User Story 2 - Quality Gates Read from Dedicated File (Priority: P1)

**Goal**: All loop scripts read quality gates from `.specify/quality-gates.sh` as the default source, with CLI and env var overrides preserved. Precedence: CLI arg > env var > file > error.

**Independent Test**: Write a quality gate file, run the pipeline or Ralph loop, verify the quality gates from the file are executed.

### Implementation for User Story 2

- [ ] T010 [P] [US2] Add `resolve_quality_gates` function to `ralph-loop.sh` implementing the precedence chain: `--quality-gates` CLI arg > `QUALITY_GATES` env var > `.specify/quality-gates.sh` file > error exit
- [ ] T011 [P] [US2] Add `resolve_quality_gates` function to `pipeline.sh` implementing the same precedence chain: `--quality-gates` CLI arg > `QUALITY_GATES` env var > `.specify/quality-gates.sh` file > error exit
- [ ] T012 [US2] Update `ralph-loop.sh` to use the resolved quality gates when invoking the Ralph agent, handling both file execution and command string evaluation
- [ ] T013 [US2] Update `pipeline.sh` to use the resolved quality gates when invoking the Ralph step, handling both file execution and command string evaluation
- [ ] T014 [US2] Add clear error message and non-zero exit when no quality gates are configured (no file, no env var, no CLI arg) in both `ralph-loop.sh` and `pipeline.sh`
- [ ] T015 [P] [US2] Run `shellcheck ralph-loop.sh` and fix any linting errors
- [ ] T016 [P] [US2] Run `shellcheck pipeline.sh` and fix any linting errors

**Checkpoint**: Loop scripts read quality gates from file by default. CLI and env var overrides work. Missing configuration produces clear error. All four acceptance scenarios from US2 pass.

---

## Phase 5: User Story 3 - End-to-End Pipeline from Spec to Implementation (Priority: P2)

**Goal**: Pipeline supports a "specify" step as optional step 0 that creates a spec from a feature description non-interactively, enabling true end-to-end automation.

**Independent Test**: Invoke the pipeline with a feature description and `--from specify`, verify it creates a spec and continues through all subsequent steps.

### Implementation for User Story 3

- [ ] T017 [US3] Add `specify` to the `STEPS` array in `pipeline.sh` as step 0 (before `homer`)
- [ ] T018 [US3] Add `--description` CLI option parsing to `pipeline.sh` for accepting a feature description string
- [ ] T019 [US3] Update `--from` validation in `pipeline.sh` to accept `specify` as a valid step value
- [ ] T020 [US3] Implement the specify step execution block in `pipeline.sh`: invoke the specify agent non-interactively with the feature description, auto-resolve clarifications
- [ ] T021 [US3] Add auto-detection logic in `pipeline.sh`: when no `--from` is specified and no `spec.md` exists but `--description` is provided, auto-start from the specify step
- [ ] T022 [US3] Add error handling for specify step failure in `pipeline.sh`: halt pipeline with clear error message and non-zero exit code per FR-018
- [ ] T023 [US3] Add error handling for missing description in `pipeline.sh`: exit with error when `--from specify` is used without `--description`
- [ ] T024 [US3] Update `speckit.pipeline.md` to document the new specify step, `--description` option, updated `--from` values, and usage examples
- [ ] T025 [US3] Run `shellcheck pipeline.sh` and fix any linting errors

**Checkpoint**: Pipeline supports full end-to-end flow from feature description to implementation. All three acceptance scenarios from US3 pass.

---

## Phase 6: User Story 4 - Existing Projects Migrate Quality Gates to File (Priority: P3)

**Goal**: Existing projects using env var or CLI-based quality gates can migrate to file-based configuration seamlessly.

**Independent Test**: Set `QUALITY_GATES` env var, create the quality gate file with the same content, verify pipeline runs without the env var.

### Implementation for User Story 4

- [ ] T026 [US4] Verify that the quality gate file created by `setup.sh` extraction (T007) correctly captures the full command content from the Ralph command file, enabling migration from inline to file-based config in `setup.sh`
- [ ] T027 [US4] Verify backward compatibility: confirm `QUALITY_GATES` env var and `--quality-gates` CLI arg continue to override the file in both `ralph-loop.sh` and `pipeline.sh`

**Checkpoint**: Existing projects can migrate to file-based quality gates. Env var and CLI overrides remain fully functional.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Final validation across all modified files

- [ ] T028 [P] Run `shellcheck` on all modified shell scripts: `setup.sh`, `ralph-loop.sh`, `pipeline.sh`
- [ ] T029 Validate all acceptance scenarios from quickstart.md testing checklist against a test project
- [ ] T030 Verify idempotency: run `setup.sh` three times in succession on a test project and confirm identical results each time

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - updates the Ralph template with sentinel marker
- **Foundational (Phase 2)**: Depends on Phase 1 - implements quality gate file creation in setup.sh
- **US1 (Phase 3)**: Depends on Phase 2 - validates setup.sh rerun safety
- **US2 (Phase 4)**: Depends on Phase 2 - adds file reading to loop scripts
- **US3 (Phase 5)**: Depends on Phase 4 - extends pipeline.sh (which is also modified in US2)
- **US4 (Phase 6)**: Depends on Phase 3 and Phase 4 - validates migration path
- **Polish (Phase 7)**: Depends on all previous phases

### User Story Dependencies

- **US1 (P1)**: Can start after Foundational (Phase 2) - no dependencies on other stories
- **US2 (P1)**: Can start after Foundational (Phase 2) - no dependencies on US1 (different code sections)
- **US3 (P2)**: Should start after US2 (Phase 4) - modifies `pipeline.sh` which US2 also modifies
- **US4 (P3)**: Should start after US1 and US2 - validates the combined behavior

### Within Each User Story

- Quality gate file infrastructure before reading logic
- Script modifications before linting validation
- Core implementation before error handling edge cases

### Parallel Opportunities

- **Phase 1**: T001 and T002 are sequential (T002 depends on T001)
- **Phase 4**: T010 and T011 can run in parallel (different files: `ralph-loop.sh` vs `pipeline.sh`)
- **Phase 4**: T015 and T016 can run in parallel (linting different files)
- **Phase 3 and Phase 4**: US1 and US2 can run in parallel after Phase 2 (different code sections)

---

## Parallel Example: User Story 2

```bash
# Launch quality gate resolution for both loop scripts in parallel:
Task: "Add resolve_quality_gates function to ralph-loop.sh" (T010)
Task: "Add resolve_quality_gates function to pipeline.sh" (T011)

# After resolution functions are in place, launch linting in parallel:
Task: "Run shellcheck ralph-loop.sh" (T015)
Task: "Run shellcheck pipeline.sh" (T016)
```

---

## Implementation Strategy

### MVP First (User Stories 1 + 2)

1. Complete Phase 1: Setup (sentinel in Ralph template)
2. Complete Phase 2: Foundational (setup.sh quality gate file creation)
3. Complete Phase 3: US1 (rerun safety validation)
4. Complete Phase 4: US2 (file-based quality gate reading)
5. **STOP and VALIDATE**: Test rerun safety and file-based reading independently

### Incremental Delivery

1. Complete Setup + Foundational -> Quality gate file infrastructure ready
2. Add US1 + US2 -> Test independently -> Core feature complete (MVP!)
3. Add US3 -> Test end-to-end pipeline -> Full automation enabled
4. Add US4 -> Test migration path -> Backward compatibility confirmed
5. Each story adds value without breaking previous stories

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- No new source files are created in this repo; `.specify/quality-gates.sh` is created per-project by `setup.sh`
- All modified files are shell scripts or markdown command files
- `shellcheck` is the primary quality validation tool for shell scripts
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
