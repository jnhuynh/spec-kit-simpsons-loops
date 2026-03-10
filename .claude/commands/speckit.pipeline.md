---
description: Orchestrate the full SpecKit pipeline (specify, homer, plan, tasks, lisa, ralph) from feature description to implementation.
---

## User Input

```text
$ARGUMENTS
```

## Pre-Flight Check

Before doing anything else, verify that the required utility scripts are installed:

1. Check if `.specify/scripts/bash/check-prerequisites.sh` exists (use the Bash tool: `test -f .specify/scripts/bash/check-prerequisites.sh && echo "EXISTS" || echo "MISSING"`)
2. If **MISSING**, display this error and **STOP** — do not proceed with any pipeline execution:

```
ERROR: Required utility script not found.

Missing: .specify/scripts/bash/check-prerequisites.sh

This script is required for feature directory resolution and prerequisite validation.
To install it, run the SpecKit setup command:

  /speckit.setup

Or manually install from the openclaw repository.
```

3. If **EXISTS**, proceed to the agent file check below.

## Agent File Check

Verify that all required agent files exist before starting the pipeline. Check each of these files using the Bash tool:

```bash
for f in specify homer plan tasks lisa ralph; do
  test -f ".claude/agents/${f}.md" && echo "${f}.md: EXISTS" || echo "${f}.md: MISSING"
done
```

If **any** agent file is MISSING, display this error and **STOP** — do not proceed with pipeline execution:

```
ERROR: Required agent file(s) not found.

Missing: .claude/agents/<name>.md

Agent files are required for pipeline sub-agents to execute. These files define
the behavior of each pipeline phase. Ensure all agent files are present:
  .claude/agents/specify.md
  .claude/agents/homer.md
  .claude/agents/plan.md
  .claude/agents/tasks.md
  .claude/agents/lisa.md
  .claude/agents/ralph.md
```

If **all** agent files exist, proceed to the Overview section below.

## Overview

Orchestrate the full SpecKit pipeline directly within this Claude Code session. Each step spawns fresh sub agents (via the Agent tool) with isolated context windows. The pipeline can start from a feature description (using the specify step) or from an existing `spec.md`.

**AUTONOMOUS EXECUTION**: This pipeline runs unattended. Do NOT ask the user for confirmation between iterations or steps. Do NOT pause for permission requests. Execute all steps and iterations back-to-back until the pipeline completes or a failure condition is met.

**STRICT SEQUENTIAL EXECUTION**: Each sub agent MUST complete and return its result before the next sub agent is spawned. Never run multiple sub agents in parallel. Within each loop step, wait for one iteration to finish before starting the next. Between pipeline steps, wait for the entire step to complete before advancing. The pipeline order is non-negotiable:

The pipeline runs these 6 steps in sequence:

0. **specify** — Create feature spec from description (optional, auto-detected)
1. **homer** — Iterative spec clarification & remediation
2. **plan** — Generate technical implementation plan
3. **tasks** — Generate dependency-ordered task list
4. **lisa** — Cross-artifact consistency analysis
5. **ralph** — Task-by-task implementation with quality gates

## Instructions

### Step 1: Parse Arguments and Determine the spec directory

Parse `$ARGUMENTS` for the following (all are optional, can appear in any order):

- **`--from <step>`**: Starting step override. Valid values: `specify`, `homer`, `plan`, `tasks`, `lisa`, `ralph`. If provided, the pipeline starts from this step instead of auto-detecting.
- **`--description <text>`**: Feature description for the specify step. Capture the full text after `--description` (may be quoted).
- **`spec-dir`**: A directory path (e.g., `specs/003-fix-pipeline-delegation`). If provided, use it as `FEATURE_DIR`.

If no `spec-dir` is provided in `$ARGUMENTS`, resolve `FEATURE_DIR` automatically by running `bash .specify/scripts/bash/check-prerequisites.sh --json` from repo root via Bash tool and parsing the JSON output for `feature_dir`. **Error handling**: If the script exits with a non-zero status (e.g., missing feature dir, invalid branch), display the script's stderr/stdout output to the user and **STOP** — do not proceed with pipeline execution.

### Step 2: Validate spec exists or can be created

- If `spec.md` exists in the resolved spec directory, proceed normally
- If `spec.md` does not exist:
  - If `--from specify` is set or `--description` is provided, allow the pipeline to continue (the specify step will create spec.md)
  - Otherwise, exit with an error instructing the user to run `/speckit.specify` first or pass `--description`
- If `--from specify` is set but no `--description` is provided, exit with an error requesting a feature description

### Step 3: Auto-detect starting step (if `--from` not specified)

Check which artifacts exist to determine where to start:
- `tasks.md` with some `- [x]` complete → start at **ralph**
- `tasks.md` with none complete → start at **lisa**
- `plan.md` exists → start at **tasks**
- `spec.md` exists → start at **homer**
- No `spec.md` but `--description` provided → start at **specify**

### Step 4: Configuration

- Homer max iterations: **20**
- Lisa max iterations: **20**
- Ralph max iterations: **incomplete_tasks + 10** (calculated at ralph step)

### Step 5: Execute Pipeline Steps

**CRITICAL**: Execute steps **strictly in sequence** — one at a time. Each Agent tool call MUST return before the next one is spawned. Never use parallel Agent calls. Each loop iteration must complete before the next iteration starts. Each pipeline step must fully complete before advancing to the next step.

For each step (starting from the detected/specified step), spawn fresh sub agents using the **Agent tool**. Each sub agent gets a fresh context window, preventing hallucination drift.

When composing the prompt for each sub agent, always include:
- Instruct the agent to read and follow the corresponding agent file from `.claude/agents/`
- When those instructions reference a slash command (e.g., `/speckit.clarify`), read the corresponding file from `.claude/commands/` and follow its instructions directly
- Provide: `Feature directory: <FEATURE_DIR>`

#### Specify (single-shot step)
Skip if `spec.md` already exists. Otherwise, spawn a sub agent:
- **subagent_type**: `general-purpose`
- **agent file**: `.claude/agents/specify.md`
- **prompt**: `Feature directory: <FEATURE_DIR>. Feature description: <DESCRIPTION>. Run non-interactively: auto-resolve all clarifications with best guesses, do not present questions to the user.`

**Failure handling**: If the sub agent fails (crash, timeout, or error), abort the pipeline immediately. Log failure context: agent type (specify) and error message. Do NOT retry — sub agent failures in loop commands are treated as deterministic. Print: "Specify step failed. Fix the issue and re-invoke with --from specify". Suggest manual review and resuming with `--from specify`.

#### Homer (loop step)
Initialize `consecutive_stuck_count = 0`. For each iteration (up to homer max), spawn ONE sub agent at a time (wait for it to return before spawning the next):

**Before** each sub agent: record `PRE_ITERATION_SHA=$(git rev-parse HEAD)` via Bash tool.

- **subagent_type**: `general-purpose`
- **agent file**: `.claude/agents/homer.md`

**After** each sub agent returns:
1. Check output for `<promise>ALL_FINDINGS_RESOLVED</promise>`. If found, homer is complete — proceed to the next pipeline step.
2. Check `git diff $PRE_ITERATION_SHA --stat` via Bash tool for file changes.
3. **Stuck detection**: If there are NO file changes (empty diff) AND the promise tag was NOT found, increment `consecutive_stuck_count`. If there ARE file changes OR the promise tag was found, reset `consecutive_stuck_count = 0`.
4. If `consecutive_stuck_count >= 2`, abort the homer loop — report "stuck: 2 consecutive iterations with no file changes and no completion signal".
5. Otherwise, continue to the next iteration.

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
Initialize `consecutive_stuck_count = 0`. For each iteration (up to lisa max), spawn ONE sub agent at a time (wait for it to return before spawning the next):

**Before** each sub agent: record `PRE_ITERATION_SHA=$(git rev-parse HEAD)` via Bash tool.

- **subagent_type**: `general-purpose`
- **agent file**: `.claude/agents/lisa.md`

**After** each sub agent returns:
1. Check output for `<promise>ALL_FINDINGS_RESOLVED</promise>`. If found, lisa is complete — proceed to the next pipeline step.
2. Check `git diff $PRE_ITERATION_SHA --stat` via Bash tool for file changes.
3. **Stuck detection**: If there are NO file changes (empty diff) AND the promise tag was NOT found, increment `consecutive_stuck_count`. If there ARE file changes OR the promise tag was found, reset `consecutive_stuck_count = 0`.
4. If `consecutive_stuck_count >= 2`, abort the lisa loop — report "stuck: 2 consecutive iterations with no file changes and no completion signal".
5. Otherwise, continue to the next iteration.

**Failure handling**: If a sub agent fails (crash, timeout, or error), abort the pipeline immediately. Log failure context: iteration number, agent type (lisa), and error message. Do NOT retry — sub agent failures in loop commands are treated as deterministic. Suggest manual review and resuming with `--from lisa`.

#### Ralph (loop step)

> **IMPORTANT**: Before running Ralph, resolve quality gates. Quality gates are read from `.specify/quality-gates.sh` in the project root. Edit that file with your project's quality gate commands (e.g., `npm test && npm run lint`). The file must exit 0 for quality gates to pass. CLI arguments (`--quality-gates`) and environment variables (`QUALITY_GATES`) override the file when provided.

Quality gates:
```bash
# SPECKIT_DEFAULT_QUALITY_GATE
bash .specify/quality-gates.sh
```

Initialize `consecutive_stuck_count = 0`. For each iteration (up to ralph max), spawn ONE sub agent at a time (wait for it to return before spawning the next):

**Before** each sub agent: record `PRE_ITERATION_SHA=$(git rev-parse HEAD)` via Bash tool.

- **subagent_type**: `general-purpose`
- **agent file**: `.claude/agents/ralph.md`
- **prompt** (additional): Include quality gates: `Quality gates: <QUALITY_GATES>`

**After** each sub agent returns:
1. Check output for `<promise>ALL_TASKS_COMPLETE</promise>`. Also verify tasks.md directly (check if any `- [ ]` tasks remain). If all tasks are complete, ralph is done — proceed to reporting.
2. Check `git diff $PRE_ITERATION_SHA --stat` via Bash tool for file changes.
3. **Stuck detection**: If there are NO file changes (empty diff) AND the promise tag was NOT found, increment `consecutive_stuck_count`. If there ARE file changes OR the promise tag was found, reset `consecutive_stuck_count = 0`.
4. If `consecutive_stuck_count >= 2`, abort the ralph loop — report "stuck: 2 consecutive iterations with no file changes and no completion signal".
5. Otherwise, continue to the next iteration.

**Failure handling**: If a sub agent fails (crash, timeout, or error), abort the pipeline immediately. Log failure context: iteration number, agent type (ralph), and error message. Do NOT retry — sub agent failures in loop commands are treated as deterministic. Suggest manual review and resuming with `--from ralph`.

### Step 6: Report Results

After all steps complete, report:
- Steps executed
- Total iterations per loop step
- Completion status (one of: **success** — all steps completed successfully; **max iterations reached** — a loop step hit its iteration limit; **stuck** — 2 consecutive iterations with no file changes and no completion signal; **failure** — a sub agent crashed or errored)
- Suggestion to resume with `--from <step>` if not fully resolved

## Examples

- `/speckit.pipeline` — Auto-detect spec dir from current branch, run full pipeline
- `/speckit.pipeline specs/a1b2-feat-user-auth` — Run pipeline for specific spec
- `/speckit.pipeline --from homer` — Start from homer step (auto-detect spec dir)
- `/speckit.pipeline --from ralph specs/a1b2-feat-user-auth` — Resume ralph for specific spec
- `/speckit.pipeline --description "Add user auth" specs/a1b2-feat-user-auth` — End-to-end from description
- `/speckit.pipeline --from specify --description "Add user auth"` — Explicit specify step start
