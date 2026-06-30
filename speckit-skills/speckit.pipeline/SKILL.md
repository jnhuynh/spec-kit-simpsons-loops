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

**POST-STEP STOP CHECK**: After each step completes (whether it was executed or skipped because its artifact already existed), if `STOP_AFTER_STEP` is set and equals the current step name, output the stop message and **skip all remaining steps** — do NOT spawn any further sub-agents. Proceed directly to Step 6 (Report Results). Each step's playbook (see the Step 5 list below) includes the specific stop check with the exact message to output.

For each step (starting from the detected/specified step), spawn fresh sub agents using the **Agent tool**. Each sub agent gets a fresh context window, preventing hallucination drift.

When composing the prompt for each sub agent, always include:
- Instruct the agent to read and follow the corresponding agent file from `.claude/agents/`
- When those instructions reference a slash command (e.g., `/speckit.clarify`), read its definition — prefer `.claude/skills/<command>/SKILL.md`, falling back to `.claude/commands/<command>.md` — and follow those instructions directly
- Provide: `Feature directory: <FEATURE_DIR>`

Each step's full playbook — sub-agent dispatch, prompt/config, conditional skips, failure handling, and its own post-step stop check — lives in a `reference/steps/<step>.md` file under the installed skill. Read a playbook **only when you reach its step** (progressive disclosure: a partial `--from`/`--stop-after` run loads only the steps it executes). Execute in this order, applying each step's stated condition:

1. **Reconcile** — conditional single-shot, child specs only → read and follow `.claude/skills/speckit.pipeline/reference/steps/reconcile.md`
2. **Specify** — single-shot → read and follow `.claude/skills/speckit.pipeline/reference/steps/specify.md`
3. **Homer** — loop → read and follow `.claude/skills/speckit.pipeline/reference/steps/homer.md`
4. **Phase** — single-shot → read and follow `.claude/skills/speckit.pipeline/reference/steps/phase.md`
5. **Plan** — single-shot → read and follow `.claude/skills/speckit.pipeline/reference/steps/plan.md`
6. **Tasks** — single-shot → read and follow `.claude/skills/speckit.pipeline/reference/steps/tasks.md`
7. **Lisa** — loop → read and follow `.claude/skills/speckit.pipeline/reference/steps/lisa.md`
8. **Split** — conditional single-shot, multi-phase parent specs only → read and follow `.claude/skills/speckit.pipeline/reference/steps/split.md`
9. **Ralph** — loop → read and follow `.claude/skills/speckit.pipeline/reference/steps/ralph.md`
10. **Simplify** — optional single-shot, skip if skill absent → read and follow `.claude/skills/speckit.pipeline/reference/steps/simplify.md`
11. **Security Review** — optional single-shot, skip if skill absent → read and follow `.claude/skills/speckit.pipeline/reference/steps/security-review.md`
12. **Marge** — loop → read and follow `.claude/skills/speckit.pipeline/reference/steps/marge.md`
13. **PR Review** — optional single-shot, skip if no open PR or skill absent → read and follow `.claude/skills/speckit.pipeline/reference/steps/pr-review.md`

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
