# Feature Specification: Phase-Aware Specs with Splitting Skill

**Feature Branch**: `c31c-feat-phase-aware-specs`  
**Created**: 2026-05-28  
**Status**: Draft  
**Input**: User description: "SpecKit's specify step becomes phase-aware. When generating a spec, it analyzes user stories for natural deployment boundaries and groups stories into ordered phases within the spec. A new splitting skill takes a phase-annotated spec and generates independent child specs, one per phase."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Phase-Aware Spec Generation (Priority: P1)

A developer runs `/speckit.specify` with a large feature description that involves multiple deployment stages -- for example, a billing overhaul requiring schema migration, third-party payment integration, and UI changes. The specify step analyzes the user stories for natural deployment boundaries and groups them into ordered phases within the spec. Each phase includes a recommended release strategy (dark launch or direct release) based on risk assessment. The developer can review the phase groupings and release recommendations directly in the spec before proceeding to planning.

**Why this priority**: Phase annotation within the spec is the foundation that all other capabilities build on. Without phase metadata in the spec, the splitting skill has nothing to work with. This also delivers standalone value -- even without splitting, seeing the recommended phase boundaries helps developers plan their work.

**Independent Test**: Can be fully tested by running `/speckit.specify` with a multi-concern feature description and verifying the resulting spec.md contains a Phases section with ordered phase groupings, story assignments, and release strategy recommendations.

**Acceptance Scenarios**:

1. **Given** a feature description involving database migration, third-party integration, and UI work, **When** the developer runs `/speckit.specify`, **Then** the spec contains a Phases section grouping stories into ordered phases with rationale for each boundary.
2. **Given** a feature description where all stories are low-risk additive work, **When** the developer runs `/speckit.specify`, **Then** the spec contains a single phase with a direct release recommendation.
3. **Given** a feature description with stories touching shared infrastructure, **When** the developer runs `/speckit.specify`, **Then** the stories touching shared infrastructure are grouped into an early phase with a dark launch recommendation.

---

### User Story 2 - Splitting a Phase-Annotated Spec (Priority: P1)

After reviewing a phase-annotated spec, the developer runs the new splitting skill. The splitting skill reads the phase metadata from the parent spec and generates one independent child spec directory per phase. All specs live as flat siblings under `specs/`, using a naming convention that expresses the parent-child and phase-order relationships (e.g., `c31c-feat-billing-overhaul` as parent, `c31c-feat-billing-overhaul--p1-expand-schema`, `c31c-feat-billing-overhaul--p2-integration`, `c31c-feat-billing-overhaul--p3-ui-reveal` as children). Each child spec has the same structure as any standard spec (spec.md) and can proceed through the full SpecKit pipeline independently. The parent spec is updated with a manifest section tracking all children in order with their status.

**Why this priority**: Splitting is the core new capability that enables multi-phase feature delivery. Without it, phase annotations are informational only. This is co-P1 with phase-aware generation because the two capabilities form a complete workflow.

**Independent Test**: Can be fully tested by creating a phase-annotated spec, running the splitting skill, and verifying child spec directories are created with correct naming, each containing a well-formed spec.md, and the parent spec contains a manifest listing all children in order.

**Acceptance Scenarios**:

1. **Given** a spec with three annotated phases, **When** the developer runs the splitting skill, **Then** three child spec directories are created under `specs/` with the naming convention `{parent-name}--p{N}-{phase-slug}`.
2. **Given** a spec with three annotated phases, **When** the developer runs the splitting skill, **Then** the parent spec is updated with a manifest section listing all children in order with status "Draft".
3. **Given** a child spec directory, **When** the developer runs `/speckit.plan` or any other pipeline step on it, **Then** the pipeline step works identically to how it works on any standalone spec.
4. **Given** a spec with a single phase, **When** the developer runs the splitting skill, **Then** the tool produces one child spec and a parent manifest with a single entry.

---

### User Story 3 - Child Spec Chain Awareness (Priority: P2)

When implementation of an earlier phase diverges from its original spec, the developer edits the earlier child spec to match what was actually built. The developer then uses the splitting skill to reconcile later child specs with the updated reality. Later child specs are updated to pick up from where things actually stand rather than from the original plan. This keeps the chain grounded in reality rather than drifting from what was implemented.

**Why this priority**: Chain awareness is what makes multi-phase delivery practical over time. Without it, later phases would plan against outdated assumptions. However, the basic split-and-execute flow (Stories 1 and 2) delivers value even without reconciliation.

**Independent Test**: Can be fully tested by splitting a spec into phases, modifying the first child spec to simulate implementation divergence, re-running the splitting skill, and verifying later child specs reflect the updated content from the first phase.

**Acceptance Scenarios**:

1. **Given** a parent with three child specs where the P1 child spec has been edited to reflect implementation reality, **When** the developer re-runs the splitting skill, **Then** the P2 and P3 child specs are updated to account for changes in P1.
2. **Given** a parent with three child specs where the P1 child spec is unchanged, **When** the developer re-runs the splitting skill, **Then** the P2 and P3 child specs remain unchanged.

---

### User Story 4 - Phase Status Tracking (Priority: P2)

The developer wants to see where a multi-phase feature stands at a glance. They check the parent spec's manifest and see which phases are complete, in progress, or still in draft. This tells them where to pick up work and which phases may need updating based on earlier phase outcomes.

**Why this priority**: Status tracking is essential for ongoing multi-phase work but depends on the split structure already existing. It enables the "living chain" concept where developers always know the current state.

**Independent Test**: Can be fully tested by creating a split spec, marking one child's status as complete, and verifying the parent manifest reflects the correct status for each child.

**Acceptance Scenarios**:

1. **Given** a parent spec with a manifest of three children, **When** one child spec's status is updated to "Complete", **Then** the parent manifest reflects "Complete" for that child and "Draft" for the others.
2. **Given** a parent spec with a manifest, **When** the developer views the manifest, **Then** they see each child listed in phase order with its current status (Draft, In Progress, Complete).

---

### User Story 5 - Adding and Removing Phases After Initial Split (Priority: P3)

After shipping the first phase and gathering production feedback, the developer realizes the original three-phase plan needs adjustment -- perhaps the third phase should be split into two, or a planned phase is no longer needed. The developer re-runs the splitting skill, which reconciles the existing child specs with the updated phase annotations in the parent spec. New child directories are created for added phases, removed phases have their directories preserved but marked as cancelled in the manifest, and existing phases are left intact.

**Why this priority**: Flexible phase management is important for real-world usage where plans change, but the core value of phase-aware specs and basic splitting is delivered by higher-priority stories.

**Independent Test**: Can be fully tested by splitting a spec, modifying the parent spec's phase annotations to add and remove phases, re-running the splitting skill, and verifying new directories are created, removed phases are marked cancelled, and existing phases are preserved.

**Acceptance Scenarios**:

1. **Given** a parent with three child specs, **When** the developer adds a fourth phase annotation to the parent spec and re-runs the splitting skill, **Then** a fourth child spec directory is created and the manifest is updated with four entries.
2. **Given** a parent with three child specs, **When** the developer removes the third phase annotation from the parent spec and re-runs the splitting skill, **Then** the third child spec directory is preserved but the manifest marks it as "Cancelled".
3. **Given** a parent with a cancelled phase, **When** the developer re-runs the splitting skill without that phase, **Then** the cancelled child directory remains on disk untouched.

---

### Edge Cases

- What happens when a developer runs the splitting skill on a spec that has no phase annotations? The splitting skill reports an error indicating no phases were found and suggests running `/speckit.specify` to generate phase annotations first.
- What happens when a child spec directory already exists from a previous split? The splitting skill updates the existing child spec rather than overwriting it, preserving any manual edits the developer made.
- What happens when the parent spec's naming convention would produce a child directory name exceeding filesystem limits? The splitting skill truncates the phase slug portion while preserving the parent prefix and phase number, and warns the developer.
- What happens when two phases have stories with overlapping concerns? The specify step assigns each story to exactly one phase and documents cross-phase dependencies in the phase annotations.
- What happens when a developer tries to run the pipeline on a parent spec that has been split? The parent spec serves as a coordination document only -- pipeline steps like `/speckit.plan` operate on individual child specs, not the parent.
- What happens when a manual edit in a child spec conflicts with a change propagated from an earlier phase during reconciliation? The splitting skill inserts inline conflict markers (e.g., `<!-- CONFLICT: ... -->`) around the conflicting sections and reports the conflicts to the developer for manual resolution, rather than silently overwriting edits.

## Clarifications

### Session 2026-05-28

- Q: What valid status transitions are allowed for child specs? → A: Forward-only: Draft → In Progress → Complete. Any active state → Cancelled. No backward transitions.
- Q: What happens when a manual edit in a child spec conflicts with a change propagated from an earlier phase during reconciliation? → A: Flag conflicts with inline markers for developer resolution rather than auto-resolving.
- Q: What is explicitly out of scope for this feature? → A: Branch automation, CI/CD infrastructure, non-linear phase dependencies, cross-repo splitting, automatic status detection, and phase-level diffing.
- Q: What is the maximum number of phases a spec can have? → A: Maximum 10 phases per parent spec. Splitting skill rejects specs exceeding this limit.

## Out of Scope

The following are explicitly excluded from this feature:

- **Automated branch creation**: The splitting skill creates spec directories only. Git branch creation for child specs is the developer's responsibility when they begin work on a phase.
- **CI/CD or deployment infrastructure**: Release strategy recommendations ("dark launch" / "direct release") are informational guidance. This feature does not create feature flags, canary configurations, or deployment pipelines.
- **Non-linear phase dependencies**: Phases are strictly ordered (P1, P2, P3...). DAG-style dependency graphs between phases are not supported.
- **Cross-repository splitting**: All child specs live under the same `specs/` directory in the same repository. Splitting across multiple repositories is not supported.
- **Automatic status detection**: Phase status (Draft, In Progress, Complete, Cancelled) is manually set by the developer. SpecKit does not auto-detect completion based on pipeline state or branch activity.
- **Phase-level diffing or changelog**: The splitting skill does not generate diffs or changelogs between versions of child specs. Conflict markers flag divergence, but detailed change tracking is not provided.

## Requirements *(mandatory)*

### Functional Requirements

#### Phase-Aware Specify

- **FR-001**: The specify step MUST analyze user stories for natural deployment boundaries including: database migrations requiring expand-and-contract sequencing, third-party integrations needing production validation, and feature size that would produce unreviewable PRs.
- **FR-002**: The specify step MUST group user stories into ordered phases within the spec and assign each story to exactly one phase.
- **FR-003**: For each phase, the specify step MUST recommend a release strategy: "dark launch with gradual reveal" for high-risk changes touching shared infrastructure, integrations, or migrations, or "direct release" for low-risk additive work like new endpoints or UI additions.
- **FR-004**: Phase grouping and release strategy MUST be recorded as a dedicated section in the spec (not inline with stories), so downstream tools can parse and consume this metadata.
- **FR-005**: When all stories are low-risk additive work, the specify step MUST produce a single phase with a direct release recommendation rather than artificial multi-phase splitting.
- **FR-006**: Each phase annotation MUST include: phase number, short descriptive slug, assigned story references, release strategy recommendation, and rationale for the phase boundary.

#### Splitting Skill

- **FR-007**: The splitting skill MUST read phase annotations from a parent spec and generate one child spec directory per phase under `specs/`.
- **FR-008**: Child spec directories MUST follow the naming convention `{parent-directory-name}--p{N}-{phase-slug}`, where N is the phase number and phase-slug is a kebab-case label.
- **FR-009**: Each child spec MUST contain a spec.md with the same structure as any standard SpecKit spec, populated with the stories, requirements, and success criteria relevant to that phase.
- **FR-010**: Each child spec MUST be independently executable through the full SpecKit pipeline (plan, tasks, homer, lisa, ralph, marge).
- **FR-011**: The splitting skill MUST update the parent spec with a manifest section listing all child specs in phase order with their current status.
- **FR-012**: The splitting skill MUST be idempotent -- re-running it on an already-split spec updates existing children rather than creating duplicates.
- **FR-012a**: A parent spec MUST NOT contain more than 10 phases. The splitting skill MUST reject specs exceeding this limit with an error message indicating the maximum and suggesting the developer consolidate phases.

#### Child Spec Chain and Reconciliation

- **FR-013**: When the splitting skill is re-run, later child specs MUST be updated to reflect changes in earlier child specs, so each phase builds on what was actually implemented rather than originally planned.
- **FR-014**: The splitting skill MUST preserve manual edits in existing child specs when re-running, merging only the changes from updated phase annotations and earlier-phase divergence. When a manual edit conflicts with a propagated change, the splitting skill MUST flag the conflict with inline markers (e.g., `<!-- CONFLICT: ... -->`) for developer resolution rather than auto-resolving.
- **FR-015**: When a phase is removed from the parent spec's annotations, the splitting skill MUST preserve the child directory on disk but mark it as "Cancelled" in the parent manifest.
- **FR-016**: When a new phase is added to the parent spec's annotations, the splitting skill MUST create a new child spec directory in the correct phase-order position.

#### Status Tracking

- **FR-017**: The parent spec manifest MUST track each child spec's status as one of: Draft, In Progress, Complete, or Cancelled.
- **FR-018**: The status view MUST be human-readable directly in the parent spec's manifest section, showing phase order, child directory name, description, and status.
- **FR-019**: Status transitions MUST follow a forward-only state machine: Draft → In Progress → Complete. Any active state (Draft, In Progress) MAY transition to Cancelled. Backward transitions (e.g., Complete → Draft, Cancelled → In Progress) are NOT permitted.

### Key Entities

- **Parent Spec**: A phase-annotated specification that describes an overall feature with multiple deployment phases. Contains the feature vision, phase annotations with release strategies, and a manifest tracking child specs. Lives in a standard spec directory (e.g., `specs/c31c-feat-billing-overhaul/`).
- **Child Spec**: An independent specification for a single phase of a larger feature. Has the same structure as any standard spec (spec.md, and eventually plan.md, tasks.md). Lives in a sibling directory under `specs/` with a naming convention linking it to its parent (e.g., `specs/c31c-feat-billing-overhaul--p1-expand-schema/`).
- **Phase Annotation**: Metadata within a parent spec that defines a deployment phase -- its number, slug, assigned stories, release strategy, and boundary rationale.
- **Manifest**: A section in the parent spec that lists all child specs in phase order with their status. Serves as the coordination hub for multi-phase delivery.
- **Release Strategy**: A recommendation attached to each phase -- either "dark launch with gradual reveal" (for high-risk changes) or "direct release" (for low-risk additive work). Informational guidance, not deployment infrastructure.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A multi-concern feature description (involving migration, integration, and UI work) produces a spec with at least 2 distinct phases when run through the specify step, with each phase having a documented release strategy recommendation.
- **SC-002**: The splitting skill generates child spec directories that each pass the existing spec quality checklist without modification, confirming they are structurally valid standalone specs.
- **SC-003**: Each child spec can be independently processed through the full SpecKit pipeline (specify -> homer -> plan -> tasks -> lisa -> ralph -> marge) without errors or references to sibling specs that would block execution.
- **SC-004**: Re-running the splitting skill after modifying an earlier child spec produces updated later child specs within one re-run, without requiring manual intervention to propagate changes.
- **SC-005**: A developer can determine the current state of a multi-phase feature (which phases are complete, in progress, or draft) by reading the parent spec manifest alone, without inspecting individual child directories.
- **SC-006**: A simple additive feature description produces a single-phase spec with no unnecessary phase splitting, confirming the specify step does not over-segment straightforward work.

## Assumptions

- The `--` double-dash separator in child directory names (e.g., `parent--p1-slug`) will not conflict with existing SpecKit naming conventions or tooling. Current specs use single-dash kebab-case, making `--` a safe delimiter to distinguish parent-child relationships.
- Phase boundary detection is a best-effort heuristic, not a guarantee. The specify step uses common patterns (migration signals, integration keywords, PR size estimates) to suggest boundaries. Developers are expected to review and adjust phase groupings before splitting.
- "Dark launch with gradual reveal" and "direct release" are the two release strategy categories. This is intentionally coarse-grained -- teams map these to their own deployment practices (feature flags, canary releases, etc.).
- Child specs do not need their own Git branches at creation time. The splitting skill creates spec directories only. Branch creation happens when a developer starts working on a specific phase and runs the standard SpecKit pipeline entry point for that child spec.
- The reconciliation logic (updating later phases when earlier ones diverge) is content-aware but not automatic rewriting. The splitting skill identifies what changed in earlier phases and flags sections in later child specs that may need updating, rather than silently rewriting spec content.
- Status transitions are manually set by the developer following a forward-only state machine (Draft → In Progress → Complete, with any active state allowing Cancelled). SpecKit does not auto-detect phase completion or enforce transitions at runtime; the constraint is documented for tooling and developer guidance.
- A parent spec supports a maximum of 10 phases. Features requiring more than 10 deployment stages should be decomposed into separate top-level features rather than a single deeply-phased spec. This keeps reconciliation manageable and child directory naming practical.
