---
name: speckit-pipeline
description: Use when a feature should run through the Spec Kit pipeline, end to end or any contiguous range of its steps. Starts from a feature description or an existing spec directory.
---

## User Input

```text
$ARGUMENTS
```

## Pre-Flight Check

Before doing anything else, verify that the required utility script is installed:

1. Check if `.specify/scripts/bash/check-prerequisites.sh` exists (use the Bash tool: `test -f .specify/scripts/bash/check-prerequisites.sh && echo "EXISTS" || echo "MISSING"`)
2. If **MISSING**, display this error and **STOP** — do not proceed with any pipeline execution:

```
ERROR: Required utility script not found.

Missing: .specify/scripts/bash/check-prerequisites.sh

This script is required for feature directory resolution and prerequisite validation.
It is installed by Spec Kit itself, not by Simpsons Loops. Initialize Spec Kit in
this project first (e.g. `specify init`), then re-run the Simpsons Loops installer:

  bash <path-to-simpsons-loops>/setup.sh

```

3. If **EXISTS**, proceed to the agent file check below.

## Agent File Check

Verify that the agent files and the loop skills the step playbooks delegate to exist. Check via the Bash tool:

```bash
for f in homer lisa ralph marge loop-orchestrator single-shot findings-ledger; do
  test -f ".claude/agents/${f}.md" && echo "${f}.md: EXISTS" || echo "${f}.md: MISSING"
done
for s in speckit-homer-clarify speckit-lisa-analyze speckit-ralph-implement speckit-marge-review; do
  test -f ".claude/skills/${s}/SKILL.md" && echo "${s}: EXISTS" || echo "${s}: MISSING"
done
```

If **any** file is MISSING, display this error and **STOP** — do not proceed with pipeline execution:

```
ERROR: Required agent or loop-skill file(s) not found.

Missing: <the missing path(s)>

Agent files define the behavior of each pipeline phase; the loop-step playbooks
delegate to the loop skills. Ensure all are present:
  .claude/agents/{homer,lisa,ralph,marge,loop-orchestrator,single-shot,findings-ledger}.md
  .claude/skills/speckit-{homer-clarify,lisa-analyze,ralph-implement,marge-review}/SKILL.md

Run setup.sh to (re)install them.
```

If **all** exist, proceed to the Overview section below.

## Overview

Orchestrate the full Spec Kit pipeline directly within this session. Each step spawns fresh sub agents (via the Agent tool) with isolated context windows. The pipeline can start from a feature description (using the specify step) or from an existing `spec.md`.

**AUTONOMOUS EXECUTION**: This pipeline runs unattended. Do NOT ask the user for confirmation between iterations or steps. Do NOT pause for permission requests. Execute all steps and iterations back-to-back until the pipeline completes or a failure condition is met.

**STRICT SEQUENTIAL EXECUTION**: Each sub agent MUST complete and return its result before the next sub agent is spawned. Never run multiple sub agents in parallel. Within each loop step, wait for one iteration to finish before starting the next. Between pipeline steps, wait for the entire step to complete before advancing.

The pipeline runs these 11 steps in sequence:

0. **reconcile** — Correct the parent spec where completed phases shipped something else (child specs only)
1. **specify** — Create feature spec from description (optional, auto-detected)
2. **homer** — Iterative spec clarification & remediation
3. **premortem** — Human-required failure-mode discovery gate (never autonomous)
4. **phase** — Detect deployment boundaries and generate phase annotations
5. **plan** — Generate technical implementation plan
6. **tasks** — Generate dependency-ordered task list
7. **lisa** — Cross-artifact consistency analysis
8. **split** — Split multi-phase parent spec into child specs (parent specs only)
9. **ralph** — Task-by-task implementation with quality gates
10. **marge** — Iterative code review of the implementation

**Child specs skip three steps.** `homer`, `premortem`, and `phase` never run on a child spec (a directory matching `--p{N}-`). A child is a phase view of an already-clarified, already-premortemed, already-phased parent. It references the parent's user stories, requirements, key entities, and success criteria by ID under `## Inherited Scope` and holds no copy of them. Clarifications go to `/speckit-homer-clarify <PARENT_DIR>`; failure modes to `/speckit-premortem <PARENT_DIR>`. A child-spec run is therefore: **reconcile → plan → tasks → lisa → ralph → marge**.

Between ralph and marge, two **optional polish phases** run automatically **if and only if the corresponding skill is installed**:

- **simplify** — invokes the `/simplify` skill for reuse/quality/efficiency fixes
- **security-review** — invokes the `/security-review` skill for a security audit

If either skill is absent, that phase is silently skipped. These phases are **not** part of the `--from` / `--stop-after` step mapping; they always run between ralph and marge when present, and are skipped when `--stop-after ralph` halts the pipeline.

## Instructions

### Step 1: Parse Arguments and Determine the spec directory

Parse `$ARGUMENTS` for the following (all are optional, can appear in any order):

- **`--from <step>`**: Starting step override. Valid values: `reconcile`, `specify`, `homer`, `premortem`, `phase`, `plan`, `tasks`, `lisa`, `split`, `ralph`, `marge`. If provided, the pipeline starts from this step instead of auto-detecting.
- **`--stop-after <step>`**: Stop-after step, same valid values. If provided, the pipeline halts after the specified step completes, skipping all subsequent steps. Store the value in `STOP_AFTER_STEP`. If `--stop-after` is NOT provided, `STOP_AFTER_STEP` MUST remain empty. Every stop check is then a no-op and the pipeline runs from the starting step through marge. If `--stop-after` is present but no step name follows, display this error and **STOP**: "Error: --stop-after requires a step name. Valid steps: reconcile, specify, homer, premortem, phase, plan, tasks, lisa, split, ralph, marge." No step name follows when it is the last argument or the next token is another flag.
- **`--description <text>`**: Feature description for the specify step. Capture the full text after `--description` (may be quoted).
- **`--skip-phase-guard`**: Skip the phase order guard for child specs. When present, the pipeline will not check whether earlier phases are complete before starting this child phase. Use when intentionally working out of order (phases are independent, or earlier phases were cancelled). Store as boolean `SKIP_PHASE_GUARD` (default: false).
- **`--skip-premortem`**: Bypass the premortem human gate (trivial features, intentional bypass). The skip is logged. Store as boolean `SKIP_PREMORTEM` (default: false).
- **`spec-dir`**: A directory path (e.g., `specs/003-fix-pipeline-delegation`). If provided, use it as `FEATURE_DIR`.

If no `spec-dir` is provided in `$ARGUMENTS`, resolve `FEATURE_DIR` automatically:

1. **Determine if on a feature branch**: Run `git rev-parse --abbrev-ref HEAD` via Bash tool. If the branch matches the pattern `^[a-z0-9]{4}-` (e.g., `c078-feat-user-auth`), it is a feature branch.

2. **Feature branch resolution**: Run `bash .specify/scripts/bash/check-prerequisites.sh --json --paths-only` from repo root via Bash tool. This resolves paths without validating artifact existence. Parse the JSON output for `FEATURE_DIR`.

3. **Non-feature branch (e.g., `main`, `HEAD`) with bootstrapping**: If on a non-feature branch and `--from specify` is set or `--description` is provided, skip `check-prerequisites.sh` entirely (it would reject the non-feature branch). Proceed with an empty `FEATURE_DIR` — the specify step will create the feature branch and directory.

4. **Non-feature branch without bootstrapping**: If on a non-feature branch and neither `--from specify` nor `--description` is provided, display an error: "Cannot auto-detect feature directory from branch 'main'. Pass a spec-dir argument or use --from specify --description." and **STOP**.

5. **Error handling for feature branch resolution**: If `check-prerequisites.sh` exits non-zero but `--from specify` is set or `--description` is provided, treat the failure as non-fatal. Proceed with `FEATURE_DIR` set to `specs/<branch-name>`, a prospective path. Otherwise display the script's output and **STOP**.

### Step 2: Validate spec exists or can be created

- If `spec.md` exists in the resolved spec directory, proceed normally
- If `spec.md` does not exist:
  - If `--from specify` is set or `--description` is provided, continue (the specify step will create spec.md)
  - Otherwise, exit with an error instructing the user to run `/speckit-specify` first or pass `--description`
- If `--from specify` is set but no `--description` is provided, exit with an error requesting a feature description

### Step 2b: Phase Order Guard (child specs only)

This guard prevents starting a child phase N when earlier phases 1..N-1 are not complete. It is a no-op for parent specs, standalone specs, phase-1 child specs, or when `--skip-phase-guard` is set.

1. **Check applicability**: If FEATURE_DIR does NOT match the `--p{N}-` pattern (e.g., `specs/c31c-feat-billing--p2-integration`), skip this step. If it matches and N = 1, skip — no earlier phases to check. If `SKIP_PHASE_GUARD` is true, skip and log: `Phase order guard skipped per --skip-phase-guard.`

2. **Resolve parent directory**: Strip `--p{N}-{slug}` from the end of FEATURE_DIR to get `PARENT_DIR`. Extract the phase number `N`.

3. **Read parent manifest**: Read `{PARENT_DIR}/spec.md` via the Read tool. Locate the `## Manifest` section. If no spec.md exists or no `## Manifest` section is found, display this error and **STOP**:

```
ERROR: Cannot verify phase order — parent manifest not found at {PARENT_DIR}/spec.md.
Ensure the parent spec has been split (/speckit-split) before running child pipelines.
```

4. **Parse manifest table**: For each row, parse the Phase column (format `P{N}: {slug}`) and the Status column.

5. **Check earlier phases**: For each phase with number < N, categorize by status:
   - **"Complete"**: Passes the guard.
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

After the phase order guard passes (or is skipped for N=1), mark this phase "In Progress" in the parent manifest. This is a no-op for parent specs and standalone specs.

1. **Check applicability**: If FEATURE_DIR does NOT match the `--p{N}-` pattern, skip this step. If PARENT_DIR was not resolved in Step 2b, resolve it now by stripping `--p{N}-{slug}` from FEATURE_DIR.

2. **Read and parse manifest**: Read `{PARENT_DIR}/spec.md`, locate the `## Manifest` section, and find the row whose Directory column matches the basename of FEATURE_DIR.

3. **Check current status and apply transition**:
   - **"Draft"**: Update to **"In Progress"**.
   - **"In Progress"**: No-op. Do not write or commit.
   - **"Complete"**: No-op — do not regress. Log: `Phase {N} is already marked Complete in parent manifest. Skipping status update.`
   - **"Cancelled"**: Log warning: `Phase {N} is marked Cancelled in the parent manifest. Proceeding with pipeline but not updating status.` Do not update.

4. **Write the update**: If a status change is needed (Draft → In Progress), use the Edit tool. Replace only the Status cell of that manifest row in `{PARENT_DIR}/spec.md`.

5. **Commit the change**:

```bash
git add {PARENT_DIR}/spec.md && git commit -m "chore: mark phase {N} In Progress in parent manifest"
```

6. **Output phase status summary**:

```
Phase Status Summary (parent: {PARENT_DIR}):
  P1: {slug} .... {status}
  P2: {slug} .... In Progress  <-- current
  P3: {slug} .... {status}
```

Use dot-padding to align status values. Mark the current phase with `<-- current`.

### Step 3: Auto-detect starting step (if `--from` not specified)

Check which artifacts exist to determine where to start:
- Child spec (directory name matches `--p{N}-`) with no `plan.md` → start at **reconcile** when N > 1, or at **plan** when N = 1. Auto-detect never selects homer, premortem, or phase for a child spec.
- `tasks.md` with all `- [x]` complete (no `- [ ]` lines remaining) → start at **marge**
- `tasks.md` with some `- [x]` complete → start at **ralph**
- `spec.md` with Phases and a `## Manifest` section (split already ran) → start at **ralph**
- `tasks.md` with none complete → start at **lisa**
- `plan.md` exists → start at **tasks**
- `spec.md` exists and has a populated `## Phases` section (contains at least one `### Phase` subsection) → start at **plan**
- `spec.md` exists, has no populated `## Phases` section, and `<FEATURE_DIR>/failure-modes.md` exists → start at **premortem** (the gate re-validates that no rows are `open`, then flows into phase)
- `spec.md` exists, has no populated `## Phases` section, and no `failure-modes.md` → start at **homer**
- No `spec.md` but `--description` provided → start at **specify**

### Step 3b: Step Index Mapping

| Step | Index |
|------|-------|
| reconcile | 0 |
| specify | 1 |
| homer | 2 |
| premortem | 3 |
| phase | 4 |
| plan | 5 |
| tasks | 6 |
| lisa | 7 |
| split | 8 |
| ralph | 9 |
| marge | 10 |

Resolve the index of the starting step (from `--from` or auto-detected) into `start_index`. If `STOP_AFTER_STEP` is set, resolve its index into `stop_after_index`.

### Step 3c: Validate --stop-after

If `STOP_AFTER_STEP` is set, validate it **before any pipeline steps execute**:

1. **Value validation**: `STOP_AFTER_STEP` must be one of the eleven step names. Otherwise display this error and **STOP**:

```
Invalid --stop-after value '<value>'. Valid steps: reconcile, specify, homer, premortem, phase, plan, tasks, lisa, split, ralph, marge.
```

2. **Range validation**: If `stop_after_index` is less than `start_index`, display this error and **STOP**:

```
Invalid range: --stop-after '<stop>' comes before starting step '<start>' in the pipeline sequence (reconcile -> specify -> homer -> premortem -> phase -> plan -> tasks -> lisa -> split -> ralph -> marge).
```

### Step 3d: Child-Spec Step Applicability

If FEATURE_DIR matches the `--p{N}-` child pattern, `homer`, `premortem`, and `phase` do not apply (see the Overview).

1. **`--from` names an inapplicable step**: log `<step> does not run on child specs — starting at <next applicable step> instead.` Advance the starting step **and** `start_index` to `plan`, the next step after all three in a child-spec run. Do not error; the developer's intent is clear.

2. **`--stop-after` names an inapplicable step**: log `<step> does not run on child specs — stopping after <previous applicable step> instead.` and update **both** `STOP_AFTER_STEP` and `stop_after_index` to `reconcile`. That is the previous step of a child-spec run; `specify` and `split` never appear in one either (see Step 4b). Updating the name matters: every stop check compares `STOP_AFTER_STEP` by name. If the remapped stop falls before the starting step, apply the Step 3c range error instead.

### Step 4b: Execution Plan Announcement

Before executing any steps, announce the steps that will run. They run from the starting step through `STOP_AFTER_STEP` (if set) or `marge` (if not), in Step 3b order.

- **When `--stop-after` is provided**: `Execution plan: specify -> homer -> premortem -> phase -> plan. Stopping after: plan.`
- **When `--stop-after` is NOT provided**: `Execution plan: homer -> premortem -> phase -> plan -> tasks -> lisa -> split -> ralph -> marge.`

Step names are joined with ` -> `. Append ` Stopping after: <step>.` only when `--stop-after` is provided.

**Child specs**: when FEATURE_DIR matches the `--p{N}-` pattern, omit `homer`, `premortem`, and `phase`; they never run on a child. Also omit `specify` and `split`: a child's `spec.md` always exists, and a child is never re-split. A phase-2 child with no artifacts announces: `Execution plan: reconcile -> plan -> tasks -> lisa -> ralph -> marge.`

### Step 5: Execute Pipeline Steps

**CRITICAL**: Execute steps **strictly in sequence** — one at a time. Each Agent tool call MUST return before the next one is spawned. Never use parallel Agent calls.

**POST-STEP STOP CHECK**: After each step completes, compare `STOP_AFTER_STEP` with that step's name. A step counts as complete whether it ran or was skipped (artifact already present, or step not applicable). On a match, output the message below and **skip all remaining steps**: spawn no further sub agents and proceed directly to Step 6 (Report Results). If `STOP_AFTER_STEP` is empty, every stop check is a no-op.

```
Pipeline stopped after <step> per --stop-after parameter. Skipping: <steps>.
```

`<steps>` lists the pipeline steps after `<step>` in the Step 3b table, joined with `, ` (comma and space). Leave out only the child-spec omissions from Step 4b; a step that will be skipped for another reason, such as `split` on a single-phase spec, is still listed. After `marge` nothing follows, so omit the `Skipping:` clause.

**FAILURE HANDLING (all steps)**: If a required step's sub agent fails (crash, timeout, or error), or a loop step aborts (stuck, stalled, oscillating, max iterations, or sub-agent failure), abort the pipeline immediately. Log the step name and the error. Do NOT retry — sub agent failures are treated as deterministic. Suggest manual review and resuming with `--from <step>`. The premortem gate halting with `awaiting-human` is NOT a failure — it is the gate working as designed (see its playbook). Exception: the optional polish steps (simplify, security-review, pr-review) log the failure and continue, per their playbooks.

For each step, spawn fresh sub agents using the **Agent tool**. Each sub agent gets a fresh context window, preventing hallucination drift. Loop iteration limits are owned by each loop's standalone skill (`.claude/skills/speckit-<loop>-*/SKILL.md`); the pipeline does not restate them.

When composing the prompt for each sub agent, always include:
- An instruction to read and follow the corresponding agent file from `.claude/agents/`
- When those instructions reference a slash command like `/speckit-<verb>`, read its definition and follow it directly. Take the first path that exists, in order: `.claude/skills/speckit-<verb>/SKILL.md`, `.claude/skills/speckit.<verb>/SKILL.md`, then `.claude/commands/speckit.<verb>.md` (older command-mode installs use the dotted name)
- `Feature directory: <FEATURE_DIR>`

Each step's full playbook — sub-agent dispatch, prompt/config, conditional skips, and failure handling — lives in a `reference/steps/<step>.md` file under the installed skill. Read a playbook **only when you reach its step** (a partial `--from`/`--stop-after` run loads only the steps it executes). Execute in this order, applying each step's stated condition:

1. **Reconcile** — conditional single-shot, child specs only → read and follow `.claude/skills/speckit-pipeline/reference/steps/reconcile.md`
2. **Specify** — single-shot → read and follow `.claude/skills/speckit-pipeline/reference/steps/specify.md`
3. **Homer** — loop → read and follow `.claude/skills/speckit-pipeline/reference/steps/homer.md`
4. **Premortem** — human gate, never spawns a sub agent → read and follow `.claude/skills/speckit-pipeline/reference/steps/premortem.md`
5. **Phase** — single-shot → read and follow `.claude/skills/speckit-pipeline/reference/steps/phase.md`
6. **Plan** — single-shot → read and follow `.claude/skills/speckit-pipeline/reference/steps/plan.md`
7. **Tasks** — single-shot → read and follow `.claude/skills/speckit-pipeline/reference/steps/tasks.md`
8. **Lisa** — loop → read and follow `.claude/skills/speckit-pipeline/reference/steps/lisa.md`
9. **Split** — conditional single-shot, multi-phase parent specs only → read and follow `.claude/skills/speckit-pipeline/reference/steps/split.md`
10. **Ralph** — loop → read and follow `.claude/skills/speckit-pipeline/reference/steps/ralph.md`
11. **Simplify** — optional single-shot, skip if skill absent → read and follow `.claude/skills/speckit-pipeline/reference/steps/simplify.md`
12. **Security Review** — optional single-shot, skip if skill absent → read and follow `.claude/skills/speckit-pipeline/reference/steps/security-review.md`
13. **Marge** — loop → read and follow `.claude/skills/speckit-pipeline/reference/steps/marge.md`
14. **PR Review** — optional single-shot, skip if no open PR or skill absent → read and follow `.claude/skills/speckit-pipeline/reference/steps/pr-review.md`

### Step 6: Report Results

After all steps complete (or after an early termination), produce a completion report with these sections:

#### 6a: Per-Step Status Table

List **all eleven pipeline steps** in order, each with a status:

- **`executed`**: The step ran during this invocation (a sub agent was spawned or, for loop steps, iterations were performed).
- **`skipped`**: The step was NOT executed, for one of three reasons:
  - it falls before the starting step
  - its artifact already existed (`spec.md` for specify, `plan.md` for plan, and so on)
  - it does not apply to this spec: `homer`, `premortem`, `phase` on a child; `split` on a child or single-phase spec; `reconcile` unless phase 2+
- **`stopped-by-param`**: The step falls after `STOP_AFTER_STEP` (its index is greater than `stop_after_index`). Never used when `--stop-after` is not provided.
- **`awaiting-human`**: The premortem gate blocked because the human premortem session is incomplete (no `failure-modes.md`, or `open` rows remain). Only the premortem step can receive this status; all downstream steps report `skipped`.

**Format**:

```
Pipeline Step Status:
  reconcile . skipped
  specify .... executed
  homer ..... executed
  premortem . executed
  phase ..... executed
  plan ...... executed
  tasks ..... stopped-by-param
  lisa ...... stopped-by-param
  split ..... stopped-by-param
  ralph ..... stopped-by-param
  marge ..... stopped-by-param
```

When the pipeline was stopped early by `--stop-after`, add a line after the table: `Last executed step: <step>`. That is the final step to complete, whether it ran or was skipped because its artifact existed.

#### 6b: Iteration Counts

For each loop step (homer, lisa, ralph, marge) that was executed, report the total number of iterations run.

#### 6c: Completion Status

Report one of:
- **success** — all steps in the execution range completed successfully
- **max iterations reached** — a loop step hit its iteration limit
- **stuck** — 2 consecutive iterations with no file changes and no completion signal
- **stalled** — 3 consecutive iterations without reducing work count
- **oscillating** — work count alternating between two values
- **failure** — a sub agent crashed or errored
- **stopped** — the pipeline halted before marge because of `--stop-after`; every step in the execution range completed
- **pr-boundary** — ralph completed a PR group from the `## Pull Request Plan` in `tasks.md` and halted so it can be opened, reviewed and merged. Tasks remain; simplify, security-review and marge were skipped. Report the PR just finished, its task range, and the remaining groups
- **awaiting-human** — the pipeline halted at the premortem gate; the human failure-mode session is incomplete
- **split-complete** — the pipeline completed through split and stopped because the user chose to work on child specs individually

#### 6d: Resume Suggestion

If the pipeline did not complete all eleven steps, suggest resuming with `--from <next-step>`, where `<next-step>` is the first step that was not executed:

- `--stop-after`: "To continue the pipeline, run with `--from <next-step>`." where `<next-step>` is the step after `STOP_AFTER_STEP`.
- `pr-boundary`: "Open PR `<N>`, get it reviewed and merged, then resume with `--from ralph` to start PR `<N+1>`."
- `awaiting-human`: "Run `/speckit-premortem` to complete the failure-mode session(s), then resume with `--from premortem`."

## Examples

- `/speckit-pipeline` — Auto-detect spec dir from current branch, run full pipeline
- `/speckit-pipeline specs/a1b2-feat-user-auth` — Run pipeline for specific spec
- `/speckit-pipeline --from homer` — Start from homer step (auto-detect spec dir)
- `/speckit-pipeline --from ralph specs/a1b2-feat-user-auth` — Resume ralph for specific spec
- `/speckit-pipeline --from specify --description "Add user auth"` — End-to-end from a description
- `/speckit-pipeline --stop-after plan` — Run through plan step only
- `/speckit-pipeline --from homer --stop-after tasks` — Run homer through tasks
- `/speckit-pipeline --from premortem` — Re-check the premortem gate and continue the pipeline
- `/speckit-pipeline --skip-premortem` — Bypass the premortem human gate (not recommended)
- `/speckit-pipeline --from marge` — Review-only; assumes ralph has already landed the implementation
- `/speckit-pipeline --stop-after ralph` — Implement but skip the review loop
- `/speckit-pipeline --from split` — Re-split and prompt for child/monolith choice
- `/speckit-pipeline --skip-phase-guard specs/proj--p3-ui-reveal` — Start phase 3 even if earlier phases aren't complete
