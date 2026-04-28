# Quickstart: Multi-Phase Deploy Support

## Overview

This feature adds multi-phase deploy support to the SpecKit + Simpsons-loops pipeline so a single feature can ship as a stack of independently-deployable pull requests. The pipeline runs end to end on a single feature branch, then a new **split** step groups commits by `Phase: N` git trailer and opens stacked pull requests with the correct base-branch chain.

Multi-phase mode is detected structurally: the presence of a `## Deploy Phases` section in `plan.md` is the sole signal. No flag, environment variable, or config file is introduced. Single-phase features keep working unchanged — exactly one pull request, no phase trailers, no per-phase findings.

The implementation surface:

- One new check pack: `.specify/marge/checks/migrations.md`.
- One new command file: `speckit-commands/speckit.split.md`.
- One new agent file: `claude-agents/split.md`.
- Targeted modifications to four existing command files (`speckit.pipeline.md`, `speckit.ralph.implement.md`, `speckit.marge.review.md`) and four existing agent files (`plan.md`, `tasks.md`, `ralph.md`, `marge.md`).
- Template updates to `.specify/templates/plan-template.md`, `.specify/templates/tasks-template.md`, and `templates/CLAUDE.md`.
- A README mention.

No new bash scripts. No changes to `.specify/scripts/bash/`. No changes to the constitution. The setup script (`setup.sh`) requires no changes — its existing idempotent check-pack seeding loop picks up `migrations.md` automatically (FR-024).

## Implementation Order

The work is structured into seven implementation phases that can be tackled top-to-bottom. Each phase is independently testable; later phases build on earlier ones.

### Phase A: Migration-safety check pack (FR-009, FR-010, FR-023, FR-024)

**File**: `.specify/marge/checks/migrations.md` (new)

Author the migration-safety check pack covering the eight production-breaking patterns (M1-M8) and the four structural-consistency patterns (S1-S4) per data-model.md and research.md R-007. Every cataloged pattern emits at `high` severity. The pack follows the existing check-pack format used by `architecture.md`, `generic-bugs.md`, `security.md`, and `testing.md` (rule statement, severity, signal, fix suggestion, optional NEEDS_HUMAN tag).

**Acceptance**: Marge picks up the new pack automatically on the next review run (no agent-discovery code changes required per FR-023). `setup.sh` seeds the pack into a downstream consumer project on a fresh install (the existing idempotent loop covers it per FR-024).

### Phase B: Plan agent multi-phase emission (FR-001, FR-002, FR-003, FR-026)

**Files**:
- `claude-agents/plan.md` (modified) — instruct the plan agent to emit a `## Deploy Phases` section when the heuristics fire (schema migration combined with reads/writes on the same data, breaking API change, multi-service rollout coordination).
- `.specify/templates/plan-template.md` (modified) — document the optional `## Deploy Phases` section with a worked example.

**Acceptance**: Running `/speckit.plan` against a synthetic feature description that requires phased rollout (e.g., "rename `users.email_address` column to `users.email`") produces a `plan.md` with a `## Deploy Phases` section enumerating phases 1..N with goal and post-deploy state for each. Running `/speckit.plan` against a single-phase feature (the vast majority) produces no `## Deploy Phases` section.

### Phase C: Tasks agent phase-tagging and Stages relabel (FR-004, FR-005, FR-027)

**Files**:
- `claude-agents/tasks.md` (modified) — when `plan.md` contains `## Deploy Phases`, organize `tasks.md` by deploy phase at the top level (`##`), nest the existing Setup/Foundational/User-Stories structure as `### Stage:` headings inside each phase, and tag every task `[phase-K]`. For single-phase features, preserve today's template unchanged.
- `.specify/templates/tasks-template.md` (modified) — document the multi-phase top-level structure and phase tagging.

**Acceptance**: For a multi-phase feature, every task in `tasks.md` carries `[phase-N]` and tasks are organized under per-phase top-level sections with `### Stage:` headings nested inside (empty stages omitted). For a single-phase feature, the template is unchanged.

### Phase D: Ralph phase-trailer commits (FR-006, FR-007, FR-008)

**Files**:
- `claude-agents/ralph.md` (modified) — when implementing a task whose tasks.md entry has `[phase-N]`, append `Phase: N` git trailer to the commit message. When the task has no phase tag, commit without the trailer.
- `speckit-commands/speckit.ralph.implement.md` (modified) — corresponding command-file changes if any (the agent file does most of the work; the command file may reference the trailer convention).

**Acceptance**: Running Ralph on a multi-phase feature produces commits whose messages each carry a `Phase: N` trailer matching the task's phase tag. Running Ralph on a single-phase feature produces commits without trailers (FR-007). All implementation occurs on a single feature branch end to end (FR-008).

### Phase E: Marge migration-safety pack loading and review-report persistence (FR-009, FR-011, FR-012, FR-012a, FR-023)

**Files**:
- `claude-agents/marge.md` (modified) — when the feature is multi-phase, emit per-phase finding tags; persist `<FEATURE_DIR>/review-report.md` on every run with the exact column schema in the contracts/review-report.md document.
- `speckit-commands/speckit.marge.review.md` (modified) — corresponding command-file changes for the persisted-report writeout.

**Acceptance**: Running Marge on a multi-phase feature produces `<FEATURE_DIR>/review-report.md` with one row per finding, columns `| ID | Severity | Phase | Status | Check Pack | Summary |`, FR-010 patterns at `high` severity, structural inconsistencies (S3, S4) with Phase column `-`. Running Marge on a single-phase feature produces the same report with Phase column `-` for every row. The migration-safety check pack is loaded automatically when present.

### Phase F: Split command and agent (FR-013, FR-014, FR-015, FR-016, FR-017, FR-018, FR-019, FR-019a)

**Files**:
- `speckit-commands/speckit.split.md` (new) — the split-step command.
- `claude-agents/split.md` (new) — agent definition for the split step.

The split step is a deterministic function of `(feature branch commits with Phase: trailers, plan.md Deploy Phases section, review-report.md, origin/main after fetch)`. It implements the contract in `contracts/split-command.md`:

1. Resolve `FEATURE_DIR` via `bash .specify/scripts/bash/check-prerequisites.sh --json --paths-only`.
2. Verify `<FEATURE_DIR>/review-report.md` exists; refuse to run otherwise.
3. Run `git fetch origin main`; fail fast on fetch error.
4. Detect multi-phase by `grep -q '^## Deploy Phases$' <FEATURE_DIR>/plan.md`.
5. Parse `review-report.md` for unresolved high-severity findings; build `gating_phases` and `global_gate`.
6. For each phase K in 1..N (multi-phase) or for the single phase (single-phase):
   - Compute `phase_branch_name`, `base`, `phase_commits`, `expected_title`, `expected_body` per FR-015 and FR-016.
   - Check `skipped-merged` (PR already merged into `origin/main`).
   - Check `gated` (per FR-018; global gate gates every phase).
   - Build/update phase branch via `git reset --hard <base>` + `git cherry-pick` + `git push --force-with-lease`.
   - Create or update PR via `gh pr create` / `gh pr edit`.
   - Fail fast on first error (FR-017); leave completed phases in place.
7. Persist `<FEATURE_DIR>/split-report.md` with one row per phase enumerated; mirror summary to stdout.

**Acceptance**: For a synthetic multi-phase column-rename feature, the split step produces 4 stacked branches (`-phase1`, `-phase2`, `-phase3`, `-phase4`) and 4 PRs with the correct base-branch chain. For a single-phase feature (`001-consistency-cleanup`), the split step opens exactly one PR against `main` (no extra branches). Re-running with no changes yields all `unchanged` rows and zero remote state changes (SC-005). Re-running after one new commit on phase 2 updates phase-2 (and downstream phase-3, phase-4 transitively) in place.

### Phase G: Pipeline orchestration of the split step (FR-020, FR-021)

**File**: `speckit-commands/speckit.pipeline.md` (modified)

Append a post-marge split step. After Marge completes (whether by reaching `<promise>ALL_FINDINGS_RESOLVED</promise>` or by hitting max iterations), spawn a fresh agent to invoke `/speckit.split` with the resolved `FEATURE_DIR`. Detect multi-phase from `plan.md`'s `## Deploy Phases` section; the split step itself handles both modes, but the orchestrator's status table (Step 6a) MUST reflect the new step.

**Acceptance**: The pipeline now runs specify -> homer -> plan -> tasks -> lisa -> ralph -> [simplify] -> [security-review] -> marge -> split end to end. The pipeline's status table includes the split step. Re-running the pipeline against a single-phase feature produces output identical in shape to today (one branch, one PR, no phase trailers, no per-phase findings).

### Phase H: Documentation (FR-025, FR-028)

**Files**:
- `templates/CLAUDE.md` (modified) — short section on multi-phase deploys: when to use, how it's authored, how to read the resulting PR stack.
- `README.md` (modified) — add multi-phase to the feature list with a one-paragraph description and a link to `.specify/marge/checks/migrations.md`.

**Acceptance**: A new author reading the project README and the downstream-consumer template can determine whether a feature they are about to write needs multi-phase deploys, and if so, how to author it, without consulting any other documentation (SC-007).

## Verification Checklist

These checks correspond directly to the spec's User Stories and Success Criteria. Run them against a real multi-phase feature in this repo's `specs/` after Phases A-H complete.

### V-001: Single-phase regression (User Story 3, SC-003)

- [ ] Run `/speckit.pipeline specs/001-consistency-cleanup --from plan` (or pick another existing single-phase feature).
- [ ] Confirm `plan.md` does NOT acquire a `## Deploy Phases` section.
- [ ] Confirm `tasks.md` carries no `[phase-N]` tags.
- [ ] Confirm Ralph commits have no `Phase:` trailers (`git log origin/main..HEAD --format='%(trailers:key=Phase,valueonly)'` returns empty for every commit).
- [ ] Confirm Marge produces `review-report.md` with Phase column `-` for every row.
- [ ] Confirm the split step opens exactly one PR against `main` and creates no extra branches.
- [ ] Confirm `split-report.md` contains exactly one row with `Phase` = `single`.

### V-002: Multi-phase happy path (User Story 1, SC-001, SC-002)

- [ ] Author a synthetic feature description: "rename `users.email_address` column to `users.email`".
- [ ] Run the full pipeline.
- [ ] Confirm `plan.md` has a `## Deploy Phases` section enumerating 4 phases (add → dual-write → switch reads → drop old) with goal and post-deploy state for each (FR-001).
- [ ] Confirm `tasks.md` is organized by deploy phase at the top level (`##`), with `### Stage:` headings nested inside each, and every task carries `[phase-K]` (FR-004, FR-005).
- [ ] Confirm `git log origin/main..HEAD --format='%(trailers:key=Phase,valueonly)' | sort -u` returns `1\n2\n3\n4` (FR-006).
- [ ] Confirm Marge's `review-report.md` carries findings (or none) tagged by phase.
- [ ] Confirm the split step produces 4 stacked branches `<feature>-phase1` ... `<feature>-phase4` (FR-015).
- [ ] Confirm `gh pr list` shows 4 PRs with the correct base-branch chain: `main <- phase1 <- phase2 <- phase3 <- phase4` (FR-016).
- [ ] Confirm each phase pull request's title is `[Phase K/4] <feature-branch-name>` and the body matches the FR-016 template (Part-of line, Phase Goal, Post-deploy production state, Stack list with `(this PR)` on the current phase).
- [ ] Confirm `split-report.md` contains 4 rows with `Status` = `created` and the correct branch names and PR URLs.

### V-003: Migration-safety pack catches every FR-010 pattern (User Story 2, SC-004)

- [ ] Author a deliberately-broken plan that exhibits every FR-010 pattern in distinct phases (M1 NOT NULL without default, M2 column drop while prior-phase reads it, M3 rename in single phase, M4 long-transaction backfill on hot table, M5 missing index, M6 schema + dependent code in same phase, M7 removed function with prior-phase callers, M8 per-phase deployability violation).
- [ ] Run Marge.
- [ ] Confirm every FR-010 pattern is reported as a `high`-severity finding tagged to the offending phase in `review-report.md`.
- [ ] Confirm the structural-consistency patterns (S1 orphan tag, S2 non-contiguous, S3 malformed trailer, S4 phase-trailer-without-deploy-phases) are emitted with Phase column set per the spec clarifications.
- [ ] Run the split step.
- [ ] Confirm the split step refuses to open or update PRs for the gated phases and emits `gated` rows in `split-report.md` citing the finding IDs (FR-018).

### V-004: Idempotent re-run (User Story 4, SC-005)

- [ ] After V-002 completes, re-run `/speckit.split` with no changes.
- [ ] Confirm every row in `split-report.md` is `unchanged`.
- [ ] Confirm zero remote state changes (no force-pushes, no `gh pr edit` calls).
- [ ] Add one new phase-tagged commit to phase 2 of the feature branch.
- [ ] Re-run `/speckit.split`.
- [ ] Confirm phase-1 reports `unchanged`, phase-2 reports `updated`, phases 3 and 4 report `updated` (because their bases moved).
- [ ] Confirm no duplicate branches or PRs were created.
- [ ] Remove a commit from phase 2 of the feature branch (rebase or amend).
- [ ] Re-run `/speckit.split`.
- [ ] Confirm phase-2 reports `updated` and the phase-2 branch reflects the shrunk commit set without orphaned commits.

### V-005: `skipped-merged` protection (Edge case, FR-017)

- [ ] After V-002, merge phase 1 into `main` (e.g., via `gh pr merge`).
- [ ] Modify a phase-1-tagged commit on the feature branch (e.g., add a no-op change via amend).
- [ ] Re-run `/speckit.split`.
- [ ] Confirm phase-1 reports `skipped-merged` with a reason citing the merged state.
- [ ] Confirm the merged phase-1 branch on the remote is unchanged (no force-push attempted).

### V-006: Failure on cherry-pick conflict (Edge case)

- [ ] Author a multi-phase feature where two phase-tagged commits modify the same line.
- [ ] Run `/speckit.split`.
- [ ] Confirm the split step writes a `failed` row for the offending phase with a reason naming the conflict.
- [ ] Confirm earlier phases that already completed remain in their successful state.
- [ ] Resolve the conflict manually, re-run `/speckit.split`.
- [ ] Confirm the run resumes from the failed phase.

### V-007: Failure on `gh pr create` (Edge case)

- [ ] Simulate a `gh pr create` failure (e.g., revoke `gh` auth temporarily on a multi-phase feature).
- [ ] Run `/speckit.split`.
- [ ] Confirm the split step writes a `failed` row citing the `gh` error and STOPS.
- [ ] Confirm earlier phases remain successfully created.
- [ ] Restore `gh` auth, re-run `/speckit.split`.
- [ ] Confirm the previously-failed phase and downstream phases complete successfully.

### V-008: `origin/main` canonical base (FR-013)

- [ ] On a working copy whose local `main` lags behind `origin/main` by several commits, run `/speckit.split`.
- [ ] Confirm the split step's commit enumeration uses `git log origin/main..HEAD` (after fetch), not `git log main..HEAD`.
- [ ] Confirm the resulting stack matches what a fresh clone of the same feature branch would produce.
- [ ] Simulate a `git fetch origin main` failure (e.g., remove network access).
- [ ] Run `/speckit.split`.
- [ ] Confirm a single `failed` row is written with reason naming the fetch failure, and no branches are touched.

### V-009: Pull-request title and body are pipeline-managed (FR-016)

- [ ] After V-002, manually edit the title or body of one phase pull request via `gh pr edit`.
- [ ] Re-run `/speckit.split`.
- [ ] Confirm the manually-edited title/body is overwritten by the deterministic computed value.
- [ ] Confirm the corresponding split-report row is `updated` (not `unchanged`), because the title/body comparison detected the drift.

### V-010: README and downstream-consumer documentation (SC-007)

- [ ] Read `README.md`. Confirm multi-phase deploys is listed in the feature list with a one-paragraph description and a link to `.specify/marge/checks/migrations.md`.
- [ ] Read `templates/CLAUDE.md`. Confirm a section describes when to use multi-phase deploys, how a multi-phase feature is authored, and how to read the resulting PR stack.
- [ ] Hand the README and `templates/CLAUDE.md` to a new author. Confirm they can determine whether a feature they are about to write needs multi-phase deploys, and if so, how to author it, without consulting any other documentation (subjective, but the spec's SC-007 is the bar).

### V-011: Resumability (Pipeline regression)

- [ ] Kill `/speckit.pipeline` mid-Ralph on a multi-phase feature.
- [ ] Re-run with the same args.
- [ ] Confirm the pipeline picks up where it left off (existing pipeline behavior MUST not regress).

### V-012: Process hygiene (CLAUDE.md "Process Cleanup")

- [ ] Before declaring V-001 through V-011 complete, run `pgrep -f "vite|webpack-dev-server|next dev|rails s|claude"` and confirm no orphaned processes.
- [ ] Run `docker ps` and confirm no stray containers from this session.

## Pre-flight (before starting implementation)

Confirm the source-of-truth directories exist and are writable:

```bash
test -d speckit-commands && echo "speckit-commands OK"
test -d claude-agents && echo "claude-agents OK"
test -d .specify/marge/checks && echo "marge checks OK"
test -d .specify/templates && echo "templates OK"
test -d templates && echo "downstream-consumer template OK"
```

Confirm the existing utilities the split step relies on are present:

```bash
command -v git && echo "git OK"
command -v gh && echo "gh OK"
gh auth status && echo "gh authenticated"
test -f .specify/scripts/bash/check-prerequisites.sh && echo "check-prerequisites.sh OK"
test -f .specify/quality-gates.sh && echo "quality-gates.sh OK"
```

Confirm Git supports trailer extraction (Git 2.32+):

```bash
git --version
git log -1 --format='%(trailers:key=Phase,valueonly)' >/dev/null && echo "trailer extraction OK"
```

After every implementation phase, re-run the relevant verification check (V-001 through V-012) to keep the work bisectable.

## Source vs installed file reminder

Per CLAUDE.md "Source vs Installed Files": always edit the source-of-truth files in `speckit-commands/`, `claude-agents/`, `.specify/marge/checks/`, `.specify/templates/`, and `templates/`. Never edit `.claude/commands/*.md` or `.claude/agents/*.md` directly — those are installed copies overwritten by `setup.sh`. After each source-file edit, run `setup.sh` (from a downstream consumer for real testing) or copy to `.claude/` manually for in-repo dogfooding.
