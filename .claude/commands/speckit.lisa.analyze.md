---
description: Orchestrate iterative cross-artifact analysis and remediation (Lisa loop) on spec.md, plan.md, and tasks.md until all findings are resolved.
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
test -f ".claude/agents/lisa.md" && echo "lisa.md: EXISTS" || echo "lisa.md: MISSING"
```

If **MISSING**, display this error and **STOP** — do not proceed with execution:

```
ERROR: Required agent file not found.

Missing: .claude/agents/lisa.md

This agent file is required for Lisa loop sub-agents to execute. It defines
the behavior of each analysis iteration. Ensure the file is present at:
  .claude/agents/lisa.md
```

If **EXISTS**, proceed to the Goal section below.

## Goal

Orchestrate the Lisa loop directly within this session. Each iteration spawns a fresh sub agent (via the Agent tool) that analyzes cross-artifact consistency, fixes the single highest-severity finding, commits, and exits. The loop continues until zero findings remain or max iterations is reached.

**AUTONOMOUS EXECUTION**: This loop runs unattended. Do NOT ask the user for confirmation between iterations. Do NOT pause for permission requests. Execute all iterations back-to-back until a completion condition is met (all findings resolved, max iterations reached, or stuck detection triggers).

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

### Step 3: Verify Artifacts

Confirm all three artifacts exist in `FEATURE_DIR`:

- `spec.md`
- `plan.md`
- `tasks.md`

If any are missing, abort with guidance:

- Missing `spec.md` → "Run /speckit.specify first"
- Missing `plan.md` → "Run /speckit.plan first"
- Missing `tasks.md` → "Run /speckit.tasks first"

### Step 4: Configuration

- If `max-iterations` was parsed from `$ARGUMENTS`, use that value
- Otherwise, default max iterations: **30**

### Step 5: Run Lisa Loop

Initialize `consecutive_stuck_count = 0`. For each iteration (up to max), spawn ONE sub agent at a time (wait for it to return before spawning the next):

**Before** each sub agent: record `PRE_ITERATION_SHA=$(git rev-parse HEAD)` via Bash tool.

1. Spawn a fresh-context sub agent using the **Agent tool**:
   - **subagent_type**: `general-purpose`
   - **prompt**: Compose a prompt containing:
     - Instruct the agent to read and follow `.claude/agents/lisa.md`
     - When those instructions reference a slash command (e.g., `/speckit.analyze`), read the corresponding file from `.claude/commands/` and follow its instructions directly
     - Provide: `Feature directory: <FEATURE_DIR>`
   - Each sub agent gets a fresh context window, preventing hallucination drift

**After** each sub agent returns:
1. Check the sub agent's returned output for the completion promise tag: `<promise>ALL_FINDINGS_RESOLVED</promise>`. If found, report success and stop looping.
2. Check `git diff $PRE_ITERATION_SHA --stat` via Bash tool for file changes.
3. **Stuck detection**: If there are NO file changes (empty diff) AND the promise tag was NOT found, increment `consecutive_stuck_count`. If there ARE file changes OR the promise tag was found, reset `consecutive_stuck_count = 0`.
4. If `consecutive_stuck_count >= 2`, abort the lisa loop — report "stuck: 2 consecutive iterations with no file changes and no completion signal". Suggest manual review.
5. Otherwise, continue to the next iteration.

**Failure handling**: If the sub agent fails (crash, timeout, or error), abort the loop immediately. Log failure context: iteration number, agent type (lisa), and error message. Do NOT retry — sub agent failures in loop commands are treated as deterministic. Suggest manual review.

### Step 6: Report Results

After the loop completes, report:
- Total iterations run
- Completion status (one of: **success** — all findings resolved; **max iterations reached** — limit hit without resolution; **stuck** — 2 consecutive iterations with no file changes and no completion signal; **failure** — sub agent crashed or errored)
- Suggestion to rerun if not fully resolved

## Examples

- `/speckit.lisa.analyze` — Auto-detect spec dir from current branch, use default max iterations (30)
- `/speckit.lisa.analyze specs/003-fix-pipeline-delegation` — Run for specific spec dir
- `/speckit.lisa.analyze 5` — Auto-detect spec dir, limit to 5 iterations
- `/speckit.lisa.analyze specs/003-fix-pipeline-delegation 5` — Specific spec dir with 5 max iterations
