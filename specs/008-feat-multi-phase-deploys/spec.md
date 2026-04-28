# Feature Specification: Multi-Phase Deploy Support

**Feature Branch**: `008-feat-multi-phase-deploys`
**Created**: 2026-04-27
**Status**: Draft
**Input**: User description: "Add multi-phase deploy support to the speckit + Simpsons-loops pipeline so a single feature can ship as a stack of independently-deployable PRs."

## Clarifications

### Session 2026-04-27

- Q: When the split step fails partway through opening a stack of pull requests (for example, `gh pr create` succeeds for phase 1 but errors on phase 2 because of a network or API failure), what should the split step do? → A: Fail fast on first error, leave successfully-created branches and pull requests in place, and rely on idempotent re-runs to complete the stack.
- Q: How does the split step discover review findings so it can enforce the per-phase gating rule in FR-018, given that today's review step prints findings to stdout only and does not persist them? → A: The review step persists its report to `<FEATURE_DIR>/review-report.md` on every run; the split step reads that file to identify unresolved high-severity findings and their phase tags. Absence of the file means the split step refuses to run and instructs the author to run review first.
- Q: What concrete values are valid for the severity, phase tag, and resolution status of each finding in the persisted review report (FR-012a), so that the split step can deterministically interpret it? → A: severity is one of `high|medium|low|informational`; phase tag is the integer phase number when multi-phase and omitted when single-phase; resolution status is one of `open|resolved`, with new findings emitted as `open` and only marked `resolved` by a subsequent review pass against the same branch state. The split step treats anything other than `resolved` as gating.
- Q: Does the split step's per-phase gating rule in FR-018 apply to every high-severity finding regardless of which check pack produced it, or only to high-severity migration-safety findings (as SC-006 currently implies)? → A: The split step gates on every unresolved high-severity finding regardless of which check pack produced it. SC-006 is updated to match FR-018; the persisted review report does not need a check-pack discriminator field for gating. Only the severity and resolution status determine whether a finding gates the split step.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Author a multi-phase feature end to end (Priority: P1)

A spec author needs to ship a change that cannot land in a single PR without breaking production — for example, renaming a database column read by a running service. The author writes one feature description that targets the desired end state. The pipeline plans the deploy phases needed to get there safely, implements every phase on a single feature branch, reviews the whole change with migration-safety checks, and finally splits the branch into a stack of per-phase pull requests that humans review and merge in order.

**Why this priority**: This is the primary capability the feature delivers. Without it, the only way to model a phased deploy today is by faking it as multiple unrelated specs, which fragments feature intent and provides no migration-safety guardrails. Every other story builds on this end-to-end flow.

**Independent Test**: Can be tested by running the full pipeline against a synthetic feature description that requires phased rollout (e.g., "rename `users.email_address` column to `users.email`"), and verifying that the pipeline produces (a) a single spec, (b) a plan that enumerates four deploy phases, (c) a tasks list where every task is tagged with its phase, (d) a feature branch whose commits each carry a `Phase: N` git trailer matching their task tag, and (e) a stack of four pull requests with the correct base-branch chain (`main` <- phase1 <- phase2 <- phase3 <- phase4).

**Acceptance Scenarios**:

1. **Given** a feature description that requires phased rollout, **When** the pipeline runs end to end, **Then** `plan.md` contains a "Deploy Phases" section enumerating phases 1..N with a goal and post-deploy production state for each phase.
2. **Given** a `plan.md` with a "Deploy Phases" section, **When** tasks are generated, **Then** every task in `tasks.md` carries a `[phase-N]` tag and tasks are organized under per-phase top-level sections.
3. **Given** a `tasks.md` with `[phase-N]` tags, **When** the implementation step commits each completed task, **Then** every commit message contains a `Phase: N` git trailer whose value matches the task's phase tag.
4. **Given** a fully-implemented feature branch with phase-tagged commits and a passing review, **When** the split step runs, **Then** stacked branches `NNNN-feat-name-phase1`, `NNNN-feat-name-phase2`, ... `NNNN-feat-name-phaseK` are created and a stack of pull requests is opened with the correct base-branch chain.

---

### User Story 2 - Catch unsafe phase boundaries before splitting (Priority: P1)

When a multi-phase feature is reviewed, the reviewer agent must apply migration-safety checks that look at each phase as a deployable slice on top of the previous one. A plan that drops a column in the same phase that adds it, that adds a NOT NULL column without a default, that contains both a schema change and the code that depends on it, or that renames a column in a single phase instead of the safe four-step expand-contract pattern must be flagged as a finding tagged with the phase that introduced the problem. The split step refuses to open a PR for a phase that has unresolved high-severity findings against it.

**Why this priority**: The whole point of multi-phase deploys is migration safety. Without per-phase migration-safety enforcement, the feature is just bookkeeping that splits commits by tag — it provides no guarantee that the resulting PR stack is actually safe to merge in order. Catching unsafe boundaries before the split step prevents the pipeline from publishing a known-broken stack.

**Independent Test**: Can be tested by deliberately authoring a broken plan (drop column in the same phase that adds the new one; no dual-write step) and confirming that the review step flags the expected migration-safety findings (rename in single phase; column dropped while prior-phase code still reads it; phase contains both schema change and dependent code) with high severity, that each finding is tagged with the offending phase, and that the split step refuses to open a PR for the broken phase until findings are resolved.

**Acceptance Scenarios**:

1. **Given** a plan that drops a column in the same phase that adds the replacement, **When** the review step runs, **Then** a high-severity finding is emitted, the finding is tagged with the offending phase, and the finding cites the migration-safety check it failed.
2. **Given** an unresolved high-severity finding tagged to phase K, **When** the split step runs, **Then** the split step refuses to open a pull request for phase K and reports which finding blocked it.
3. **Given** a plan that adds a NOT NULL column without a default, **When** the review step runs, **Then** the finding identifies the affected phase and references the relevant migration-safety check.
4. **Given** a phase that contains both a schema change and code that depends on the new schema, **When** the review step runs, **Then** the review emits a finding directing the author to split the schema change into an earlier phase and the code switch into a later phase.

---

### User Story 3 - Single-phase features keep working unchanged (Priority: P1)

Authors of features that do not need phased rollout (the vast majority) must see no change in behavior. A `plan.md` without a "Deploy Phases" section continues to produce a single feature branch and a single pull request, with no phase trailers required on commits, no per-phase findings emitted by the reviewer, and no extra PRs opened by the split step.

**Why this priority**: Backward compatibility is non-negotiable. Every existing feature in `specs/` was authored under the single-phase assumption. Breaking any of them — by requiring phase tags, by changing commit-message conventions, by inserting an extra split step that opens duplicate PRs — would invalidate the project's existing pipeline and force a migration of completed work. Backward compat must be structural (driven by the absence of a "Deploy Phases" section), not gated behind a flag.

**Independent Test**: Can be tested by re-running the pipeline against an existing single-phase feature (e.g., `001-consistency-cleanup`) and confirming that the output is the same shape as before: one branch, one PR, no `Phase:` trailers in commits, no per-phase findings in the review output, and no additional branches or PRs created by the split step.

**Acceptance Scenarios**:

1. **Given** a `plan.md` without a "Deploy Phases" section, **When** the pipeline runs, **Then** the implementation step commits without `Phase:` trailers and the review step does not emit per-phase finding tags.
2. **Given** a feature branch with no `Phase:` trailer on any commit, **When** the split step runs, **Then** exactly one pull request is opened against `main` (matching today's behavior) and no additional stacked branches are created.
3. **Given** a `tasks.md` without `[phase-N]` tags, **When** the implementation step processes a task, **Then** the resulting commit omits the `Phase:` trailer rather than defaulting silently to `Phase: 1` in the commit text.

---

### User Story 4 - Re-run the split step idempotently (Priority: P2)

When the split step runs more than once on the same feature branch — because the author re-ran the pipeline after fixing review findings, or because a phase needed an additional commit — re-running the split must update existing stacked branches and existing pull requests in place rather than creating duplicates. The author must be able to iterate on a multi-phase feature without manually pruning stale branches or stale PRs.

**Why this priority**: Pipelines re-run all the time. If split is not idempotent, every re-run leaves orphaned branches and orphaned PRs behind, and the human reviewer cannot tell which stack is current. Idempotence is what makes the split step safe to invoke automatically from the pipeline without requiring a "first run vs. re-run" distinction.

**Independent Test**: Can be tested by running the pipeline to completion on a multi-phase feature, observing the resulting stack of branches and PRs, then adding one new phase-tagged commit to the feature branch and re-running the split step. The expected result is that the corresponding phase branch is updated to include the new commit, the corresponding pull request is updated in place, and no additional branches or PRs are created.

**Acceptance Scenarios**:

1. **Given** a feature whose split step has already produced a stack of phase branches and PRs, **When** the split step runs again with no new commits, **Then** the existing branches and PRs are unchanged and no duplicates are created.
2. **Given** a feature whose split step has already produced a stack, **When** a new phase-tagged commit is added to the feature branch and the split step runs again, **Then** the corresponding phase branch is updated to include the new commit and the corresponding PR is updated in place.
3. **Given** a re-run that would shrink a phase (a commit was removed from the feature branch), **When** the split step runs, **Then** the corresponding phase branch is updated to reflect the new commit set without leaving orphaned commits.

---

### Edge Cases

- A phase tag references a phase number not declared in `plan.md` (e.g., a task tagged `[phase-5]` when the plan only enumerates phases 1..4). The review step must flag this as a high-severity inconsistency and the split step must refuse to open a PR for the orphan phase.
- The feature branch contains commits with `Phase: 1`, `Phase: 3`, and no `Phase: 2` (a phase has no commits). The split step must report the missing phase as an error rather than silently producing a non-contiguous stack.
- A single commit body contains a `Phase:` trailer with a non-integer or empty value. The split step must treat the commit as malformed and refuse to proceed until the trailer is fixed.
- A task's `[phase-N]` tag in `tasks.md` is changed after some commits with that tag have already shipped. Spec freeze applies once Phase 1 has merged and deployed; this rule is documented but not enforced by tooling. The pipeline must not silently rewrite history when this happens.
- The author runs the pipeline against a feature that produces only one phase even though a "Deploy Phases" section is present. The split step must produce exactly one PR (matching single-phase behavior) rather than an empty stack.
- A phase contains code that references symbols that will only be introduced in a later phase. The review step must flag this as a per-phase deployability violation.
- Cherry-picking a phase's commits onto the previous phase branch produces a merge conflict. The split step must report the conflict and stop rather than committing a partial stack; conflict resolution is a manual step in this iteration.
- Pull-request creation fails partway through the stack (for example, `gh pr create` succeeds for phase 1 but returns a network or API error on phase 2). The split step must fail fast on the first error, leave successfully-created phase branches and pull requests in place, report which phase failed and why, and rely on its idempotent re-run behavior (FR-017) to complete or repair the stack on the next invocation.

## Requirements *(mandatory)*

### Functional Requirements

#### Authoring and planning

- **FR-001**: The plan artifact MUST support an optional "Deploy Phases" section that enumerates phases 1..N, with a goal and a post-deploy production-state description for each phase.
- **FR-002**: The presence of a "Deploy Phases" section in the plan artifact MUST be the sole signal that marks a feature as multi-phase. Absence MUST mean single-phase.
- **FR-003**: When the plan identifies a multi-phase rollout, the planning agent MUST produce the "Deploy Phases" section in the plan artifact based on documented heuristics (schema migration combined with reads or writes on the same data, breaking API change, multi-service rollout coordination).
- **FR-004**: When the plan contains a "Deploy Phases" section, the tasks artifact MUST organize tasks under per-phase top-level sections and MUST tag every task with `[phase-N]` indicating which phase it belongs to.
- **FR-005**: When a feature is multi-phase, the existing per-story task structure (currently labeled "Phase 1: Setup", "Phase 2: Foundational", "Phase 3+: User Stories") MUST be relabeled as "Stages" within the tasks artifact to disambiguate from deploy phases. For single-phase features, the existing labels MUST be preserved unchanged.

#### Implementation

- **FR-006**: When the implementation agent commits a task whose tasks-artifact entry carries a `[phase-N]` tag, the commit message MUST include a `Phase: N` git trailer whose value matches the task's phase tag.
- **FR-007**: When the implementation agent commits a task whose tasks-artifact entry does NOT carry a phase tag, the commit message MUST NOT include a `Phase:` trailer.
- **FR-008**: All implementation work for a multi-phase feature MUST occur on a single feature branch end to end before any pull request is opened.

#### Review

- **FR-009**: A migration-safety check pack MUST be available to the review agent and MUST be loaded automatically when present.
- **FR-010**: The migration-safety check pack MUST cover at minimum: NOT NULL column adds without default; column drops while prior-phase code still reads them; renames executed in a single phase rather than the four-step expand-contract pattern; long-transaction backfills on hot tables; missing index for a new read path; phases containing both a schema change and code that depends on the new schema; removed function or endpoint while prior-phase callers still exist; per-phase deployability (each phase must be deployable on top of `main + earlier phases` while previous-phase code is still running).
- **FR-011**: When the feature is multi-phase, every review finding MUST be tagged with the phase that introduced the issue.
- **FR-012**: The review step MUST run once on the whole integrated feature branch before the split step runs. Per-phase review MUST be expressed as findings tagged by phase, not as separate per-phase review passes.
- **FR-012a**: The review step MUST persist its findings report to `<FEATURE_DIR>/review-report.md` on every run, overwriting any prior copy. For each finding, the persisted report MUST include:
  - **severity**: one of `high`, `medium`, `low`, `informational`.
  - **phase tag**: the integer phase number that introduced the finding when the feature is multi-phase; omitted entirely when the feature is single-phase.
  - **resolution status**: one of `open` (the finding has not been addressed in the current branch state) or `resolved` (the finding was addressed in a subsequent review pass against the same branch state). New findings are emitted as `open`; the review step marks a previously-recorded finding as `resolved` only when a subsequent run confirms the underlying issue is gone.

  The split step MUST treat any finding whose resolution status is anything other than `resolved` as gating per FR-018. The persisted report MUST be machine-readable enough that the split step can extract `(severity, phase tag, resolution status)` for every finding without re-running the review agent.

#### Splitting

- **FR-013**: A new split step MUST read commits on the feature branch using `git log main..HEAD` and group them by their `Phase:` git trailer.
- **FR-014**: Commits without a `Phase:` trailer MUST default to phase 1 for grouping purposes.
- **FR-015**: For each phase 1..N, the split step MUST create a stacked branch named `NNNN-<type>-<slug>-phaseK` (where `NNNN-<type>-<slug>` is the feature branch name and `K` is the phase number) by cherry-picking that phase's commits onto the previous phase's branch (or onto `main` for phase 1).
- **FR-016**: The split step MUST open a pull request for every phase branch immediately, with the correct base-branch chain (`main` <- phase1 <- phase2 <- ... <- phaseN), so reviewers can read them in sequence.
- **FR-017**: The split step MUST be idempotent: re-running it MUST update existing phase branches and pull requests in place rather than creating duplicates. When the split step encounters an error while creating or updating a phase branch or its pull request (for example, a `gh pr create` failure on phase K), it MUST fail fast on the first error, leave already-completed phase branches and pull requests in place, and report which phase failed and why so that an idempotent re-run can resume from the failed phase.
- **FR-018**: The split step MUST refuse to open or update a pull request for any phase that has an unresolved high-severity review finding tagged to it. The split step MUST read findings from the persisted review report at `<FEATURE_DIR>/review-report.md` (see FR-012a). If the review report is missing, the split step MUST refuse to run and instruct the author to run the review step first. The split step MUST report which finding blocked which phase.
- **FR-019**: When the feature is single-phase (no "Deploy Phases" section in the plan), the split step MUST produce exactly one pull request against `main`, matching today's single-PR behavior, with no additional branches created.

#### Pipeline orchestration

- **FR-020**: The pipeline orchestrator MUST detect whether a feature is multi-phase by checking the plan artifact for a "Deploy Phases" section. The orchestrator MUST NOT introduce a separate flag, environment variable, or command-line switch to indicate multi-phase mode.
- **FR-021**: The pipeline orchestrator MUST invoke the split step after the review step completes for both single-phase and multi-phase features. For single-phase features, the split step delegates to today's single-PR behavior.

#### Backward compatibility

- **FR-022**: Every existing single-phase feature MUST continue to work unchanged after this feature ships. Re-running the pipeline against an existing single-phase feature MUST produce the same shape of output (one branch, one PR, no phase trailers, no per-phase findings) as today.
- **FR-023**: The review agent's existing check-pack discovery MUST pick up the new migration-safety check pack automatically when present, without requiring code changes to the review agent.
- **FR-024**: The project's setup script (`setup.sh`) MUST seed the migration-safety check pack into downstream consumer projects idempotently — existing files MUST be preserved.

#### Documentation

- **FR-025**: The downstream-consumer template documentation MUST describe when to use multi-phase deploys, how a multi-phase feature is authored, and how to read the resulting pull request stack.
- **FR-026**: The plan artifact template MUST document the optional "Deploy Phases" section with a worked example.
- **FR-027**: The tasks artifact template MUST document phase tagging and the per-phase top-level structure used when a feature is multi-phase.
- **FR-028**: The project README MUST list multi-phase deploy support among the project's features.

### Key Entities

- **Deploy Phase**: A named step in a phased rollout. Has a phase number (1..N), a goal, and a description of the post-deploy production state. Lives as a section inside `plan.md`. Phases are totally ordered and contiguous.
- **Phase Tag**: A marker `[phase-N]` attached to a task in `tasks.md` indicating which deploy phase the task belongs to. References a phase declared in the plan's "Deploy Phases" section.
- **Phase Trailer**: A git trailer of the form `Phase: N` attached to a commit message indicating which deploy phase the commit belongs to. Set by the implementation agent based on the task's phase tag. Used by the split step to group commits.
- **Migration-Safety Check Pack**: A new check pack file (`migrations.md`) that the review agent loads to evaluate per-phase migration safety. Contains the catalog of unsafe patterns to detect and the rules for evaluating per-phase deployability.
- **Phase Branch**: A stacked branch produced by the split step, named `NNNN-<type>-<slug>-phaseK`. Contains the cherry-picked commits for one phase and is based on either `main` (phase 1) or the previous phase's branch.
- **Phase Pull Request**: A pull request produced by the split step for each phase branch. Forms a stack with the correct base-branch chain so reviewers read phases in deploy order.
- **Per-Phase Finding**: A review finding tagged with the phase number that introduced the issue. Used by the split step to gate which pull requests it is willing to open.
- **Review Report**: A persisted artifact at `<FEATURE_DIR>/review-report.md` produced by the review step on every run. Lists all findings (severity, phase tag when multi-phase, resolution status). Read by the split step to enforce per-phase gating without re-running review.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An author can take a feature description that requires phased rollout (such as a column rename) and produce a working stack of pull requests through the pipeline without manually editing branches, commit messages, or PR base-branch references.
- **SC-002**: For a multi-phase feature with K phases, the pipeline produces exactly K stacked pull requests with the correct base-branch chain on the first successful pipeline run, with zero manual cleanup steps required.
- **SC-003**: For every existing single-phase feature in the project's `specs/` directory, re-running the pipeline produces output of the same shape as today (one branch, one PR, no phase trailers in commits, no per-phase finding tags) — measured by spot-checking at least one existing feature end to end.
- **SC-004**: The migration-safety check pack catches every unsafe pattern enumerated in FR-010 when applied to a deliberately-broken plan that exhibits each pattern, with each finding tagged to the offending phase.
- **SC-005**: Re-running the split step against a feature that has already been split produces zero duplicate branches and zero duplicate pull requests; existing branches and pull requests are updated in place when their underlying commits change.
- **SC-006**: The split step refuses to open or update a pull request for any phase carrying an unresolved high-severity review finding (regardless of which check pack produced it), and the refusal message identifies which finding blocked which phase.
- **SC-007**: A new author reading the project README and the downstream-consumer template can determine whether a feature they are about to write needs multi-phase deploys, and if so, how to author it, without consulting any other documentation.

## Assumptions

- The `gh` CLI is available in the pipeline environment and authenticated for the repository, since the split step opens pull requests via `gh pr create`. This matches the assumption made by the existing single-PR pipeline.
- All commits on a multi-phase feature branch are linear (no merges from `main` mid-way through implementation), so cherry-picking by phase produces a clean stack. Resolving cherry-pick conflicts is treated as a manual step in this iteration; the split step reports the conflict and stops.
- Phases are totally ordered and contiguous (1, 2, 3, ... N with no gaps). A feature branch with commits tagged only `Phase: 1` and `Phase: 3` is a malformed input, not a supported configuration.
- The single global quality gate at `.specify/quality-gates.sh` applies to the integrated feature branch as a whole. There are no per-phase quality gates in this iteration.
- Spec freeze on first deploy is a documented social rule; the pipeline does not enforce it. Once Phase 1 of a feature has merged and deployed, further changes to the same feature's spec, plan, or tasks are out of scope for this iteration's tooling.
- The existing review agent's check-pack discovery loop picks up new check packs by filename, so dropping `migrations.md` into `.specify/marge/checks/` is sufficient to make it discoverable without modifying the agent's discovery logic.
- Review findings rated below high severity (medium, low, informational) do NOT block the split step from opening pull requests regardless of which check pack produced them; they are surfaced as review comments for the human reviewer to address. Only high-severity findings gate the split step, and they gate it regardless of which check pack produced them (migration-safety, baseline, project-specific, etc.).
- The project's existing branch-naming convention (`NNNN-<type>-<slug>`) is preserved for the feature branch. Phase branches extend this with a `-phaseK` suffix; this suffix lives within GitHub's 244-byte branch-name limit for all realistic phase counts.
- "One commit per task" remains the implementation agent's convention. Commits without a corresponding task entry (e.g., infrastructure commits inserted by the agent) inherit the phase of the most recent prior phase-tagged commit when present, or omit the trailer otherwise.
- Cross-feature phase coordination, deploy automation, deploy-state tracking, and rollback automation are explicitly out of scope.
