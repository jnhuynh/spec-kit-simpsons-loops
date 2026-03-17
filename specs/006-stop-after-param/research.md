# Research: Stop-After Pipeline Parameter

**Branch**: `006-stop-after-param` | **Date**: 2026-03-16

## R-001: Argument Parsing Pattern for --stop-after

**Decision**: Follow the same pattern used by `--from` in `speckit.pipeline.md`. The `--stop-after <step>` argument is parsed from `$ARGUMENTS` alongside `--from`, `--description`, and `spec-dir`. It accepts the same six valid step names: `specify`, `homer`, `plan`, `tasks`, `lisa`, `ralph`. Parsing is position-independent (can appear anywhere in the argument list).

**Rationale**: The `--from` argument already establishes a working pattern for step-name arguments in the pipeline. Reusing the same conventions (position-independent, same valid values) ensures consistency and minimizes cognitive overhead for users.

**Alternatives considered**: Using a separate parsing function or script for `--stop-after` -- rejected because the existing inline parsing in Step 1 of the pipeline command is simple and adding another flag follows the same approach with no added complexity.

## R-002: Stop Logic Placement

**Decision**: The stop logic lives entirely in the pipeline command file (`speckit.pipeline.md`). After each step completes, the pipeline checks whether the current step matches `--stop-after`. If it does, the pipeline outputs the stop message, reports per-step status, and exits. No modifications to sub-agent files (`.claude/agents/*.md`).

**Rationale**: The spec explicitly places stopping logic in the pipeline command file (Out of Scope: "No sub-agent file modifications"). The pipeline already controls step sequencing; adding a conditional check after each step is the minimal change needed.

**Alternatives considered**: Adding stop-awareness to each agent file -- rejected per spec ("No sub-agent file modifications"). Adding a wrapper script -- rejected because command files are the sole invocation path (per 005).

## R-003: Validation Strategy for --stop-after

**Decision**: Validation happens in two phases, both during Step 1 (argument parsing) of the pipeline:

1. **Value validation**: Check that `--stop-after` is one of the six valid step names. If not, display an error listing valid options and exit before any steps run.
2. **Range validation**: Check that `--stop-after` does not come before the starting step (whether set via `--from` or auto-detected). If `--stop-after` precedes the starting step in the sequence, display an error and exit before any steps run.

Both validations must complete before Step 5 (Execute Pipeline Steps) begins, satisfying FR-005 and FR-006.

**Rationale**: Validating early (before any steps execute) prevents wasted work and provides immediate feedback. This matches how `--from` validation works -- invalid values are caught before execution.

**Alternatives considered**: Lazy validation (check at each step) -- rejected because it could allow partial execution before discovering an invalid range, violating FR-005's requirement that "no steps execute."

## R-004: Step Ordering and Index Comparison

**Decision**: Use a fixed ordered list of step names to determine step indices for comparison. The step order is:

| Index | Step |
|-------|------|
| 0 | specify |
| 1 | homer |
| 2 | plan |
| 3 | tasks |
| 4 | lisa |
| 5 | ralph |

When `--stop-after` is provided, convert both the starting step and stop-after step to their indices. If `stop_after_index < start_index`, the combination is invalid.

**Rationale**: Index-based comparison is the simplest way to validate step ordering. The step sequence is fixed and immutable per spec.

**Alternatives considered**: String-based comparison using case/switch chains -- rejected as more verbose and error-prone than index lookup.

## R-005: Execution Plan Announcement (FR-011)

**Decision**: Before executing any steps, the pipeline outputs a line listing the steps it will run and the stop point. Format: `Execution plan: specify -> homer -> plan. Stopping after: plan.` When `--stop-after` is not provided, omit the "Stopping after" clause and show all steps from start to ralph.

**Rationale**: FR-011 requires an upfront announcement. This provides transparency about what the pipeline will do before it starts, enabling users to abort if the plan looks wrong.

**Alternatives considered**: A multi-line formatted table -- rejected in favor of a single readable line that doesn't clutter the output.

## R-006: Completion Report Format (FR-008)

**Decision**: The Step 6 report is expanded to list all six pipeline steps with per-step status. Each step gets one of three statuses:

- `executed` -- step ran to completion
- `skipped` -- step was not executed, either because its artifact already existed (e.g., plan.md present so plan step skipped) or because the step falls before the `--from` starting step
- `stopped-by-param` -- step was not executed because `--stop-after` halted the pipeline before reaching it

When `--stop-after` caused early termination, the report explicitly states the last executed step and lists remaining steps as `stopped-by-param`.

**Rationale**: FR-008 requires per-step status reporting. Three statuses cover all possible step outcomes. This extends the existing Step 6 report (which currently only lists executed steps and total iterations).

**Alternatives considered**: Adding a fourth status "not-reached" for steps before `--from` -- rejected because `skipped` already covers both "artifact exists" and "outside execution range" cases. Adding a fourth status increases complexity without meaningful user value. All six steps should be listed regardless.

## R-007: Stop Message Format (FR-010)

**Decision**: When `--stop-after` triggers early termination, the pipeline outputs: `Pipeline stopped after <step> per --stop-after parameter. Skipping: <remaining steps>.` followed by the completion report. The pipeline must NOT spawn any further sub-agents after outputting this message.

**Rationale**: FR-010 specifies the exact format and explicitly requires no further sub-agent spawning. The message makes it clear why the pipeline stopped and what was skipped.

**Alternatives considered**: A generic "Pipeline complete" message with details in the report only -- rejected because FR-010 requires an explicit stop message separate from the report.

## R-008: Behavior When --stop-after Is Not Provided (FR-007)

**Decision**: No changes to existing behavior. When `--stop-after` is absent, the pipeline runs from the starting step through ralph exactly as it does today. The `stop_after` variable is left unset/empty, and the post-step stop check is a no-op.

**Rationale**: FR-007 requires zero regression when `--stop-after` is not used. By defaulting to "no stop point," all existing invocations behave identically.

**Alternatives considered**: Defaulting `--stop-after` to `ralph` internally -- functionally equivalent but adds unnecessary noise to the execution plan announcement. Better to leave it unset.

## Files Requiring Changes

### Modify

| File | Changes | FRs |
|---|---|---|
| `.claude/commands/speckit.pipeline.md` | Add `--stop-after` parsing in Step 1, add value/range validation, add execution plan announcement before Step 5, add post-step stop check in Step 5, expand Step 6 report with per-step status | FR-001 through FR-011 |

### No Changes Needed

| File | Reason |
|---|---|
| `.claude/agents/*.md` | Agent files are explicitly out of scope per spec |
| `.claude/commands/speckit.homer.clarify.md` | Standalone loop commands don't support `--stop-after` |
| `.claude/commands/speckit.lisa.analyze.md` | Standalone loop commands don't support `--stop-after` |
| `.claude/commands/speckit.ralph.implement.md` | Standalone loop commands don't support `--stop-after` |
| `.specify/scripts/bash/*.sh` | Utility scripts are unaffected |
| `.specify/quality-gates.sh` | Quality gates are unaffected |
| `setup.sh` | No new source files to install |
