# Tasks: Multi-Phase Deploy Support

**Input**: Design documents from `/specs/008-feat-multi-phase-deploys/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/, quickstart.md

**Tests**: Not requested. Per plan.md "Constitution Check / Test-First Development", this feature modifies declarative markdown command/agent/template files only — no executable code units. Verification is via the quickstart.md checklist (V-001 through V-012) covering single-phase regression, multi-phase happy path, migration-safety pack coverage, idempotent re-run, and edge cases. Following the same pattern as 005-fix-subagent-quality-gates and 006-stop-after-param.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3, US4)
- Include exact file paths in descriptions

## Path Conventions

Source-of-truth files (per CLAUDE.md "Source vs Installed Files"):

- Slash commands: `speckit-commands/*.md` (installed copies in `.claude/commands/` are overwritten by `setup.sh`)
- Agent definitions: `claude-agents/*.md` (installed copies in `.claude/agents/` are overwritten by `setup.sh`)
- Marge check packs: `.specify/marge/checks/*.md` (seeded into downstream consumers idempotently by `setup.sh`)
- SpecKit templates: `.specify/templates/*.md`
- Downstream-consumer template: `templates/CLAUDE.md`

Always edit the source-of-truth files. Never edit `.claude/commands/*.md` or `.claude/agents/*.md` directly.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Confirm the source-of-truth directories and tooling required by every later phase are present and functioning.

- [x] T001 Run pre-flight checks from `specs/008-feat-multi-phase-deploys/quickstart.md` ("Pre-flight" section) to confirm `speckit-commands/`, `claude-agents/`, `.specify/marge/checks/`, `.specify/templates/`, and `templates/` exist; confirm `git` (2.32+ for trailer extraction), `gh` (authenticated), and `.specify/scripts/bash/check-prerequisites.sh` are available

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Build the migration-safety check pack and the persisted review-report format. These are blocking prerequisites for the split step (US1, US2, US4) and for Marge's per-phase finding emission (US2). They must be in place before any user-story work because the split step gates on `<FEATURE_DIR>/review-report.md` per FR-018 and refuses to run when the file is missing.

**CRITICAL**: No user story work can begin until this phase is complete.

- [x] T002 [P] Create migration-safety check pack at `.specify/marge/checks/migrations.md` covering the eight production-breaking patterns M1-M8 (NOT NULL without default, column drop while prior-phase reads, single-phase rename, long-transaction backfill on hot table, missing index for new read path, schema-plus-dependent-code in same phase, removed function with prior-phase callers, per-phase deployability) and the four structural-consistency patterns S1-S4 (orphan phase tag, non-contiguous phases, malformed `Phase:` trailer, phase-trailer-without-deploy-phases) per research.md R-007 and data-model.md "Migration-Safety Check Pack"; every cataloged M*/S* entry MUST emit at `high` severity per FR-010; pack format follows the existing `architecture.md`, `generic-bugs.md`, `security.md`, `testing.md` style (rule statement, severity, signal, fix suggestion, optional NEEDS_HUMAN tag) (FR-009, FR-010, FR-023, FR-024)
- [x] T003 [P] Modify `claude-agents/marge.md` to persist `<FEATURE_DIR>/review-report.md` on every run with the exact GFM table schema `| ID | Severity | Phase | Status | Check Pack | Summary |` per `specs/008-feat-multi-phase-deploys/contracts/review-report.md` and FR-012a; assign stable per-finding IDs reused across runs against the same branch state; emit new findings as `open` and transition to `resolved` only when a subsequent run confirms the issue is gone; escape pipe characters in cell values as `\|` so `awk -F '|'` parses cleanly; overwrite any prior copy on every run (FR-012, FR-012a)
- [x] T004 [P] Modify `speckit-commands/speckit.marge.review.md` to mirror the agent's review-report persistence: instruct the review command to write `<FEATURE_DIR>/review-report.md` with the FR-012a schema; reference the same persisted-report contract used by `claude-agents/marge.md` (FR-012a)

**Checkpoint**: Migration-safety check pack exists; Marge persists `review-report.md` on every run with the FR-012a schema. User stories can now proceed.

---

## Phase 3: User Story 1 — Author a multi-phase feature end to end (Priority: P1) MVP

**Goal**: A spec author can take a feature description that requires phased rollout (such as a column rename) and produce a working stack of pull requests through the pipeline without manually editing branches, commit messages, or PR base-branch references.

**Independent Test**: Run the full pipeline against a synthetic feature description ("rename `users.email_address` column to `users.email`") and verify the pipeline produces (a) a single spec, (b) a plan with a `## Deploy Phases` section enumerating four phases, (c) a tasks list where every task is tagged `[phase-N]`, (d) a feature branch whose commits each carry a `Phase: N` git trailer, and (e) a stack of four pull requests with the correct base-branch chain (`main <- phase1 <- phase2 <- phase3 <- phase4`).

### Implementation for User Story 1

- [x] T005 [US1] Modify `claude-agents/plan.md` to emit a `## Deploy Phases` section in `plan.md` when the multi-phase heuristics fire (schema migration combined with reads/writes on the same data, breaking API change, multi-service rollout coordination); render every phase entry in the canonical machine-parseable format pinned by FR-001 and the data-model "Deploy Phase" canonical example — `### Phase K: <title>` heading followed by `**Goal**: <text>` and `**Post-deploy production state**: <text>` labelled fields; phases are totally ordered and contiguous starting at 1; absence of the section MUST be the default for single-phase features (FR-001, FR-002, FR-003)
- [x] T006 [P] [US1] Modify `.specify/templates/plan-template.md` to document the optional `## Deploy Phases` section using the canonical machine-parseable format pinned by FR-001 and the data-model "Deploy Phase" canonical example (`### Phase K: <title>` headings with `**Goal**:` and `**Post-deploy production state**:` labelled fields); include a worked example (e.g., the four-phase column-rename template: add nullable column, dual-write + backfill, switch reads, drop old column) rendered in this canonical format so the plan agent (T005) and the split step (T011) consume the same authoritative layout (FR-001, FR-026)
- [x] T007 [US1] Modify `claude-agents/tasks.md` to detect multi-phase features by `grep -q '^## Deploy Phases$' <FEATURE_DIR>/plan.md`; when multi-phase, organize `tasks.md` with deploy phases as the sole top-level (`##`) sections in deploy order, nest the existing Setup/Foundational/User-Stories structure as second-level (`###`) `Stage:` headings (`### Stage: Setup`, `### Stage: Foundational`, `### Stage: User Stories`) inside each deploy-phase section, omit empty stages, and tag every task `[phase-K]` where K is the enclosing deploy-phase number; allocate Setup/Foundational/User-Story work into the deploy phases that need it (the same kind of work MAY appear in multiple deploy phases); when single-phase, preserve today's template unchanged (no Stage relabel, no `[phase-N]` tags) per FR-022 (FR-004, FR-005)
- [ ] T008 [P] [US1] Modify `.specify/templates/tasks-template.md` to document multi-phase phase tagging and the per-phase top-level structure; show an example multi-phase tasks.md skeleton with `## Phase K: <goal>` top-level headings and nested `### Stage:` headings; preserve the existing single-phase template unchanged so it remains a strict subset (FR-027)
- [ ] T009 [US1] Modify `claude-agents/ralph.md` to append a `Phase: N` git trailer to commit messages when the task entry in `tasks.md` carries `[phase-N]`; when the task has no phase tag, commit without the trailer (do not silently default to `Phase: 1` in the commit text); use Git's standard trailer mechanism (RFC 5322) so `git interpret-trailers` and `git log --format='%(trailers:key=Phase,valueonly)'` parse them deterministically; all implementation work for a multi-phase feature MUST occur on a single feature branch end to end before any pull request is opened (FR-006, FR-007, FR-008)
- [ ] T010 [US1] Modify `speckit-commands/speckit.ralph.implement.md` to align with the trailer convention introduced in T009 (reference the `Phase: N` trailer requirement; defer trailer logic to the agent file)
- [ ] T011 [US1] Create new command file `speckit-commands/speckit.split.md` implementing the split step per `specs/008-feat-multi-phase-deploys/contracts/split-command.md`: pre-flight (resolve `FEATURE_DIR` via `bash .specify/scripts/bash/check-prerequisites.sh --json --paths-only`; refuse to run if `<FEATURE_DIR>/review-report.md` is missing with the exact message from the contract; run `git fetch origin main` and fail fast if the fetch fails by writing a single `failed` row); detect multi-phase by `grep -q '^## Deploy Phases$' <FEATURE_DIR>/plan.md`; parse `review-report.md` via the awk recipe in contracts/review-report.md to build `gating_phases` and `global_gate`; for each phase K in 1..N (multi-phase), enumerate commits via `git log origin/main..HEAD --reverse --format='%H %(trailers:key=Phase,valueonly)'`, group by phase number with untrailerd commits defaulting to phase 1 per FR-014; build phase branch names `NNNN-<type>-<slug>-phaseK` per FR-015; create or update each phase branch via `git checkout -B`, `git reset --hard <base>`, `git cherry-pick <phase_commits>`, `git push --force-with-lease` per FR-017; extract each phase's goal and post-deploy text from the plan's `## Deploy Phases` section by parsing the canonical format pinned by FR-001 and the data-model "Deploy Phase" canonical example (locate the `### Phase K: <title>` heading, then read the `**Goal**: <text>` and `**Post-deploy production state**: <text>` labelled fields); open or update PRs via `gh pr create --base` / `gh pr edit` with the deterministic title `[Phase K/N] <feature-branch-name>` and the FR-016 body composition (Part-of line, `## Phase Goal` containing the extracted goal text, `## Post-deploy production state` containing the extracted post-deploy text, `## Stack` with `(this PR)` suffix); for single-phase, open exactly one PR against `main` with title `<feature-branch-name>` and body `Part of <FEATURE_DIR>/spec.md` per FR-019; persist `<FEATURE_DIR>/split-report.md` per `contracts/split-report.md` and FR-019a; mirror a concise summary to stdout (FR-001, FR-013, FR-014, FR-015, FR-016, FR-019)
- [ ] T012 [US1] Create new agent file `claude-agents/split.md` providing the agent persona and tool-use guidance for `/speckit.split`; describe pre-flight, multi-phase detection, gating semantics, idempotent rebuild via reset+cherry-pick+force-with-lease, fail-fast behavior, and the persisted split-report contract; reference `speckit-commands/speckit.split.md` for the executable instruction sequence
- [ ] T013 [US1] Modify `speckit-commands/speckit.pipeline.md` to invoke `/speckit.split` after Marge completes (whether by reaching `<promise>ALL_FINDINGS_RESOLVED</promise>` or by hitting max iterations); spawn a fresh agent with the resolved `FEATURE_DIR`; the split step itself handles both single-phase and multi-phase modes via the `## Deploy Phases` detection in `plan.md`; update the orchestrator's status table (Step 6a) to include the new split step; the orchestrator MUST NOT introduce a separate flag, environment variable, or command-line switch to indicate multi-phase mode per FR-020 (FR-020, FR-021)

**Checkpoint**: A spec author can run the full pipeline against a multi-phase feature description and receive a working stack of phase branches and PRs. User Story 1 is independently testable per V-002 in quickstart.md.

---

## Phase 4: User Story 2 — Catch unsafe phase boundaries before splitting (Priority: P1)

**Goal**: When a multi-phase feature is reviewed, Marge applies migration-safety checks to each phase as a deployable slice on top of the previous one. A plan that drops a column in the same phase that adds it, that adds a NOT NULL column without a default, that contains both a schema change and the code that depends on it, or that renames a column in a single phase is flagged as a `high`-severity finding tagged with the offending phase. The split step refuses to open a PR for a phase that has unresolved high-severity findings against it.

**Independent Test**: Author a deliberately-broken plan exhibiting every FR-010 pattern in distinct phases, run Marge, and confirm every pattern is reported as a `high`-severity finding tagged to the offending phase in `review-report.md`. Run the split step and confirm it refuses to open or update PRs for the gated phases and emits `gated` rows in `split-report.md` citing the finding IDs.

### Implementation for User Story 2

- [ ] T014 [US2] Modify `claude-agents/marge.md` (extending T003) to tag every multi-phase finding with the phase number that introduced the issue per FR-011; for findings attributable to a specific phase, set the Phase column to the integer phase number; for structural inconsistencies the migration-safety check pack cannot attribute (S3 malformed `Phase:` trailer, S4 phase-trailer-without-deploy-phases), set the Phase column to the literal `-` per data-model.md "Review Report"; for orphan phase tags (S1), set Phase to the integer of the offending tag; for non-contiguous phases (S2), set Phase to the integer of the missing phase; run Marge once on the integrated feature branch — per-phase scope is expressed entirely via finding tags, not as separate per-phase review passes per FR-012 (FR-011, FR-012)
- [ ] T015 [US2] Verify in `claude-agents/marge.md` that the existing check-pack discovery loop picks up `.specify/marge/checks/migrations.md` automatically without modifying the agent's discovery logic per FR-023 (the discovery loop scans `.specify/marge/checks/*.md` by filename); add a note to the agent file documenting that the migration-safety pack is loaded automatically when present
- [ ] T016 [US2] Extend `speckit-commands/speckit.split.md` (built in T011) with the gating logic per FR-018: parse `review-report.md` for unresolved high-severity findings (Status anything other than `resolved`); for multi-phase, treat findings with Phase = integer K as gating phase K and every downstream phase K+1..N transitively; treat findings with Phase = `-` as a global gate that gates every phase in the run; for single-phase, treat any unresolved high-severity finding as gating the single PR per FR-019; refuse to open or update the affected pull request and emit `gated` rows in `split-report.md` citing the gating finding's ID and summary; the split step MUST NOT independently re-verify any structural invariant from FR-010 — the persisted review report is the single source of truth for gating decisions (FR-018, FR-019)

**Checkpoint**: Marge emits per-phase findings tagged by phase and gates the split step on unresolved high-severity findings. User Story 2 is independently testable per V-003 in quickstart.md (deliberately-broken plan).

---

## Phase 5: User Story 3 — Single-phase features keep working unchanged (Priority: P1)

**Goal**: Authors of features that do not need phased rollout (the vast majority) see no change in behavior. A `plan.md` without a `## Deploy Phases` section continues to produce a single feature branch and a single pull request, with no phase trailers required on commits, no per-phase findings emitted by Marge, and no extra PRs opened by the split step.

**Independent Test**: Re-run the pipeline against an existing single-phase feature (`001-consistency-cleanup`) and confirm the output is the same shape as before: one branch, one PR, no `Phase:` trailers in commits, no per-phase findings in `review-report.md` (Phase column `-` for every row), `split-report.md` contains exactly one row with `Phase` = `single`, and no additional branches or PRs created by the split step.

### Implementation for User Story 3

- [ ] T017 [US3] Verify in `claude-agents/plan.md` (per T005) that single-phase features (the default heuristic outcome) produce a `plan.md` WITHOUT a `## Deploy Phases` section; absence of the section MUST be the sole signal for single-phase mode per FR-002 — no flag, environment variable, or command-line switch is introduced per FR-020
- [ ] T018 [US3] Verify in `claude-agents/tasks.md` (per T007) that single-phase features (no `## Deploy Phases` in `plan.md`) produce a `tasks.md` with the existing top-level Setup/Foundational/User-Stories structure unchanged; no `### Stage:` relabel; no `[phase-N]` tags; today's tasks template is preserved as a strict subset of multi-phase behavior per FR-022
- [ ] T019 [US3] Verify in `claude-agents/ralph.md` (per T009) that single-phase features (tasks without `[phase-N]` tags) produce commits without `Phase:` trailers per FR-007; do not silently default to `Phase: 1` in the commit text
- [ ] T020 [US3] Verify in `speckit-commands/speckit.split.md` (per T011) that for single-phase features (no `## Deploy Phases` section in `plan.md`), the split step produces exactly one pull request against `main` matching today's behavior; no additional branches created; the split-report contains exactly one row with `Phase` = `single` per FR-019 and FR-019a; the gating rule in FR-018 still applies (any unresolved high-severity finding gates the single PR) per FR-019
- [ ] T021 [US3] Run V-001 (single-phase regression) from `specs/008-feat-multi-phase-deploys/quickstart.md` against `001-consistency-cleanup` (or another existing single-phase feature) to confirm `plan.md` does not acquire a `## Deploy Phases` section, `tasks.md` carries no `[phase-N]` tags, Ralph commits have no `Phase:` trailers, Marge produces `review-report.md` with Phase column `-` for every row, the split step opens exactly one PR against `main` and creates no extra branches, and `split-report.md` contains exactly one row with `Phase` = `single` per SC-003 and FR-022

**Checkpoint**: Single-phase backward compatibility is preserved end to end. User Story 3 is independently testable per V-001 in quickstart.md.

---

## Phase 6: User Story 4 — Re-run the split step idempotently (Priority: P2)

**Goal**: When the split step runs more than once on the same feature branch, re-running updates existing stacked branches and existing pull requests in place rather than creating duplicates. Authors can iterate on a multi-phase feature without manually pruning stale branches or stale PRs.

**Independent Test**: Run the pipeline to completion on a multi-phase feature, observe the resulting stack of branches and PRs, then re-run the split step with no changes (expect every row in `split-report.md` to be `unchanged` and zero remote state changes); add one new phase-tagged commit to the feature branch and re-run (expect the corresponding phase branch and downstream phase branches to report `updated` and the PRs to be updated in place); remove a commit from the feature branch and re-run (expect the affected phase to report `updated` and the phase branch to reflect the shrunk commit set without orphaned commits).

### Implementation for User Story 4

- [ ] T022 [US4] Extend `speckit-commands/speckit.split.md` (built in T011, T016) with idempotent rebuild logic per FR-017: identify existing phase branches by the deterministic naming convention `NNNN-<type>-<slug>-phaseK`; a remote branch matching that name is treated as an existing phase branch to update; no remote branch with that name means a new phase branch to create; deterministically rebuild a phase branch by `git checkout -B <phase-branch>`, `git reset --hard <base>` (where base is `origin/main` for K=1 or the previous phase branch for K>1), `git cherry-pick <phase_commits>` in deploy order, then `git push --force-with-lease origin <phase-branch>` (skipped if no SHA change vs. the existing remote ref AND the existing PR title and body match the recomputed values per FR-016); compute the deterministic title `[Phase K/N] <feature-branch-name>` and the deterministic body per FR-016 (Part-of line, `## Phase Goal`, `## Post-deploy production state`, `## Stack` with `(this PR)` suffix on the current phase) on every run; compare against the existing PR's title/body via `gh pr view --json title,body` and overwrite via `gh pr edit --title --body` when they differ; phase pull-request title and body are pipeline-managed artifacts that WILL be overwritten on every run; the `unchanged` status is deterministically computable from `(commit SHAs, title, body)` per FR-019a (FR-016, FR-017)
- [ ] T023 [US4] Extend `speckit-commands/speckit.split.md` (built in T011, T016, T022) with `skipped-merged` protection per FR-017: when a phase branch's pull request is already merged into `origin/main`, skip rebuilding that phase (treat it as immutable history) and emit a `skipped-merged` row in `split-report.md` with a reason citing the merged state; this is the only safeguard against the spec-freeze edge case where a tasks-artifact `[phase-N]` tag is changed after commits with that tag have already shipped (FR-017)
- [ ] T024 [US4] Extend `speckit-commands/speckit.split.md` (built in T011, T016, T022, T023) with fail-fast error handling per FR-017: when an error occurs while creating or updating a phase branch or its pull request (e.g., `gh pr create` failure, `gh pr edit` failure, cherry-pick conflict, `git push --force-with-lease` rejected), fail fast on the first error, leave already-completed phase branches and pull requests in place, write a `failed` row in `split-report.md` with reason naming the failure, and STOP — subsequent phases are NOT processed in this run; idempotent re-run resumes from the failed phase per the contract in `specs/008-feat-multi-phase-deploys/contracts/split-command.md` "Failure handling" section (FR-017)
- [ ] T025 [US4] Verify the persisted `split-report.md` writeout in `speckit-commands/speckit.split.md` (per T011) emits all six terminal statuses correctly (`created`, `updated`, `unchanged`, `skipped-merged`, `gated`, `failed`); the report MUST be overwritten on every run (never appended to); the table MUST use the exact column headers `| Phase | Status | Branch | PR URL | Reason |` in that order per `specs/008-feat-multi-phase-deploys/contracts/split-report.md` and FR-019a; pipe characters in cell values MUST be escaped as `\|`; for single-phase the Phase column is `single`; for multi-phase the Phase column is the integer phase number; the pipeline orchestrator MUST treat absence of `<FEATURE_DIR>/split-report.md` after a split-step invocation as a split-step failure (FR-019a)

**Checkpoint**: The split step is idempotent end to end. User Story 4 is independently testable per V-004 (idempotent re-run), V-005 (`skipped-merged` protection), V-006 (cherry-pick conflict), V-007 (`gh pr create` failure), V-008 (`origin/main` canonical base), and V-009 (PR title/body overwrite) in quickstart.md.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Documentation updates, dogfooding-copy refresh, and final verification across all stories.

- [ ] T026 [P] Modify `templates/CLAUDE.md` to add a section describing multi-phase deploys: when to use them (schema migration combined with reads/writes on the same data, breaking API change, multi-service rollout coordination), how a multi-phase feature is authored (the plan agent emits a `## Deploy Phases` section automatically when heuristics fire — no flag required), and how to read the resulting pull request stack (read in deploy order, merge in deploy order, each PR is independently deployable on top of the previous one); reference the migration-safety check pack at `.specify/marge/checks/migrations.md` (FR-025, SC-007)
- [ ] T027 [P] Modify `README.md` to add multi-phase deploy support to the project's feature list with a one-paragraph description and a link to `.specify/marge/checks/migrations.md`; mention that single-phase features keep working unchanged per FR-022 (FR-028, SC-007)
- [ ] T028 Refresh installed copies under `.claude/commands/` and `.claude/agents/` from the source-of-truth files edited in Phases 2-6 — copy `speckit-commands/speckit.split.md` to `.claude/commands/speckit.split.md`, `speckit-commands/speckit.pipeline.md` to `.claude/commands/speckit.pipeline.md`, `speckit-commands/speckit.ralph.implement.md` to `.claude/commands/speckit.ralph.implement.md`, `speckit-commands/speckit.marge.review.md` to `.claude/commands/speckit.marge.review.md`, `claude-agents/plan.md` to `.claude/agents/plan.md`, `claude-agents/tasks.md` to `.claude/agents/tasks.md`, `claude-agents/ralph.md` to `.claude/agents/ralph.md`, `claude-agents/marge.md` to `.claude/agents/marge.md`, and `claude-agents/split.md` to `.claude/agents/split.md` (or run `setup.sh` for in-repo dogfooding) per CLAUDE.md "Source vs Installed Files"
- [ ] T029 Verify `setup.sh` idempotently seeds `.specify/marge/checks/migrations.md` into a downstream consumer project on a fresh install per FR-024 — confirm the existing idempotent check-pack seeding loop picks up the new file without modifications; existing files MUST be preserved per FR-024
- [ ] T030 Run V-001 through V-012 from `specs/008-feat-multi-phase-deploys/quickstart.md` ("Verification Checklist") end to end against the integrated implementation: V-001 single-phase regression, V-002 multi-phase happy path, V-003 migration-safety pack coverage of FR-010 patterns, V-004 idempotent re-run, V-005 `skipped-merged` protection, V-006 cherry-pick conflict failure, V-007 `gh pr create` failure, V-008 `origin/main` canonical base, V-009 PR title/body overwrite, V-010 README and downstream-consumer documentation, V-011 pipeline resumability, V-012 process hygiene per CLAUDE.md "Process Cleanup"

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on Setup — BLOCKS all user stories
- **User Story 1 (Phase 3, P1, MVP)**: Depends on Foundational (T002, T003, T004) — MVP scope
- **User Story 2 (Phase 4, P1)**: Depends on Foundational (T002, T003, T004) and on US1 task T011 (split command file) for the gating extension in T016
- **User Story 3 (Phase 5, P1)**: Depends on Foundational AND on US1 (T005, T007, T009, T011) — verifies single-phase paths in the same files US1 modifies
- **User Story 4 (Phase 6, P2)**: Depends on US1 (T011, T012) — extends `speckit-commands/speckit.split.md` with idempotency, `skipped-merged`, fail-fast, and split-report writeout
- **Polish (Phase 7)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational — delivers the multi-phase happy path end to end (plan agent, tasks agent, Ralph trailers, split command/agent, pipeline orchestration)
- **User Story 2 (P1)**: Must run after US1 task T011 (`speckit-commands/speckit.split.md` exists) because T016 extends it with gating logic; T014 and T015 (Marge per-phase tagging and pack discovery) can start in parallel with US1 once Foundational is complete
- **User Story 3 (P1)**: Must run after US1 because it verifies the single-phase paths in `claude-agents/plan.md`, `claude-agents/tasks.md`, `claude-agents/ralph.md`, and `speckit-commands/speckit.split.md` — all files US1 modifies
- **User Story 4 (P2)**: Must run after US1 because it extends `speckit-commands/speckit.split.md`

### Within Each User Story

- Models/templates before agents that consume them (e.g., T006 plan-template can run alongside T005 plan-agent)
- Command files before pipeline integration (T011 split command before T013 pipeline orchestration)
- Single-phase verification (US3) after multi-phase implementation (US1) — same files, single-phase is the default branch
- Idempotent rebuild (T022) before `skipped-merged` (T023) before fail-fast (T024) — all extend the same split command file in sequence

### Parallel Opportunities

- T002, T003, T004 (Foundational) can run in parallel — different files (`migrations.md`, `marge.md`, `speckit.marge.review.md`)
- T006 (plan template) can run in parallel with T005 (plan agent) — different files
- T008 (tasks template) can run in parallel with T007 (tasks agent) — different files
- T026 (CLAUDE.md template) and T027 (README.md) can run in parallel — different files
- US3 verification tasks (T017, T018, T019, T020) are read-only verifications of files modified in US1; they can run in parallel once US1 is complete
- US2 tasks T014 and T015 can run in parallel with US1 tasks T011, T012, T013 (different files: `marge.md` vs split command/agent and pipeline)

---

## Parallel Example: Foundational Phase

```bash
# Launch all Foundational tasks together (different files):
Task: "Create migration-safety check pack at .specify/marge/checks/migrations.md (T002)"
Task: "Modify claude-agents/marge.md to persist <FEATURE_DIR>/review-report.md (T003)"
Task: "Modify speckit-commands/speckit.marge.review.md to mirror review-report persistence (T004)"
```

## Parallel Example: User Story 1

```bash
# Plan agent and template can run in parallel (different files):
Task: "Modify claude-agents/plan.md to emit ## Deploy Phases section (T005)"
Task: "Modify .specify/templates/plan-template.md to document the Deploy Phases section (T006)"

# Tasks agent and template can run in parallel:
Task: "Modify claude-agents/tasks.md for multi-phase phase tagging and Stage relabel (T007)"
Task: "Modify .specify/templates/tasks-template.md to document multi-phase tasks structure (T008)"
```

## Parallel Example: Polish Phase

```bash
# Documentation updates can run in parallel (different files):
Task: "Modify templates/CLAUDE.md to describe multi-phase deploys (T026)"
Task: "Modify README.md to list multi-phase deploys in the feature list (T027)"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001 pre-flight)
2. Complete Phase 2: Foundational (T002-T004; CRITICAL — blocks all stories)
3. Complete Phase 3: User Story 1 (T005-T013)
4. **STOP and VALIDATE**: Run V-002 (multi-phase happy path) from quickstart.md against a synthetic column-rename feature
5. Confirm: `plan.md` has `## Deploy Phases`, `tasks.md` has phase tags and Stage headings, Ralph commits carry `Phase: N` trailers, the split step produces 4 stacked branches and 4 PRs with the correct base-branch chain, `split-report.md` contains 4 `created` rows
6. MVP shippable at this point — author can produce a working stack of pull requests

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 → Test V-002 → Multi-phase happy path works end to end (MVP!)
3. Add User Story 2 → Test V-003 (deliberately-broken plan) → Migration-safety gating works
4. Add User Story 3 → Test V-001 (single-phase regression against `001-consistency-cleanup`) → Backward compat preserved
5. Add User Story 4 → Test V-004 through V-009 → Idempotent re-run, skipped-merged, fail-fast, origin/main base, PR title/body overwrite all work
6. Add Polish → Test V-010 (docs), V-011 (resumability), V-012 (process hygiene) → Documentation and hygiene verified
7. Each story adds value without breaking previous stories

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational together (T001-T004)
2. Once Foundational is done:
   - Developer A: User Story 1 (T005-T013) — multi-phase happy path; this work blocks US3 and US4
   - Developer B: User Story 2 task T014, T015 (Marge per-phase tagging and pack discovery) — parallel with US1 T005-T010, T012, T013; T016 must wait for US1 T011
3. After User Story 1 ships:
   - Developer A: User Story 3 verification (T017-T021) — read-only verification of single-phase paths
   - Developer B: User Story 2 task T016 (split-step gating) — extends `speckit.split.md`
   - Developer C: User Story 4 (T022-T025) — extends `speckit.split.md`; serialize T022, T023, T024 since they all touch the same file
4. Polish (T026-T030) runs after all user stories are complete

---

## Notes

- [P] tasks = different files, no dependencies on incomplete tasks
- [Story] label maps task to specific user story (US1, US2, US3, US4) for traceability
- Each user story is independently completable and testable per its Independent Test in spec.md
- Verification is via the quickstart.md V-001 through V-012 checklist — there are no automated unit tests for this medium (markdown command/agent/template files); see plan.md "Constitution Check / Test-First Development" for the rationale and the precedent set by 005-fix-subagent-quality-gates and 006-stop-after-param
- Source-of-truth files live in the repo root (`speckit-commands/`, `claude-agents/`, `.specify/marge/checks/`, `.specify/templates/`, `templates/`); installed copies under `.claude/` are overwritten by `setup.sh` and exist only for dogfooding — never edit `.claude/commands/*.md` or `.claude/agents/*.md` directly
- Commit after each task or logical group; commit format `type(scope): [008] description` per CLAUDE.md "Git Discipline"
- Stop at any checkpoint to validate the story independently
- Avoid: vague tasks, same-file conflicts within a parallel group, cross-story dependencies that break independence
- Process hygiene per CLAUDE.md: the split step does not start dev servers, watchers, or containers; the only side effects are `git` operations and `gh` invocations against the GitHub remote
