---
description: Orchestrate task-by-task implementation (Ralph loop) until all tasks are complete.
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Pre-Flight Check

Before doing anything else, verify that the required utility scripts are installed:

1. Check if `.specify/scripts/bash/check-prerequisites.sh` exists (use the Bash tool: `test -f .specify/scripts/bash/check-prerequisites.sh && echo "EXISTS" || echo "MISSING"`)
2. If **MISSING**, display this error and **STOP** — do not proceed with any execution:

```
ERROR: Required utility script not found.

Missing: .specify/scripts/bash/check-prerequisites.sh

This script is required for feature directory resolution and prerequisite validation.
To install it, run the SpecKit setup command:

  /speckit.setup

```

3. If **EXISTS**, proceed to the agent file check below.

## Agent File Check

Verify that the required agent file exists before starting the loop. Check using the Bash tool:

```bash
test -f ".claude/agents/ralph.md" && echo "ralph.md: EXISTS" || echo "ralph.md: MISSING"
```

If **MISSING**, display this error and **STOP** — do not proceed with execution:

```
ERROR: Required agent file not found.

Missing: .claude/agents/ralph.md

This agent file is required for Ralph loop sub-agents to execute. It defines
the behavior of each implementation iteration. Ensure the file is present at:
  .claude/agents/ralph.md
```

If **EXISTS**, proceed to the Goal section below.

## Goal

Orchestrate the Ralph loop directly within this session. Each iteration spawns a fresh sub agent (via the Agent tool) that implements one task from tasks.md, runs quality gates, commits, and exits. The loop continues until all tasks are complete or max iterations is reached.

**AUTONOMOUS EXECUTION**: This loop runs unattended. Do NOT ask the user for confirmation between iterations. Do NOT pause for permission requests. Execute all iterations back-to-back until a completion condition is met (all tasks complete, max iterations reached, or stuck detection triggers).

**STRICT SEQUENTIAL EXECUTION**: Each sub agent MUST complete and return its result before the next sub agent is spawned. Never run multiple sub agents in parallel. Wait for one iteration to finish before starting the next.

## Execution Steps

### Step 1: Parse Arguments

Parse `$ARGUMENTS` for the following (all are optional, can appear in any order):

- **`spec-dir`**: A directory path (e.g., `specs/003-fix-pipeline-delegation`). If provided, use it as `FEATURE_DIR`.
- **`max-iterations`**: A numeric value (e.g., `5`). If provided, use it as the max iteration count instead of the default.

**Parsing rules**:
- A token that looks like a directory path (contains `/` or matches a known `specs/` pattern) is treated as `spec-dir`
- A standalone numeric token (e.g., `5`, `10`) is treated as `max-iterations`
- If neither is provided, use defaults for both

### Step 2: Resolve Feature Directory

- If `spec-dir` was parsed from `$ARGUMENTS`, use it as `FEATURE_DIR`
- Otherwise, run `bash .specify/scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks` from repo root and parse JSON output for `FEATURE_DIR`. **Error handling**: If the script exits with a non-zero status (e.g., missing feature dir, invalid branch), display the script's stderr/stdout output to the user and **STOP** — do not proceed with execution.

### Step 3: Analyze Tasks

1. Count incomplete tasks (`- [ ]` lines) in `FEATURE_DIR/tasks.md`
2. Count completed tasks (`- [x]` lines)
3. Exit early if nothing to do

### Step 4: Validate and Extract Quality Gates

**Validation (MUST pass before proceeding)**: Run the following checks using the Bash tool:

1. **File existence**: `test -f .specify/quality-gates.sh && echo "EXISTS" || echo "MISSING"`
2. **Non-empty executable content**: `grep -v '^\s*#' .specify/quality-gates.sh | grep -v '^\s*$' | head -1`

If the file is **MISSING** or the grep produces no output (file contains only comments/whitespace), display this error and **STOP** — do not proceed with execution:

```
ERROR: Quality gates file is missing or empty.

Expected: .specify/quality-gates.sh with executable commands
Found: File missing or contains only comments/whitespace

The quality gates file is required for Ralph to validate task implementations.
Create or update .specify/quality-gates.sh with your project's quality gate
commands (e.g., npm test && npm run lint). The file must exit 0 for gates to pass.
```

If validation passes, quality gates are read from `.specify/quality-gates.sh` in the project root:

```bash
# SPECKIT_DEFAULT_QUALITY_GATE
bash .specify/quality-gates.sh
```

### Step 5: Configuration

- If `max-iterations` was parsed from `$ARGUMENTS`, use that value
- Otherwise, default max iterations: `incomplete_tasks + 10`

### Step 6: Run Ralph Loop

Initialize `consecutive_stuck_count = 0`. For each iteration (up to max), spawn ONE sub agent at a time (wait for it to return before spawning the next):

**Before** each sub agent: record `PRE_ITERATION_SHA=$(git rev-parse HEAD)` via Bash tool.

1. Spawn a fresh-context sub agent using the **Agent tool**:
   - **subagent_type**: `general-purpose`
   - **prompt**: Compose a prompt containing:
     - Instruct the agent to read and follow `.claude/agents/ralph.md`
     - When those instructions reference a slash command (e.g., `/speckit.implement`), read the corresponding file from `.claude/commands/` and follow its instructions directly
     - Provide: `Feature directory: <FEATURE_DIR>. Quality gates: bash .specify/quality-gates.sh`
   - Each sub agent gets a fresh context window, preventing hallucination drift

**After** each sub agent returns:
1. Check the sub agent's returned output for the completion promise tag: `<promise>ALL_TASKS_COMPLETE</promise>`. If found, report success and stop looping.
2. If not found: also verify tasks.md directly — if no `- [ ]` remain and at least one `- [x]` exists, treat as complete.
3. Check `git diff $PRE_ITERATION_SHA --stat` via Bash tool for file changes.
4. **Stuck detection**: If there are NO file changes (empty diff) AND the promise tag was NOT found, increment `consecutive_stuck_count`. If there ARE file changes OR the promise tag was found, reset `consecutive_stuck_count = 0`.
5. If `consecutive_stuck_count >= 2`, abort the ralph loop — report "stuck: 2 consecutive iterations with no file changes and no completion signal". Suggest manual review.
6. Otherwise, continue to the next iteration.

**Failure handling**: If the sub agent fails (crash, timeout, or error), abort the loop immediately. Log failure context: iteration number, agent type (ralph), and error message. Do NOT retry — sub agent failures in loop commands are treated as deterministic. Suggest manual review.

### Step 7: Report Results

After the loop completes, report:
- Total iterations run
- Tasks completed vs remaining
- Completion status (one of: **success** — all tasks completed; **max iterations reached** — limit hit with tasks remaining; **stuck** — 2 consecutive iterations with no file changes and no completion signal; **failure** — sub agent crashed or errored)
- Suggestion to rerun if not fully resolved

## Examples

- `/speckit.ralph.implement` — Auto-detect spec dir from current branch, use default max iterations (incomplete_tasks + 10)
- `/speckit.ralph.implement specs/003-fix-pipeline-delegation` — Run for specific spec dir
- `/speckit.ralph.implement 5` — Auto-detect spec dir, limit to 5 iterations
- `/speckit.ralph.implement specs/003-fix-pipeline-delegation 5` — Specific spec dir with 5 max iterations
