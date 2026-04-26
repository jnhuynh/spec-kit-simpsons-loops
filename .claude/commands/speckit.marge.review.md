---
description: Orchestrate iterative code review and remediation (Marge loop) over the feature branch diff until all findings are resolved.
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Pre-Flight Check

Before doing anything else, verify that the required utility scripts are installed:

1. Check if `.specify/scripts/bash/check-prerequisites.sh` exists (use the Bash tool: `test -f .specify/scripts/bash/check-prerequisites.sh && echo "EXISTS" || echo "MISSING"`)
2. If **MISSING**, display this error and **STOP** — do not proceed with any execution:

```
ERROR: Required utility script not found.

Missing: .specify/scripts/bash/check-prerequisites.sh

This script is required for feature directory resolution and prerequisite validation.
To install it, run the SpecKit setup command:

  /speckit.setup

```

3. If **EXISTS**, proceed to the agent file check below.

## Agent File Check

Verify that the required agent file exists before starting the loop. Check using the Bash tool:

```bash
test -f ".claude/agents/marge.md" && echo "marge.md: EXISTS" || echo "marge.md: MISSING"
```

If **MISSING**, display this error and **STOP** — do not proceed with execution:

```
ERROR: Required agent file not found.

Missing: .claude/agents/marge.md

This agent file is required for Marge loop sub-agents to execute. It defines
the behavior of each review iteration. Ensure the file is present at:
  .claude/agents/marge.md
```

If **EXISTS**, proceed to the review command check below.

## Review Command Check

Verify that the single-pass review command exists. Marge's Phase 0 delegates to it:

```bash
test -f ".claude/commands/speckit.review.md" && echo "speckit.review.md: EXISTS" || echo "speckit.review.md: MISSING"
```

If **MISSING**, display this error and **STOP**:

```
ERROR: Required command file not found.

Missing: .claude/commands/speckit.review.md

Marge invokes /speckit.review during Phase 0 to generate findings.
Ensure the file is present at:
  .claude/commands/speckit.review.md
```

If **EXISTS**, proceed to the Goal section below.

## Goal

Orchestrate the Marge loop directly within this session. Each iteration spawns a fresh sub agent (via the Agent tool) that reviews the feature branch's diff against baseline and project-specific review packs, fixes the single highest-severity finding, commits, and exits. The loop continues until zero findings remain or max iterations is reached.

**AUTONOMOUS EXECUTION**: This loop runs unattended. Do NOT ask the user for confirmation between iterations. Do NOT pause for permission requests. Execute all iterations back-to-back until a completion condition is met (all findings resolved, max iterations reached, or stuck detection triggers).

**STRICT SEQUENTIAL EXECUTION**: Each sub agent MUST complete and return its result before the next sub agent is spawned. Never run multiple sub agents in parallel. Wait for one iteration to finish before starting the next.

## Execution Steps

### Step 1: Parse Arguments

Parse `$ARGUMENTS` for the following (all are optional, can appear in any order):

- **`spec-dir`**: A directory path (e.g., `specs/003-fix-pipeline-delegation`). If provided, use it as `FEATURE_DIR`.
- **`max-iterations`**: A numeric value (e.g., `5`). If provided, use it as the max iteration count instead of the default.
- **`--phase <N>`**: A 1-indexed phase number (e.g., `--phase 3`). If provided, scope the review to that phase's diff range as resolved from `<FEATURE_DIR>/phase-manifest.yaml`. Implements FR-022 / R-012. When absent, marge reviews the full feature diff (the holistic pass).

**Parsing rules**:
- A token that looks like a directory path (contains `/` or matches a known `specs/` pattern) is treated as `spec-dir`
- A standalone numeric token (e.g., `5`, `10`) is treated as `max-iterations`
- The two-token sequence `--phase <N>` (where `<N>` is a positive integer) is treated as `phase`. The `<N>` token consumed by `--phase` is NOT also counted as `max-iterations`.
- If `--phase` is provided without a following numeric `<N>`, abort: "`--phase` requires a positive integer phase number (e.g., `--phase 3`)."
- If neither `spec-dir`, `max-iterations`, nor `--phase` is provided, use defaults for both.

### Step 2: Resolve Feature Directory

- If `spec-dir` was parsed from `$ARGUMENTS`, use it as `FEATURE_DIR`
- Otherwise, run `bash .specify/scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks` from repo root and parse JSON output for `FEATURE_DIR`. **Error handling**: If the script exits with a non-zero status (e.g., missing feature dir, invalid branch), display the script's stderr/stdout output to the user and **STOP** — do not proceed with execution.

### Step 3: Verify Artifacts

Confirm all three artifacts exist in `FEATURE_DIR`:

- `spec.md`
- `plan.md`
- `tasks.md`

If any are missing, abort with guidance:

- Missing `spec.md` → "Run /speckit.specify first"
- Missing `plan.md` → "Run /speckit.plan first"
- Missing `tasks.md` → "Run /speckit.tasks first"

If `--phase <N>` was parsed in Step 1, additionally:

1. Confirm `<FEATURE_DIR>/phase-manifest.yaml` exists. If missing, abort: "Cannot scope review to phase <N>: <FEATURE_DIR>/phase-manifest.yaml not found. Run /speckit.phaser first to produce the manifest, or omit --phase to run the holistic review."
2. Read the manifest and locate the entry whose `number` equals `<N>`. If no such entry exists, abort: "Phase <N> not found in <FEATURE_DIR>/phase-manifest.yaml. Available phases: <list of `number` fields>."
3. Extract `BASE_BRANCH` from that entry's `base_branch` field and `HEAD_BRANCH` from its `branch_name` field. Both fields are required by the manifest schema (`contracts/phase-manifest.schema.yaml`); if either is empty, abort: "Phase <N> entry in phase-manifest.yaml is missing `base_branch` or `branch_name`. Manifest is malformed — re-run /speckit.phaser to regenerate."
4. Compute the phase diff range as the literal string `<BASE_BRANCH>...<HEAD_BRANCH>` (three dots — symmetric-difference form, per R-012). This is the `PHASE_DIFF_RANGE` value passed to each sub agent in Step 5.
5. Confirm there is a diff to review for that phase. Run `git diff --quiet <BASE_BRANCH>...<HEAD_BRANCH>` via Bash tool; if the command exits 0 (no diff), abort: "Phase <N> has no diff between `<BASE_BRANCH>` and `<HEAD_BRANCH>`. Nothing to review."

If `--phase` was NOT provided, confirm there is a diff to review. Run `git diff --quiet $(git merge-base HEAD origin/main 2>/dev/null || git merge-base HEAD main)...HEAD` via Bash tool; if the command exits 0 (no diff), abort: "No changes detected between the feature branch and main. Nothing to review — run /speckit.ralph.implement first."

### Step 4: Configuration

- If `max-iterations` was parsed from `$ARGUMENTS`, use that value
- Otherwise, default max iterations: **30**

### Step 5: Run Marge Loop

Initialize `consecutive_stuck_count = 0`. For each iteration (up to max), spawn ONE sub agent at a time (wait for it to return before spawning the next):

**Before** each sub agent: record `PRE_ITERATION_SHA=$(git rev-parse HEAD)` via Bash tool.

1. Spawn a fresh-context sub agent using the **Agent tool**:
   - **subagent_type**: `general-purpose`
   - **prompt**: Compose a prompt containing:
     - Instruct the agent to read and follow `.claude/agents/marge.md`
     - When those instructions reference a slash command (e.g., `/speckit.review`), read the corresponding file from `.claude/commands/` and follow its instructions directly
     - Provide: `Feature directory: <FEATURE_DIR>`
     - **If `--phase <N>` was parsed in Step 1**, also provide:
       - `Phase scope: <N>`
       - `Diff range: <PHASE_DIFF_RANGE>` (the `<BASE_BRANCH>...<HEAD_BRANCH>` string resolved in Step 3)
       - The instruction: "When invoking /speckit.review, scope the review to the diff range above instead of the default merge-base diff. Concretely: invoke /speckit.review with the additional argument token `range:<PHASE_DIFF_RANGE>` and instruct it to use that range as the diff scope. Findings outside this range are out of scope for this iteration." This implements FR-022 / R-012 — per-phase scoping for the per-phase marge passes invoked by /speckit.pipeline.
   - Each sub agent gets a fresh context window, preventing hallucination drift

**After** each sub agent returns:
1. Check the sub agent's returned output for the completion promise tag: `<promise>ALL_FINDINGS_RESOLVED</promise>`. If found, report success and stop looping.
2. Check `git diff $PRE_ITERATION_SHA --stat` via Bash tool for file changes.
3. **Stuck detection**: If there are NO file changes (empty diff) AND the promise tag was NOT found, increment `consecutive_stuck_count`. If there ARE file changes OR the promise tag was found, reset `consecutive_stuck_count = 0`.
4. If `consecutive_stuck_count >= 2`, abort the marge loop — report "stuck: 2 consecutive iterations with no file changes and no completion signal". Suggest manual review.
5. Otherwise, continue to the next iteration.

**Failure handling**: If the sub agent fails (crash, timeout, or error), abort the loop immediately. Log failure context: iteration number, agent type (marge), and error message. Do NOT retry — sub agent failures in loop commands are treated as deterministic. Suggest manual review.

### Step 6: Report Results

After the loop completes, report:
- Total iterations run
- Completion status (one of: **success** — all findings resolved; **max iterations reached** — limit hit without resolution; **stuck** — 2 consecutive iterations with no file changes and no completion signal; **failure** — sub agent crashed or errored)
- Count of findings that remain flagged `NEEDS_HUMAN` (extract from the last sub agent's report) — these require manual review
- Suggestion to rerun if not fully resolved

## Examples

- `/speckit.marge.review` — Auto-detect spec dir from current branch, use default max iterations (30); review the full feature diff (holistic pass)
- `/speckit.marge.review specs/003-fix-pipeline-delegation` — Run for specific spec dir
- `/speckit.marge.review 5` — Auto-detect spec dir, limit to 5 iterations
- `/speckit.marge.review specs/003-fix-pipeline-delegation 5` — Specific spec dir with 5 max iterations
- `/speckit.marge.review --phase 3` — Auto-detect spec dir, scope review to phase 3's diff range as resolved from `<FEATURE_DIR>/phase-manifest.yaml` (FR-022 / R-012)
- `/speckit.marge.review specs/007-multi-phase-pipeline --phase 1 5` — Specific spec dir, scope review to phase 1, limit to 5 iterations
