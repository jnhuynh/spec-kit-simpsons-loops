---
description: Split a feature branch into stacked phase pull requests (or open a single PR for single-phase features) per the persisted plan and review artifacts.
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

Verify that the split agent file exists. Check using the Bash tool:

```bash
test -f ".claude/agents/split.md" && echo "split.md: EXISTS" || echo "split.md: MISSING"
```

If **MISSING**, display this error and **STOP** — do not proceed with execution:

```
ERROR: Required agent file not found.

Missing: .claude/agents/split.md

This agent file is required for the split step to execute. Ensure the file is
present at:
  .claude/agents/split.md
```

If **EXISTS**, proceed to the Goal section below.

## Goal

Group the current feature branch's commits by their `Phase: N` git trailer (per FR-013), build stacked phase branches `NNNN-<type>-<slug>-phaseK` (per FR-015), and open or update a stack of pull requests with the correct base-branch chain `main <- phase1 <- phase2 <- ... <- phaseN` (per FR-016). For single-phase features (no `## Deploy Phases` section in `plan.md`), open exactly one pull request against `main` matching today's behavior (per FR-019).

The split step is idempotent: re-running with the same inputs produces no remote state changes (`unchanged` rows in `<FEATURE_DIR>/split-report.md`). When the feature branch's commit set changes, the next run rebuilds the affected phase branches via `git reset --hard <base>` + `git cherry-pick` + `git push --force-with-lease` (per FR-017).

The full behavior contract lives in `specs/008-feat-multi-phase-deploys/contracts/split-command.md`. The persisted-report contracts live in `specs/008-feat-multi-phase-deploys/contracts/split-report.md` and `specs/008-feat-multi-phase-deploys/contracts/review-report.md`. This command file is the executable instruction sequence; the agent persona and tool-use guidance live in `.claude/agents/split.md`.

**AUTONOMOUS EXECUTION**: The split step runs unattended. Do NOT ask the user for confirmation between phases. Execute every phase back-to-back until a terminal status is written for it (or fail-fast halts the run).

## Execution Steps

### Step 1: Parse Arguments

Parse `$ARGUMENTS` for:

- **`spec-dir`**: A directory path (e.g., `specs/008-feat-multi-phase-deploys`). If provided, use it as `FEATURE_DIR`.

A token containing `/` or matching a known `specs/` pattern is treated as `spec-dir`. If absent, resolve via Step 2.

### Step 2: Resolve Feature Directory

- If `spec-dir` was parsed from `$ARGUMENTS`, use it as `FEATURE_DIR`.
- Otherwise, run `bash .specify/scripts/bash/check-prerequisites.sh --json --paths-only` from repo root and parse JSON output for `FEATURE_DIR`. If the script exits non-zero, display its stderr/stdout output and **STOP** — do not proceed.

### Step 3: Verify Persisted Review Report Exists (FR-018)

Check via the Bash tool:

```bash
test -f "<FEATURE_DIR>/review-report.md" && echo "EXISTS" || echo "MISSING"
```

If **MISSING**, display the **exact** error message below and **STOP**. Do NOT write `<FEATURE_DIR>/split-report.md`. Do NOT touch any branches.

```
Review report not found at <FEATURE_DIR>/review-report.md. Run /speckit.marge.review first.
```

If **EXISTS**, proceed to Step 4.

### Step 4: Refresh `origin/main` (FR-013)

Run `git fetch origin main` via the Bash tool. If the command exits non-zero, write a single `failed` row to `<FEATURE_DIR>/split-report.md` with:

- `Phase` = `single`
- `Status` = `failed`
- `Branch` = `-`
- `PR URL` = `-`
- `Reason` = `Failed to fetch origin/main: <stderr verbatim>` (escape pipe characters as `\|`)

Then **STOP**. Do NOT touch any branches.

If the fetch succeeds, proceed to Step 5.

### Step 5: Detect Multi-Phase Mode

Run via the Bash tool:

```bash
grep -q '^## Deploy Phases$' <FEATURE_DIR>/plan.md && echo "multi-phase" || echo "single-phase"
```

- If output is `multi-phase`: continue to Step 6 then Step 7 (multi-phase execution).
- If output is `single-phase`: skip to Step 8 (single-phase execution).

The `## Deploy Phases` section's presence is the **sole** signal for multi-phase mode (per FR-002). No flag, environment variable, or command-line switch exists.

### Step 6: Parse Persisted Review Report

Parse `<FEATURE_DIR>/review-report.md` via the awk recipe from `specs/008-feat-multi-phase-deploys/contracts/review-report.md`:

```bash
awk -F '|' '
  function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
  /^\| ID \| Severity \| Phase \| Status \| Check Pack \| Summary \|/ {
    in_table = 1
    next
  }
  in_table && /^\| --- / { next }
  in_table && /^$/        { in_table = 0; next }
  in_table {
    id       = trim($2)
    severity = trim($3)
    phase    = trim($4)
    status   = trim($5)
    pack     = trim($6)
    summary  = trim($7)
    if (severity == "high" && status != "resolved") {
      print "GATE", phase, id, summary
    }
  }
' <FEATURE_DIR>/review-report.md
```

Build two structures from the `GATE` lines:

- `gating_phases`: set of integer phase numbers with at least one unresolved high-severity finding (rows where `phase` is an integer).
- `global_gate`: a list of (id, summary) tuples for unresolved high-severity findings whose `phase` is the literal `-`. If non-empty, every phase in this run is globally gated (FR-018).

Per FR-018 and the review-report contract, the split step does **not** independently re-verify any structural invariant from FR-010; the persisted review report is the single source of truth for gating decisions.

### Idempotent Rebuild Logic (FR-016, FR-017)

The split step is fully idempotent: re-running with the same `(feature branch commit SHAs, plan.md, review-report.md, origin/main)` inputs produces zero remote state changes. Re-running after the feature branch has changed produces deterministic per-phase rebuilds. The contract is:

1. **Phase branches are identified by the deterministic naming convention `<feature-branch-name>-phaseK`** (per FR-015): a remote branch matching that name is treated as an existing phase branch to update; absence of a remote branch with that name means a new phase branch must be created. The split step never consults metadata other than the branch name to identify a phase branch.

2. **Phase branch rebuild is deterministic**:

   ```bash
   git checkout -B <phase-branch-name>
   git reset --hard <base>                  # origin/main for K=1; <feature>-phase(K-1) for K>1
   git cherry-pick <phase_commits...>       # in deploy order, from `git log origin/main..HEAD --reverse`
   ```

   Every run starts from `<base>` and re-applies the current phase commits — there is no incremental diff. The recomputed branch SHA depends only on `(base SHA, phase commit set, deploy order)`.

3. **Force-push is skipped when the remote branch's SHA already matches the recomputed SHA** AND the existing PR title and body already match the recomputed values per FR-016. This is the only path to an `unchanged` row. Otherwise:
   - If the remote branch does not exist: `git push origin <phase-branch-name>`.
   - If the remote SHA differs from the recomputed SHA: `git push --force-with-lease origin <phase-branch-name>`.
   - If the remote SHA matches but the PR title or body differs: skip the push, but proceed to `gh pr edit` in the PR step.

4. **PR title and body are pipeline-managed artifacts** (per FR-016) — they are recomputed deterministically on every run from `(feature_branch_name, K, N, plan.md goal text, plan.md post-deploy text)` and overwritten via `gh pr edit --title --body` whenever they differ from the existing PR's fields. Human edits to a phase pull request's title or body **WILL be overwritten** on the next run; reviewers requesting changes MUST use pull-request review comments rather than editing the description. This makes title and body fully reproducible from the plan artifact and the feature branch name.

5. **The `unchanged` terminal status is deterministically computable** from the tuple `(commit SHAs, title, body)`:
   - `unchanged` if and only if the recomputed branch SHA equals `git rev-parse origin/<phase-branch-name>` AND the recomputed title equals the existing PR title AND the recomputed body equals the existing PR body.
   - `updated` if any of the three components differ (force-push performed, or `gh pr edit` performed, or both).
   - `created` if the remote branch did not exist and no PR existed for it before this run.

6. **Comparison uses `gh pr view --json title,body`** (or equivalently `gh pr list ... --json title,body` from step 7c.5) to fetch the existing PR's fields; the comparison is byte-exact (no whitespace normalization, no trailing-newline tolerance) so the deterministic body composition in step 7d MUST be reproduced exactly on every run.

This logic is implemented step-by-step in Step 7 (multi-phase) and Step 8 (single-phase) below; this section is the consolidated contract that those steps satisfy.

### Step 7: Multi-Phase Execution

7a. **Resolve feature branch metadata**:

- `feature_branch_name` = `git branch --show-current`
- Phase count `N` = number of `### Phase K:` headings inside the `## Deploy Phases` section of `<FEATURE_DIR>/plan.md`. Sanity-check that the phase numbers form a contiguous sequence 1..N. If they do not, the migration-safety check pack should already have flagged this as **S2** (non-contiguous phases) and emitted a `high`-severity finding; the split step still uses the maximum declared phase number as `N` and relies on the persisted review report's gating decision.

7b. **Enumerate phase commits**:

Run via the Bash tool:

```bash
git log origin/main..HEAD --reverse --format='%H %(trailers:key=Phase,valueonly)'
```

Group commits by phase number. For commits with no `Phase:` trailer, default the group to phase 1 per FR-014.

7c. **For each phase K in 1..N**, in deploy order:

1. **Compute target state**:
   - `phase_branch_name` = `${feature_branch_name}-phaseK`
   - `base` = `origin/main` if K == 1; `${feature_branch_name}-phase(K-1)` if K > 1
   - `phase_commits` = ordered list of commit SHAs for phase K (from 7b)
   - `expected_title` = `[Phase K/N] ${feature_branch_name}`
   - `expected_body` = the deterministic body composed per the FR-016 layout below.

2. **`skipped-merged` check (FR-017)**: If the remote branch `phase_branch_name` exists AND its corresponding pull request is already merged into `origin/main` (verify via `gh pr list --base main --head phase_branch_name --state merged --json number,url`), write a `skipped-merged` row with the merged PR URL preserved in the `PR URL` column and a reason citing the merged state. **Continue to phase K+1** without rebuilding.

3. **Gating check (FR-018)**:
   - If `global_gate` is non-empty: write a `gated` row with reason `Global gate: <id> (<summary>)` (citing the first global-gate finding). **Continue to phase K+1.**
   - Otherwise if K is in `gating_phases`: write a `gated` row with reason `<id> (high) is open against phase K: <summary>`. **Continue to phase K+1.**
   - Otherwise if any earlier phase J (J < K) was reported as `gated` in this run: write a `gated` row with reason `Downstream of gated phase J; resolve <upstream-finding-id> then re-run.`. **Continue to phase K+1.** (Downstream phases inherit gates transitively per FR-018.)
   - Otherwise: proceed to step 7c.4.

4. **Build/update phase branch (FR-015, FR-017)**:

   ```bash
   git checkout -B <phase_branch_name>
   git reset --hard <base>
   git cherry-pick <phase_commits...>   # in deploy order
   ```

   - If any `git cherry-pick` returns non-zero, abort the cherry-pick (`git cherry-pick --abort`), write a `failed` row with reason `Cherry-pick conflict on commit <sha>: <conflict description>. Resolve manually then re-run /speckit.split.`, and **STOP** the entire run (fail-fast per FR-017). Do NOT enumerate later phases in this run.
   - Compute `recomputed_sha = git rev-parse HEAD`.
   - Determine whether the remote phase branch already exists: `git ls-remote --heads origin <phase_branch_name>`.
   - If the remote branch does NOT exist: `git push origin <phase_branch_name>`. Mark this phase as **created** (final status determined at step 7c.6 after PR is created).
   - If the remote branch exists: compare `recomputed_sha` against `git rev-parse origin/<phase_branch_name>`. If they differ, run `git push --force-with-lease origin <phase_branch_name>` and mark this phase as **updated**. If they match, mark this phase as **unchanged** for now (still subject to PR-body comparison at step 7c.6).
   - If `git push --force-with-lease` is rejected (e.g., concurrent remote change), write a `failed` row with reason `Force-with-lease rejected on <phase_branch_name>: <stderr verbatim>. Reconcile manually then re-run /speckit.split.`, and **STOP** the entire run.

5. **Create or update pull request (FR-016)**:

   Determine whether a PR already exists for the phase branch:

   ```bash
   gh pr list --base <base-without-origin-prefix> --head <phase_branch_name> --json number,url,title,body --state open
   ```

   - The base branch passed to `gh` is `main` for K == 1, or `${feature_branch_name}-phase(K-1)` for K > 1. (Strip any `origin/` prefix.)
   - **If no PR exists**: open one via:

     ```bash
     gh pr create \
       --base <base-without-origin-prefix> \
       --head <phase_branch_name> \
       --title "<expected_title>" \
       --body "<expected_body>"
     ```

     Capture the PR URL. If `gh pr create` returns non-zero, write a `failed` row for phase K with reason `gh pr create failed: <stderr verbatim>` and **STOP** the entire run (fail-fast per FR-017).
   - **If a PR exists**: compare its current `title` and `body` against `expected_title` and `expected_body` (from `gh pr list ... --json title,body` or `gh pr view --json title,body`). If either differs, overwrite via:

     ```bash
     gh pr edit <pr-number> --title "<expected_title>" --body "<expected_body>"
     ```

     If `gh pr edit` returns non-zero, write a `failed` row with reason `gh pr edit failed: <stderr verbatim>` and **STOP**.

6. **Determine final terminal status for this phase**:
   - If the branch was newly pushed AND the PR was newly created: status = `created`.
   - Otherwise if the branch SHA changed OR the PR title/body was edited: status = `updated`.
   - Otherwise (branch SHA unchanged AND PR title/body unchanged): status = `unchanged`.

7. Append the row `| K | <status> | <phase_branch_name> | <pr_url> | <reason or -> |` to the in-memory split-report rows. Mirror a one-line human-readable summary to stdout (e.g., `Phase 2: created -> https://github.com/.../pull/124`).

7d. **Body composition for multi-phase pull requests (FR-016)**:

For each phase K, the deterministic body is:

```markdown
Part of <FEATURE_DIR>/spec.md

## Phase Goal

<goal_text_for_phase_K>

## Post-deploy production state

<post_deploy_text_for_phase_K>

## Stack

- Phase 1: <feature_branch_name>-phase1
- Phase 2: <feature_branch_name>-phase2
- ...
- Phase N: <feature_branch_name>-phaseN
```

Append the literal suffix ` (this PR)` to the bullet whose phase number equals K.

Extract `<goal_text_for_phase_K>` and `<post_deploy_text_for_phase_K>` from `<FEATURE_DIR>/plan.md` by parsing the canonical format pinned by FR-001 and the data-model "Deploy Phase" canonical example:

1. Locate the line `### Phase K: <title>` within the `## Deploy Phases` section.
2. Inside that block, find the line beginning `**Goal**:`. The goal text is everything after `**Goal**: ` on that line, plus any continuation paragraphs until the next labelled field, the next `### Phase` heading, or the end of the section. Copy verbatim into the PR body.
3. Likewise for `**Post-deploy production state**:`.

If either field is missing for any phase, the migration-safety check pack should have flagged the phase as malformed; the split step writes `<missing>` (literal) into the corresponding PR body section and continues — the gating decision is the persisted review report's responsibility.

### Step 8: Single-Phase Execution (FR-019)

8a. **Resolve feature branch metadata**:

- `feature_branch_name` = `git branch --show-current`
- `expected_title` = `${feature_branch_name}`
- `expected_body` = `Part of <FEATURE_DIR>/spec.md`

8b. **Gating check (FR-018, FR-019)**:

If `global_gate` is non-empty OR any unresolved high-severity finding exists in the persisted review report (regardless of Phase column value, since the single-phase report has Phase = `-` for every row), write a single `gated` row:

```
| single | gated | <feature_branch_name> | - | <id> (high) is open in review-report.md: <summary>. |
```

Skip to Step 9.

8c. **Open or update the single PR**:

```bash
gh pr list --base main --head <feature_branch_name> --json number,url,title,body --state open
```

- **If no PR exists**: `gh pr create --base main --head <feature_branch_name> --title "<expected_title>" --body "<expected_body>"`. Capture URL. Write a `created` row.
- **If a PR exists**: compare `title` and `body` against `expected_title` / `expected_body`. If either differs, `gh pr edit <pr-number> --title --body`. Write `updated`. Otherwise write `unchanged`.

For any `gh` failure, write a `failed` row with reason citing the stderr and **STOP**.

The single-phase row uses `Phase` = `single`, `Branch` = `<feature_branch_name>`, `PR URL` = the PR URL or `-` if gated/failed.

### Step 9: Persist `<FEATURE_DIR>/split-report.md` (FR-019a)

Overwrite `<FEATURE_DIR>/split-report.md` with the report. The file MAY contain optional human-readable prose before/after the table; the machine-readable surface is **exactly one** GFM table.

Required header row, in this exact order:

```markdown
| Phase | Status | Branch | PR URL | Reason |
| ----- | ------ | ------ | ------ | ------ |
```

For each row written during Steps 7c or 8c (in deploy order, or the single row for single-phase, or the single `failed` row from Step 4):

- `Phase`: integer phase number (multi-phase) or literal `single` (single-phase).
- `Status`: one of `created`, `updated`, `unchanged`, `skipped-merged`, `gated`, `failed`.
- `Branch`: the phase branch name (multi-phase), the feature branch name (single-phase), or literal `-` only when the run failed before resolving the branch name (e.g., fetch failure).
- `PR URL`: the pull-request URL, or literal `-` when omitted.
- `Reason`: single-sentence explanation, or literal `-`. Pipe characters in cell values MUST be escaped as `\|`.

The file MUST be overwritten in full on every run (never appended to). If the file cannot be written (e.g., permission error), surface the failure and **STOP**.

### Step 10: Mirror Summary to Stdout

After writing the report, print a concise per-phase summary to stdout in the form:

```
Phase 1: created -> <pr-url>
Phase 2: gated -> F003 (M3 rename in single phase)
Phase 3: gated -> downstream of phase 2
...
```

This mirrors the persisted report's rows so a human running the command sees the outcome immediately. The persisted `<FEATURE_DIR>/split-report.md` remains the machine-readable source of truth.

## Failure Handling Summary

| Failure mode | Action |
|---|---|
| `git fetch origin main` fails | Write single `failed` row (Phase=`single`, Branch=`-`, PR URL=`-`); **STOP** before any branch is touched |
| Review report missing | Refuse to run with the exact message above; do NOT write a split report; instruct the author to run `/speckit.marge.review` |
| Cherry-pick conflict on phase K | Abort cherry-pick; write `failed` row for phase K; **STOP**. Conflict resolution is manual; idempotent re-run resumes from phase K |
| `gh pr create` fails on phase K | Write `failed` row for phase K with the `gh` stderr; **STOP** |
| `gh pr edit` fails on phase K | Same as `gh pr create` failure |
| `git push --force-with-lease` rejected | Write `failed` row for phase K with reason; **STOP**. Author must reconcile manually |

In every fail-fast case, phase branches and pull requests built earlier in the same run are left in their successfully-completed state. The next idempotent re-run resumes from the failed phase per the contract in `specs/008-feat-multi-phase-deploys/contracts/split-command.md` "Failure handling" section.

## Persisted Split Report (FR-019a)

The persisted `<FEATURE_DIR>/split-report.md` is the contract that the pipeline orchestrator (`speckit.pipeline.md`) reads to determine the split step's outcome. Its full schema lives in `specs/008-feat-multi-phase-deploys/contracts/split-report.md`. Key invariants the orchestrator relies on:

- The header row is **exactly** `| Phase | Status | Branch | PR URL | Reason |` in that order.
- Pipe characters in cell values are escaped as `\|`.
- The file is overwritten in full on every run.
- Absence of the file after a split-step invocation is treated as a split-step failure by the pipeline orchestrator.

## Examples

- `/speckit.split` — Auto-detect feature directory from current branch; run multi-phase or single-phase split per `## Deploy Phases` detection in `plan.md`.
- `/speckit.split specs/008-feat-multi-phase-deploys` — Run for the specified feature directory.
