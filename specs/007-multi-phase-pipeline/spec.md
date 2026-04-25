# Feature Specification: Multi-Phase Pipeline for SpecKit Simpsons

**Feature Branch**: `007-multi-phase-pipeline`
**Created**: 2026-04-25
**Status**: Draft
**Input**: User description: "Multi-Phase Pipeline for SpecKit Simpsons - phaser stage between Ralph and Marge for stacked PRs in zero-downtime deploys"

## Overview

SpecKit Simpsons currently ships every feature as a single branch with a single pull request. This works for code-only changes but produces unsafe deploys when a feature touches production schemas, data, or infrastructure where zero-downtime correctness requires deploying in stages (for example, schema migration, then backfill, then code switch, then cleanup). This feature adds a **phaser stage** to the pipeline that sits between the implementation step and the review step, classifies each implemented task by its deploy-safety category, validates that risky operations are accompanied by their required predecessor tasks, and computes a deterministic phase split that drives stacked branches and stacked pull requests. The phasing capability is **opt-in**: a project that does not select a "flavor" (a project-specific catalog of task types and rules) sees no behavior change.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Phaser Engine Validates and Splits Tasks Using a Pluggable Flavor (Priority: P1)

A pipeline maintainer needs a generic phasing engine that does not know anything about Rails or Postgres. The engine consumes a project-supplied flavor (a catalog of task types, isolation rules, precedent rules, and inference rules) plus the set of commits on a feature branch, and emits a phase manifest that lists which commits go into which phase, in what order. A toy "example-minimal" flavor with two task types and one precedent rule exists purely to prove the engine carries no domain leakage from any specific real flavor.

**Why this priority**: Without a working, flavor-agnostic engine, no real flavor can be built and the pipeline cannot be extended. Every other story depends on this. The example-minimal flavor is the regression contract that protects future flavors from accidental coupling to the first real flavor.

**Independent Test**: Run the phaser command-line entry point against a synthetic feature branch with the example-minimal flavor configured. Verify that the resulting phase manifest is identical across repeated runs on the same input, that the split respects the precedent and isolation rules declared by the flavor, that an untagged task is assigned the flavor's default type, and that the engine source contains no references to Rails, Postgres, or any other concrete technology.

**Acceptance Scenarios**:

1. **Given** a feature branch with five commits and the example-minimal flavor active, **When** the phaser stage runs, **Then** a phase manifest is emitted that groups the commits according to the flavor's isolation and precedent rules and is byte-identical to the manifest produced by re-running the same input.
2. **Given** a commit whose file changes match no inference rule and carries no operator-supplied type tag, **When** the phaser stage classifies it, **Then** the commit is assigned the flavor's declared default type and proceeds without error.
3. **Given** a flavor declares a precedent rule "type A must be preceded by type B in an earlier phase," **When** a feature branch contains a type-A commit with no preceding type-B commit, **Then** the phaser fails with an error that names the offending commit and explains the missing precedent.
4. **Given** the engine source code, **When** inspected for references to Rails, Postgres, strong_migrations, ActiveRecord, or any other concrete framework or database, **Then** no such references are found.

---

### User Story 2 - Reference Flavor for Rails + Postgres + strong_migrations (Priority: P2)

A team running a Rails application backed by Postgres with the strong_migrations gem needs a ready-to-use flavor that classifies their tasks correctly. The flavor ships a complete catalog of deploy-safety task types (nullable column adds, concurrent indexes, validated foreign keys, batched backfills, code dual-writes, ignored-columns directives, drop-column with required precedent, and more), a file-pattern inference layer that classifies most commits without operator tagging, validators that catch unsafe backfill scripts and missing precedents, and a registry of forbidden operations that get rejected with a canonical decomposition message.

**Why this priority**: This is the first real-world demonstration that the engine produces useful phasing decisions. It also unblocks dogfooding inside any Rails+Postgres team that adopts SpecKit Simpsons. Without it, the phaser engine is theoretical.

**Independent Test**: Run the phaser stage against a fixture set that exercises every type in the catalog, every forbidden operation, and the column-rename worked example. Verify that every fixture is classified correctly, every forbidden operation is rejected with the canonical decomposition message, every backfill-safety violation is caught, and the column-rename example produces exactly seven ordered phases without any operator intervention.

**Acceptance Scenarios**:

1. **Given** a fixture commit that adds a nullable column with no default, **When** the flavor's inference layer classifies it, **Then** the commit is tagged as "schema add-nullable-column."
2. **Given** a fixture commit that adds a concurrent index, **When** classified, **Then** the commit is tagged as "schema add-concurrent-index."
3. **Given** a backfill rake task that lacks batching, throttling, or the directive to run outside a transaction, **When** the backfill-safety validator runs, **Then** the task is rejected with an error that names the missing safeguard.
4. **Given** a commit that drops a column without earlier commits that mark the column as ignored AND remove all references to it, **When** the precedent validator runs, **Then** the drop-column commit is rejected with an error naming the missing precedent commits.
5. **Given** a commit that performs a forbidden operation (such as a direct column-type change, a direct rename, or a non-concurrent index), **When** the inference layer encounters it, **Then** the commit is rejected with the canonical decomposition message that lists the safe sequence of replacement tasks.
6. **Given** the worked example for renaming a `users.email` column to `users.email_address` with all required commits in place, **When** the phaser stage runs, **Then** exactly seven phases are produced in the order specified by the worked example with no operator intervention required.
7. **Given** a commit carries an operator-supplied type tag, **When** classification runs, **Then** the operator's tag overrides the inference layer's guess.

---

### User Story 3 - Phaser Integrated as a Real Pipeline Stage with Per-Phase and Holistic Review (Priority: P3)

A user who runs the end-to-end SpecKit pipeline expects the phaser to slot in as a normal stage between the implementation step and the review step. After phasing, the review step (Marge) runs once per phase, scoped to that phase's diff range, and then runs once more across the whole feature for cross-phase concerns. The phase manifest is committed to the feature's spec directory so it is auditable and re-runnable. If no flavor is configured, the pipeline behaves exactly as today: single phase, single review pass, single pull request.

**Why this priority**: The engine and flavor are useless until they are actually invoked by the pipeline that users run every day. This story is what turns the phaser from a tool into a workflow. Backward compatibility is critical so that adopters who do not need phasing are not disrupted.

**Independent Test**: Run the full pipeline on a feature branch in a project with the Rails flavor configured, and verify that the phase manifest is committed to the spec directory, that per-phase review passes are observable in the pipeline output, and that a holistic review pass runs after the per-phase passes complete. Then delete the flavor configuration and re-run the pipeline against a different feature branch, and verify it behaves exactly as today.

**Acceptance Scenarios**:

1. **Given** a project with a flavor configured and a feature branch ready for review, **When** the pipeline runs, **Then** the phaser stage executes after the implementation step and before the review step, the phase manifest is written to the feature's spec directory, and the manifest is included in the feature branch's commit history.
2. **Given** a phase manifest with N phases, **When** the review step runs, **Then** the review runs N+1 times: once per phase scoped to that phase's diff range, plus once across the whole feature for cross-phase concerns.
3. **Given** a feature branch contains a commit that violates a precedent rule, **When** the phaser stage runs, **Then** the pipeline halts with an error that names the offending commit and the missing precedent, and the review step is not invoked.
4. **Given** a project that has no flavor configuration, **When** the pipeline runs end-to-end, **Then** the phaser stage is skipped, the review step runs as a single pass over the whole feature, a single pull request is produced, and no phase manifest is created.

---

### User Story 4 - Stacked Branches and Stacked Pull Requests Auto-Created from the Phase Manifest (Priority: P4)

After the phaser produces a manifest, the user wants stacked branches and stacked pull requests created automatically. Each phase becomes its own branch (named after the feature branch with a phase suffix) based on the previous phase's branch, and each branch gets its own pull request whose description includes the phase rationale, the rollback plan, and a link to the previous phase's pull request. Each phase's branch runs continuous integration independently so phases can be merged in order with confidence.

**Why this priority**: Reviewers and deployers cannot safely act on a single mega-pull-request that contains a schema change, a backfill, and a code switch. This story turns the manifest into the artifact deployers actually use.

**Independent Test**: Run the phaser stage with stacked-PR creation enabled on a multi-phase feature, then verify that the expected branches exist with the correct base relationships, that one pull request exists per phase, that each pull request body contains the phase rationale and rollback plan, that each non-first pull request links to the previous phase's pull request, and that continuous integration is triggered independently for each branch.

**Acceptance Scenarios**:

1. **Given** a phase manifest with N phases for feature branch `<feature>`, **When** stacked-PR creation runs, **Then** branches `<feature>-phase-1` through `<feature>-phase-N` exist, each based on the previous phase's branch (with phase 1 based on the project's default integration branch).
2. **Given** stacked branches exist, **When** pull request creation runs, **Then** one pull request is opened per phase, each containing the phase rationale, the rollback plan, and the dependency relationship to the previous phase.
3. **Given** stacked pull requests exist, **When** continuous integration triggers fire, **Then** each phase branch runs its own continuous integration pipeline independently of the other phases.
4. **Given** phase N has been merged into the integration branch, **When** the maintainer is ready to advance, **Then** phase N+1's pull request is open and ready for review (the system does not block phase N+1 review on deploy confirmation in this version).

---

### User Story 5 - One-Shot Flavor Initialization Command (Priority: P5)

A maintainer who wants to opt a project into phasing should be able to run a single command that detects the project's stack, suggests the matching flavor, asks for confirmation, and writes the flavor configuration file. If no shipped flavor matches, the command exits cleanly with a "no flavor matched" message rather than guessing. A force option overwrites an existing flavor configuration.

**Why this priority**: Lowering the activation cost from "read the docs and hand-write a configuration" to "run one command and confirm" is the difference between a feature that gets adopted and one that does not. This story is last because everything else can be exercised by writing the flavor file by hand; this is convenience, not capability.

**Independent Test**: Run the command in three repositories: a Rails project that uses Postgres and includes the strong_migrations gem, a project with no recognizable stack, and a project that already has a flavor configuration. Verify the suggested flavor in case one, the clean "no flavor matched" exit in case two, the refusal-to-overwrite default in case three, and the successful overwrite when the force flag is supplied.

**Acceptance Scenarios**:

1. **Given** a Rails project whose dependency manifest declares Postgres and the strong_migrations gem, **When** the flavor initialization command runs, **Then** the command suggests the rails-postgres-strong-migrations flavor, asks for confirmation, and on confirmation writes the flavor configuration to the project's SpecKit configuration directory.
2. **Given** a project whose stack matches no shipped flavor, **When** the command runs, **Then** it reports "no flavor matched" and exits without writing any file.
3. **Given** a project that already has a flavor configuration file, **When** the command runs without the force option, **Then** it refuses to overwrite and exits with a non-zero status.
4. **Given** the same project, **When** the command runs with the force option, **Then** the existing flavor configuration is overwritten with the newly suggested one.

---

### Edge Cases

- A commit touches files that match more than one inference rule (for example, a single commit that adds both a migration and a model change). The phaser must resolve this deterministically. The chosen rule is the one with the highest declared precedence in the flavor's rule order; ties are broken by rule name, alphabetically.
- A flavor's rule catalog changes mid-feature (someone updates the flavor while a feature is already in flight). The phase manifest pins the flavor version it was generated against, so re-running the phaser on an in-flight feature does not re-classify previously classified commits unless the operator explicitly opts in.
- An operator supplies a type tag that is not in the flavor's catalog. The phaser fails with an error that names the unknown tag and lists the valid tags from the active flavor.
- A commit's diff is empty (for example, a merge commit or a tag-only commit). The phaser skips it, does not classify it, and does not include it in the manifest.
- A backfill task is part of a feature that contains two such tasks. By default the two backfills are placed in sequential phases, not the same phase. An override mechanism in the flavor can permit parallel placement, but the default is sequential.
- A feature has only "groups"-isolation tasks (no "alone"-isolation tasks). The phaser produces a single phase containing all of them.
- A feature has only "alone"-isolation tasks (no "groups"-isolation tasks). The phaser produces one phase per task, in commit order, subject to precedent rules.
- The pipeline is re-run on a feature branch whose phase manifest already exists in the spec directory. The phaser regenerates the manifest from the current commits and overwrites the file; if any classification changed, the change is visible in the diff and the operator can review it before continuing.
- The flavor configuration file exists but references a flavor name that is not shipped with the installed phaser. The pipeline halts with an error that names the unknown flavor and lists the shipped flavors.
- A phase contains only one task. The phaser still emits a phase entry for it; the stacked-PR creator still creates a single-task branch and pull request for it.
- A long-running backfill (multi-hour) blocks the next phase's pull request from opening. This version does not orchestrate that wait; the operator must merge the backfill phase manually when ready. A follow-up specification will address long-running backfill orchestration.

## Requirements *(mandatory)*

### Functional Requirements

#### Phaser Engine (User Story 1)

- **FR-001**: The phaser engine MUST consume a feature branch's commit list together with a project-supplied flavor (a catalog of task types, isolation rules, precedent rules, inference rules, and a default type) and produce a phase manifest.
- **FR-002**: The phaser engine MUST be deterministic: the same feature branch with the same flavor at the same flavor version MUST produce a byte-identical phase manifest on repeated runs.
- **FR-003**: The phaser engine MUST contain no logic specific to any concrete framework, database, or programming language; all such knowledge MUST live in flavors.
- **FR-004**: The phaser engine MUST classify each commit by either honoring an operator-supplied type tag (highest precedence) or applying the flavor's inference rules in declared precedence order, falling back to the flavor's declared default type when no rule matches.
- **FR-005**: The phaser engine MUST enforce the flavor's isolation rules: tasks declared as "alone" MUST be placed in their own phase, and tasks declared as "groups" MAY share a phase with other "groups" tasks subject to precedent rules.
- **FR-006**: The phaser engine MUST enforce the flavor's precedent rules: a task whose type requires a predecessor type MUST be placed in a strictly later phase than its predecessor; if no qualifying predecessor exists in the feature branch, the engine MUST fail with an error that names the offending commit and the missing predecessor.
- **FR-007**: The phaser engine MUST reject any operator-supplied type tag that is not present in the active flavor's catalog, naming both the unknown tag and the valid tags.
- **FR-008**: The phaser engine MUST be invocable as a standalone command for testing, independent of the full pipeline.
- **FR-009**: The phaser engine MUST skip commits with empty diffs (such as merge or tag-only commits) without including them in the manifest.

#### Reference Rails Flavor (User Story 2)

- **FR-010**: The reference flavor MUST ship a catalog of deploy-safety task types covering at minimum: nullable column add, column add with static default, table add, concurrent index add, foreign key add without validation, foreign key validation, check constraint add without validation, check constraint validation, virtual not-null via check, real not-null flip after check, column default change, column drop with required code-cleanup precedent, table drop, concurrent index drop, batched backfill, batched cleanup, default catch-all code change, dual-write old-and-new column, switch reads to new column, ignore column for pending drop, remove all references to a pending-drop column, remove ignored-columns directive, feature-flag create-default-off, feature-flag enable, feature-flag remove, infrastructure provision, infrastructure wire, and infrastructure decommission.
- **FR-011**: The reference flavor MUST classify each catalog type's isolation as either "alone" (own phase) or "groups" (may share a phase with other "groups" tasks).
- **FR-012**: The reference flavor MUST provide a file-pattern inference layer that correctly classifies, without operator intervention, every commit in a shipped fixture set that exercises every type in the catalog.
- **FR-013**: The reference flavor MUST provide a backfill-safety validator that rejects backfill commits lacking batching, throttling between batches, or the directive to run outside a transaction; the rejection error MUST name the missing safeguard.
- **FR-014**: The reference flavor MUST provide a precedent validator that rejects a column-drop commit that is not preceded by both an "ignore column for pending drop" commit AND a "remove all references to column" commit; the rejection error MUST name the missing precedent commits.
- **FR-015**: The reference flavor MUST ship a registry of forbidden operations (such as direct column-type change, direct rename, non-concurrent index, direct not-null add, direct foreign-key add, column add with volatile default, and column drop without code cleanup) and MUST reject any commit performing one of them with a canonical decomposition message that lists the safe sequence of replacement tasks for that forbidden operation.
- **FR-016**: The reference flavor MUST honor an operator-supplied per-commit type tag (delivered via a commit message trailer) that overrides the inference layer's classification.
- **FR-017**: The reference flavor MUST ship a fixture for the worked example "rename `users.email` to `users.email_address`" and the phaser MUST produce exactly seven ordered phases from this fixture without any operator intervention.
- **FR-018**: The reference flavor MUST require that any commit which performs an irreversible schema operation references the precedent commit hash in its safety-assertion block, so that audit reviewers can trace the precedent chain.

#### Pipeline Integration (User Story 3)

- **FR-019**: The pipeline MUST invoke the phaser stage after the implementation step and before the review step when a flavor configuration is present in the project.
- **FR-020**: The pipeline MUST commit the phase manifest to the feature's spec directory under a fixed file name and include it in the feature branch.
- **FR-021**: The phase manifest MUST record the flavor name, the flavor version, the generation timestamp, the feature branch name, and for each phase: the phase number, a human-readable name, the branch name to use, the base branch, the ordered list of tasks (each with its identifier, classified type, and source commit hash), the continuous-integration gates applicable to that phase, and a rollback note.
- **FR-022**: The review step MUST accept a directive to scope its review to the diff range between two specified phase boundaries.
- **FR-023**: The pipeline MUST run the review step once per phase (each scoped to that phase's diff range) and then once more holistically across the whole feature; the holistic pass MUST run after all per-phase passes have completed.
- **FR-024**: The pipeline MUST halt with a clear error when the phaser stage fails, MUST NOT invoke the review step in that case, and the error MUST name the offending commit and the failing rule.
- **FR-025**: The pipeline MUST behave exactly as it did before this feature when no flavor configuration is present in the project: no phaser stage, no per-phase review, no stacked-PR creation, no phase manifest, single pull request.

#### Stacked Branches and Pull Requests (User Story 4)

- **FR-026**: For a phase manifest with N phases on feature branch `<feature>`, the system MUST create branches named `<feature>-phase-1` through `<feature>-phase-N`, with each phase branch based on the previous phase's branch and phase 1 based on the project's default integration branch.
- **FR-027**: The system MUST open one pull request per phase branch, and each pull request body MUST include the phase rationale, the rollback plan, and (for non-first phases) a link to the previous phase's pull request.
- **FR-028**: Each phase branch MUST trigger its own continuous-integration pipeline independently of the other phase branches.
- **FR-029**: This version MUST advance to opening phase N+1's pull request as soon as phase N is merged into the integration branch (deploy confirmation is not required to unblock N+1).
- **FR-030**: This version MUST NOT auto-rebase later phase branches when an upstream phase changes; rebasing remains a manual operator step.

#### Flavor Initialization Command (User Story 5)

- **FR-031**: The flavor-initialization command MUST detect the project's stack by inspecting the project's dependency manifest and other well-known signals declared by each shipped flavor.
- **FR-032**: When exactly one shipped flavor matches, the command MUST suggest that flavor, ask for confirmation, and on confirmation write the flavor configuration file to the project's SpecKit configuration directory.
- **FR-033**: When no shipped flavor matches, the command MUST report "no flavor matched" and exit with a non-zero status without writing any file.
- **FR-034**: When the flavor configuration file already exists, the command MUST refuse to overwrite it by default and exit with a non-zero status; a force option MUST be available to override this refusal.

#### Cross-Cutting

- **FR-035**: The phase manifest MUST pin the flavor version that produced it; re-running the phaser on an in-flight feature MUST NOT re-classify previously classified commits unless the operator explicitly opts in.
- **FR-036**: The phaser MUST treat a commit that matches multiple inference rules as belonging to the rule with the highest declared precedence in the flavor; ties MUST be broken alphabetically by rule name to preserve determinism.
- **FR-037**: When a feature contains multiple backfill tasks, the phaser MUST place them in sequential phases by default; a flavor-level override MAY permit parallel placement.
- **FR-038**: The phase manifest file format MUST be human-readable and reviewable in a code-review tool.

### Key Entities

- **Flavor**: A project-specific catalog that names task types, declares each type's isolation rule (alone or groups), declares precedent rules between types, declares inference rules that map file patterns or content patterns to types, declares the default type for unmatched commits, declares the registry of forbidden operations and their canonical decomposition messages, and carries a version number that is pinned by every manifest it produces.
- **Task Type**: A named category of work (for example, "schema add-nullable-column" or "code dual-write") that carries an isolation rule and may participate in precedent rules.
- **Phase**: An ordered group of one or more classified commits from a feature branch that can safely be deployed together as a single unit before the next phase begins. A phase has a number, a human-readable name, a branch name, a base branch, an ordered task list, applicable continuous-integration gates, and a rollback note.
- **Phase Manifest**: The artifact produced by the phaser for one feature, listing the active flavor and version, the generation timestamp, the feature branch name, and the ordered phases.
- **Precedent Rule**: A flavor-declared statement that a task of type X must be placed in a strictly later phase than at least one task of type Y from the same feature.
- **Isolation Rule**: A flavor-declared statement that a task of type X must occupy its own phase (alone) or may share a phase with other groups-isolation tasks (groups).
- **Forbidden Operation**: A flavor-declared category of work that has no valid task type because it is unsafe for production deploys. It is paired with a canonical decomposition message that lists the safe sequence of replacement tasks.
- **Flavor Configuration File**: The project-level file that selects which shipped flavor a project uses; its presence opts the project into phasing, its absence opts the project out.
- **Stacked Pull Request**: A pull request opened against the previous phase's branch (rather than the project's default integration branch), used to review and deploy a single phase in isolation while keeping the dependency chain explicit.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A team running the canonical column-rename worked example end-to-end with the reference flavor configured produces exactly seven phases, seven stacked pull requests, and zero operator interventions during phasing.
- **SC-002**: The same feature branch with the same flavor produces a byte-identical phase manifest on every re-run, verified across at least 100 consecutive runs of the engine's deterministic-output regression test.
- **SC-003**: The phaser engine source code, when scanned for references to any concrete framework, database, or library name shipped in the reference flavor, contains zero such references.
- **SC-004**: At least 90 percent of commits in the reference flavor's shipped fixture set are classified correctly by the file-pattern inference layer without any operator-supplied type tag.
- **SC-005**: Every entry in the forbidden-operations registry has a regression test that produces the canonical decomposition message when the forbidden operation is encountered.
- **SC-006**: A project that does not have a flavor configuration file installed runs the full pipeline and produces a single pull request with no phaser-related output, no phase manifest, and no behavioral difference from the pre-feature pipeline; verified by a regression test that diffs the pipeline output against a captured baseline.
- **SC-007**: A maintainer can opt a Rails+Postgres+strong_migrations project into phasing with a single command invocation followed by one confirmation prompt, with no manual file authoring required.
- **SC-008**: When the phaser stage fails on a precedent or forbidden-operation violation, the resulting error message names the offending commit and the violated rule precisely enough that the maintainer can correct the issue without reading the phaser engine source.
- **SC-009**: When a phase manifest is committed to the spec directory, a reviewer can determine, by reading the manifest alone, the exact list of branches and pull requests that will be created and the exact order in which they must be merged and deployed.

## Assumptions

- The phaser engine is implemented in a language that allows the reference flavor to parse its target language's source files natively. The user's input nominates Ruby for this purpose; no other language has been requested.
- The project uses Git as its version control system and a Git-hosting service that supports stacked pull requests through a command-line interface. The user's input references the GitHub command-line tool; the same workflow is assumed available for any Git host with equivalent stacked-PR semantics.
- Continuous-integration runs per branch are configured by the project's existing CI system, not by this feature. The phaser's role is to produce branches and pull requests; CI configuration is out of scope.
- Long-running backfill orchestration (operations that take hours and might block the opening of a downstream phase's pull request) is intentionally deferred to a follow-up specification. Until then, operators are expected to manage long backfills manually.
- Cross-service phasing (where one phase deploys a change to service A and the next phase deploys a change to service B) is out of scope for this version. This feature targets single-repository features only.
- Auto-rebase of stacked branches when an upstream phase changes is out of scope for this version. Rebasing remains a manual operator action.
- A single feature branch maps to a single database in the reference flavor. Projects with multiple databases per service are not supported by this version of the reference flavor.
- The reference flavor delegates migration-file-level safety checks to the existing strong_migrations gem rather than reimplementing them; the reference flavor's validators add the orchestration-level concerns (precedent enforcement, backfill-script structure, decomposition of forbidden operations) that the gem does not cover.
- The default branch for stacking phase 1 is the project's standard integration branch (commonly named `main` or `master`); the actual name is read from the project's configuration rather than assumed.
- Operator-supplied per-commit type tags are delivered via a commit message trailer (for example, a line of the form `Phase-Type: <type-name>` in the commit message), as nominated in the user's input.
- The "holistic" review pass is run by the same review agent as the per-phase passes, with no scope filter applied; it sees the full feature diff and is expected to surface concerns that span phase boundaries.
- Per-phase pull requests advance to "open for review" as soon as the previous phase is merged. Deploy confirmation is not required to unblock the next phase in this version; this is documented behavior, not a defect.
