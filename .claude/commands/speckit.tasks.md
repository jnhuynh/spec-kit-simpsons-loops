---
description: Generate an actionable, dependency-ordered tasks.md for the feature based on available design artifacts.
handoffs: 
  - label: Analyze For Consistency
    agent: speckit.analyze
    prompt: Run a project analysis for consistency
    send: true
  - label: Implement Project
    agent: speckit.implement
    prompt: Start the implementation in phases
    send: true
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Pre-Execution Checks

**Check for extension hooks (before tasks generation)**:
- Check if `.specify/extensions.yml` exists in the project root.
- If it exists, read it and look for entries under the `hooks.before_tasks` key
- If the YAML cannot be parsed or is invalid, skip hook checking silently and continue normally
- Filter to only hooks where `enabled: true`
- For each remaining hook, do **not** attempt to interpret or evaluate hook `condition` expressions:
  - If the hook has no `condition` field, or it is null/empty, treat the hook as executable
  - If the hook defines a non-empty `condition`, skip the hook and leave condition evaluation to the HookExecutor implementation
- For each executable hook, output the following based on its `optional` flag:
  - **Optional hook** (`optional: true`):
    ```
    ## Extension Hooks

    **Optional Pre-Hook**: {extension}
    Command: `/{command}`
    Description: {description}

    Prompt: {prompt}
    To execute: `/{command}`
    ```
  - **Mandatory hook** (`optional: false`):
    ```
    ## Extension Hooks

    **Automatic Pre-Hook**: {extension}
    Executing: `/{command}`
    EXECUTE_COMMAND: {command}
    
    Wait for the result of the hook command before proceeding to the Outline.
    ```
- If no hooks are registered or `.specify/extensions.yml` does not exist, skip silently

## Outline

1. **Setup**: Run `.specify/scripts/bash/check-prerequisites.sh --json` from repo root and parse FEATURE_DIR and AVAILABLE_DOCS list. All paths must be absolute. For single quotes in args like "I'm Groot", use escape syntax: e.g 'I'\''m Groot' (or double-quote if possible: "I'm Groot").

2. **Load design documents**: Read from FEATURE_DIR:
   - **Required**: plan.md (tech stack, libraries, structure), spec.md (user stories with priorities)
   - **Optional**: data-model.md (entities), contracts/ (interface contracts), research.md (decisions), quickstart.md (test scenarios)
   - Note: Not all projects have all documents. Generate tasks based on what's available.

3. **Execute task generation workflow**:
   - Load plan.md and extract tech stack, libraries, project structure
   - Load spec.md and extract user stories with their priorities (P1, P2, P3, etc.)
   - If data-model.md exists: Extract entities and map to user stories
   - If contracts/ exists: Map interface contracts to user stories
   - If research.md exists: Extract decisions for setup tasks
   - Generate tasks organized by user story (see Task Generation Rules below)
   - Generate dependency graph showing user story completion order
   - Create parallel execution examples per user story
   - Validate task completeness (each user story has all needed tasks, independently testable)

4. **Generate tasks.md**: Use `.specify/templates/tasks-template.md` as structure, fill with:
   - Correct feature name from plan.md
   - Phase 1: Setup tasks (project initialization)
   - Phase 2: Foundational tasks (blocking prerequisites for all user stories)
   - Phase 3+: One phase per user story (in priority order from spec.md)
   - Each phase includes: story goal, independent test criteria, tests (if requested), implementation tasks
   - Final Phase: Polish & cross-cutting concerns
   - All tasks must follow the strict checklist format (see Task Generation Rules below)
   - Clear file paths for each task
   - Dependencies section showing story completion order
   - Parallel execution examples per story
   - Implementation strategy section (MVP first, incremental delivery)
   - `## Pull Request Plan` section (see Pull Request Plan Rules below)

5. **Generate the Pull Request Plan**: Group the tasks into pull requests and emit the `## Pull Request Plan` section. See Pull Request Plan Rules below for applicability, grouping, and the validation that must pass before you finish.

6. **Report**: Output path to generated tasks.md and summary:
   - Total task count
   - Task count per user story
   - Parallel opportunities identified
   - Independent test criteria for each story
   - Suggested MVP scope (typically just User Story 1)
   - Format validation: Confirm ALL tasks follow the checklist format (checkbox, ID, labels, file paths)
   - PR plan: the number of PRs, each one's task range, and confirmation that the coverage and ordering checks passed (or that the section was deliberately omitted for a split parent spec)

7. **Check for extension hooks**: After tasks.md is generated, check if `.specify/extensions.yml` exists in the project root.
   - If it exists, read it and look for entries under the `hooks.after_tasks` key
   - If the YAML cannot be parsed or is invalid, skip hook checking silently and continue normally
   - Filter to only hooks where `enabled: true`
   - For each remaining hook, do **not** attempt to interpret or evaluate hook `condition` expressions:
     - If the hook has no `condition` field, or it is null/empty, treat the hook as executable
     - If the hook defines a non-empty `condition`, skip the hook and leave condition evaluation to the HookExecutor implementation
   - For each executable hook, output the following based on its `optional` flag:
     - **Optional hook** (`optional: true`):
       ```
       ## Extension Hooks

       **Optional Hook**: {extension}
       Command: `/{command}`
       Description: {description}

       Prompt: {prompt}
       To execute: `/{command}`
       ```
     - **Mandatory hook** (`optional: false`):
       ```
       ## Extension Hooks

       **Automatic Hook**: {extension}
       Executing: `/{command}`
       EXECUTE_COMMAND: {command}
       ```
   - If no hooks are registered or `.specify/extensions.yml` does not exist, skip silently

Context for task generation: $ARGUMENTS

The tasks.md should be immediately executable - each task must be specific enough that an LLM can complete it without additional context.

## Task Generation Rules

**CRITICAL**: Tasks MUST be organized by user story to enable independent implementation and testing.

**Tests are OPTIONAL**: Only generate test tasks if explicitly requested in the feature specification or if user requests TDD approach.

### Checklist Format (REQUIRED)

Every task MUST strictly follow this format:

```text
- [ ] [TaskID] [P?] [Story?] Description with file path
```

**Format Components**:

1. **Checkbox**: ALWAYS start with `- [ ]` (markdown checkbox)
2. **Task ID**: Sequential number (T001, T002, T003...) in execution order
3. **[P] marker**: Include ONLY if task is parallelizable (different files, no dependencies on incomplete tasks)
4. **[Story] label**: REQUIRED for user story phase tasks only
   - Format: [US1], [US2], [US3], etc. (maps to user stories from spec.md)
   - Setup phase: NO story label
   - Foundational phase: NO story label  
   - User Story phases: MUST have story label
   - Polish phase: NO story label
5. **Description**: Clear action with exact file path

**Examples**:

- ✅ CORRECT: `- [ ] T001 Create project structure per implementation plan`
- ✅ CORRECT: `- [ ] T005 [P] Implement authentication middleware in src/middleware/auth.py`
- ✅ CORRECT: `- [ ] T012 [P] [US1] Create User model in src/models/user.py`
- ✅ CORRECT: `- [ ] T014 [US1] Implement UserService in src/services/user_service.py`
- ❌ WRONG: `- [ ] Create User model` (missing ID and Story label)
- ❌ WRONG: `T001 [US1] Create model` (missing checkbox)
- ❌ WRONG: `- [ ] [US1] Create User model` (missing Task ID)
- ❌ WRONG: `- [ ] T001 [US1] Create model` (missing file path)

### Task Organization

1. **From User Stories (spec.md)** - PRIMARY ORGANIZATION:
   - Each user story (P1, P2, P3...) gets its own phase
   - Map all related components to their story:
     - Models needed for that story
     - Services needed for that story
     - Interfaces/UI needed for that story
     - If tests requested: Tests specific to that story
   - Mark story dependencies (most stories should be independent)

2. **From Contracts**:
   - Map each interface contract → to the user story it serves
   - If tests requested: Each interface contract → contract test task [P] before implementation in that story's phase

3. **From Data Model**:
   - Map each entity to the user story(ies) that need it
   - If entity serves multiple stories: Put in earliest story or Setup phase
   - Relationships → service layer tasks in appropriate story phase

4. **From Setup/Infrastructure**:
   - Shared infrastructure → Setup phase (Phase 1)
   - Foundational/blocking tasks → Foundational phase (Phase 2)
   - Story-specific setup → within that story's phase

### Phase Structure

- **Phase 1**: Setup (project initialization)
- **Phase 2**: Foundational (blocking prerequisites - MUST complete before user stories)
- **Phase 3+**: User Stories in priority order (P1, P2, P3...)
  - Within each story: Tests (if requested) → Models → Services → Endpoints → Integration
  - Each phase should be a complete, independently testable increment
- **Final Phase**: Polish & Cross-Cutting Concerns

## Pull Request Plan Rules

The `## Pull Request Plan` section slices the task list into the pull requests that will deliver it. Ralph reads it at implementation time, works one PR group at a time, and halts at each boundary so the group can be opened, reviewed and merged before the next one starts. A malformed or incomplete table therefore breaks implementation, not just documentation.

### Applicability

Emit the section for every spec **except** a parent spec that was split into children. Detect that case by reading `spec.md`: if it contains a `## Manifest` section, its `tasks.md` describes the full feature for reference only and each child runs its own pipeline — skip the section and say so in the report. Every other spec gets one, including child specs (directories matching `--p{N}-`) and multi-phase parents being implemented as a monolith.

### Placement and format

Place the section after the final task phase and before `## Dependencies & Execution Order`, following the structure in `.specify/templates/tasks-template.md`. The format rules listed there are binding: one heading, one table, the columns `PR | Tasks | Ships`, ascending integer PR numbers with no gaps, ASCII hyphen ranges (`T001-T018`, never `T001–T018`), no prose between rows.

A group's task IDs need **not** be contiguous, and groups may interleave with the file's task order: the tasks forming one reviewable change are rarely adjacent in a list ordered by user story. Ralph walks the table by PR number, so `| 2 | T022-T023, T028-T031 |` followed by `| 3 | T024-T027, T032-T039 |` is a correct plan. What is forbidden is a **backward dependency** — a task in a later PR that must land before a task in an earlier one. Check each boundary for that before you finish; it is the one ordering property the format cannot enforce for you.

### Grouping rules

Slice on these boundaries, in priority order:

1. **A deployment-phase boundary is always a PR boundary.** If `spec.md` has a populated `## Phases` section, no PR may span two phases. Phases encode what forces a separate *release*; PRs encode what makes a reviewable *change*, so a phase boundary is necessarily also a review boundary.
2. **Migrations ship alone.** Schema migrations go in their own PR ahead of the code that uses them — they get read differently from application code, and the deploy risk profile is different.
3. **Additive units before the behaviour change that references them.** New classes, selectors and error types nothing calls yet make a low-risk PR; the change that wires them in is where the review attention belongs.
4. **Human-gate tasks head the PR they gate.** A sign-off, confirmation or measurement task goes at the top of the PR whose merge it blocks, and that PR's `Ships` cell states the gate. Never leave such a task out of the table.
5. **Keep a story's Red tests with the implementation that turns them Green.** Splitting them puts a knowingly failing suite on the default branch.
6. **Quality-gate and polish tasks** go with the work they gate when they are scoped to it, or form a final PR when they cover the whole feature.

### Sizing

Target 5–15 tasks per PR. A spec with 8 or fewer tasks gets a single-row table covering all of them — that is a valid plan, not a missing one, and Ralph simply never halts. Cap the plan at 10 PRs; if the rules above produce more, merge adjacent groups within the same deployment phase until it fits.

### The `Ships` cell

One sentence naming what a reviewer is being asked to approve, plus the gate that proves it where one exists (e.g. "the frozen suite passes with zero lines modified"). Not a restatement of the task IDs. Where a PR is not safe to merge alone, say what holds it.

### Validation before you finish

Both checks must pass. If either fails, fix the table — do not report the plan as generated.

1. **Total coverage**: collect every task ID in the file and every ID covered by the table (expanding ranges). The two sets must be identical — no task in zero PRs, no task in two, no ID in the table that does not exist as a task.
2. **No backward dependency**: walk the groups in PR order and confirm that each one could be merged with only its predecessors in place. If a group needs something from a later group, move the task or merge the groups.
