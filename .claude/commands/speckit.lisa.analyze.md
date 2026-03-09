---
description: Orchestrate iterative cross-artifact analysis and remediation (Lisa loop) on spec.md, plan.md, and tasks.md until all findings are resolved.
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Goal

Orchestrate the Lisa loop directly within this Claude Code session. Each iteration spawns a fresh sub agent (via the Agent tool) that analyzes cross-artifact consistency, fixes the single highest-severity finding, commits, and exits. The loop continues until zero findings remain or max iterations is reached.

**AUTONOMOUS EXECUTION**: This loop runs unattended. Do NOT ask the user for confirmation between iterations. Do NOT pause for permission requests. Execute all iterations back-to-back until a completion condition is met (all findings resolved, max iterations reached, or stuck detection triggers).

**STRICT SEQUENTIAL EXECUTION**: Each sub agent MUST complete and return its result before the next sub agent is spawned. Never run multiple sub agents in parallel. Wait for one iteration to finish before starting the next.

## Execution Steps

### Step 1: Resolve Feature Directory

- If `$ARGUMENTS` contains a directory path, use it as `FEATURE_DIR`
- Otherwise, run `.specify/scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks` from repo root and parse JSON output for `FEATURE_DIR`

### Step 2: Verify Artifacts

Confirm all three artifacts exist in `FEATURE_DIR`:

- `spec.md`
- `plan.md`
- `tasks.md`

If any are missing, abort with guidance:

- Missing `spec.md` → "Run /speckit.specify first"
- Missing `plan.md` → "Run /speckit.plan first"
- Missing `tasks.md` → "Run /speckit.tasks first"

### Step 3: Configuration

- Default max iterations: **10** (4 severity levels + buffer)

### Step 4: Run Lisa Loop

For each iteration (up to max):

1. Spawn a fresh-context sub agent using the **Agent tool**:
   - **subagent_type**: `general-purpose`
   - **prompt**: Compose a prompt containing:
     - Instruct the agent to read and follow `.claude/agents/lisa.md`
     - When those instructions reference a slash command (e.g., `/speckit.analyze`), read the corresponding file from `.claude/commands/` and follow its instructions directly
     - Provide: `Feature directory: <FEATURE_DIR>`
   - Each sub agent gets a fresh context window, preventing hallucination drift

2. Check the sub agent's returned output for the completion promise tag: `<promise>ALL_FINDINGS_RESOLVED</promise>`
   - If found: report success and stop looping
   - If not found: continue to next iteration

3. **Stuck detection**: Track consecutive iterations with identical output. If 3 consecutive iterations produce identical output, abort and suggest manual review.

4. **Failure handling**: If the sub agent fails (crash, timeout, or error), abort the loop immediately. Log failure context: iteration number, agent type (lisa), and error message. Do NOT retry — sub agent failures in loop commands are treated as deterministic. Suggest manual review.

### Step 5: Report Results

After the loop completes, report:
- Total iterations run
- Completion status (one of: **success** — all findings resolved; **max iterations reached** — limit hit without resolution; **stuck** — 3 consecutive identical outputs detected; **failure** — sub agent crashed or errored)
- Suggestion to rerun if not fully resolved
