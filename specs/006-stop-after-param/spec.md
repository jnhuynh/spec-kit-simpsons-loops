# Feature Specification: Stop-After Pipeline Parameter

**Feature Branch**: `006-stop-after-param`
**Created**: 2026-03-16
**Status**: Draft
**Input**: User description: "I want stop-after to be a param that is passed just like --from."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Stop pipeline after a specific step (Priority: P1)

As a user running the SpecKit pipeline, I want to pass a `--stop-after <step>` parameter so the pipeline halts after completing the specified step instead of running all the way through to ralph. This lets me review intermediate artifacts (e.g., the spec or plan) before continuing.

**Why this priority**: This is the core feature — without it, users must either run the full pipeline end-to-end or manually interrupt execution. Partial pipeline runs allow iterative review and course-correction between steps.

**Independent Test**: Can be fully tested by invoking the pipeline with `--stop-after plan` and verifying it completes the plan step but does not start the tasks step. The generated artifacts up through the stopped step are present and correct.

**Acceptance Scenarios**:

1. **Given** a feature with an existing spec.md, **When** the user runs the pipeline with `--stop-after plan`, **Then** the pipeline executes homer and plan steps, does not execute tasks/lisa/ralph, and reports that it stopped after the plan step.
2. **Given** a feature with no existing artifacts, **When** the user runs the pipeline with `--from specify --description "Add feature X" --stop-after homer`, **Then** the pipeline executes specify and homer steps, does not execute plan/tasks/lisa/ralph, and reports that it stopped after homer.
3. **Given** a valid pipeline invocation, **When** the user passes `--stop-after ralph`, **Then** the pipeline behaves identically to a run without `--stop-after` (all steps execute).

---

### User Story 2 - Combine --from and --stop-after for a step range (Priority: P2)

As a user, I want to combine `--from` and `--stop-after` to run only a specific range of pipeline steps. For example, `--from plan --stop-after tasks` runs only the plan and tasks steps.

**Why this priority**: Builds on the core stop-after capability and enables precise control over which pipeline segment executes — useful for re-running specific steps after manual edits.

**Independent Test**: Can be fully tested by invoking the pipeline with `--from plan --stop-after tasks` on a feature that has an existing spec.md. Verify that only the plan and tasks steps execute.

**Acceptance Scenarios**:

1. **Given** a feature with a completed spec.md, **When** the user runs the pipeline with `--from plan --stop-after tasks`, **Then** only the plan and tasks steps execute.
2. **Given** `--from lisa --stop-after lisa`, **When** the pipeline runs, **Then** only the lisa step executes.

---

### User Story 3 - Validation and error reporting for invalid --stop-after values (Priority: P3)

As a user, I want clear error messages when I provide an invalid `--stop-after` value or a logically impossible combination with `--from`.

**Why this priority**: Good error messages prevent confusion and wasted time. Lower priority because it's a guardrail, not core functionality.

**Independent Test**: Can be tested by passing invalid values and verifying error output without any pipeline steps executing.

**Acceptance Scenarios**:

1. **Given** the user passes `--stop-after invalidstep`, **When** the pipeline parses arguments, **Then** it displays an error listing the valid step names and does not execute any steps.
2. **Given** the user passes `--from tasks --stop-after plan` (stop-after comes before from in the pipeline sequence), **When** the pipeline parses arguments, **Then** it displays an error explaining that stop-after must not precede the from step, and does not execute any steps.

---

### Edge Cases

- What happens when `--stop-after` is the same step as `--from`? The pipeline executes that single step only.
- What happens when `--stop-after` is passed without a value? The pipeline displays an error indicating that a step name is required.
- What happens when `--stop-after specify` is used but specify is skipped because spec.md already exists? The pipeline still stops after the specify step (it does not continue to homer). The specify step status is `skipped` (artifact already existed) and all subsequent steps are `stopped-by-param`. The pipeline reports that it stopped after the specify step.

## Out of Scope

- **No `--stop-before` parameter** — only `--stop-after` (inclusive of the named step) is supported.
- **No interactive step picker** — step selection is via CLI flags only, not interactive prompts.
- **No sub-agent file modifications** — the individual agent files (`.claude/agents/*.md`) are not modified; stopping logic lives in the pipeline command file.
- **No changes to step ordering** — the six-step sequence (specify → homer → plan → tasks → lisa → ralph) is fixed and immutable for this feature.

## Clarifications

### Session 2026-03-16

- Q: Should the spec require an explicit stop-decision output at the agent level to ensure the pipeline reliably stops in Claude Code? → A: Yes — require that after the stop-after step completes, the pipeline MUST output an explicit stop message AND MUST NOT spawn any further sub-agents.
- Q: Should the pipeline announce its execution plan upfront before starting any steps? → A: Yes — require an upfront execution plan announcement listing steps to run and the stop point.
- Q: What detail level should the completion report include for steps? → A: List all steps with per-step status: executed, skipped (artifact exists), or stopped-by-param.
- Q: Should the spec add an explicit out-of-scope section? → A: Yes — declare out of scope: no `--stop-before`, no interactive step picker, no sub-agent file modifications, no changes to step ordering.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The pipeline MUST accept a `--stop-after <step>` parameter where valid values are: `specify`, `homer`, `plan`, `tasks`, `lisa`, `ralph`.
- **FR-002**: When `--stop-after` is provided, the pipeline MUST halt after the specified step completes successfully, skipping all subsequent steps.
- **FR-003**: The `--stop-after` parameter MUST be combinable with `--from` to define a range of steps to execute.
- **FR-004**: When `--stop-after` is the same step as the starting step, the pipeline MUST execute only that single step.
- **FR-005**: The pipeline MUST validate that the `--stop-after` step is not earlier in the sequence than the starting step (whether set via `--from` or auto-detected). If invalid, it MUST display an error and not execute any steps.
- **FR-006**: The pipeline MUST validate that the `--stop-after` value is one of the six valid step names. If invalid, it MUST display an error listing the valid options.
- **FR-007**: When `--stop-after` is not provided, the pipeline MUST behave exactly as it does today (run through all steps from the starting step to ralph).
- **FR-008**: The pipeline's completion report MUST list all six pipeline steps with a per-step status: `executed`, `skipped` (step was not executed — either because its artifact already exists or because it falls before the `--from` starting step), or `stopped-by-param` (not executed due to `--stop-after`). When execution was stopped early, the report MUST clearly indicate which step was the last executed and that remaining steps were stopped by the `--stop-after` parameter.
- **FR-009**: The `--stop-after` parameter MUST be parseable in any argument position (same flexibility as `--from`).
- **FR-010**: When `--stop-after` causes early termination, the pipeline MUST output an explicit stop message (e.g., "Pipeline stopped after <step> per --stop-after parameter. Skipping: <remaining steps>.") before ceasing execution. The pipeline MUST NOT spawn any further sub-agents after the stop-after step completes.
- **FR-011**: Before executing any steps, the pipeline MUST output an execution plan announcement listing the steps it will run and the stop point (e.g., "Execution plan: specify → homer → plan. Stopping after: plan.").

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can run a partial pipeline (e.g., specify through plan only) in a single command without manual interruption.
- **SC-002**: All existing pipeline invocations without `--stop-after` continue to work identically (zero regression).
- **SC-003**: Invalid `--stop-after` values or impossible `--from`/`--stop-after` combinations produce clear error messages before any steps execute.
- **SC-004**: The pipeline completion report accurately reflects which steps ran and whether the run was partial due to `--stop-after`.

## Assumptions

- The six pipeline steps and their ordering (specify → homer → plan → tasks → lisa → ralph) remain unchanged.
- `--stop-after` follows the same parsing conventions as `--from` (a flag followed by a step name, position-independent in the argument list).
- When `--stop-after` causes early termination, all artifacts produced by completed steps are committed normally — no special cleanup or rollback is needed.
