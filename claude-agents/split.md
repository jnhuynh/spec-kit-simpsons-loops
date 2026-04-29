# Split Agent - Spec Kit Integration

Split a feature branch into stacked phase pull requests (multi-phase) or open a single pull request (single-phase) per the persisted plan and review artifacts. This is a **single-shot** agent — run once and exit.

> **Note:** The split step is idempotent. Re-running with the same inputs produces no remote state changes (`unchanged` rows). When the feature branch's commit set changes, the next run rebuilds the affected phase branches via `git reset --hard <base>` + `git cherry-pick` + `git push --force-with-lease` (per FR-017).

## Feature Directory

The feature directory is provided via the `-p` prompt when this agent is invoked. Extract the path from the prompt (e.g., "Feature directory: specs/a1b2-feat-foo").

## Instructions

Run `/speckit.split` with the resolved feature directory. The full executable instruction sequence — pre-flight checks, multi-phase detection, gating semantics, idempotent rebuild via `reset` + `cherry-pick` + `force-with-lease`, fail-fast handling, and the persisted split-report writeout — lives in `speckit-commands/speckit.split.md` (installed at `.claude/commands/speckit.split.md`).

This agent file documents the persona, the tool-use guidance, and the high-level behavior contract. Always defer to the command file for the executable steps.

**CRITICAL — Autonomous Execution**: The split step runs unattended. Do NOT ask the user for confirmation between phases. Execute every phase back-to-back until a terminal status is written for it (or fail-fast halts the run).

## Phase 0: Pre-flight (FR-018)

The split step MUST refuse to run when prerequisites are not satisfied. The command file enforces these checks; the agent's role is to surface failures clearly without touching any branches.

1. **Resolve `FEATURE_DIR`** via `bash .specify/scripts/bash/check-prerequisites.sh --json --paths-only` (or use the path provided in the agent invocation prompt).
2. **Verify the persisted review report exists** at `<FEATURE_DIR>/review-report.md`. If missing, refuse to run with the **exact** message:

   ```
   Review report not found at <FEATURE_DIR>/review-report.md. Run /speckit.marge.review first.
   ```

   Do NOT write `<FEATURE_DIR>/split-report.md` in this case. Do NOT touch any branches.
3. **Refresh `origin/main`** via `git fetch origin main`. If the fetch fails, write a single `failed` row to `<FEATURE_DIR>/split-report.md` (per the schema in `specs/008-feat-multi-phase-deploys/contracts/split-report.md`) and STOP before any branch is touched.

## Phase 1: Detect Mode (FR-002)

Detect multi-phase mode by checking for a `## Deploy Phases` section in `plan.md`:

```bash
grep -q '^## Deploy Phases$' <FEATURE_DIR>/plan.md
```

The presence of the section is the **sole** signal for multi-phase mode (FR-002). No flag, environment variable, or command-line switch is introduced (FR-020). If the section is absent, the feature is single-phase and the split step opens exactly one pull request against `main` matching today's behavior (FR-019).

## Phase 2: Parse Gating Decisions (FR-018)

Parse `<FEATURE_DIR>/review-report.md` for unresolved high-severity findings (`Status` not `resolved`). Use the awk recipe from `specs/008-feat-multi-phase-deploys/contracts/review-report.md` to locate the table by its exact header row `| ID | Severity | Phase | Status | Check Pack | Summary |`.

Build two structures:

- `gating_phases`: set of integer phase numbers with at least one unresolved high-severity finding (rows where `Phase` is an integer).
- `global_gate`: list of `(id, summary)` tuples for unresolved high-severity findings whose `Phase` is the literal `-`. If non-empty, every phase in this run is globally gated.

**Important**: The split step does NOT independently re-verify any structural invariant from FR-010. The persisted review report is the single source of truth for gating decisions. Findings flagged by the migration-safety check pack at `.specify/marge/checks/migrations.md` propagate through the report; the split step trusts what Marge wrote.

## Phase 3: Execute (Multi-Phase or Single-Phase)

### Multi-phase (FR-013, FR-014, FR-015, FR-016, FR-017)

For each phase K in 1..N (where N is the count of `### Phase K:` headings in the plan's `## Deploy Phases` section), in deploy order:

1. **Compute target state**:
   - `phase_branch_name` = `<feature_branch_name>-phaseK` (FR-015)
   - `base` = `origin/main` if K == 1; `<feature_branch_name>-phase(K-1)` if K > 1
   - `phase_commits` = ordered list of commit SHAs whose `Phase: K` git trailer matches K, enumerated via:

     ```bash
     git log origin/main..HEAD --reverse --format='%H %(trailers:key=Phase,valueonly)'
     ```

     Commits with no `Phase:` trailer default to phase 1 (FR-014).
   - `expected_title` = `[Phase K/N] <feature_branch_name>` (FR-016)
   - `expected_body` = the deterministic FR-016 body composition: `Part of <FEATURE_DIR>/spec.md` line, `## Phase Goal` section copied verbatim from `**Goal**:`, `## Post-deploy production state` section copied verbatim from `**Post-deploy production state**:`, and `## Stack` listing every phase branch with ` (this PR)` appended only to the bullet whose phase number equals K.
2. **`skipped-merged` check (FR-017)**: If the remote branch exists AND its pull request is already merged into `origin/main`, write a `skipped-merged` row and continue to phase K+1 without rebuilding. This is the only safeguard against the spec-freeze edge case where a tasks-artifact `[phase-N]` tag is changed after commits with that tag have already shipped.
3. **Gating check (FR-018)**:
   - If `global_gate` is non-empty: write a `gated` row citing the global-gate finding and continue.
   - Otherwise if K is in `gating_phases`: write a `gated` row citing the phase-K finding and continue.
   - Otherwise if any earlier phase J (J < K) was reported as `gated` in this run: write a `gated` row noting the downstream gate (gates propagate transitively per FR-018) and continue.
4. **Build/update phase branch via `reset` + `cherry-pick` + `force-with-lease`** (FR-017):
   - `git checkout -B <phase_branch_name>`
   - `git reset --hard <base>`
   - `git cherry-pick <phase_commits...>` in deploy order
   - If a remote branch with the same name already exists: compare the recomputed SHA against `origin/<phase_branch_name>`. If they differ, `git push --force-with-lease`. If they match, mark the branch state as `unchanged` for now (still subject to PR-body comparison).
   - If the remote branch does not exist: `git push origin <phase_branch_name>`.
5. **Create or update pull request** (FR-016):
   - Use `gh pr list --base <base-without-origin-prefix> --head <phase_branch_name> --json number,url,title,body --state open` to detect existing PRs.
   - If absent: `gh pr create --base <base> --head <phase_branch_name> --title "<expected_title>" --body "<expected_body>"`.
   - If present: compare title and body against the recomputed values. If either differs, overwrite via `gh pr edit <pr-number> --title --body`. Phase pull-request title and body are pipeline-managed artifacts — they WILL be overwritten on every run.
6. **Compute terminal status** for this phase:
   - `created` if the branch was newly pushed AND the PR was newly opened.
   - `updated` if the branch SHA changed OR the PR title/body was edited.
   - `unchanged` if neither changed.

### Single-phase (FR-019)

If `## Deploy Phases` is absent from `plan.md`, open exactly one pull request:

- `expected_title` = `<feature_branch_name>`
- `expected_body` = `Part of <FEATURE_DIR>/spec.md`
- Gating: any unresolved high-severity finding (regardless of `Phase` column value, since the single-phase report has Phase = `-` for every row) gates the single PR per FR-018 and FR-019.
- Otherwise open or update the PR via `gh pr create --base main` (or `gh pr edit`) and write a single row with `Phase` = `single`.

## Phase 4: Persist `<FEATURE_DIR>/split-report.md` (FR-019a)

Overwrite `<FEATURE_DIR>/split-report.md` per the contract in `specs/008-feat-multi-phase-deploys/contracts/split-report.md`:

- Header row, in this exact order:

  ```markdown
  | Phase | Status | Branch | PR URL | Reason |
  | ----- | ------ | ------ | ------ | ------ |
  ```

- One row per phase enumerated by the run, in deploy order.
- `Status` is one of `created`, `updated`, `unchanged`, `skipped-merged`, `gated`, `failed`.
- For multi-phase, `Phase` is the integer phase number; for single-phase, `Phase` is the literal `single`.
- Pipe characters in cell values MUST be escaped as `\|` so `awk -F '|'` parses cleanly.
- The file MUST be overwritten in full on every run; never appended to.

After writing the file, mirror a concise per-phase summary to stdout (one line per phase) so a human running the command sees the outcome immediately.

## Failure handling (FR-017 fail-fast)

| Failure mode | Action |
| --- | --- |
| `git fetch origin main` fails | Write a single `failed` row (`Phase`=`single`, `Branch`=`-`, `PR URL`=`-`); STOP before any branch is touched |
| Review report missing | Refuse to run with the exact message above; do NOT write a split report; instruct the author to run `/speckit.marge.review` |
| Cherry-pick conflict on phase K | Abort the cherry-pick; write a `failed` row for phase K; STOP. Conflict resolution is manual; the next idempotent re-run resumes from phase K |
| `gh pr create` / `gh pr edit` fails on phase K | Write a `failed` row for phase K with the `gh` stderr; STOP |
| `git push --force-with-lease` rejected (concurrent remote change) | Write a `failed` row for phase K; STOP. Author must reconcile manually |

In every fail-fast case, phase branches and pull requests built earlier in the same run remain in their successfully-completed state. The next idempotent re-run resumes from the failed phase.

## Idempotent re-run contract (FR-017)

- Re-running with no input changes produces an `unchanged` row for every phase.
- Adding a phase-K commit causes phase K and every downstream phase to report `updated`.
- Removing a commit from a phase causes the affected phase to be rebuilt to the shrunk commit set without orphans.
- The `skipped-merged` status protects already-merged phase branches from being rewritten.

## Guardrails

| #   | Rule                                                                                                |
| --- | --------------------------------------------------------------------------------------------------- |
| 999 | **Single-shot** — Run the split step once and exit; never loop                                      |
| 998 | **Pre-flight is mandatory** — Refuse to run when the persisted review report is missing            |
| 997 | **Trust the review report** — Never re-verify FR-010 invariants; the persisted report is the truth |
| 996 | **Idempotent rebuild** — Use `reset --hard` + `cherry-pick` + `--force-with-lease` deterministically |
| 995 | **Fail fast** — On the first error, write a `failed` row and STOP; later phases wait for the re-run |
| 994 | **Persist split-report.md** — Overwrite `<FEATURE_DIR>/split-report.md` on every run; never append   |
| 993 | **Skipped-merged is sacred** — Never rewrite a phase branch whose PR is already merged into `main`   |

## File Paths

- Plan (multi-phase signal): `<FEATURE_DIR>/plan.md` — read for `## Deploy Phases` section (FR-002)
- Review report (gating source of truth): `<FEATURE_DIR>/review-report.md` — read for unresolved high-severity findings (FR-018)
- Split report (persisted output): `<FEATURE_DIR>/split-report.md` — overwritten on every run (FR-019a)
- Command file (executable instruction sequence): `speckit-commands/speckit.split.md` (installed at `.claude/commands/speckit.split.md`)
- Behavior contract: `specs/008-feat-multi-phase-deploys/contracts/split-command.md`
- Split-report schema: `specs/008-feat-multi-phase-deploys/contracts/split-report.md`
- Review-report schema: `specs/008-feat-multi-phase-deploys/contracts/review-report.md`
- Migration-safety check pack: `.specify/marge/checks/migrations.md`
