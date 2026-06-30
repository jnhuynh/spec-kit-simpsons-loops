---
name: speckit.pipeline
description: Orchestrate the full SpecKit pipeline (reconcile, specify, homer, phase, plan, tasks, lisa, split, ralph, marge) from feature description to reviewed implementation.
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
for f in reconcile specify homer phase plan tasks lisa split ralph marge; do
  test -f ".claude/agents/${f}.md" && echo "${f}.md: EXISTS" || echo "${f}.md: MISSING"
done
```

If **any** agent file is MISSING, display this error and **STOP** — do not proceed with pipeline execution:

```
ERROR: Required agent file(s) not found.

Missing: .claude/agents/<name>.md

Agent files are required for pipeline sub-agents to execute. These files define
the behavior of each pipeline phase. Ensure all agent files are present:
  .claude/agents/reconcile.md
  .claude/agents/specify.md
  .claude/agents/homer.md
  .claude/agents/phase.md
  .claude/agents/plan.md
  .claude/agents/tasks.md
  .claude/agents/lisa.md
  .claude/agents/split.md
  .claude/agents/ralph.md
  .claude/agents/marge.md
```

If **all** agent files exist, proceed to the Overview section below.

## Overview

Orchestrate the full SpecKit pipeline directly within this session. Each step spawns fresh sub agents (via the Agent tool) with isolated context windows. The pipeline can start from a feature description (using the specify step) or from an existing `spec.md`.

**AUTONOMOUS EXECUTION**: This pipeline runs unattended. Do NOT ask the user for confirmation between iterations or steps. Do NOT pause for permission requests. Execute all steps and iterations back-to-back until the pipeline completes or a failure condition is met.

**STRICT SEQUENTIAL EXECUTION**: Each sub agent MUST complete and return its result before the next sub agent is spawned. Never run multiple sub agents in parallel. Within each loop step, wait for one iteration to finish before starting the next. Between pipeline steps, wait for the entire step to complete before advancing. The pipeline order is non-negotiable:

The pipeline runs these 10 steps in sequence:

0. **reconcile** — Sync child spec with earlier sibling phases (child specs only)
1. **specify** — Create feature spec from description (optional, auto-detected)
2. **homer** — Iterative spec clarification & remediation
3. **phase** — Detect deployment boundaries and generate phase annotations
4. **plan** — Generate technical implementation plan
5. **tasks** — Generate dependency-ordered task list
6. **lisa** — Cross-artifact consistency analysis
7. **split** — Split multi-phase parent spec into child specs (parent specs only)
8. **ralph** — Task-by-task implementation with quality gates
9. **marge** — Iterative code review of the implementation

Between ralph and marge, two **optional polish phases** run automatically **if and only if the corresponding skill is installed** in the environment:

- **simplify** — invokes the `/simplify` skill for reuse/quality/efficiency fixes
- **security-review** — invokes the `/security-review` skill for a security audit

If either skill is absent, that phase is silently skipped. These phases are **not** part of the `--from` / `--stop-after` step mapping; they always run between ralph and marge when present, and are skipped when `--stop-after ralph` halts the pipeline.

## Instructions

### Step 1: Parse Arguments and Determine the spec directory

Parse `$ARGUMENTS` for the following (all are optional, can appear in any order):

- **`--from <step>`**: Starting step override. Valid values: `reconcile`, `specify`, `homer`, `phase`, `plan`, `tasks`, `lisa`, `split`, `ralph`, `marge`. If provided, the pipeline starts from this step instead of auto-detecting.
- **`--stop-after <step>`**: Stop-after step. Valid values: `reconcile`, `specify`, `homer`, `phase`, `plan`, `tasks`, `lisa`, `split`, `ralph`, `marge`. If provided, the pipeline halts after the specified step completes, skipping all subsequent steps. Store the value in `STOP_AFTER_STEP`. If `--stop-after` is NOT provided, `STOP_AFTER_STEP` MUST remain empty/unset so that all stop checks are no-ops and the pipeline runs all steps from the starting step through marge — identical to the behavior before `--stop-after` was added (FR-007). If `--stop-after` is present but no step name follows (e.g., it is the last argument or the next token is another flag), display an error: "Error: --stop-after requires a step name. Valid steps: reconcile, specify, homer, phase, plan, tasks, lisa, split, ralph, marge." and **STOP**.
- **`--description <text>`**: Feature description for the specify step. Capture the full text after `--description` (may be quoted).
- **`--skip-phase-guard`**: Skip the phase order guard for child specs. When present, the pipeline will not check whether earlier phases are complete before starting this child phase. Use when intentionally working out of order (e.g., phases are independent or earlier phases were cancelled). Store as boolean `SKIP_PHASE_GUARD` (default: false).
- **`spec-dir`**: A directory path (e.g., `specs/003-fix-pipeline-delegation`). If provided, use it as `FEATURE_DIR`.

If no `spec-dir` is provided in `$ARGUMENTS`, resolve `FEATURE_DIR` automatically:

1. **Determine if on a feature branch**: Run `git rev-parse --abbrev-ref HEAD` via Bash tool. If the branch matches the pattern `^[a-z0-9]{4}-` (e.g., `c078-feat-user-auth`), it is a feature branch.

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

### Step 2b: Phase Order Guard (child specs only)

This guard prevents starting a child phase N pipeline when earlier phases 1..N-1 are not complete. It is a no-op for parent specs, standalone specs, phase-1 child specs, or when `--skip-phase-guard` is set.

1. **Check applicability**: If FEATURE_DIR does NOT match the `--p{N}-` pattern (e.g., `specs/c31c-feat-billing--p2-integration`), skip this step entirely — it is not a child spec. If it matches and N = 1, skip — no earlier phases to check. If `SKIP_PHASE_GUARD` is true, skip and log: `Phase order guard skipped per --skip-phase-guard.`

2. **Resolve parent directory**: Strip `--p{N}-{slug}` from the end of FEATURE_DIR to get `PARENT_DIR`. Extract the phase number `N`. (Same logic as the Reconcile step.)

3. **Read parent manifest**: Read `{PARENT_DIR}/spec.md` via the Read tool. Locate the `## Manifest` section. If no spec.md exists or no `## Manifest` section is found, display this error and **STOP**:

```
ERROR: Cannot verify phase order — parent manifest not found at {PARENT_DIR}/spec.md.
Ensure the parent spec has been split (/speckit.split) before running child pipelines.
```

4. **Parse manifest table**: Extract each row from the manifest markdown table. For each row, parse the Phase column (format `P{N}: {slug}`) and the Status column. Build a list of all phases with their numbers and statuses.

5. **Check earlier phases**: For each phase with number < N (i.e., phases 1 through N-1), categorize by status:
   - **"Complete"**: Passes the guard — this phase is done.
   - **"Draft" or "In Progress"**: Blocks — this phase is not done yet.
   - **"Cancelled"**: Blocks — this phase was abandoned, dependencies may be missing.

6. **All earlier phases "Complete"**: Guard passes. Continue to Step 2c.

7. **Any earlier phases "Draft" or "In Progress"**: Display error and **STOP** — do not execute any pipeline steps:

```
ERROR: Phase {N} cannot start — earlier phases are incomplete.

Blocking phases:
  P{X}: {slug} — {status}
  P{Y}: {slug} — {status}

Complete these phases before starting phase {N}, or re-run with --skip-phase-guard to bypass this check.
```

(List all blocking phases, not just the first one.)

8. **Any earlier phases "Cancelled" (and none are Draft/In Progress)**: Display error and **STOP**:

```
ERROR: Phase {N} cannot start — earlier phases are cancelled.

Cancelled phases:
  P{X}: {slug} — Cancelled

If phase {N} does not depend on cancelled phases, re-run with --skip-phase-guard to bypass this check.
```

### Step 2c: Mark Phase "In Progress" in Parent Manifest (child specs only)

After the phase order guard passes (or is skipped for N=1), update the parent manifest to mark this phase as "In Progress". This is a no-op for parent specs and standalone specs.

1. **Check applicability**: If FEATURE_DIR does NOT match the `--p{N}-` pattern, skip this step (not a child spec). If PARENT_DIR was not resolved in Step 2b (because N=1 and Step 2b was skipped), resolve it now by stripping `--p{N}-{slug}` from FEATURE_DIR.

2. **Read and parse manifest**: Read `{PARENT_DIR}/spec.md`, locate the `## Manifest` section, and parse the table. Find the row where the Directory column matches the basename of FEATURE_DIR (the child directory name without the `specs/` prefix).

3. **Check current status and apply transition**:
   - If current status is **"Draft"**: Update to **"In Progress"**.
   - If current status is **"In Progress"**: No-op — already correct. Do not write or commit.
   - If current status is **"Complete"**: No-op — do not regress. Log: `Phase {N} is already marked Complete in parent manifest. Skipping status update.`
   - If current status is **"Cancelled"**: Log warning: `Phase {N} is marked Cancelled in the parent manifest. Proceeding with pipeline but not updating status.` Do not update.

4. **Write the update**: If a status change is needed (Draft → In Progress), use the Edit tool to update the Status cell in the specific manifest table row in `{PARENT_DIR}/spec.md`. Replace only the status value in that row — preserve all other content in the file.

5. **Commit the change**:

```bash
git add {PARENT_DIR}/spec.md && git commit -m "chore: mark phase {N} In Progress in parent manifest"
```

6. **Output phase status summary**: After updating (or confirming no update needed), output a summary of all phases and their current statuses:

```
Phase Status Summary (parent: {PARENT_DIR}):
  P1: {slug} .... {status}
  P2: {slug} .... In Progress  <-- current
  P3: {slug} .... {status}
```

Use dot-padding to align status values. Mark the current phase with `<-- current`.

### Step 3: Auto-detect starting step (if `--from` not specified)

Check which artifacts exist to determine where to start:
- Child spec (directory name matches `--p{N}-` pattern) with N > 1 and no `plan.md` → start at **reconcile**
- `tasks.md` with all `- [x]` complete (no `- [ ]` lines remaining) → start at **marge**
- `tasks.md` with some `- [x]` complete → start at **ralph**
- `spec.md` with Phases and a `## Manifest` section (split already ran) → start at **ralph**
- `tasks.md` with none complete → start at **lisa**
- `plan.md` exists → start at **tasks**
- `spec.md` exists and has a populated `## Phases` section (contains at least one `### Phase` subsection) → start at **plan**
- `spec.md` exists but has no populated `## Phases` section → start at **homer**
- No `spec.md` but `--description` provided → start at **specify**

### Step 3b: Step Index Mapping

Assign a numeric index to each pipeline step for use in validation and execution plan computation:

| Step | Index |
|------|-------|
| reconcile | 0 |
| specify | 1 |
| homer | 2 |
| phase | 3 |
| plan | 4 |
| tasks | 5 |
| lisa | 6 |
| split | 7 |
| ralph | 8 |
| marge | 9 |

Resolve the index for the starting step (from `--from` or auto-detected) into `start_index`. If `STOP_AFTER_STEP` is set, resolve its index into `stop_after_index`. These indices are used in subsequent validation and execution plan steps.

### Step 3c: Validate --stop-after

If `STOP_AFTER_STEP` is set, perform the following validations **before any pipeline steps execute**:

1. **Value validation (FR-006)**: Verify that `STOP_AFTER_STEP` is one of the ten valid step names: `reconcile`, `specify`, `homer`, `phase`, `plan`, `tasks`, `lisa`, `split`, `ralph`, `marge`. If the value is not in this list, display the following error and **STOP** — do not execute any pipeline steps:

```
Invalid --stop-after value '<value>'. Valid steps: reconcile, specify, homer, phase, plan, tasks, lisa, split, ralph, marge.
```

(Replace `<value>` with the actual invalid value the user provided.)

2. **Range validation (FR-005)**: If `STOP_AFTER_STEP` is set and its `stop_after_index` is less than the `start_index` (the starting step, whether set via `--from` or auto-detected), display the following error and **STOP** — do not execute any pipeline steps:

```
Invalid range: --stop-after '<stop>' comes before starting step '<start>' in the pipeline sequence (reconcile -> specify -> homer -> phase -> plan -> tasks -> lisa -> split -> ralph -> marge).
```

(Replace `<stop>` with the actual `STOP_AFTER_STEP` value and `<start>` with the actual starting step name.)

### Step 4: Configuration

- Homer max iterations: **30**
- Lisa max iterations: **30**
- Ralph max iterations: **incomplete_tasks + 10** (count `- [ ]` lines in tasks.md at the start of the ralph step, then add 10)
- Marge max iterations: **30**

### Step 4b: Execution Plan Announcement

Before executing any steps, output an execution plan announcement listing the steps that will run. Build the list of planned steps from the starting step through either the `STOP_AFTER_STEP` (if set) or `marge` (if not set), using the step index mapping from Step 3b.

**Format**:

- **When `--stop-after` is provided**: `Execution plan: specify -> homer -> plan. Stopping after: plan.`
- **When `--stop-after` is NOT provided**: `Execution plan: homer -> phase -> plan -> tasks -> lisa -> split -> ralph -> marge.`

The step names in the plan are joined with ` -> `. Only include steps from the starting step through the stop step (inclusive). When `--stop-after` is provided, append ` Stopping after: <step>.` to the announcement. When `--stop-after` is not provided, omit the "Stopping after" clause entirely.

### Step 5: Execute Pipeline Steps

**CRITICAL**: Execute steps **strictly in sequence** — one at a time. Each Agent tool call MUST return before the next one is spawned. Never use parallel Agent calls. Each loop iteration must complete before the next iteration starts. Each pipeline step must fully complete before advancing to the next step.

**POST-STEP STOP CHECK**: After each step completes (whether it was executed or skipped because its artifact already existed), if `STOP_AFTER_STEP` is set and equals the current step name, output the stop message and **skip all remaining steps** — do NOT spawn any further sub-agents. Proceed directly to Step 6 (Report Results). Each step section below includes the specific stop check with the exact message to output.

For each step (starting from the detected/specified step), spawn fresh sub agents using the **Agent tool**. Each sub agent gets a fresh context window, preventing hallucination drift.

When composing the prompt for each sub agent, always include:
- Instruct the agent to read and follow the corresponding agent file from `.claude/agents/`
- When those instructions reference a slash command (e.g., `/speckit.clarify`), read its definition — prefer `.claude/skills/<command>/SKILL.md`, falling back to `.claude/commands/<command>.md` — and follow those instructions directly
- Provide: `Feature directory: <FEATURE_DIR>`

#### Reconcile (conditional single-shot step — child specs only)
Detect if the current spec is a child spec by checking FEATURE_DIR for the `--p{N}-` pattern (e.g., `specs/c31c-feat-billing--p2-integration`).

- **If not a child spec** (parent or standalone): skip, continue to specify.
- **If child spec with N = 1** (first phase): skip, no earlier siblings to reconcile with.
- **If child spec with N > 1**: resolve the parent directory by stripping `--p{N}-{slug}` from the child directory name. Spawn a sub agent:
  - **subagent_type**: `general-purpose`
  - **agent file**: `.claude/agents/reconcile.md`
  - **prompt**: `Feature directory: <FEATURE_DIR>. Run non-interactively.`

**Failure handling**: If the sub agent fails, abort the pipeline. Suggest resuming with `--from reconcile`.

**Post-step stop check**: After the reconcile step completes (whether executed or skipped), check STOP_AFTER_STEP. If equals `reconcile`, output: `Pipeline stopped after reconcile per --stop-after parameter. Skipping: specify, homer, phase, plan, tasks, lisa, split, ralph, marge.` and skip all remaining steps.

#### Specify (single-shot step)
Skip if `spec.md` already exists. Otherwise, spawn a sub agent:
- **subagent_type**: `general-purpose`
- **agent file**: `.claude/agents/specify.md`
- **prompt**: `Feature directory: <FEATURE_DIR>. Feature description: <DESCRIPTION>. Run non-interactively: auto-resolve all clarifications with best guesses, do not present questions to the user.`

**Failure handling**: If the sub agent fails (crash, timeout, or error), abort the pipeline immediately. Log failure context: agent type (specify) and error message. Do NOT retry — sub agent failures in loop commands are treated as deterministic. Print: "Specify step failed. Fix the issue and re-invoke with --from specify". Suggest manual review and resuming with `--from specify`.

**Post-specify re-resolution**: After the specify step completes successfully, if `FEATURE_DIR` is empty or the directory does not exist, re-resolve by running `bash .specify/scripts/bash/check-prerequisites.sh --json --paths-only` from repo root via Bash tool and parsing the JSON output for `FEATURE_DIR`. This is required because the specify step (via `create-new-feature.sh`) creates the feature branch and directory. If re-resolution fails, abort the pipeline with: "Specify step completed but feature directory could not be resolved." The re-resolved `FEATURE_DIR` MUST be used for all subsequent steps.

**Post-step stop check**: After the specify step completes (whether it was executed or skipped because `spec.md` already exists), check if `STOP_AFTER_STEP` is set and equals `specify`. If it does, output: `Pipeline stopped after specify per --stop-after parameter. Skipping: homer, phase, plan, tasks, lisa, split, ralph, marge.` and **skip all remaining steps** — do NOT spawn any further sub-agents. Proceed directly to Step 6 (Report Results). If `STOP_AFTER_STEP` is empty/unset, this check is a no-op — continue to the next step.

#### Homer (loop step)
Execute the Homer loop using the shared loop orchestrator. Read and follow `.claude/agents/loop-orchestrator.md` with this LOOP_CONFIG:

- **AGENT_NAME**: homer
- **AGENT_DISPLAY_NAME**: Homer
- **AGENT_FILE**: .claude/agents/homer.md
- **SLASH_COMMAND_REF**: /speckit.clarify
- **PROMISE_TAG**: ALL_FINDINGS_RESOLVED
- **PREREQ_FLAGS**: --json --paths-only
- **REQUIRED_ARTIFACTS**: spec.md
- **MAX_ITERATIONS**: 30 (or homer max from Step 4)
- **EXTRA_PROMPT_SUFFIX**: (none)
- **REPORT_MODE**: standard

Skip the orchestrator's Pre-Flight and Agent File checks (already done in pipeline pre-flight). Start from Step 1 (Parse Arguments) using the already-resolved `FEATURE_DIR`.

**Failure handling**: If the loop aborts (stuck, stalled, oscillating, or sub agent failure), abort the pipeline immediately. Suggest manual review and resuming with `--from homer`.

**Post-step stop check**: After the homer step completes, check if `STOP_AFTER_STEP` is set and equals `homer`. If it does, output: `Pipeline stopped after homer per --stop-after parameter. Skipping: phase, plan, tasks, lisa, split, ralph, marge.` and **skip all remaining steps** — do NOT spawn any further sub-agents. Proceed directly to Step 6 (Report Results). If `STOP_AFTER_STEP` is empty/unset, this check is a no-op — continue to the next step.

#### Phase (single-shot step)
Skip if `spec.md` already contains a populated `## Phases` section (check for at least one `### Phase` subsection within it). Otherwise, spawn a sub agent:
- **subagent_type**: `general-purpose`
- **agent file**: `.claude/agents/phase.md`
- **prompt**: `Feature directory: <FEATURE_DIR>. Run non-interactively.`

**Failure handling**: If the sub agent fails (crash, timeout, or error), abort the pipeline immediately. Log failure context: agent type (phase) and error message. Do NOT retry — sub agent failures in loop commands are treated as deterministic. Print: "Phase step failed. Fix the issue and re-invoke with --from phase". Suggest manual review and resuming with `--from phase`.

**Post-step stop check**: After the phase step completes (whether it was executed or skipped because `## Phases` is already populated), check if `STOP_AFTER_STEP` is set and equals `phase`. If it does, output: `Pipeline stopped after phase per --stop-after parameter. Skipping: plan, tasks, lisa, split, ralph, marge.` and **skip all remaining steps** — do NOT spawn any further sub-agents. Proceed directly to Step 6 (Report Results). If `STOP_AFTER_STEP` is empty/unset, this check is a no-op — continue to the next step.

#### Plan (single-shot step)

Skip if `plan.md` already exists. Otherwise, spawn a sub agent:
- **subagent_type**: `general-purpose`
- **agent file**: `.claude/agents/plan.md`

**Failure handling**: If the sub agent fails (crash, timeout, or error), abort the pipeline immediately. Log failure context: agent type (plan) and error message. Do NOT retry — sub agent failures in loop commands are treated as deterministic. Suggest manual review and resuming with `--from plan`.

**Post-step stop check**: After the plan step completes (whether it was executed or skipped because `plan.md` already exists), check if `STOP_AFTER_STEP` is set and equals `plan`. If it does, output: `Pipeline stopped after plan per --stop-after parameter. Skipping: tasks, lisa, split, ralph, marge.` and **skip all remaining steps** — do NOT spawn any further sub-agents. Proceed directly to Step 6 (Report Results). If `STOP_AFTER_STEP` is empty/unset, this check is a no-op — continue to the next step.

#### Tasks (single-shot step)
Skip if `tasks.md` already exists. Otherwise, spawn a sub agent:
- **subagent_type**: `general-purpose`
- **agent file**: `.claude/agents/tasks.md`

**Failure handling**: If the sub agent fails (crash, timeout, or error), abort the pipeline immediately. Log failure context: agent type (tasks) and error message. Do NOT retry — sub agent failures in loop commands are treated as deterministic. Suggest manual review and resuming with `--from tasks`.

**Post-step stop check**: After the tasks step completes (whether it was executed or skipped because `tasks.md` already exists), check if `STOP_AFTER_STEP` is set and equals `tasks`. If it does, output: `Pipeline stopped after tasks per --stop-after parameter. Skipping: lisa, split, ralph, marge.` and **skip all remaining steps** — do NOT spawn any further sub-agents. Proceed directly to Step 6 (Report Results). If `STOP_AFTER_STEP` is empty/unset, this check is a no-op — continue to the next step.

#### Lisa (loop step)
Execute the Lisa loop using the shared loop orchestrator. Read and follow `.claude/agents/loop-orchestrator.md` with this LOOP_CONFIG:

- **AGENT_NAME**: lisa
- **AGENT_DISPLAY_NAME**: Lisa
- **AGENT_FILE**: .claude/agents/lisa.md
- **SLASH_COMMAND_REF**: /speckit.analyze
- **PROMISE_TAG**: ALL_FINDINGS_RESOLVED
- **PREREQ_FLAGS**: --json --require-tasks --include-tasks
- **REQUIRED_ARTIFACTS**: spec.md, plan.md, tasks.md
- **MAX_ITERATIONS**: 30 (or lisa max from Step 4)
- **EXTRA_PROMPT_SUFFIX**: (none)
- **REPORT_MODE**: standard

Skip the orchestrator's Pre-Flight and Agent File checks (already done in pipeline pre-flight). Start from Step 1 (Parse Arguments) using the already-resolved `FEATURE_DIR`.

**Failure handling**: If the loop aborts (stuck, stalled, oscillating, or sub agent failure), abort the pipeline immediately. Suggest manual review and resuming with `--from lisa`.

**Post-step stop check**: After the lisa step completes, check if `STOP_AFTER_STEP` is set and equals `lisa`. If it does, output: `Pipeline stopped after lisa per --stop-after parameter. Skipping: split, ralph, marge.` and **skip all remaining steps** — do NOT spawn any further sub-agents. Proceed directly to Step 6 (Report Results). If `STOP_AFTER_STEP` is empty/unset, this check is a no-op — continue to the next step.

#### Split (conditional single-shot step — multi-phase parent specs only)
Check if the current spec is a child spec (directory name matches `--p{N}-` pattern). If it IS a child spec, **skip** — no recursive splitting. Continue to ralph.

If not a child spec, check if spec.md has 2+ phases (count `### Phase` subsections within `## Phases`). If single-phase or no phases, **skip** and continue to ralph.

If multi-phase parent spec (2+ phases): spawn a sub agent:
- **subagent_type**: `general-purpose`
- **agent file**: `.claude/agents/split.md`
- **prompt**: `Feature directory: <FEATURE_DIR>. Run non-interactively.`

After split completes, read the parent spec's `## Manifest` section to get the list of child directories. Then prompt the user with two options using the AskUserQuestion tool:

**Option 1 (Recommended)**: "Stop and work on children" — Display the child spec directories and guidance:
"This parent spec has been split into {N} child specs:

  {list child directories}

The parent spec's plan and tasks describe the full feature scope. Each child spec should now be run through its own pipeline.

To pipeline each child spec (run in phase order):

  /speckit.pipeline {child-dir-1}
  /speckit.pipeline {child-dir-2}
  ...

Deploy and validate each phase in production before starting the next. When you pipeline a child spec, it auto-reconciles with what earlier phases actually built."

**Option 2**: "Continue implementing full parent spec as a monolith" — With description: "WARNING: This will implement all phases as a single deployment, producing one large PR with all changes across all phases. This defeats the purpose of phased delivery. Only choose this if phased delivery is not needed despite having multiple phases."

If user selects option 1 (default/recommended): stop the pipeline. Set completion status to **split-complete**. Proceed to Step 6 (Report Results).
If user selects option 2: log the warning and continue to ralph/marge.

**Failure handling**: If the sub agent fails, abort. Suggest resuming with `--from split`.

**Post-step stop check**: After split completes, if STOP_AFTER_STEP equals `split`, output: `Pipeline stopped after split per --stop-after parameter. Skipping: ralph, marge.` and skip all remaining steps.

#### Ralph (loop step)

**Quality gate validation**: Before starting the ralph loop, validate that `.specify/quality-gates.sh` (full gate, required) exists and contains executable content, and check for `.specify/quality-gates-fast.sh` (fast gate, optional). Run the following via Bash tool:

```bash
test -f .specify/quality-gates.sh && grep -v '^\s*#' .specify/quality-gates.sh | grep -v '^\s*$' | head -1
test -f .specify/quality-gates-fast.sh && echo "FAST_GATE_EXISTS" || echo "FAST_GATE_MISSING"
```

If the full gate file does not exist or contains only comments/whitespace (the first command produces no output), **STOP** the pipeline with this error:

```
ERROR: Quality gates file is missing or empty.

Expected: .specify/quality-gates.sh with executable commands.

Create the file with your project's quality gate commands, e.g.:
  echo 'npm test && npm run lint' > .specify/quality-gates.sh

The ralph and marge phases require quality gates to validate implementation work.

Optionally, also create .specify/quality-gates-fast.sh with scoped commands
that check only changed files for faster per-iteration feedback.
```

Determine the per-iteration gate command: if `.specify/quality-gates-fast.sh` exists and is non-empty, use `bash .specify/quality-gates-fast.sh`; otherwise fall back to `bash .specify/quality-gates.sh`.

**Calculate ralph max iterations**: Count incomplete tasks in tasks.md and add 10:

```bash
incomplete_count=$(grep -c '^\s*- \[ \]' "<FEATURE_DIR>/tasks.md" 2>/dev/null || echo "0")
echo $((incomplete_count + 10))
```

Use the resulting number as `ralph_max_iterations`.

Execute the Ralph loop using the shared loop orchestrator. Read and follow `.claude/agents/loop-orchestrator.md` with this LOOP_CONFIG:

- **AGENT_NAME**: ralph
- **AGENT_DISPLAY_NAME**: Ralph
- **AGENT_FILE**: .claude/agents/ralph.md
- **SLASH_COMMAND_REF**: /speckit.implement
- **PROMISE_TAG**: ALL_TASKS_COMPLETE
- **PREREQ_FLAGS**: --json --require-tasks --include-tasks
- **REQUIRED_ARTIFACTS**: spec.md, plan.md, tasks.md
- **MAX_ITERATIONS**: (use `ralph_max_iterations` calculated above)
- **EXTRA_PROMPT_SUFFIX**: Quality gates: (use the per-iteration gate command determined above)
- **REPORT_MODE**: tasks

Skip the orchestrator's Pre-Flight and Agent File checks (already done in pipeline pre-flight). Start from Step 1 (Parse Arguments) using the already-resolved `FEATURE_DIR`.

**Post-loop verification**: After the orchestrator reports completion via promise tag, also verify tasks.md directly — if any `- [ ]` tasks remain, report the discrepancy.

**End-of-loop full quality gate**: When the ralph loop exits via the success path (all tasks complete), run the full gate once via Bash tool:

```bash
bash .specify/quality-gates.sh
```

If it exits non-zero, abort the pipeline with completion status **failure** and reason "ralph end-of-loop full quality gates failed". Surface the failing output in the report and suggest resuming with `--from ralph`. Skip the simplify, security-review, and marge steps. Do NOT run this gate on max-iterations, stuck, or failure exits — those already terminate the pipeline.

**Failure handling**: If the loop aborts (stuck, stalled, oscillating, or sub agent failure), abort the pipeline immediately. Suggest manual review and resuming with `--from ralph`.

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

#### Marge (loop step)

**Diff existence check**: Confirm there is a diff to review. Run `git diff --quiet $(git merge-base HEAD origin/main 2>/dev/null || git merge-base HEAD main)...HEAD` via Bash tool; if the command exits 0 (no diff), abort: "No changes detected between the feature branch and main. Nothing to review."

Execute the Marge loop using the shared loop orchestrator. Read and follow `.claude/agents/loop-orchestrator.md` with this LOOP_CONFIG:

- **AGENT_NAME**: marge
- **AGENT_DISPLAY_NAME**: Marge
- **AGENT_FILE**: .claude/agents/marge.md
- **SLASH_COMMAND_REF**: /speckit.review
- **PROMISE_TAG**: ALL_FINDINGS_RESOLVED
- **PREREQ_FLAGS**: --json --require-tasks --include-tasks
- **REQUIRED_ARTIFACTS**: spec.md, plan.md, tasks.md
- **MAX_ITERATIONS**: 30 (or marge max from Step 4)
- **EXTRA_PROMPT_SUFFIX**: (none)
- **REPORT_MODE**: needs_human

Skip the orchestrator's Pre-Flight and Agent File checks (already done in pipeline pre-flight). Start from Step 1 (Parse Arguments) using the already-resolved `FEATURE_DIR`.

**End-of-loop full quality gate**: When the marge loop exits via the success path (all findings resolved), run the full gate once via Bash tool:

```bash
bash .specify/quality-gates.sh
```

If it exits non-zero, set the pipeline completion status to **failure** with reason "marge end-of-loop full quality gates failed", surface the failing output in the report, and suggest resuming with `--from marge`. Do NOT run this gate on max-iterations, stuck, or failure exits.

**Post-marge manifest update (child specs only)**: When the marge loop exits via the success path (all findings resolved) AND the full quality gate passes, update the parent manifest to mark this phase as "Complete". Skip this entirely if FEATURE_DIR does not match the `--p{N}-` pattern (not a child spec).

1. Resolve `PARENT_DIR` by stripping `--p{N}-{slug}` from FEATURE_DIR. Extract the phase number `N`.

2. Read `{PARENT_DIR}/spec.md`, locate the `## Manifest` section, and parse the table. Find the row where the Directory column matches this child's directory name.

3. Check current status and apply transition:
   - If **"In Progress"**: Update to **"Complete"**.
   - If **"Draft"**: Update to **"Complete"** (the pipeline ran the full lifecycle, implicitly passing through In Progress).
   - If **"Complete"**: No-op — already marked. Do not write or commit.
   - If **"Cancelled"**: Log warning: `Phase {N} is marked Cancelled in the parent manifest. Pipeline completed but not updating status.` Do not update.

4. Write the update using the Edit tool — replace only the Status cell in the matching manifest table row in `{PARENT_DIR}/spec.md`. Preserve all other content.

5. Commit the change:

```bash
git add {PARENT_DIR}/spec.md && git commit -m "chore: mark phase {N} Complete in parent manifest"
```

6. Output phase status summary:

```
Phase Status Summary (parent: {PARENT_DIR}):
  P1: {slug} .... Complete
  P2: {slug} .... Complete  <-- complete
  P3: {slug} .... Draft
```

Use dot-padding to align status values. Mark the phase that was just completed with `<-- complete`.

**Failure handling**: If the loop aborts (stuck, stalled, oscillating, or sub agent failure), abort the pipeline immediately. Do NOT run the manifest update on failure exits — the phase is not complete. Suggest manual review and resuming with `--from marge`.

#### PR Review (optional single-shot step — skip if no open PR or skill absent)

Detect whether the `/speckit.review.pr` skill is installed. Run via Bash tool:

```bash
if test -f ".claude/skills/speckit.review.pr/SKILL.md" || test -f ".claude/commands/speckit.review.pr.md"; then echo "PRESENT"; else echo "ABSENT"; fi
```

If **ABSENT**, log `speckit.review.pr not installed — skipping PR review` and proceed to Step 6.

If **PRESENT**, check for an open PR:

```bash
gh pr view --json number --jq '.number' 2>/dev/null
```

If no PR exists, log `No open PR for current branch — skipping PR review` and proceed to Step 6.

If both conditions pass, spawn a sub agent:
- **subagent_type**: `general-purpose`
- **prompt**: `Read and follow the instructions in .claude/skills/speckit.review.pr/SKILL.md (or .claude/commands/speckit.review.pr.md if that file does not exist). Run non-interactively — auto-detect the PR from the current branch.`

**Failure handling**: If the sub agent fails, log `PR review phase failed — continuing pipeline`. Do NOT abort — PR review is informational, not a gate.

This phase is not an independent step in the `--stop-after` mapping; it runs implicitly after marge when its skill is present and an open PR exists.

### Step 6: Report Results

After all steps complete (or after a `--stop-after` early termination), produce a completion report that includes the following sections:

#### 6a: Per-Step Status Table

List **all ten pipeline steps** in order, each with a status. Determine the status for each step as follows:

- **`executed`**: The step ran during this pipeline invocation (either a sub-agent was spawned or, for loop steps, iterations were performed).
- **`skipped`**: The step was NOT executed. This applies when:
  - The step falls before the `--from` starting step (outside the execution range), OR
  - The step's artifact already existed so the step was skipped (e.g., `spec.md` already existed so specify was skipped, `plan.md` already existed so plan was skipped).
- **`stopped-by-param`**: The step was NOT executed because it falls after the `STOP_AFTER_STEP`. This status applies to all steps whose index is greater than the `stop_after_index`. When `--stop-after` is not provided, no step receives this status.

**Format** — output a table like:

```
Pipeline Step Status:
  reconcile . skipped
  specify .... executed
  homer ..... executed
  phase ..... executed
  plan ...... executed
  tasks ..... stopped-by-param
  lisa ...... stopped-by-param
  split ..... stopped-by-param
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
- **stalled** — 3 consecutive iterations without reducing work count
- **oscillating** — work count alternating between two values
- **failure** — a sub agent crashed or errored
- **stopped** — the pipeline was stopped early by `--stop-after` (use this when the pipeline halted before marge due to the `--stop-after` parameter; all steps in the execution range completed successfully but the full pipeline did not run)
- **split-complete** — the pipeline completed through split and stopped because the user chose to work on child specs individually

#### 6d: Resume Suggestion

If the pipeline did not complete all ten steps (whether due to `--stop-after`, failure, stuck, or max iterations), suggest resuming with `--from <next-step>` where `<next-step>` is the first step that was not executed. For `--stop-after` early termination, suggest: "To continue the pipeline, run with `--from <next-step>`." where `<next-step>` is the step immediately after `STOP_AFTER_STEP`.

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
- `/speckit.pipeline --from split` — Re-split and prompt for child/monolith choice
- `/speckit.pipeline --stop-after split` — Run through split step only (plan the whole, then decompose)
- `/speckit.pipeline --skip-phase-guard specs/proj--p3-ui-reveal` — Start phase 3 even if earlier phases aren't complete
