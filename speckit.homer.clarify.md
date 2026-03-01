---
description: Orchestrate iterative spec clarification and remediation (Homer loop) on spec.md until all findings are resolved.
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Goal

Orchestrate the Homer loop directly within this Claude Code session. Each iteration spawns a fresh sub agent (via the Agent tool) that clarifies spec artifacts, fixes the single highest-severity finding, commits, and exits. The loop continues until zero findings remain or max iterations is reached.

**AUTONOMOUS EXECUTION**: This loop runs unattended. Do NOT ask the user for confirmation between iterations. Do NOT pause for permission requests. Execute all iterations back-to-back until a completion condition is met (all findings resolved, max iterations reached, or stuck detection triggers).

## Execution Steps

### Step 1: Resolve Feature Directory

- If `$ARGUMENTS` contains a directory path, use it as `FEATURE_DIR`
- Otherwise, run `.specify/scripts/bash/check-prerequisites.sh --json` from repo root and parse JSON output for `FEATURE_DIR`

### Step 2: Verify Artifacts

Confirm `spec.md` exists in `FEATURE_DIR`.

If missing, abort with guidance: "Run /speckit.specify first"

### Step 3: Configuration

- Default max iterations: **10** (4 severity levels + buffer)

### Step 4: Run Homer Loop

For each iteration (up to max):

1. Spawn a fresh-context sub agent using the **Agent tool**:
   - **subagent_type**: `general-purpose`
   - **prompt**: Compose a prompt containing:
     - Instruct the agent to read and follow `.claude/agents/homer.md`
     - When those instructions reference a slash command (e.g., `/speckit.clarify`), read the corresponding file from `.claude/commands/` and follow its instructions directly
     - Provide: `Feature directory: <FEATURE_DIR>`
   - Each sub agent gets a fresh context window, preventing hallucination drift

2. Check the sub agent's returned output for the completion promise tag: `<promise>ALL_FINDINGS_RESOLVED</promise>`
   - If found: report success and stop looping
   - If not found: continue to next iteration

3. **Stuck detection**: Track consecutive iterations with identical output. If 3 consecutive iterations produce identical output, abort and suggest manual review.

4. **Failure handling**: If the sub agent fails, increment failure counter. Abort after 3 consecutive failures.

### Step 5: Report Results

After the loop completes, report:
- Total iterations run
- Whether all findings were resolved or max iterations reached
- Suggestion to rerun if max iterations reached
