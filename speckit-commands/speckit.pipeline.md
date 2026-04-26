---
description: Orchestrate the full SpecKit pipeline (specify, homer, plan, tasks, lisa, ralph, marge) from feature description to reviewed implementation.
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
for f in specify homer plan tasks lisa ralph marge; do
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
  .claude/agents/marge.md
```

If **all** agent files exist, proceed to the Flavor Configuration Gate below.

## Flavor Configuration Gate

Per FR-019, FR-025, and plan.md D-008, the phaser stage and per-phase marge invocations are gated entirely on the presence of `.specify/flavor.yaml` at the repository root. Detect the gate state once, immediately after pre-flight, and reuse it throughout the pipeline.

Run the following via the Bash tool (per quickstart.md "Pattern: Conditional Pipeline Behavior"):

```bash
if test -f .specify/flavor.yaml; then echo "FLAVOR_PRESENT"; else echo "FLAVOR_ABSENT"; fi
```

Capture the result into a pipeline-scoped variable `FLAVOR_GATE`:

- `FLAVOR_GATE = present` when the file exists.
- `FLAVOR_GATE = absent` when the file does not exist.

The gate's effects are:

- **`FLAVOR_GATE = present`**: After the polish phases (simplify, security-review) complete, the pipeline runs the phaser step and then invokes marge `N+1` times per FR-023 (once per phase with `--phase N` against the resolved phase manifest, then once holistically). After marge succeeds across all phases (per-phase passes plus the holistic pass), the pipeline runs the stacked-PR creation step (`phaser/bin/phaser-stacked-prs`) per FR-026..FR-030, FR-039, FR-040, FR-044..FR-047. If the phaser step fails, the pipeline MUST halt without invoking marge per FR-024 (and therefore without invoking the stacked-PR creator either). If marge fails, the stacked-PR creator does not run.
- **`FLAVOR_GATE = absent`**: The phaser step is skipped entirely, the stacked-PR creation step is skipped entirely, marge runs once holistically as a single pass, and the pipeline behaves byte-identically to the pre-feature pipeline per FR-025 and SC-006. This is the default for projects that have not opted into phasing.

Additionally, the agent file check above is augmented when `FLAVOR_GATE = present`: also verify `.claude/agents/phaser.md` exists. If MISSING when the flavor gate is present, display the standard "Required agent file(s) not found" error naming `phaser.md` and **STOP**. When `FLAVOR_GATE = absent`, the absence of `phaser.md` is not an error (the phaser step will be skipped anyway).

Proceed to the Overview section below.

## Overview

Orchestrate the full SpecKit pipeline directly within this session. Each step spawns fresh sub agents (via the Agent tool) with isolated context windows. The pipeline can start from a feature description (using the specify step) or from an existing `spec.md`.

**AUTONOMOUS EXECUTION**: This pipeline runs unattended. Do NOT ask the user for confirmation between iterations or steps. Do NOT pause for permission requests. Execute all steps and iterations back-to-back until the pipeline completes or a failure condition is met.

**STRICT SEQUENTIAL EXECUTION**: Each sub agent MUST complete and return its result before the next sub agent is spawned. Never run multiple sub agents in parallel. Within each loop step, wait for one iteration to finish before starting the next. Between pipeline steps, wait for the entire step to complete before advancing. The pipeline order is non-negotiable:

The pipeline runs these 7 steps in sequence:

0. **specify** — Create feature spec from description (optional, auto-detected)
1. **homer** — Iterative spec clarification & remediation
2. **plan** — Generate technical implementation plan
3. **tasks** — Generate dependency-ordered task list
4. **lisa** — Cross-artifact consistency analysis
5. **ralph** — Task-by-task implementation with quality gates
6. **marge** — Iterative code review of the implementation

Between ralph and marge, two **optional polish phases** run automatically **if and only if the corresponding skill is installed** in the environment:

- **simplify** — invokes the `/simplify` skill for reuse/quality/efficiency fixes
- **security-review** — invokes the `/security-review` skill for a security audit

If either skill is absent, that phase is silently skipped. These phases are **not** part of the `--from` / `--stop-after` step mapping; they always run between ralph and marge when present, and are skipped when `--stop-after ralph` halts the pipeline.

After the polish phases and **before marge**, when `FLAVOR_GATE = present` (per the Flavor Configuration Gate section above), an additional **phaser** step runs:

- **phaser** — invokes the `/speckit.phaser` command via the phaser sub agent to classify the feature branch's commits, validate them against the active flavor's rules, and write `phase-manifest.yaml` to the feature directory.

The phaser step is positioned **after** simplify/security-review per plan.md D-008 so that any commits created by those polish phases are classified into the manifest rather than left unclassified on the branch. When `FLAVOR_GATE = absent`, the phaser step is skipped entirely (FR-025). Like simplify and security-review, the phaser step is **not** part of the `--from` / `--stop-after` step mapping; it runs implicitly between security-review and marge when its gate is met. When `--stop-after ralph` halts the pipeline, the phaser step does not run.

When `FLAVOR_GATE = present`, the marge step also gains phase-aware behavior: marge is invoked `N+1` times per FR-023 — once per phase listed in the manifest (with `--phase N` scoping each pass to that phase's diff range per FR-022) and then once more holistically across the whole feature. The holistic pass MUST run after every per-phase pass completes. When `FLAVOR_GATE = absent`, marge runs once holistically (a single pass, identical to the pre-feature pipeline).

After the marge step finishes successfully, when `FLAVOR_GATE = present`, an additional **stacked-PR creation** step runs:

- **stacked-pr-creation** — invokes `phaser/bin/phaser-stacked-prs --feature-dir <FEATURE_DIR>` to create one stacked branch and one pull request per phase listed in `<FEATURE_DIR>/phase-manifest.yaml` (FR-026..FR-030). Authentication is delegated entirely to the operator-configured `gh` CLI (FR-044, FR-045). Failures partway through are recoverable via idempotent re-runs (FR-039, FR-040). No log line or status-file field may contain credential material (FR-047, SC-013).

The stacked-PR creation step is gated on the same `.specify/flavor.yaml` check as the phaser step. When `FLAVOR_GATE = absent`, it is skipped entirely. Like simplify, security-review, and phaser, it is **not** part of the `--from` / `--stop-after` step mapping; it runs implicitly after the marge step completes when its gate is met. When `--stop-after ralph` or `--stop-after marge` halts the pipeline, the stacked-PR creation step does not run.

## Instructions

### Step 1: Parse Arguments and Determine the spec directory

Parse `$ARGUMENTS` for the following (all are optional, can appear in any order):

- **`--from <step>`**: Starting step override. Valid values: `specify`, `homer`, `plan`, `tasks`, `lisa`, `ralph`, `marge`. If provided, the pipeline starts from this step instead of auto-detecting.
- **`--stop-after <step>`**: Stop-after step. Valid values: `specify`, `homer`, `plan`, `tasks`, `lisa`, `ralph`, `marge`. If provided, the pipeline halts after the specified step completes, skipping all subsequent steps. Store the value in `STOP_AFTER_STEP`. If `--stop-after` is NOT provided, `STOP_AFTER_STEP` MUST remain empty/unset so that all stop checks are no-ops and the pipeline runs all steps from the starting step through marge — identical to the behavior before `--stop-after` was added (FR-007). If `--stop-after` is present but no step name follows (e.g., it is the last argument or the next token is another flag), display an error: "Error: --stop-after requires a step name. Valid steps: specify, homer, plan, tasks, lisa, ralph, marge." and **STOP**.
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
- `tasks.md` with all `- [x]` complete (no `- [ ]` lines remaining) → start at **marge**
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
| marge | 6 |

Resolve the index for the starting step (from `--from` or auto-detected) into `start_index`. If `STOP_AFTER_STEP` is set, resolve its index into `stop_after_index`. These indices are used in subsequent validation and execution plan steps.

### Step 3c: Validate --stop-after

If `STOP_AFTER_STEP` is set, perform the following validations **before any pipeline steps execute**:

1. **Value validation (FR-006)**: Verify that `STOP_AFTER_STEP` is one of the seven valid step names: `specify`, `homer`, `plan`, `tasks`, `lisa`, `ralph`, `marge`. If the value is not in this list, display the following error and **STOP** — do not execute any pipeline steps:

```
Invalid --stop-after value '<value>'. Valid steps: specify, homer, plan, tasks, lisa, ralph, marge.
```

(Replace `<value>` with the actual invalid value the user provided.)

2. **Range validation (FR-005)**: If `STOP_AFTER_STEP` is set and its `stop_after_index` is less than the `start_index` (the starting step, whether set via `--from` or auto-detected), display the following error and **STOP** — do not execute any pipeline steps:

```
Invalid range: --stop-after '<stop>' comes before starting step '<start>' in the pipeline sequence (specify -> homer -> plan -> tasks -> lisa -> ralph -> marge).
```

(Replace `<stop>` with the actual `STOP_AFTER_STEP` value and `<start>` with the actual starting step name.)

### Step 4: Configuration

- Homer max iterations: **30**
- Lisa max iterations: **30**
- Ralph max iterations: **incomplete_tasks + 10** (count `- [ ]` lines in tasks.md at the start of the ralph step, then add 10)
- Marge max iterations: **30**

### Step 4b: Execution Plan Announcement

Before executing any steps, output an execution plan announcement listing the steps that will run. Build the list of planned steps from the starting step through either the `STOP_AFTER_STEP` (if set) or `ralph` (if not set), using the step index mapping from Step 3b.

**Format**:

- **When `--stop-after` is provided**: `Execution plan: specify -> homer -> plan. Stopping after: plan.`
- **When `--stop-after` is NOT provided**: `Execution plan: homer -> plan -> tasks -> lisa -> ralph -> marge.`

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

**Post-step stop check**: After the specify step completes (whether it was executed or skipped because `spec.md` already exists), check if `STOP_AFTER_STEP` is set and equals `specify`. If it does, output: `Pipeline stopped after specify per --stop-after parameter. Skipping: homer, plan, tasks, lisa, ralph, marge.` and **skip all remaining steps** — do NOT spawn any further sub-agents. Proceed directly to Step 6 (Report Results). If `STOP_AFTER_STEP` is empty/unset, this check is a no-op — continue to the next step.

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

**Post-step stop check**: After the homer step completes, check if `STOP_AFTER_STEP` is set and equals `homer`. If it does, output: `Pipeline stopped after homer per --stop-after parameter. Skipping: plan, tasks, lisa, ralph, marge.` and **skip all remaining steps** — do NOT spawn any further sub-agents. Proceed directly to Step 6 (Report Results). If `STOP_AFTER_STEP` is empty/unset, this check is a no-op — continue to the next step.

#### Plan (single-shot step)
Skip if `plan.md` already exists. Otherwise, spawn a sub agent:
- **subagent_type**: `general-purpose`
- **agent file**: `.claude/agents/plan.md`

**Failure handling**: If the sub agent fails (crash, timeout, or error), abort the pipeline immediately. Log failure context: agent type (plan) and error message. Do NOT retry — sub agent failures in loop commands are treated as deterministic. Suggest manual review and resuming with `--from plan`.

**Post-step stop check**: After the plan step completes (whether it was executed or skipped because `plan.md` already exists), check if `STOP_AFTER_STEP` is set and equals `plan`. If it does, output: `Pipeline stopped after plan per --stop-after parameter. Skipping: tasks, lisa, ralph, marge.` and **skip all remaining steps** — do NOT spawn any further sub-agents. Proceed directly to Step 6 (Report Results). If `STOP_AFTER_STEP` is empty/unset, this check is a no-op — continue to the next step.

#### Tasks (single-shot step)
Skip if `tasks.md` already exists. Otherwise, spawn a sub agent:
- **subagent_type**: `general-purpose`
- **agent file**: `.claude/agents/tasks.md`

**Failure handling**: If the sub agent fails (crash, timeout, or error), abort the pipeline immediately. Log failure context: agent type (tasks) and error message. Do NOT retry — sub agent failures in loop commands are treated as deterministic. Suggest manual review and resuming with `--from tasks`.

**Post-step stop check**: After the tasks step completes (whether it was executed or skipped because `tasks.md` already exists), check if `STOP_AFTER_STEP` is set and equals `tasks`. If it does, output: `Pipeline stopped after tasks per --stop-after parameter. Skipping: lisa, ralph, marge.` and **skip all remaining steps** — do NOT spawn any further sub-agents. Proceed directly to Step 6 (Report Results). If `STOP_AFTER_STEP` is empty/unset, this check is a no-op — continue to the next step.

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

**Post-step stop check**: After the lisa step completes, check if `STOP_AFTER_STEP` is set and equals `lisa`. If it does, output: `Pipeline stopped after lisa per --stop-after parameter. Skipping: ralph, marge.` and **skip all remaining steps** — do NOT spawn any further sub-agents. Proceed directly to Step 6 (Report Results). If `STOP_AFTER_STEP` is empty/unset, this check is a no-op — continue to the next step.

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

**Post-step stop check**: After the ralph step completes, check if `STOP_AFTER_STEP` is set and equals `ralph`. If it does, output: `Pipeline stopped after ralph per --stop-after parameter. Skipping: marge.` and **skip all remaining steps** — do NOT spawn any further sub-agents. Proceed directly to Step 6 (Report Results). If `STOP_AFTER_STEP` is empty/unset, this check is a no-op — continue to the next step.

#### Simplify (optional single-shot step — skip if skill absent)

Detect whether the `/simplify` skill is installed. Run via Bash tool:

```bash
if test -d "$HOME/.claude/skills/simplify" || test -f "$HOME/.claude/commands/simplify.md" || test -f ".claude/commands/simplify.md"; then echo "PRESENT"; else echo "ABSENT"; fi
```

If **ABSENT**, log `simplify skill not installed — skipping post-ralph simplify pass` and proceed to the security-review phase. Do NOT spawn a sub agent.

If **PRESENT**, spawn a sub agent:

- **subagent_type**: `general-purpose`
- **prompt**: `Invoke the /simplify skill via the Skill tool. It will review the current diff for reuse, quality, and efficiency issues and apply fixes. When it finishes, stage and commit any resulting changes with: git add -A && type=$(git branch --show-current | cut -f 2 -d '-') && scope=$(git branch --show-current | cut -f 3- -d '-') && ticket=$(git branch --show-current | cut -f 1 -d '-') && git commit -m "chore($scope): [$ticket] post-ralph simplify pass". If the skill made no changes, exit without committing. Report "no changes" or a one-line summary of what was fixed.`

**Failure handling**: If the sub agent fails (crash, timeout, or error), log `simplify phase failed — continuing pipeline` and proceed to security-review. Do NOT abort — simplify is optional polish.

This phase is not an independent step in the `--stop-after` mapping; it runs implicitly between ralph and marge when its skill is present.

#### Security Review (optional single-shot step — skip if skill absent)

Detect whether the `/security-review` skill is installed. Run via Bash tool:

```bash
if test -d "$HOME/.claude/skills/security-review" || test -f "$HOME/.claude/commands/security-review.md" || test -f ".claude/commands/security-review.md"; then echo "PRESENT"; else echo "ABSENT"; fi
```

If **ABSENT**, log `security-review skill not installed — skipping pre-marge security pass` and proceed to marge. Do NOT spawn a sub agent.

If **PRESENT**, spawn a sub agent:

- **subagent_type**: `general-purpose`
- **prompt**: `Invoke the /security-review skill via the Skill tool. It will perform a security review of the pending changes on the current branch. Apply any straightforward fixes it recommends. When finished, stage and commit any resulting changes with: git add -A && type=$(git branch --show-current | cut -f 2 -d '-') && scope=$(git branch --show-current | cut -f 3- -d '-') && ticket=$(git branch --show-current | cut -f 1 -d '-') && git commit -m "chore($scope): [$ticket] pre-marge security review pass". If no changes were needed, exit without committing. Report "no changes" or a one-line summary of what was fixed; any residual findings will be picked up by marge.`

**Failure handling**: If the sub agent fails (crash, timeout, or error), log `security-review phase failed — continuing pipeline` and proceed to marge. Do NOT abort — security-review is optional polish.

This phase is not an independent step in the `--stop-after` mapping; it runs implicitly between ralph and marge when its skill is present.

#### Phaser (conditional single-shot step — skip when flavor gate is absent)

This step is gated entirely on `FLAVOR_GATE` (resolved in the Flavor Configuration Gate section). Per FR-019, FR-024, FR-025, and plan.md D-008, the phaser stage runs **after** the simplify and security-review polish phases and **before** marge.

If `FLAVOR_GATE = absent`, log `no .specify/flavor.yaml found — skipping phaser step (FR-025)` and proceed directly to marge. Initialize `PHASE_COUNT = 0` so that the marge step runs as a single holistic pass (per FR-025). Do NOT spawn a sub agent.

If `FLAVOR_GATE = present`, spawn a sub agent:

- **subagent_type**: `general-purpose`
- **prompt**: Compose a prompt containing:
  - Instruct the agent to read and follow `.claude/agents/phaser.md`
  - When those instructions reference a slash command (e.g., `/speckit.phaser`), read the corresponding file from `.claude/commands/` and follow its instructions directly
  - Provide: `Feature directory: <FEATURE_DIR>`

The phaser agent is single-shot per its own guardrails (`.claude/agents/phaser.md`). Do **NOT** loop. Wait for the sub agent to return before continuing.

**After the sub agent returns**, determine success vs. failure:

1. **Success**: The sub agent returns and the file `<FEATURE_DIR>/phase-manifest.yaml` exists. Verify via Bash tool:

   ```bash
   test -f "<FEATURE_DIR>/phase-manifest.yaml" && echo "MANIFEST_PRESENT" || echo "MANIFEST_MISSING"
   ```

   Read the manifest's `phases` list and count its entries into `PHASE_COUNT` (used by the marge step below to determine the per-phase invocation count). Per FR-023, the marge step will then invoke marge `PHASE_COUNT + 1` times.

2. **Failure**: The sub agent reports a non-zero phaser exit OR `<FEATURE_DIR>/phase-manifest.yaml` does not exist after the sub agent returns. Per FR-024, the pipeline MUST halt without invoking marge. Specifically:
   - Read `<FEATURE_DIR>/phase-creation-status.yaml` (written by the phaser engine per FR-042) and print its contents to the operator so the offending commit hash, failing rule name, and (for forbidden operations) canonical decomposition message are visible.
   - Set the completion status to **failure** and skip the marge step entirely (do NOT spawn the marge sub agent).
   - Suggest manual review and resuming with `--from marge` once the phaser failure is resolved.

**Failure handling for the sub agent itself**: If the sub agent crashes, times out, or errors before reaching either path above, treat the outcome as a phaser failure per FR-024: halt the pipeline without invoking marge, print the failure context (agent type: phaser, error message), set the completion status to **failure**, and suggest manual review. Do NOT retry — phaser sub agent failures are treated as deterministic.

This phase is not an independent step in the `--stop-after` mapping; it runs implicitly between security-review and marge when `FLAVOR_GATE = present`. When `--stop-after ralph` halts the pipeline, the phaser step does not run.

#### Marge (loop step)

The marge step has two execution modes, selected by `FLAVOR_GATE` (resolved in the Flavor Configuration Gate section) and `PHASE_COUNT` (resolved by the phaser step):

- **Holistic-only mode** (when `FLAVOR_GATE = absent`, OR when `FLAVOR_GATE = present` but `PHASE_COUNT = 0`): Run a single marge loop reviewing the full feature diff. This is the pre-feature pipeline behavior preserved by FR-025 and SC-006.
- **Per-phase + holistic mode** (when `FLAVOR_GATE = present` AND `PHASE_COUNT >= 1`): Run marge `PHASE_COUNT + 1` times per FR-023 — once per phase scoped to that phase's diff range via `--phase N` (FR-022), then once holistically without the flag. The holistic pass MUST run after every per-phase pass completes.

**Pre-flight for per-phase mode**: When in per-phase + holistic mode, before spawning any sub agents, verify `<FEATURE_DIR>/phase-manifest.yaml` exists (the phaser step above already produced it; this is a defensive double-check). If missing, abort with: "Cannot run per-phase marge: <FEATURE_DIR>/phase-manifest.yaml not found. Phaser step did not produce a manifest." and **STOP**.

**Per-phase passes (only when in per-phase + holistic mode)**: For each phase number `N` from `1` through `PHASE_COUNT` (inclusive), in ascending order, run a per-phase marge loop:

Initialize `consecutive_stuck_count = 0`. For each iteration (up to marge max), spawn ONE sub agent at a time (wait for it to return before spawning the next):

**Before** each sub agent: record `PRE_ITERATION_SHA=$(git rev-parse HEAD)` via Bash tool.

- **subagent_type**: `general-purpose`
- **agent file**: `.claude/agents/marge.md`
- **prompt** (additional): Include the per-phase scope directive: `Phase scope: --phase <N>` and instruct the agent: "When invoking the marge command (`/speckit.marge.review`), pass `--phase <N>` so the review is scoped to that phase's diff range as resolved from `<FEATURE_DIR>/phase-manifest.yaml` (per FR-022 and R-012). Findings outside that range are out of scope for this iteration."

**After** each sub agent returns:
1. Check output for `<promise>ALL_FINDINGS_RESOLVED</promise>`. If found, this per-phase marge pass is complete — proceed to phase `N+1` (or to the holistic pass if `N == PHASE_COUNT`).
2. Check `git diff $PRE_ITERATION_SHA --stat` via Bash tool for file changes.
3. **Stuck detection**: If there are NO file changes (empty diff) AND the promise tag was NOT found, increment `consecutive_stuck_count`. If there ARE file changes OR the promise tag was found, reset `consecutive_stuck_count = 0`.
4. If `consecutive_stuck_count >= 2`, abort the marge loop — report "stuck: 2 consecutive iterations with no file changes and no completion signal in per-phase marge for phase `<N>`". Do NOT proceed to remaining per-phase passes or the holistic pass.
5. Otherwise, continue to the next iteration of the same phase's loop.

**Holistic pass (always runs in both modes, after any per-phase passes complete successfully)**: Initialize `consecutive_stuck_count = 0`. For each iteration (up to marge max), spawn ONE sub agent at a time (wait for it to return before spawning the next):

**Before** each sub agent: record `PRE_ITERATION_SHA=$(git rev-parse HEAD)` via Bash tool.

- **subagent_type**: `general-purpose`
- **agent file**: `.claude/agents/marge.md`
- **prompt**: Compose the standard marge prompt (no `--phase` directive). The agent reviews the full feature diff.

**After** each sub agent returns:
1. Check output for `<promise>ALL_FINDINGS_RESOLVED</promise>`. If found, the holistic marge pass is complete — proceed to reporting.
2. Check `git diff $PRE_ITERATION_SHA --stat` via Bash tool for file changes.
3. **Stuck detection**: If there are NO file changes (empty diff) AND the promise tag was NOT found, increment `consecutive_stuck_count`. If there ARE file changes OR the promise tag was found, reset `consecutive_stuck_count = 0`.
4. If `consecutive_stuck_count >= 2`, abort the marge loop — report "stuck: 2 consecutive iterations with no file changes and no completion signal in holistic marge".
5. Otherwise, continue to the next iteration.

**Failure handling**: If a sub agent fails (crash, timeout, or error) at any point during the per-phase or holistic passes, abort the pipeline immediately. Log failure context: iteration number, agent type (marge), the phase number when in a per-phase pass (or `holistic` when in the holistic pass), and the error message. Do NOT retry — sub agent failures in loop commands are treated as deterministic. Suggest manual review and resuming with `--from marge`.

#### Stacked PR Creation (conditional single-shot step — skip when flavor gate is absent)

This step is gated entirely on `FLAVOR_GATE` (resolved in the Flavor Configuration Gate section). It runs **after** the marge step completes successfully (both the per-phase passes and the holistic pass when in per-phase + holistic mode, or the single holistic pass when in holistic-only mode), and only when `FLAVOR_GATE = present`. Per FR-026..FR-030, FR-039, FR-040, FR-044..FR-047 and `contracts/stacked-pr-creator-cli.md`, this step creates one stacked branch and one pull request per phase listed in `<FEATURE_DIR>/phase-manifest.yaml`.

If `FLAVOR_GATE = absent`, log `no .specify/flavor.yaml found — skipping stacked-PR creation step (FR-025)` and proceed directly to Step 6 (Report Results). Do NOT spawn a sub agent and do NOT invoke the CLI.

If marge did not complete successfully (failure, stuck, or max iterations), do NOT invoke the stacked-PR creation step — proceed directly to Step 6 (Report Results) so the pipeline reports the marge failure without attempting to create stacked PRs against an unreviewed implementation.

If `FLAVOR_GATE = present` AND marge completed successfully, run the stacked-PR creator directly via the Bash tool (this step is a thin CLI invocation; it does not need a sub agent because the CLI itself encapsulates all `gh`-related logic, idempotency, and credential-handling guarantees per `contracts/stacked-pr-creator-cli.md`):

```bash
phaser/bin/phaser-stacked-prs --feature-dir <FEATURE_DIR>
stacked_prs_exit=$?
```

**Pre-flight defensive check**: Before invoking the CLI, verify `<FEATURE_DIR>/phase-manifest.yaml` exists (the phaser step above already produced it; this is a defensive double-check). If missing, log `Cannot run stacked-PR creation: <FEATURE_DIR>/phase-manifest.yaml not found. Phaser step did not produce a manifest.` and proceed directly to Step 6 (Report Results) with the stacked-PR step recorded as a failure. Do NOT invoke the CLI.

**After the CLI returns**, determine success vs. failure from `stacked_prs_exit`:

1. **Success (exit 0)**: All phases have stacked branches and PRs (FR-026, FR-027). The CLI deletes `<FEATURE_DIR>/phase-creation-status.yaml` on full success per FR-040. Capture the JSON run-summary from stdout (per `contracts/stacked-pr-creator-cli.md` it is exactly one JSON object on one line: `{"phases_created": [...], "phases_skipped_existing": [...], "manifest": "<path>"}`) and surface it to the operator. Proceed to Step 6 (Report Results).

2. **Failure (any non-zero exit)**: Per FR-039 and FR-045, the CLI has already written `<FEATURE_DIR>/phase-creation-status.yaml` with `stage: stacked-pr-creation`, the appropriate `failure_class` (`auth-missing`, `auth-insufficient-scope`, `rate-limit`, `network`, or `other` per FR-046), and `first_uncreated_phase`. Read the status file and print its contents to the operator so the failure class and resume point are visible without scrolling through stderr logs. Set the completion status to **failure** for Step 6's report. Suggest manual remediation per the `failure_class`:
   - `auth-missing` → instruct the operator to run `gh auth login` and re-invoke the pipeline with `--from marge` (the holistic marge will re-run as a no-op and the stacked-PR creator will resume idempotently per FR-040).
   - `auth-insufficient-scope` → instruct the operator to grant the `repo` scope (`gh auth refresh -s repo`) and re-invoke as above.
   - `rate-limit` → instruct the operator to wait for the host's rate-limit window to reset, then re-invoke as above.
   - `network` → instruct the operator to verify connectivity to the Git host, then re-invoke as above.
   - `other` → instruct the operator to inspect the status file's `summary` field for the underlying message and re-invoke as above once resolved.

**Map exit codes** per `contracts/stacked-pr-creator-cli.md`:

| Exit code | Meaning |
|---|---|
| 0 | Success — all phases have branches and PRs (status file deleted). |
| 1 | Stacked-PR creation failure (network, rate-limit, unexpected gh error). Status file written. |
| 2 | Authentication failure. Status file written with `failure_class: auth-missing` or `auth-insufficient-scope` and `first_uncreated_phase: 1`. |
| 3 | Operational error (manifest missing, manifest schema invalid, gh binary not on PATH). No status file. |
| 64 | Usage error. |

**Failure handling for the CLI invocation itself**: If the CLI binary cannot be invoked at all (file not found, permission denied), log `stacked-PR creation step failed to invoke phaser/bin/phaser-stacked-prs` along with the underlying shell error, set the completion status to **failure**, and proceed to Step 6 (Report Results). Do NOT retry — the CLI failure is treated as deterministic and idempotent re-invocation is the operator's responsibility.

This phase is not an independent step in the `--from` / `--stop-after` mapping; it runs implicitly after marge when `FLAVOR_GATE = present`. When `--stop-after ralph` or `--stop-after marge` halts the pipeline, the stacked-PR creation step does not run.

### Step 6: Report Results

After all steps complete (or after a `--stop-after` early termination), produce a completion report that includes the following sections:

#### 6a: Per-Step Status Table

List **all seven pipeline steps** in order, each with a status. Determine the status for each step as follows:

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
  marge ..... stopped-by-param
```

When the pipeline was stopped early by `--stop-after`, add a line after the table: `Last executed step: <step>` indicating which step was the final one to complete (whether it was actually executed or skipped-because-artifact-existed).

#### 6b: Iteration Counts

For loop steps (homer, lisa, ralph, marge) that were executed, report the total number of iterations run.

#### 6c: Completion Status

Report one of:
- **success** — all steps in the execution range completed successfully
- **max iterations reached** — a loop step hit its iteration limit
- **stuck** — 2 consecutive iterations with no file changes and no completion signal
- **failure** — a sub agent crashed or errored
- **stopped** — the pipeline was stopped early by `--stop-after` (use this when the pipeline halted before marge due to the `--stop-after` parameter; all steps in the execution range completed successfully but the full pipeline did not run)

#### 6d: Resume Suggestion

If the pipeline did not complete all seven steps (whether due to `--stop-after`, failure, stuck, or max iterations), suggest resuming with `--from <next-step>` where `<next-step>` is the first step that was not executed. For `--stop-after` early termination, suggest: "To continue the pipeline, run with `--from <next-step>`." where `<next-step>` is the step immediately after `STOP_AFTER_STEP`.

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
- `/speckit.pipeline --from marge` — Review-only; assumes ralph has already landed the implementation
- `/speckit.pipeline --stop-after ralph` — Implement but skip the review loop
