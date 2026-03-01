---
description: Orchestrate the full SpecKit pipeline (homer, plan, tasks, lisa, ralph) after spec is complete.
---

## User Input

```text
$ARGUMENTS
```

## Overview

Orchestrate the full SpecKit pipeline directly within this Claude Code session. Each step spawns fresh sub agents (via the Agent tool) with isolated context windows. This command assumes `/speckit.specify` has already been completed interactively and a `spec.md` exists in the feature's spec directory.

**AUTONOMOUS EXECUTION**: This pipeline runs unattended. Do NOT ask the user for confirmation between iterations or steps. Do NOT pause for permission requests. Execute all steps and iterations back-to-back until the pipeline completes or a failure condition is met.

**STRICT SEQUENTIAL EXECUTION**: Each sub agent MUST complete and return its result before the next sub agent is spawned. Never run multiple sub agents in parallel. Within each loop step, wait for one iteration to finish before starting the next. Between pipeline steps, wait for the entire step to complete before advancing. The pipeline order is non-negotiable:

The pipeline runs these steps in sequence:

1. **homer** — Iterative spec clarification & remediation
2. **plan** — Generate technical implementation plan
3. **tasks** — Generate dependency-ordered task list
4. **lisa** — Cross-artifact consistency analysis
5. **ralph** — Task-by-task implementation with quality gates

## Instructions

### Step 1: Determine the spec directory

- If `$ARGUMENTS` contains a directory path, use it as `FEATURE_DIR`
- If `$ARGUMENTS` contains `--from <step>`, note the starting step (homer, plan, tasks, lisa, ralph)
- Otherwise, auto-detect from the current git branch name (extract the 4-char prefix and find the matching `specs/<prefix>-*` directory)

### Step 2: Validate spec exists

- Confirm that `spec.md` exists in the resolved spec directory
- If not found, inform the user they need to run `/speckit.specify` first

### Step 3: Auto-detect starting step (if `--from` not specified)

Check which artifacts exist to determine where to start:
- `tasks.md` with some `- [x]` complete → start at **ralph**
- `tasks.md` with none complete → start at **lisa**
- `plan.md` exists → start at **tasks**
- `spec.md` exists → start at **homer** (first step)

### Step 4: Configuration

- Homer max iterations: **10**
- Lisa max iterations: **10**
- Ralph max iterations: **incomplete_tasks + 10** (calculated at ralph step)

### Step 5: Execute Pipeline Steps

**CRITICAL**: Execute steps **strictly in sequence** — one at a time. Each Agent tool call MUST return before the next one is spawned. Never use parallel Agent calls. Each loop iteration must complete before the next iteration starts. Each pipeline step must fully complete before advancing to the next step.

For each step (starting from the detected/specified step), spawn fresh sub agents using the **Agent tool**. Each sub agent gets a fresh context window, preventing hallucination drift.

When composing the prompt for each sub agent, always include:
- Instruct the agent to read and follow the corresponding agent file from `.claude/agents/`
- When those instructions reference a slash command (e.g., `/speckit.clarify`), read the corresponding file from `.claude/commands/` and follow its instructions directly
- Provide: `Feature directory: <FEATURE_DIR>`

#### Homer (loop step)
For each iteration (up to homer max), spawn ONE sub agent at a time (wait for it to return before spawning the next):
- **subagent_type**: `general-purpose`
- **agent file**: `.claude/agents/homer.md`

Check output for `<promise>ALL_FINDINGS_RESOLVED</promise>`. Continue looping if not found. Apply stuck detection (3 identical outputs = abort).

**Failure handling**: If a sub agent fails (crash, timeout, or error), abort the pipeline immediately. Log failure context: iteration number, agent type (homer), and error message. Do NOT retry — sub agent failures in loop commands are treated as deterministic. Suggest manual review and resuming with `--from homer`.

#### Plan (single-shot step)
Skip if `plan.md` already exists. Otherwise, spawn a sub agent:
- **subagent_type**: `general-purpose`
- **agent file**: `.claude/agents/plan.md`

**Failure handling**: If the sub agent fails (crash, timeout, or error), abort the pipeline immediately. Log failure context: agent type (plan) and error message. Do NOT retry — sub agent failures in loop commands are treated as deterministic. Suggest manual review and resuming with `--from plan`.

#### Tasks (single-shot step)
Skip if `tasks.md` already exists. Otherwise, spawn a sub agent:
- **subagent_type**: `general-purpose`
- **agent file**: `.claude/agents/tasks.md`

**Failure handling**: If the sub agent fails (crash, timeout, or error), abort the pipeline immediately. Log failure context: agent type (tasks) and error message. Do NOT retry — sub agent failures in loop commands are treated as deterministic. Suggest manual review and resuming with `--from tasks`.

#### Lisa (loop step)
For each iteration (up to lisa max), spawn ONE sub agent at a time (wait for it to return before spawning the next):
- **subagent_type**: `general-purpose`
- **agent file**: `.claude/agents/lisa.md`

Check output for `<promise>ALL_FINDINGS_RESOLVED</promise>`. Continue looping if not found. Apply stuck detection (3 identical outputs = abort).

**Failure handling**: If a sub agent fails (crash, timeout, or error), abort the pipeline immediately. Log failure context: iteration number, agent type (lisa), and error message. Do NOT retry — sub agent failures in loop commands are treated as deterministic. Suggest manual review and resuming with `--from lisa`.

#### Ralph (loop step)

> **IMPORTANT**: Before running Ralph, extract quality gates. The default is a placeholder — update `speckit.ralph.implement.md` or `speckit.pipeline.md` with your project's quality gates.

Quality gates (PLACEHOLDER):
```bash
echo "PLACEHOLDER: Update quality gates before using Ralph." && exit 1
```

For each iteration (up to ralph max), spawn ONE sub agent at a time (wait for it to return before spawning the next):
- **subagent_type**: `general-purpose`
- **agent file**: `.claude/agents/ralph.md`
- **prompt** (additional): Include quality gates: `Quality gates: <QUALITY_GATES>`

Check output for `<promise>ALL_TASKS_COMPLETE</promise>`. Also verify tasks.md directly. Apply stuck detection (3 identical outputs = abort).

**Failure handling**: If a sub agent fails (crash, timeout, or error), abort the pipeline immediately. Log failure context: iteration number, agent type (ralph), and error message. Do NOT retry — sub agent failures in loop commands are treated as deterministic. Suggest manual review and resuming with `--from ralph`.

### Step 6: Report Results

After all steps complete, report:
- Steps executed
- Total iterations per loop step
- Completion status (one of: **success** — all steps completed successfully; **max iterations reached** — a loop step hit its iteration limit; **stuck** — 3 consecutive identical outputs detected in a loop step; **failure** — a sub agent crashed or errored)
- Suggestion to resume with `--from <step>` if not fully resolved

## Examples

- `/speckit.pipeline` — Auto-detect spec dir from current branch, run full pipeline
- `/speckit.pipeline specs/a1b2-feat-user-auth` — Run pipeline for specific spec
- `/speckit.pipeline --from homer` — Start from homer step (auto-detect spec dir)
- `/speckit.pipeline --from ralph specs/a1b2-feat-user-auth` — Resume ralph for specific spec
