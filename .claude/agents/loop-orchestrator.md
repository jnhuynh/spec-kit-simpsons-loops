# Speckit Loop Orchestrator

Shared loop orchestration logic for all Speckit iterative stages (Homer, Lisa, Ralph, Marge). This file is parameterized by a LOOP_CONFIG block provided by the calling command. Do NOT execute this file directly — it must be invoked by a loop command that provides the configuration.

## Required Configuration (LOOP_CONFIG)

The calling command MUST have provided all of these values before you begin. Confirm you have each one:

- **AGENT_NAME**: lowercase name (e.g., `homer`, `lisa`, `ralph`, `marge`)
- **AGENT_DISPLAY_NAME**: display name (e.g., `Homer`, `Lisa`, `Ralph`, `Marge`)
- **AGENT_FILE**: path to agent behavior file (e.g., `.claude/agents/homer.md`)
- **SLASH_COMMAND_REF**: the slash command the agent references (e.g., `/speckit.clarify`)
- **PROMISE_TAG**: completion signal (e.g., `ALL_FINDINGS_RESOLVED` or `ALL_TASKS_COMPLETE`)
- **PREREQ_FLAGS**: flags for `check-prerequisites.sh` (e.g., `--json --paths-only`)
- **REQUIRED_ARTIFACTS**: list of files that must exist in FEATURE_DIR (e.g., `spec.md` or `spec.md, plan.md, tasks.md`)
- **MAX_ITERATIONS**: numeric value (pre-computed by calling command, including any dynamic calculation)
- **EXTRA_PROMPT_SUFFIX**: additional text appended to sub-agent prompts (empty string if none)
- **REPORT_MODE**: one of `standard`, `tasks`, or `needs_human`

If any value is missing, abort with: "ERROR: Incomplete LOOP_CONFIG. Missing: [list missing fields]. The calling command must provide all configuration values."

## Pre-Flight Check

Verify that the required utility script is installed:

```bash
test -f .specify/scripts/bash/check-prerequisites.sh && echo "EXISTS" || echo "MISSING"
```

If **MISSING**, display this error and **STOP**:

```
ERROR: Required utility script not found.

Missing: .specify/scripts/bash/check-prerequisites.sh

This script is required for feature directory resolution and prerequisite validation.
To install it, run the SpecKit setup command:

  /speckit.setup

```

## Agent File Check

Verify that the required agent file exists:

```bash
test -f "<AGENT_FILE>" && echo "<AGENT_NAME>.md: EXISTS" || echo "<AGENT_NAME>.md: MISSING"
```

If **MISSING**, display this error and **STOP**:

```
ERROR: Required agent file not found.

Missing: <AGENT_FILE>

This agent file is required for <AGENT_DISPLAY_NAME> loop sub-agents to execute.
It defines the behavior of each iteration. Ensure the file is present at:
  <AGENT_FILE>
```

## Goal

Orchestrate the <AGENT_DISPLAY_NAME> loop directly within this session. Each iteration spawns a fresh sub agent (via the Agent tool) that executes one unit of work, commits, and exits. The loop continues until the completion condition is met or max iterations is reached.

**AUTONOMOUS EXECUTION**: This loop runs unattended. Do NOT ask the user for confirmation between iterations. Do NOT pause for permission requests. Execute all iterations back-to-back until a completion condition is met (completion signal received, max iterations reached, or stuck detection triggers).

**STRICT SEQUENTIAL EXECUTION**: Each sub agent MUST complete and return its result before the next sub agent is spawned. Never run multiple sub agents in parallel. Wait for one iteration to finish before starting the next.

## Step 1: Parse Arguments

Parse `$ARGUMENTS` (passed through from the calling command) for the following (all optional, any order):

- **`spec-dir`**: A directory path (e.g., `specs/003-fix-pipeline-delegation`). If provided, use it as `FEATURE_DIR`.
- **`max-iterations`**: A numeric value (e.g., `5`). If provided, **override** the MAX_ITERATIONS from LOOP_CONFIG.

**Parsing rules**:
- A token that looks like a directory path (contains `/` or matches a known `specs/` pattern) is treated as `spec-dir`
- A standalone numeric token (e.g., `5`, `10`) is treated as `max-iterations`
- If neither is provided, use defaults for both

## Step 2: Resolve Feature Directory

- If `spec-dir` was parsed from `$ARGUMENTS`, use it as `FEATURE_DIR`
- Otherwise, run `bash .specify/scripts/bash/check-prerequisites.sh <PREREQ_FLAGS>` from repo root and parse JSON output for `FEATURE_DIR`. **Error handling**: If the script exits with a non-zero status, display the script's stderr/stdout output and **STOP**.

## Step 3: Verify Artifacts

For each file listed in REQUIRED_ARTIFACTS, confirm it exists in `FEATURE_DIR`.

If any are missing, abort with guidance:
- Missing `spec.md` → "Run /speckit.specify first"
- Missing `plan.md` → "Run /speckit.plan first"
- Missing `tasks.md` → "Run /speckit.tasks first"

## Step 4: Run Loop

Initialize tracking state:
- `consecutive_stuck_count = 0`
- `progress_history = []` (tracks work-remaining count per iteration for stall/oscillation detection)

For each iteration (up to MAX_ITERATIONS), spawn ONE sub agent at a time:

**Before** each sub agent: record `PRE_ITERATION_SHA=$(git rev-parse HEAD)` via Bash tool.

1. Spawn a fresh-context sub agent using the **Agent tool**:
   - **subagent_type**: `general-purpose`
   - **prompt**: Compose a prompt containing:
     - Instruct the agent to read and follow `<AGENT_FILE>`
     - When those instructions reference a slash command (e.g., `<SLASH_COMMAND_REF>`), read its definition — prefer `.claude/skills/<command>/SKILL.md`, falling back to `.claude/commands/<command>.md` — and follow those instructions directly
     - Provide: `Feature directory: <FEATURE_DIR>`
     - Append EXTRA_PROMPT_SUFFIX if non-empty
   - Each sub agent gets a fresh context window, preventing hallucination drift

**After** each sub agent returns:

1. **Completion check**: Check the sub agent's returned output for the completion promise tag: `<promise><PROMISE_TAG></promise>`. If found, report success and stop looping.

2. **Progress tracking**: Extract the work-remaining count from the sub agent's output if available (total findings for Homer/Lisa/Marge, incomplete tasks for Ralph). Append to `progress_history`.

3. **File change check**: Run `git diff $PRE_ITERATION_SHA --stat` via Bash tool.

4. **Stuck detection** (three modes):

   **a. No-progress stuck** (existing): If there are NO file changes (empty diff) AND the promise tag was NOT found, increment `consecutive_stuck_count`. If there ARE file changes OR the promise tag was found, reset `consecutive_stuck_count = 0`. If `consecutive_stuck_count >= 2`, abort — report "stuck: 2 consecutive iterations with no file changes and no completion signal". Suggest manual review.

   **b. Stalled** (new): If `progress_history` has 3+ entries AND the last 3 entries show the same work-remaining count (no reduction), abort — report "stalled: 3 consecutive iterations without reducing work count (consistently at N). The loop is making changes but not making progress." Suggest manual review.

   **c. Oscillating** (new): If `progress_history` has 4+ entries AND the last 4 entries alternate between two values (e.g., 5, 4, 5, 4), abort — report "oscillating: work count alternating between N and M. A fix is likely introducing a new issue." Suggest manual review.

5. Otherwise, continue to the next iteration.

**Failure handling**: If the sub agent fails (crash, timeout, or error), abort the loop immediately. Log failure context: iteration number, agent type (<AGENT_NAME>), and error message. Do NOT retry — sub agent failures in loop commands are treated as deterministic. Suggest manual review.

## Step 5: Report Results

After the loop completes, report:

- Total iterations run
- Completion status (one of: **success** — completion signal received; **max iterations reached** — limit hit without completion; **stuck** — 2 consecutive iterations with no changes and no completion signal; **stalled** — 3 iterations without reducing work count; **oscillating** — work count alternating between two values; **failure** — sub agent crashed or errored)

**Additional reporting based on REPORT_MODE**:

- `standard`: No additional fields
- `tasks`: Include "Tasks completed vs remaining" counts
- `needs_human`: Include count of findings flagged `NEEDS_HUMAN` and one-line summaries of each (extract from the last sub agent's report)

If not fully resolved, suggest rerunning the loop command.

## Examples

- `/<command>` — Auto-detect spec dir from current branch, use default max iterations
- `/<command> specs/003-fix-pipeline-delegation` — Run for specific spec dir
- `/<command> 5` — Auto-detect spec dir, limit to 5 iterations
- `/<command> specs/003-fix-pipeline-delegation 5` — Specific spec dir with 5 max iterations
