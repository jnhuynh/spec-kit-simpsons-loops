---
description: Orchestrate task-by-task implementation (Ralph loop) until all tasks are complete.
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Pre-Loop: Quality Gates Validation

Before configuring the loop, validate that quality gates are set up. Run the following checks using the Bash tool:

1. **File existence**: `test -f .specify/quality-gates.sh && echo "EXISTS" || echo "MISSING"`
2. **Non-empty executable content**: `grep -v '^\s*#' .specify/quality-gates.sh | grep -v '^\s*$' | head -1`

If the file is **MISSING** or the grep produces no output, display this error and **STOP**:

```
ERROR: Quality gates file is missing or empty.

Expected: .specify/quality-gates.sh with executable commands
Found: File missing or contains only comments/whitespace

The quality gates file is required for Ralph to validate task implementations.
Create or update .specify/quality-gates.sh with your project's quality gate
commands (e.g., npm test && npm run lint). The file must exit 0 for gates to pass.
```

## Pre-Loop: Task Counting

After resolving FEATURE_DIR (the orchestrator handles this), count tasks in `FEATURE_DIR/tasks.md`:

1. Count incomplete tasks: `grep -c '^\s*- \[ \]' "<FEATURE_DIR>/tasks.md"`
2. Count completed tasks: `grep -c '^\s*- \[x\]' "<FEATURE_DIR>/tasks.md"`
3. If no incomplete tasks remain, exit early — nothing to implement
4. Calculate dynamic max iterations: `incomplete_tasks + 10`

Use the calculated value as MAX_ITERATIONS in the loop configuration below.

## Loop Configuration

Set the following LOOP_CONFIG values for this execution:

- **AGENT_NAME**: ralph
- **AGENT_DISPLAY_NAME**: Ralph
- **AGENT_FILE**: .claude/agents/ralph.md
- **SLASH_COMMAND_REF**: /speckit.implement
- **PROMISE_TAG**: ALL_TASKS_COMPLETE
- **PREREQ_FLAGS**: --json --require-tasks --include-tasks
- **REQUIRED_ARTIFACTS**: spec.md, plan.md, tasks.md
- **MAX_ITERATIONS**: (use the value calculated in Task Counting above)
- **EXTRA_PROMPT_SUFFIX**: Quality gates: bash .specify/quality-gates.sh
- **REPORT_MODE**: tasks

## Execute

Read and follow the instructions in `.claude/agents/loop-orchestrator.md`, using the LOOP_CONFIG values above. Pass `$ARGUMENTS` through for argument parsing.

## Post-Loop: Tasks Verification

After the loop orchestrator reports completion via the promise tag, also verify `tasks.md` directly — if no `- [ ]` lines remain and at least one `- [x]` exists, confirm completion. If incomplete tasks remain despite the promise tag, report the discrepancy.

## Examples

- `/speckit.ralph.implement` — Auto-detect spec dir from current branch, use default max iterations (incomplete_tasks + 10)
- `/speckit.ralph.implement specs/003-fix-pipeline-delegation` — Run for specific spec dir
- `/speckit.ralph.implement 5` — Auto-detect spec dir, limit to 5 iterations
- `/speckit.ralph.implement specs/003-fix-pipeline-delegation 5` — Specific spec dir with 5 max iterations
