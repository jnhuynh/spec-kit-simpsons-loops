---
description: Orchestrate task-by-task implementation (Ralph loop) until all tasks are complete.
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Goal

Orchestrate the Ralph loop directly within this Claude Code session. Each iteration spawns a fresh sub agent (via the Agent tool) that implements one task from tasks.md, runs quality gates, commits, and exits. The loop continues until all tasks are complete or max iterations is reached.

**AUTONOMOUS EXECUTION**: This loop runs unattended. Do NOT ask the user for confirmation between iterations. Do NOT pause for permission requests. Execute all iterations back-to-back until a completion condition is met (all tasks complete, max iterations reached, or stuck detection triggers).

**STRICT SEQUENTIAL EXECUTION**: Each sub agent MUST complete and return its result before the next sub agent is spawned. Never run multiple sub agents in parallel. Wait for one iteration to finish before starting the next.

## Execution Steps

### Step 1: Resolve Feature Directory

- If `$ARGUMENTS` contains a directory path, use it as `FEATURE_DIR`
- Otherwise, run `.specify/scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks` from repo root and parse JSON output for `FEATURE_DIR`

### Step 2: Analyze Tasks

1. Count incomplete tasks (`- [ ]` lines) in `FEATURE_DIR/tasks.md`
2. Count completed tasks (`- [x]` lines)
3. Exit early if nothing to do

### Step 3: Extract Quality Gates

> **PLACEHOLDER** — Replace the command below with your project's quality gates before running Ralph.

```bash
echo "PLACEHOLDER: Update this quality gate in speckit.ralph.implement.md before using Ralph." && exit 1
```

### Step 4: Configuration

- Calculate max iterations: `incomplete_tasks + 10`

### Step 5: Run Ralph Loop

For each iteration (up to max):

1. Spawn a fresh-context sub agent using the **Agent tool**:
   - **subagent_type**: `general-purpose`
   - **prompt**: Compose a prompt containing:
     - Instruct the agent to read and follow `.claude/agents/ralph.md`
     - When those instructions reference a slash command (e.g., `/speckit.implement`), read the corresponding file from `.claude/commands/` and follow its instructions directly
     - Provide: `Feature directory: <FEATURE_DIR>. Quality gates: <QUALITY_GATES>`
   - Each sub agent gets a fresh context window, preventing hallucination drift

2. Check the sub agent's returned output for the completion promise tag: `<promise>ALL_TASKS_COMPLETE</promise>`
   - If found: report success and stop looping
   - If not found: also verify tasks.md directly — if no `- [ ]` remain and at least one `- [x]` exists, treat as complete

3. **Stuck detection**: Track consecutive iterations with identical output. If 3 consecutive iterations produce identical output, abort and suggest reviewing tasks.md.

4. **Failure handling**: If the sub agent fails (crash, timeout, or error), abort the loop immediately. Log failure context: iteration number, agent type (ralph), and error message. Do NOT retry — sub agent failures in loop commands are treated as deterministic. Suggest manual review.

### Step 6: Report Results

After the loop completes, report:
- Total iterations run
- Tasks completed vs remaining
- Whether all tasks were completed or max iterations reached
- Suggestion to rerun if max iterations reached
