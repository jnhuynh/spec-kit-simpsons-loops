# Quickstart: Stop-After Pipeline Parameter

## Overview

This feature adds a `--stop-after <step>` parameter to the pipeline command (`speckit.pipeline.md`) that halts execution after the specified step completes. It enables partial pipeline runs and combines with the existing `--from` parameter to define precise step ranges.

All changes are in a single file: `.claude/commands/speckit.pipeline.md`.

## Implementation Order

### Phase 1: Argument Parsing (FR-001, FR-009)

**File**: `.claude/commands/speckit.pipeline.md` -- Step 1

Add `--stop-after <step>` to the argument parser in Step 1. Parse it alongside `--from`, `--description`, and `spec-dir`. Store the value in `STOP_AFTER_STEP`. It is position-independent (same flexibility as `--from`).

### Phase 2: Validation (FR-005, FR-006)

**File**: `.claude/commands/speckit.pipeline.md` -- after Step 3

Add a validation section after Step 3 (auto-detect starting step) so both start and stop-after steps are known:

1. **Value validation**: If `--stop-after` is provided, check it is one of `specify`, `homer`, `plan`, `tasks`, `lisa`, `ralph`. If invalid, display error listing valid step names and exit.
2. **Range validation**: If `--stop-after` step index is less than the starting step index, display error explaining that stop-after must not precede the from step. Exit without executing any steps.

### Phase 3: Execution Plan Announcement (FR-011)

**File**: `.claude/commands/speckit.pipeline.md` -- before Step 5

Before executing any steps, output a line listing the planned steps:
- With `--stop-after`: `Execution plan: specify -> homer -> plan. Stopping after: plan.`
- Without `--stop-after`: `Execution plan: homer -> plan -> tasks -> lisa -> ralph.`

### Phase 4: Post-Step Stop Check (FR-002, FR-004, FR-010)

**File**: `.claude/commands/speckit.pipeline.md` -- Step 5

After each step completes, add a stop check: if the current step matches `STOP_AFTER_STEP`, output the stop message and skip all remaining steps. No further sub-agents are spawned.

Stop message format: `Pipeline stopped after <step> per --stop-after parameter. Skipping: <remaining steps>.`

### Phase 5: Enhanced Completion Report (FR-008)

**File**: `.claude/commands/speckit.pipeline.md` -- Step 6

Expand the completion report to list all six pipeline steps with per-step status:
- `executed` -- step ran
- `skipped` -- step was skipped because artifact already existed
- `stopped-by-param` -- step was not reached due to `--stop-after`

### Phase 6: Default Behavior Preservation (FR-007)

No explicit code needed. When `--stop-after` is not provided, the variable is empty and all stop checks are no-ops. Verify existing behavior is unchanged.

## Key Patterns

### Step index mapping for validation

```text
specify=0, homer=1, plan=2, tasks=3, lisa=4, ralph=5

Validation: stop_after_index >= start_index
```

### Examples section update

Add these examples to the command file:
- `/speckit.pipeline --stop-after plan` -- Run through plan step only
- `/speckit.pipeline --from homer --stop-after tasks` -- Run homer through tasks
- `/speckit.pipeline --stop-after homer --from specify --description "Add feature X"` -- Specify and homer only

## Verification Checklist

### Argument Parsing (FR-001, FR-009)

- [ ] `--stop-after plan` is parsed correctly
- [ ] `--stop-after` can appear in any argument position
- [ ] `--stop-after` without a value produces an error

### Validation (FR-005, FR-006)

- [ ] `--stop-after invalidstep` produces error listing valid step names
- [ ] `--from tasks --stop-after plan` produces range error
- [ ] Errors occur before any steps execute

### Execution (FR-002, FR-003, FR-004, FR-010)

- [ ] `--stop-after plan` runs specify/homer/plan, skips tasks/lisa/ralph
- [ ] `--from plan --stop-after tasks` runs only plan and tasks
- [ ] `--from homer --stop-after homer` runs only homer
- [ ] `--stop-after ralph` behaves same as no `--stop-after`
- [ ] Stop message is output when stopping early
- [ ] No sub-agents spawn after the stop-after step

### Reporting (FR-008, FR-011)

- [ ] Execution plan announcement appears before any steps run
- [ ] Completion report lists all six steps with correct per-step status
- [ ] Stopped steps show `stopped-by-param`

### Default Behavior (FR-007)

- [ ] Pipeline without `--stop-after` behaves identically to before
