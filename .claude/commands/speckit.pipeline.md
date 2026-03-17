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

Orchestrate the full SpecKit pipeline directly within this session. Each step spawns fresh sub agents (via the Agent tool) with isolated context windows. The pipeline can start from a feature description (using the specify step) or from an existing `spec.md`.

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
- **`--stop-after <step>`**: Stop-after step. Valid values: `specify`, `homer`, `plan`, `tasks`, `lisa`, `ralph`. If provided, the pipeline halts after the specified step completes, skipping all subsequent steps. Store the value in `STOP_AFTER_STEP`. If `--stop-after` is NOT provided, `STOP_AFTER_STEP` MUST remain empty/unset so that all stop checks are no-ops and the pipeline runs all steps from the starting step through ralph — identical to the behavior before `--stop-after` was added (FR-007). If `--stop-after` is present but no step name follows (e.g., it is the last argument or the next token is another flag), display an error: "Error: --stop-after requires a step name. Valid steps: specify, homer, plan, tasks, lisa, ralph." and **STOP**.
- **`--description <text>`**: Feature description for the specify step. Capture the full text after `--description` (may be quoted).
- **`spec-dir`**: A directory path (e.g., `specs/003-fix-pipeline-delegation`). If provided, use it as `FEATURE_DIR`.

If no `spec-dir` is provided in `$ARGUMENTS`, resolve `FEATURE_DIR` automatically:

1. **Determine if on a feature branch**: Run `git rev-parse --abbrev-ref HEAD` via Bash tool. If the branch matches the pattern `^[0-9]{3}-` (e.g., `004-fix-prereq-bootstrap`), it is a feature branch.

2. **Feature branch resolution**: Run `bash .specify/scripts/bash/check-prerequisites.sh --json --paths-only` from repo root via Bash tool. This resolves paths without validating artifact existence. Parse the JSON output for `FEATURE_DIR`.

3. **Non-feature branch (e.g., `main`, `HEAD`) with bootstrapping**: If on a non-feature branch and `--from specify` is set or `--description` is provided, skip `check-prerequisites.sh` entirely (it would reject the non-feature branch). Proceed with an empty/unresolved `FEATURE_DIR` — the specify step will create the feature branch and directory.

4. **Non-feature branch without bootstrapping**: If on a non-feature branch and neither `--from specify` nor `--description` is provided, display an error: "Cannot auto-detect feature directory from branch 'main'. Pass a spec-dir argument or use --from specify --description." and **STOP**.

5. **Error handling for feature branch resolution**: If `check-prerequisites.sh` exits with a non-zero status but `--from specify` is set or `--description` is provided, treat the failure as non-fatal — proceed with `FEATURE_DIR` set to `specs/<branch-name>` (a prospective path). If neither `--from specify` nor `--description` is set, display the script's stderr/stdout output and **STOP**.

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

### Step 3b: Step Index Mapping

Assign a numeric index to each pipeline step for use in validation and execution plan computation:

| Step | Index |
|------|-------|
| specify | 0 |
| homer | 1 |
| plan | 2 |
| tasks | 3 |
| lisa | 4 |
| ralph | 5 |

Resolve the index for the starting step (from `--from` or auto-detected) into `start_index`. If `STOP_AFTER_STEP` is set, resolve its index into `stop_after_index`. These indices are used in subsequent validation and execution plan steps.

### Step 3c: Validate --stop-after

If `STOP_AFTER_STEP` is set, perform the following validations **before any pipeline steps execute**:

1. **Value validation (FR-006)**: Verify that `STOP_AFTER_STEP` is one of the six valid step names: `specify`, `homer`, `plan`, `tasks`, `lisa`, `ralph`. If the value is not in this list, display the following error and **STOP** — do not execute any pipeline steps:

```
Invalid --stop-after value '<value>'. Valid steps: specify, homer, plan, tasks, lisa, ralph.
```

(Replace `<value>` with the actual invalid value the user provided.)

2. **Range validation (FR-005)**: If `STOP_AFTER_STEP` is set and its `stop_after_index` is less than the `start_index` (the starting step, whether set via `--from` or auto-detected), display the following error and **STOP** — do not execute any pipeline steps:

```
Invalid range: --stop-after '<stop>' comes before starting step '<start>' in the pipeline sequence (specify -> homer -> plan -> tasks -> lisa -> ralph).
```

(Replace `<stop>` with the actual `STOP_AFTER_STEP` value and `<start>` with the actual starting step name.)

### Step 4: Configuration

- Homer max iterations: **30**
- Lisa max iterations: **30**
- Ralph max iterations: **incomplete_tasks + 10** (count `- [ ]` lines in tasks.md at the start of the ralph step, then add 10)

### Step 4b: Execution Plan Announcement

Before executing any steps, output an execution plan announcement listing the steps that will run. Build the list of planned steps from the starting step through either the `STOP_AFTER_STEP` (if set) or `ralph` (if not set), using the step index mapping from Step 3b.

**Format**:

- **When `--stop-after` is provided**: `Execution plan: specify -> homer -> plan. Stopping after: plan.`
- **When `--stop-after` is NOT provided**: `Execution plan: homer -> plan -> tasks -> lisa -> ralph.`

The step names in the plan are joined with ` -> `. Only include steps from the starting step through the stop step (inclusive). When `--stop-after` is provided, append ` Stopping after: <step>.` to the announcement. When `--stop-after` is not provided, omit the "Stopping after" clause entirely.

### Step 5: Execute Pipeline Steps

**CRITICAL**: Execute steps **strictly in sequence** — one at a time. Each Agent tool call MUST return before the next one is spawned. Never use parallel Agent calls. Each loop iteration must complete before the next iteration starts. Each pipeline step must fully complete before advancing to the next step.

**POST-STEP STOP CHECK**: After each step completes (whether it was executed or skipped because its artifact already existed), if `STOP_AFTER_STEP` is set and equals the current step name, output the stop message and **skip all remaining steps** — do NOT spawn any further sub-agents. Proceed directly to Step 6 (Report Results). Each step section below includes the specific stop check with the exact message to output.

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

**Post-specify re-resolution**: After the specify step completes successfully, if `FEATURE_DIR` is empty or the directory does not exist, re-resolve by running `bash .specify/scripts/bash/check-prerequisites.sh --json --paths-only` from repo root via Bash tool and parsing the JSON output for `FEATURE_DIR`. This is required because the specify step (via `create-new-feature.sh`) creates the feature branch and directory. If re-resolution fails, abort the pipeline with: "Specify step completed but feature directory could not be resolved." The re-resolved `FEATURE_DIR` MUST be used for all subsequent steps.

**Post-step stop check**: After the specify step completes (whether it was executed or skipped because `spec.md` already exists), check if `STOP_AFTER_STEP` is set and equals `specify`. If it does, output: `Pipeline stopped after specify per --stop-after parameter. Skipping: homer, plan, tasks, lisa, ralph.` and **skip all remaining steps** — do NOT spawn any further sub-agents. Proceed directly to Step 6 (Report Results). If `STOP_AFTER_STEP` is empty/unset, this check is a no-op — continue to the next step.

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

**Post-step stop check**: After the homer step completes, check if `STOP_AFTER_STEP` is set and equals `homer`. If it does, output: `Pipeline stopped after homer per --stop-after parameter. Skipping: plan, tasks, lisa, ralph.` and **skip all remaining steps** — do NOT spawn any further sub-agents. Proceed directly to Step 6 (Report Results). If `STOP_AFTER_STEP` is empty/unset, this check is a no-op — continue to the next step.

#### Plan (single-shot step)
Skip if `plan.md` already exists. Otherwise, spawn a sub agent:
- **subagent_type**: `general-purpose`
- **agent file**: `.claude/agents/plan.md`

**Failure handling**: If the sub agent fails (crash, timeout, or error), abort the pipeline immediately. Log failure context: agent type (plan) and error message. Do NOT retry — sub agent failures in loop commands are treated as deterministic. Suggest manual review and resuming with `--from plan`.

**Post-step stop check**: After the plan step completes (whether it was executed or skipped because `plan.md` already exists), check if `STOP_AFTER_STEP` is set and equals `plan`. If it does, output: `Pipeline stopped after plan per --stop-after parameter. Skipping: tasks, lisa, ralph.` and **skip all remaining steps** — do NOT spawn any further sub-agents. Proceed directly to Step 6 (Report Results). If `STOP_AFTER_STEP` is empty/unset, this check is a no-op — continue to the next step.

#### Tasks (single-shot step)
Skip if `tasks.md` already exists. Otherwise, spawn a sub agent:
- **subagent_type**: `general-purpose`
- **agent file**: `.claude/agents/tasks.md`

**Failure handling**: If the sub agent fails (crash, timeout, or error), abort the pipeline immediately. Log failure context: agent type (tasks) and error message. Do NOT retry — sub agent failures in loop commands are treated as deterministic. Suggest manual review and resuming with `--from tasks`.

**Post-step stop check**: After the tasks step completes (whether it was executed or skipped because `tasks.md` already exists), check if `STOP_AFTER_STEP` is set and equals `tasks`. If it does, output: `Pipeline stopped after tasks per --stop-after parameter. Skipping: lisa, ralph.` and **skip all remaining steps** — do NOT spawn any further sub-agents. Proceed directly to Step 6 (Report Results). If `STOP_AFTER_STEP` is empty/unset, this check is a no-op — continue to the next step.

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

**Post-step stop check**: After the lisa step completes, check if `STOP_AFTER_STEP` is set and equals `lisa`. If it does, output: `Pipeline stopped after lisa per --stop-after parameter. Skipping: ralph.` and **skip all remaining steps** — do NOT spawn any further sub-agents. Proceed directly to Step 6 (Report Results). If `STOP_AFTER_STEP` is empty/unset, this check is a no-op — continue to the next step.

#### Ralph (loop step)

**Quality gate validation**: Before starting the ralph loop, validate that `.specify/quality-gates.sh` exists and contains executable content. Run the following via Bash tool:

```bash
test -f .specify/quality-gates.sh && grep -v '^\s*#' .specify/quality-gates.sh | grep -v '^\s*$' | head -1
```

If the file does not exist or contains only comments/whitespace (the command above produces no output), **STOP** the pipeline with this error:

```
ERROR: Quality gates file is missing or empty.

Expected: .specify/quality-gates.sh with executable commands.

Create the file with your project's quality gate commands, e.g.:
  echo 'npm test && npm run lint' > .specify/quality-gates.sh

The ralph phase requires quality gates to validate implementation work.
```

**Calculate ralph max iterations**: Count incomplete tasks in tasks.md and add 10:

```bash
incomplete_count=$(grep -c '^\s*- \[ \]' "<FEATURE_DIR>/tasks.md" 2>/dev/null || echo "0")
echo $((incomplete_count + 10))
```

Use the resulting number as `ralph_max_iterations`.

Initialize `consecutive_stuck_count = 0`. For each iteration (up to ralph max), spawn ONE sub agent at a time (wait for it to return before spawning the next):

**Before** each sub agent: record `PRE_ITERATION_SHA=$(git rev-parse HEAD)` via Bash tool.

- **subagent_type**: `general-purpose`
- **agent file**: `.claude/agents/ralph.md`
- **prompt** (additional): Include quality gates: `Quality gates: bash .specify/quality-gates.sh`

**After** each sub agent returns:
1. Check output for `<promise>ALL_TASKS_COMPLETE</promise>`. Also verify tasks.md directly (check if any `- [ ]` tasks remain). If all tasks are complete, ralph is done — proceed to reporting.
2. Check `git diff $PRE_ITERATION_SHA --stat` via Bash tool for file changes.
3. **Stuck detection**: If there are NO file changes (empty diff) AND the promise tag was NOT found, increment `consecutive_stuck_count`. If there ARE file changes OR the promise tag was found, reset `consecutive_stuck_count = 0`.
4. If `consecutive_stuck_count >= 2`, abort the ralph loop — report "stuck: 2 consecutive iterations with no file changes and no completion signal".
5. Otherwise, continue to the next iteration.

**Failure handling**: If a sub agent fails (crash, timeout, or error), abort the pipeline immediately. Log failure context: iteration number, agent type (ralph), and error message. Do NOT retry — sub agent failures in loop commands are treated as deterministic. Suggest manual review and resuming with `--from ralph`.

### Step 6: Report Results

After all steps complete (or after a `--stop-after` early termination), produce a completion report that includes the following sections:

#### 6a: Per-Step Status Table

List **all six pipeline steps** in order, each with a status. Determine the status for each step as follows:

- **`executed`**: The step ran during this pipeline invocation (either a sub-agent was spawned or, for loop steps, iterations were performed).
- **`skipped`**: The step was NOT executed. This applies when:
  - The step falls before the `--from` starting step (outside the execution range), OR
  - The step's artifact already existed so the step was skipped (e.g., `spec.md` already existed so specify was skipped, `plan.md` already existed so plan was skipped).
- **`stopped-by-param`**: The step was NOT executed because it falls after the `STOP_AFTER_STEP`. This status applies to all steps whose index is greater than the `stop_after_index`. When `--stop-after` is not provided, no step receives this status.

**Format** — output a table like:

```
Pipeline Step Status:
  specify .... executed
  homer ..... executed
  plan ...... executed
  tasks ..... stopped-by-param
  lisa ...... stopped-by-param
  ralph ..... stopped-by-param
```

When the pipeline was stopped early by `--stop-after`, add a line after the table: `Last executed step: <step>` indicating which step was the final one to complete (whether it was actually executed or skipped-because-artifact-existed).

#### 6b: Iteration Counts

For loop steps (homer, lisa, ralph) that were executed, report the total number of iterations run.

#### 6c: Completion Status

Report one of:
- **success** — all steps in the execution range completed successfully
- **max iterations reached** — a loop step hit its iteration limit
- **stuck** — 2 consecutive iterations with no file changes and no completion signal
- **failure** — a sub agent crashed or errored
- **stopped** — the pipeline was stopped early by `--stop-after` (use this when the pipeline halted before ralph due to the `--stop-after` parameter; all steps in the execution range completed successfully but the full pipeline did not run)

#### 6d: Resume Suggestion

If the pipeline did not complete all six steps (whether due to `--stop-after`, failure, stuck, or max iterations), suggest resuming with `--from <next-step>` where `<next-step>` is the first step that was not executed. For `--stop-after` early termination, suggest: "To continue the pipeline, run with `--from <next-step>`." where `<next-step>` is the step immediately after `STOP_AFTER_STEP`.

## Examples

- `/speckit.pipeline` — Auto-detect spec dir from current branch, run full pipeline
- `/speckit.pipeline specs/a1b2-feat-user-auth` — Run pipeline for specific spec
- `/speckit.pipeline --from homer` — Start from homer step (auto-detect spec dir)
- `/speckit.pipeline --from ralph specs/a1b2-feat-user-auth` — Resume ralph for specific spec
- `/speckit.pipeline --description "Add user auth" specs/a1b2-feat-user-auth` — End-to-end from description
- `/speckit.pipeline --from specify --description "Add user auth"` — Explicit specify step start
- `/speckit.pipeline --stop-after plan` — Run through plan step only
- `/speckit.pipeline --from homer --stop-after tasks` — Run homer through tasks
- `/speckit.pipeline --stop-after homer --from specify --description "Add feature X"` — Specify and homer only
