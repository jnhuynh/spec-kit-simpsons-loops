# Contract: `/speckit.split` Command

## Purpose

The split step groups the feature branch's commits by `Phase: N` git trailer, builds stacked phase branches `NNNN-<type>-<slug>-phaseK`, and opens stacked pull requests with the correct base-branch chain. For single-phase features (no `## Deploy Phases` section in `plan.md`), the split step opens exactly one pull request against `main`, matching today's behavior.

## Invocation

The split step is invoked via the slash command `/speckit.split` from `.claude/commands/speckit.split.md` (source of truth: `speckit-commands/speckit.split.md`). The pipeline orchestrator (`speckit.pipeline.md`) calls this command after Marge completes.

### Inputs

| Input | Source | Description |
|---|---|---|
| `FEATURE_DIR` | `bash .specify/scripts/bash/check-prerequisites.sh --json --paths-only` | Resolved by the pipeline orchestrator and passed to the split step |
| `plan.md` | `<FEATURE_DIR>/plan.md` | Read for the `## Deploy Phases` section (multi-phase detection signal) |
| `review-report.md` | `<FEATURE_DIR>/review-report.md` | Read for unresolved high-severity findings (gating per FR-018) |
| Feature branch | Current Git branch | Source of phase-trailered commits |
| `origin/main` | Remote-tracking ref refreshed by `git fetch origin main` | Canonical base for commit enumeration, phase 1 cherry-pick, and idempotent rebuild |

### Outputs

| Output | Destination | Description |
|---|---|---|
| Phase branches | Git remote (`origin`) | `NNNN-<type>-<slug>-phaseK` for K in 1..N (multi-phase); none beyond the feature branch (single-phase) |
| Pull requests | GitHub repository | `[Phase K/N] <feature-branch-name>` (multi-phase); `<feature-branch-name>` (single-phase) |
| `split-report.md` | `<FEATURE_DIR>/split-report.md` | Persisted outcome report; overwritten on every run |
| stdout | Terminal | Concise human-readable summary mirroring the split-report rows |

## Behavior

### Pre-flight

1. **Resolve `FEATURE_DIR`** via `bash .specify/scripts/bash/check-prerequisites.sh --json --paths-only`.
2. **Verify review report exists**: if `<FEATURE_DIR>/review-report.md` is missing, refuse to run with the message: `Review report not found at <FEATURE_DIR>/review-report.md. Run /speckit.marge.review first.` Do NOT write a split report; do NOT touch any branches.
3. **Refresh `origin/main`**: run `git fetch origin main`. If the fetch fails, write a single `failed` row to `split-report.md` with reason `Failed to fetch origin/main: <error>` and STOP. Do NOT touch any branches.
4. **Detect multi-phase**: run `grep -q '^## Deploy Phases$' <FEATURE_DIR>/plan.md`. If present, multi-phase mode; otherwise single-phase mode.
5. **Parse review report**: extract unresolved high-severity findings from `<FEATURE_DIR>/review-report.md` via `awk -F '|'` (locate the table by its exact header row `| ID | Severity | Phase | Status | Check Pack | Summary |`). Build:
   - `gating_phases`: set of integer phase numbers with at least one unresolved high-severity finding.
   - `global_gate`: true if any unresolved high-severity finding has Phase column `-` (multi-phase) or any unresolved high-severity finding exists at all (single-phase).

### Multi-phase execution

For each phase K in 1..N (where N is the count of entries in the plan's `## Deploy Phases` section):

1. **Determine target state**:
   - `phase_branch_name` = `<feature-branch-name>-phaseK`
   - `base` = `origin/main` if K=1; `<feature-branch-name>-phase(K-1)` if K>1
   - `phase_commits` = commits on the feature branch with `Phase: K` trailer (or no trailer for K=1, per FR-014), enumerated via `git log origin/main..HEAD --reverse --format='%H %(trailers:key=Phase,valueonly)'` and grouped by phase number.
   - `expected_title` = `[Phase K/N] <feature-branch-name>`
   - `expected_body` = the deterministic body per FR-016 (see body composition below)
2. **Check `skipped-merged`**: if a remote branch `phase_branch_name` exists AND its corresponding pull request is already merged into `origin/main`, write a `skipped-merged` row and continue to phase K+1. Do NOT rebuild.
3. **Check `gated`**:
   - If `global_gate` is true, write a `gated` row with reason citing the global-gate finding and continue to phase K+1.
   - Otherwise if K is in `gating_phases`, write a `gated` row with reason citing the phase-K finding(s) and continue to phase K+1.
4. **Build/update phase branch**:
   - If the phase branch does not exist on the remote: create it via `git checkout -B phase_branch_name`, `git reset --hard <base>`, `git cherry-pick <phase_commits>`, then `git push origin phase_branch_name`. Write a `created` row.
   - If the phase branch exists on the remote: rebuild via `git checkout -B phase_branch_name`, `git reset --hard <base>`, `git cherry-pick <phase_commits>`. If the resulting branch SHA equals the existing remote SHA AND the existing PR title and body match the recomputed values, write an `unchanged` row. Otherwise force-push via `git push --force-with-lease origin phase_branch_name` and write an `updated` row.
5. **Create or update pull request**:
   - If no pull request exists for the phase branch: open one via `gh pr create --base <base-branch-without-origin-prefix> --head phase_branch_name --title "<expected_title>" --body "<expected_body>"`. Capture the PR URL.
   - If a pull request exists: fetch its current title and body via `gh pr view --json title,body`. If either differs from `expected_title` / `expected_body`, overwrite via `gh pr edit --title "<expected_title>" --body "<expected_body>"`.
6. **Fail fast**: if any step in 4-5 returns a non-zero exit, write a `failed` row with reason and STOP. Subsequent phases are NOT processed in this run; they will be processed on the next idempotent re-run.

### Single-phase execution

If the plan has no `## Deploy Phases` section:

1. **Check `gated`** using the global-gate rule (any unresolved high-severity finding gates the single PR per FR-019). If gated, write a single `gated` row with `Phase` = `single`, `Branch` = `<feature-branch-name>`, `PR URL` = `-`, and a reason citing the finding(s).
2. **Otherwise open or update the single pull request**:
   - `expected_title` = `<feature-branch-name>`
   - `expected_body` = `Part of <FEATURE_DIR>/spec.md` (path relative to repo root)
   - If no pull request exists for the feature branch: open one via `gh pr create --base main --head <feature-branch-name> --title "<expected_title>" --body "<expected_body>"`. Write a `created` row.
   - If a pull request exists: fetch via `gh pr view --json title,body`. If either differs, overwrite via `gh pr edit`. Write `updated`. Otherwise write `unchanged`.

### Body composition for multi-phase pull requests

The body is a deterministic GitHub Flavored Markdown document composed of:

```markdown
Part of <FEATURE_DIR>/spec.md

## Phase Goal

<goal text copied verbatim from the corresponding plan entry>

## Post-deploy production state

<post-deploy state text copied verbatim from the same plan entry>

## Stack

- Phase 1: NNNN-<type>-<slug>-phase1
- Phase 2: NNNN-<type>-<slug>-phase2 (this PR)
- Phase 3: NNNN-<type>-<slug>-phase3
- Phase 4: NNNN-<type>-<slug>-phase4
```

The ` (this PR)` suffix is appended only to the bullet whose phase number equals the PR's own phase number.

For single-phase features, the body is just the first line: `Part of <FEATURE_DIR>/spec.md`.

### Idempotent re-runs

The split step is idempotent: re-running with the same inputs produces no remote state changes (`unchanged` rows). When the feature branch's commit set changes (commits added, removed, or amended), the next run rebuilds the affected phase branches via `git reset --hard <base>` + `git cherry-pick` + `git push --force-with-lease`. Phase branches are pipeline-managed; humans MUST NOT commit directly to them.

### Failure handling

| Failure mode | Action |
|---|---|
| `git fetch origin main` fails | Write single `failed` row; STOP before any branch is touched |
| Review report missing | Refuse to run; do NOT write a split report; instruct author to run `/speckit.marge.review` |
| Cherry-pick conflict on phase K | Write `failed` row for phase K with the conflict description; STOP. Conflict resolution is a manual step in this iteration |
| `gh pr create` fails on phase K | Write `failed` row for phase K with the `gh` error; STOP. Phase K-1 and earlier remain in their successfully-completed state |
| `gh pr edit` fails on phase K | Same as `gh pr create` failure |
| `git push --force-with-lease` rejected (concurrent remote change) | Write `failed` row for phase K with reason; STOP. Author must reconcile manually |

### Examples

**Multi-phase 4-phase feature, fresh run, no findings**:

```
| Phase | Status   | Branch                                      | PR URL                                  | Reason |
| ----- | -------- | ------------------------------------------- | --------------------------------------- | ------ |
| 1     | created  | 008-feat-multi-phase-deploys-phase1         | https://github.com/org/repo/pull/123    | -      |
| 2     | created  | 008-feat-multi-phase-deploys-phase2         | https://github.com/org/repo/pull/124    | -      |
| 3     | created  | 008-feat-multi-phase-deploys-phase3         | https://github.com/org/repo/pull/125    | -      |
| 4     | created  | 008-feat-multi-phase-deploys-phase4         | https://github.com/org/repo/pull/126    | -      |
```

**Multi-phase re-run after one new commit on phase 2**:

```
| Phase | Status    | Branch                                      | PR URL                                  | Reason |
| ----- | --------- | ------------------------------------------- | --------------------------------------- | ------ |
| 1     | unchanged | 008-feat-multi-phase-deploys-phase1         | https://github.com/org/repo/pull/123    | -      |
| 2     | updated   | 008-feat-multi-phase-deploys-phase2         | https://github.com/org/repo/pull/124    | New commit added to phase 2; rebuilt and force-pushed |
| 3     | updated   | 008-feat-multi-phase-deploys-phase3         | https://github.com/org/repo/pull/125    | Rebased onto updated phase 2 |
| 4     | updated   | 008-feat-multi-phase-deploys-phase4         | https://github.com/org/repo/pull/126    | Rebased onto updated phase 3 |
```

**Multi-phase run gated by phase-2 finding**:

```
| Phase | Status | Branch                                      | PR URL                                  | Reason |
| ----- | ------ | ------------------------------------------- | --------------------------------------- | ------ |
| 1     | unchanged | 008-feat-multi-phase-deploys-phase1      | https://github.com/org/repo/pull/123    | -      |
| 2     | gated  | 008-feat-multi-phase-deploys-phase2         | -                                       | Unresolved high-severity finding F003 (M3 rename in single phase) |
| 3     | gated  | 008-feat-multi-phase-deploys-phase3         | -                                       | Phase 2 is gated; downstream phases blocked until phase 2 finding resolves |
| 4     | gated  | 008-feat-multi-phase-deploys-phase4         | -                                       | Phase 2 is gated; downstream phases blocked until phase 2 finding resolves |
```

**Single-phase happy path**:

```
| Phase  | Status  | Branch                          | PR URL                                  | Reason |
| ------ | ------- | ------------------------------- | --------------------------------------- | ------ |
| single | created | 001-consistency-cleanup         | https://github.com/org/repo/pull/127    | -      |
```

## Postconditions

- `<FEATURE_DIR>/split-report.md` exists and contains exactly one row per phase enumerated by the run (or one row with `Phase` = `single` for single-phase features).
- For every `created` row: a phase branch exists on the remote with the expected commit set, and a corresponding pull request is open.
- For every `updated` row: the phase branch's remote SHA matches the recomputed SHA, and the pull request's title and body match the recomputed values.
- For every `unchanged` row: no remote state changed.
- For every `skipped-merged` row: the phase branch's pull request remains in its merged state; no rewrite occurred.
- For every `gated` row: no pull request was created or modified for this phase; the gating finding's ID is cited in the Reason column.
- For every `failed` row: the failure reason is cited; the run halted before processing later phases.

## Permissions / external commands required

| Command | Purpose | Already permitted in repo? |
|---|---|---|
| `git fetch`, `git log`, `git checkout`, `git reset`, `git cherry-pick`, `git push --force-with-lease` | Branch manipulation | Yes (Git is permitted) |
| `gh pr create`, `gh pr edit`, `gh pr view` | Pull-request management | Yes (gh is permitted) |
| `awk`, `grep`, `sed`, `test` | Report parsing and assertions | Yes (standard Unix tools) |
| `bash .specify/scripts/bash/check-prerequisites.sh --json --paths-only` | FEATURE_DIR resolution | Yes (existing utility) |
