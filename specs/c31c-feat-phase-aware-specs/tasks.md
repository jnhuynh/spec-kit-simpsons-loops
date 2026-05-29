# Tasks: Phase-Aware Specs with Splitting Skill

**Input**: Design documents from `/specs/c31c-feat-phase-aware-specs/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Tests**: Test-first development is N/A for markdown command files and agent files, which contain no unit-testable application logic. Shell script changes (setup.sh) are validated by shellcheck (T012) and the functional testing checklist in quickstart.md (T013). No unit-testable business logic is introduced by this feature (per plan.md constitution check).

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Establish source copies of existing files and project structure needed for all subsequent work

- [x] T001 Copy `.claude/commands/speckit.specify.md` to `speckit-commands/speckit.specify.md` to create the source copy per project convention (source of truth in `speckit-commands/`, installed copies in `.claude/commands/`)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Template changes that both phase-aware specify and splitting skill depend on

**CRITICAL**: No user story work can begin until this phase is complete

- [x] T002 Add `## Phases` section placeholder to `.specify/templates/spec-template.md` between the User Scenarios section and the Requirements section, with an HTML comment explaining the section's purpose and when it is generated

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 1 - Phase-Aware Spec Generation (Priority: P1)

**Goal**: The specify step analyzes user stories for deployment boundaries and groups them into ordered phases with release strategy recommendations

**Independent Test**: Run `/speckit.specify` with a multi-concern feature description and verify the resulting spec.md contains a `## Phases` section with ordered phase groupings, story assignments, and release strategy recommendations. Run again with a simple single-concern description and verify a single phase with `direct release` is produced.

### Implementation for User Story 1

- [x] T003 [US1] Add phase detection and grouping logic to `speckit-commands/speckit.specify.md` -- insert a new step after User Scenarios generation and before Requirements generation that: (a) evaluates user stories for migration signals (schema change, migration, expand-and-contract, alter table, new columns), integration signals (API key, webhook, OAuth, payment provider, external service), infrastructure signals (shared service, middleware, message queue, cache invalidation), and scope signals (4+ stories with distinct concerns); (b) assigns each story to exactly one phase; (c) determines release strategy per phase: "dark launch with gradual reveal" for phases with migration/integration/infrastructure signals, "direct release" for low-risk additive work; (d) for single-concern features with no signals, generates a single phase with "direct release"
- [x] T004 [US1] Add `## Phases` section output generation to `speckit-commands/speckit.specify.md` -- after the phase detection step, generate the Phases section using the format from `contracts/speckit-specify-phases.md`: each phase as a subsection with Phase number, slug (kebab-case), Stories (comma-separated references), Release Strategy, and Rationale fields; enforce constraints: sequential numbering from 1, maximum 10 phases, each story assigned once

**Checkpoint**: User Story 1 complete -- `/speckit.specify` now produces phase-annotated specs

---

## Phase 4: User Story 2 - Splitting a Phase-Annotated Spec (Priority: P1)

**Goal**: A new splitting skill reads phase annotations from a parent spec and generates independent child spec directories, each processable through the full SpecKit pipeline, with a manifest in the parent spec

**Independent Test**: Create a phase-annotated spec (manually or via US1), run the splitting skill, and verify: (a) child directories created under `specs/` with naming convention `{parent}--p{N}-{slug}`; (b) each child contains a valid standalone spec.md; (c) parent spec updated with a `## Manifest` section tracking all children; (d) re-running produces identical results

### Implementation for User Story 2

- [x] T005 [P] [US2] Create `speckit-commands/speckit.split.md` -- the splitting skill command file. Must include: (a) reading the parent spec.md and parsing the `## Phases` section; (b) validation: phases exist (error if missing, suggest running `/speckit.specify`), count <= 10 (error if exceeded), slugs are valid kebab-case, sequential numbering, each story assigned once; (c) for each phase, create child directory `{parent-directory-name}--p{N}-{phase-slug}` under `specs/`, with directory name truncation and warning if total exceeds 200 characters; (d) generate a child `spec.md` in each directory with standard SpecKit spec structure populated with the stories, requirements, and success criteria relevant to that phase -- relevance is determined by story assignment: include only the user stories assigned to this phase (from the Phases section), then include any functional requirements that reference or support those stories, and include success criteria that validate those requirements; requirements and success criteria not tied to any specific story are included in the first phase; (e) each child spec must be independently executable through the full SpecKit pipeline without referencing siblings; (f) create or update `## Manifest` section in parent spec using the table format from `contracts/manifest-format.md` with all children in phase order, initial status "Draft", preceded by a notice that the parent spec is now a coordination document and pipeline steps (`/speckit.plan`, `/speckit.tasks`, etc.) should be run on individual child specs, not the parent; the manifest MUST track each child's status (FR-017) and MUST be human-readable directly in the parent spec showing phase order, directory name, description, and status without requiring external tools (FR-018); (g) idempotent re-runs: detect existing children and update rather than recreate, preserve existing manifest status values
- [x] T006 [P] [US2] Create `claude-agents/split.md` -- the splitting skill agent file. Single-shot agent (modeled after existing agents like `tasks.md`): invokes `/speckit.split`, then commits and pushes results using the project's git commit convention
- [x] T007 [US2] Update `setup.sh` to copy the new splitting skill files and the specify command source copy during installation: copy `speckit-commands/speckit.split.md` to `.claude/commands/speckit.split.md`, copy `claude-agents/split.md` to `.claude/agents/split.md`, and copy `speckit-commands/speckit.specify.md` to `.claude/commands/speckit.specify.md` (the specify command is now a source file in `speckit-commands/` per T001, so `setup.sh` must install it alongside the other source-managed commands)

**Checkpoint**: User Story 2 complete -- splitting skill creates child specs and manifest from phase-annotated parent specs

---

## Phase 5: User Story 3 - Child Spec Chain Awareness (Priority: P2)

**Goal**: Re-running the splitting skill after earlier child specs diverge propagates changes to later child specs, with conflict markers when manual edits conflict

**Independent Test**: Split a spec into phases, modify the first child spec to simulate implementation divergence, re-run the splitting skill, and verify later child specs reflect updated content from the first phase. Also verify unchanged earlier specs leave later specs unchanged.

### Implementation for User Story 3

- [x] T008 [US3] Extend `speckit-commands/speckit.split.md` with reconciliation logic for re-runs: (a) on re-run, read current state of all earlier child specs; (b) determine the original baseline for each child spec by regenerating it from the current parent spec's phase annotations using the same generation logic as the initial split -- this regenerated content represents "what would be generated fresh" and serves as the comparison baseline without requiring stored copies; (c) compare the regenerated baseline section-by-section (using markdown heading boundaries) against the actual child spec on disk to detect manual edits; (d) for later child specs, identify sections affected by earlier-phase changes by regenerating later child specs with the updated earlier-phase context and comparing against the regenerated baseline from (b); (e) if a later child spec section has no manual edits (disk matches baseline), update it in place with content reflecting the updated earlier phase; (f) if a later child spec section has manual edits that conflict with propagated changes, insert conflict markers using the format from `data-model.md`: `<!-- CONFLICT: {description} -->` before the section and `<!-- END CONFLICT -->` after, preserving the original content between markers; (g) report any conflicts to the developer

**Checkpoint**: User Story 3 complete -- chain awareness keeps later phases grounded in what was actually implemented

---

## Phase 6: User Story 4 - Phase Status Tracking (Priority: P2)

**Goal**: The parent manifest tracks phase status with forward-only state transitions, readable at a glance

**Independent Test**: Create a split spec, manually update a child's status in the manifest to "Complete", re-run the splitting skill, and verify the status is preserved and invalid transitions are rejected.

### Implementation for User Story 4

- [x] T009 [US4] Extend `speckit-commands/speckit.split.md` with status transition validation: (a) on re-run, read existing status values from the manifest; (b) validate that any status changes follow the forward-only state machine: Draft -> In Progress -> Complete, with any active state (Draft, In Progress) allowing transition to Cancelled; (c) reject invalid backward transitions (In Progress -> Draft, Complete -> Draft, Complete -> In Progress, Complete -> Cancelled, Cancelled -> Draft/In Progress/Complete) with an error message identifying the phase and the invalid transition -- note that Complete is NOT an active state per FR-019, so Complete -> Cancelled is also invalid; (d) preserve manually-set status values during re-runs

**Checkpoint**: User Story 4 complete -- developers can track multi-phase feature progress via the parent manifest

---

## Phase 7: User Story 5 - Adding and Removing Phases After Initial Split (Priority: P3)

**Goal**: Re-running the splitting skill after modifying parent phase annotations creates new child directories for added phases and marks removed phases as Cancelled without deleting directories

**Independent Test**: Split a spec, add a fourth phase annotation to the parent, re-run and verify a new child directory is created. Remove a phase annotation, re-run and verify the directory is preserved but manifest marks it Cancelled.

### Implementation for User Story 5

- [x] T010 [US5] Extend `speckit-commands/speckit.split.md` with phase management for adds and removes: (a) detect added phases: phases present in parent annotations but not in existing manifest -- create new child spec directories in the correct phase-order position; (b) detect removed phases: phases present in existing manifest but not in parent annotations -- preserve directory on disk, mark status as "Cancelled" in manifest; (c) maintain correct phase ordering in manifest after adds/removes; (d) for cancelled phases, preserve the child directory untouched on subsequent re-runs

**Checkpoint**: User Story 5 complete -- flexible phase management supports evolving multi-phase plans

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Validation and cleanup across all user stories

- [x] T011 Run `setup.sh` and verify all new files are copied to installed locations (`.claude/commands/speckit.split.md`, `.claude/agents/split.md`)
- [x] T012 [P] Run shellcheck on any modified shell scripts (`setup.sh`)
- [ ] T013 Run quickstart.md testing checklist to validate end-to-end behavior

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies -- can start immediately
- **Foundational (Phase 2)**: Depends on Setup (T001 must complete before T002)
- **User Story 1 (Phase 3)**: Depends on Foundational (T002) -- extends the specify command
- **User Story 2 (Phase 4)**: Depends on Foundational (T002) -- T005 and T006 can run in parallel, T007 depends on T005/T006
- **User Story 3 (Phase 5)**: Depends on User Story 2 (T005) -- extends the split command
- **User Story 4 (Phase 6)**: Depends on User Story 2 (T005) -- extends the split command
- **User Story 5 (Phase 7)**: Depends on User Story 2 (T005) -- extends the split command
- **Polish (Phase 8)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational -- no dependencies on other stories
- **User Story 2 (P1)**: Can start after Foundational -- no dependencies on User Story 1 (reads phase annotations, does not depend on the specify step generating them)
- **User Story 3 (P2)**: Depends on User Story 2 -- extends the splitting skill command file
- **User Story 4 (P2)**: Depends on User Story 2 -- extends the splitting skill command file
- **User Story 5 (P3)**: Depends on User Story 2 -- extends the splitting skill command file

### Within Each User Story

- Core logic before output generation
- Command file before agent file
- Setup.sh updates after command/agent files exist

### Parallel Opportunities

- T005 and T006 can run in parallel (different files: command vs agent)
- User Stories 1 and 2 can run in parallel after Foundational phase
- User Stories 3, 4, and 5 all extend the same file (`speckit.split.md`) -- they must run sequentially to avoid conflicts
- T011 and T012 can run in parallel (different validation targets)

---

## Parallel Example: User Story 2

```bash
# Launch command and agent creation together:
Task: "Create speckit-commands/speckit.split.md"
Task: "Create claude-agents/split.md"

# Then sequentially:
Task: "Update setup.sh to copy new files"
```

---

## Implementation Strategy

### MVP First (User Stories 1 + 2)

1. Complete Phase 1: Setup (create source copy of specify command)
2. Complete Phase 2: Foundational (add Phases placeholder to template)
3. Complete Phase 3: User Story 1 (phase-aware specify)
4. Complete Phase 4: User Story 2 (splitting skill)
5. **STOP and VALIDATE**: Test phase-aware specify and splitting end-to-end
6. Deploy/demo if ready

### Incremental Delivery

1. Setup + Foundational -> foundation ready
2. Add User Story 1 -> phase-aware specify works -> Test independently
3. Add User Story 2 -> splitting skill works -> Test end-to-end with US1 (MVP!)
4. Add User Story 3 -> chain awareness -> Test reconciliation
5. Add User Story 4 -> status tracking -> Test transition validation
6. Add User Story 5 -> phase management -> Test add/remove phases
7. Each story adds capability without breaking previous stories

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- All changes to `speckit-commands/` and `claude-agents/` must be reflected in `setup.sh` for installation
- Always edit source files (`speckit-commands/`, `claude-agents/`), never installed copies (`.claude/commands/`, `.claude/agents/`)
