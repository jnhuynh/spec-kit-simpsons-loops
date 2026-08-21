---
name: speckit-split
description: Split a phase-annotated spec into independent child specs, one per phase.
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Outline

1. Run `.specify/scripts/bash/check-prerequisites.sh --json --require-tasks` from repo root and parse FEATURE_DIR from the JSON output. The `--require-tasks` flag makes the check require **both** `plan.md` and `tasks.md` to exist before splitting: the spec is decomposed only after the whole-feature plan and task list are in place, so the phase boundaries have been validated against the full implementation design rather than the spec alone. If either artifact is missing, the script reports it (e.g. "Run /speckit-plan first" or "Run /speckit-tasks first") and exits non-zero — stop and surface that message instead of proceeding. All paths must be absolute. For single quotes in args like "I'm Groot", use escape syntax: e.g 'I'\''m Groot' (or double-quote if possible: "I'm Groot").

2. Read the parent spec at `FEATURE_DIR/spec.md`.

3. **Parse the `## Phases` section** from the parent spec:

   a. Locate the `## Phases` section. If no `## Phases` section exists, report this error and **STOP**:
      ```
      ERROR: No phase annotations found in spec.md.
      Run `/speckit-phase` to generate phase annotations before splitting.
      ```

   b. Parse each phase subsection (`### Phase {N}: {slug}`) and extract:
      - Phase number (integer)
      - Slug (kebab-case string)
      - Assigned stories (from the `**Stories**:` line)
      - Release strategy (from the `**Release Strategy**:` line)
      - Rationale (from the `**Rationale**:` line)

   c. **Validate phases**:
      - Phase count must not exceed 10. If it does, report this error and **STOP**:
        ```
        ERROR: Maximum 10 phases exceeded ({N} found). Consolidate phases before splitting.
        ```
      - Phase numbers must be sequential starting from 1 with no gaps
      - Each slug must be valid kebab-case (lowercase alphanumeric and hyphens only)
      - Each user story must be assigned to exactly one phase (no duplicates, no omissions)

4. **Determine the parent directory name**:
   - Extract the directory name from FEATURE_DIR (e.g., if FEATURE_DIR is `specs/c31c-feat-billing-overhaul`, the parent directory name is `c31c-feat-billing-overhaul`)

5. **Check for existing manifest and child directories**:
   - Check if the parent spec already has a `## Manifest` section (indicates a previous split)
   - If a manifest exists, parse the existing status values for each phase entry
   - Check which child directories already exist under `specs/`

   **Detect added and removed phases** (when a manifest exists from a previous split):

   a. **Added phases**: Phases present in the current parent `## Phases` annotations (from step 3) but absent from the existing manifest. These are new phases the developer added to the parent spec after the initial split. They will receive new child spec directories in step 6 and appear in the manifest with status "Draft" in step 7.

   b. **Removed phases**: Phases present in the existing manifest but absent from the current parent `## Phases` annotations. These are phases the developer removed from the parent spec. Their child directories are **preserved on disk** (never deleted). They will be marked as "Cancelled" in the manifest in step 7.

   c. **Continuing phases**: Phases present in both the current annotations and the existing manifest. These proceed through the normal create-or-update logic in step 6.

6. **For each phase, create or update the child spec directory** (skip removed/cancelled phases):

   **Important**: Only process phases that are present in the current parent `## Phases` annotations (continuing phases and added phases). Do NOT create or refresh child specs for removed phases -- their directories remain on disk untouched, and they are handled solely through the manifest in step 7.

   a. Compute the child directory name: `{parent-directory-name}--p{N}-{phase-slug}`
      - If the total directory name exceeds 200 characters, truncate the slug portion to fit within 200 characters while preserving `{parent-directory-name}--p{N}-`, and warn the developer about the truncation

   b. Create the directory under `specs/` if it does not exist: `specs/{child-directory-name}/`

   c. **Generate or refresh the child `spec.md`**:
      - If the child spec does not exist (first run), generate it from the shape in step 6d
      - If the child spec already exists (re-run), refresh only its derived sections per step 6e

   d. **Child spec content** (first run): A child spec is a **phase view** of the parent, not a copy of it. User stories, functional requirements, key entities, and success criteria are defined **once** -- in the parent -- and are referenced by ID from the child. **Never copy parent prose into a child spec.**

      Two ID namespaces keep authorship unambiguous:

      - **Inherited IDs** (`User Story N`, `FR-###`, `SC-###`, entity names) belong to the parent. The child lists them; it never restates or redefines them.
      - **Phase-local IDs** (`FR-P{N}-###`, `SC-P{N}-###`) belong to the child. They cover requirements that exist *only because the work is phased* -- feature flags, dark-launch scaffolding, backfills, compatibility shims. The `P{N}` infix makes collision with parent IDs impossible.

      Generate the child `spec.md` in this shape:

      ```markdown
      # Feature Specification: {feature name} - Phase {N}: {slug}

      **Feature Branch**: `{parent-branch}--p{N}-{slug}`
      **Created**: {current date}
      **Status**: Draft
      **Parent Spec**: `../{parent-directory-name}/spec.md` <- AUTHORITATIVE
      **Phase**: {N} of {total phases}
      **Release Strategy**: {release strategy for this phase}

      > **This is a phase view, not a standalone spec.** User stories, requirements,
      > key entities, and success criteria are defined once in the parent spec and are
      > **not** restated here. Any agent or reviewer reading this file MUST read the
      > parent sections named under **Inherited Scope** before planning, implementing,
      > analyzing, or reviewing this phase.

      ## Inherited Scope

      Authoritative source: `../{parent-directory-name}/spec.md`

      | Kind | Parent reference | Parent section |
      |------|------------------|----------------|
      | User Story | {story id and title, with priority} | `## User Scenarios & Testing` |
      | Functional Requirement | {comma-separated FR ids} | `## Requirements` -> Functional Requirements |
      | Key Entity | {comma-separated entity names} | `## Requirements` -> Key Entities |
      | Success Criterion | {comma-separated SC ids} | `## Success Criteria` |

      **Deferred elsewhere**: {ids owned by other phases, each annotated with its phase}

      ## Phase Boundary

      **Entry state** -- what is already true when this phase starts:

      - {condition delivered by an earlier phase, stated as present-tense fact}

      **Exit state** -- what must be true when this phase is deployed and validated:

      - {observable condition that closes this phase}

      ## User Scenarios & Testing *(mandatory)*

      Inherited: {story ids} -- see **Inherited Scope**. The parent spec is authoritative.

      ## Requirements *(mandatory)*

      Inherited: {FR ids} -- see **Inherited Scope**. The parent spec is authoritative.

      Phase-local additions:

      - **FR-P{N}-001**: {requirement that exists only because the work is phased}

      ### Key Entities

      Inherited: {entity names} -- see **Inherited Scope**. The parent spec is authoritative.

      ## Success Criteria *(mandatory)*

      Inherited: {SC ids} -- see **Inherited Scope**. The parent spec is authoritative.

      Phase-local additions:

      - **SC-P{N}-001**: {criterion that validates the phase boundary itself}
      ```

      **Content rules**:

      - Copy **no** prose from the parent. Only IDs, entity names, and story titles cross the boundary -- a title is a label for the reference, not a restatement of the story.
      - Every parent user story, functional requirement, key entity, and success criterion MUST appear in exactly one child's Inherited Scope. Items tied to no specific story belong to Phase 1's child.
      - Keep the canonical headings (`## User Scenarios & Testing`, `## Requirements`, `## Success Criteria`) even when a phase adds nothing of its own -- upstream Spec Kit commands (`/speckit-plan`, `/speckit-tasks`, `/speckit-analyze`) look for them.
      - Omit a "Phase-local additions" list when the phase adds none; always keep the `Inherited:` line.
      - Write entry state as present-tense fact, never as a dependency on a sibling ("`provider_ref` exists, nullable, unbackfilled" -- not "after Phase 1 adds `provider_ref`"). The Manifest and the pipeline's phase order guard already encode sequencing.

   e. **Refresh logic** (existing child specs on re-run):

      A child spec holds exactly two kinds of content, and only one of them is derived:

      - **Derived** -- the title line, the metadata block, `## Inherited Scope`, and the `Inherited:` line under each canonical heading. All of it comes from the parent's `## Phases` section. Regenerate it in place on every run.
      - **Authored** -- `## Phase Boundary` and the phase-local `FR-P{N}-###` / `SC-P{N}-###` entries. Written by a developer, or by the pipeline while the phase is worked. **Never overwrite, reorder, or delete them.**

      Re-running split therefore needs no baseline regeneration, no section diffing, and no conflict markers. The parent holds exactly one copy of every inherited item, so a parent edit cannot conflict with a child -- it simply becomes visible to every child that references it. Re-phasing (a story moved between phases) surfaces as a changed Inherited Scope table and nothing else.

      **Orphaned phase-local requirements**: if a refresh moves an inherited item out of a phase whose authored `FR-P{N}-###` or `SC-P{N}-###` entries reference that item, refresh the table anyway and report the affected phase-local IDs so the developer can revisit them. Do not edit or delete authored content to resolve this.

7. **Create or update the `## Manifest` section in the parent spec**:

   a. If no manifest exists, append a `## Manifest` section at the end of the parent spec.

   b. Before the manifest table, include this notice:
      ```markdown
      > **Note**: This spec has been split into phases. Pipeline steps (`/speckit-plan`, `/speckit-tasks`, etc.) should be run on individual child specs listed below, not on this parent spec. This spec remains the **single source of truth** for user stories, requirements, key entities, and success criteria -- the children reference them by ID and never restate them, so requirement edits and clarifications belong here.
      ```

   c. Generate the manifest table with columns: Phase, Directory, Description, Status, Release Strategy

      ```markdown
      ## Manifest

      > **Note**: This spec has been split into phases. Pipeline steps (`/speckit-plan`, `/speckit-tasks`, etc.) should be run on individual child specs listed below, not on this parent spec. This spec remains the **single source of truth** for user stories, requirements, key entities, and success criteria -- the children reference them by ID and never restate them, so requirement edits and clarifications belong here.

      | Phase | Directory | Description | Status | Release Strategy |
      |-------|-----------|-------------|--------|------------------|
      | P1: {slug} | {parent}--p1-{slug} | {brief description from rationale} | Draft | {strategy} |
      | P2: {slug} | {parent}--p2-{slug} | {brief description from rationale} | Draft | {strategy} |
      ```

   d. **Status preservation and phase management**: If a manifest already exists from a previous run:
      - **Continuing phases**: Preserve manually-set status values for phases present in both the old manifest and the current annotations.
      - **Added phases**: Phases present in the current annotations but absent from the old manifest get status "Draft".
      - **Removed phases**: Phases present in the old manifest but absent from the current annotations are marked "Cancelled" in the updated manifest. Their child directories remain on disk untouched (never deleted). If a removed phase was already "Cancelled" in the old manifest, its status remains "Cancelled". If a removed phase had status "Complete", report an error per the status transition validation in step 7e (Complete -> Cancelled is invalid).

   e. **Manifest ordering**: The manifest table lists all phases in phase-number order. Continuing and added phases appear at their position from the current annotations. Removed phases retain their original phase number from the old manifest and appear in order alongside the current phases. This provides a complete view of all phases -- active and cancelled -- in a single table.

   f. **Status transition validation**: When a manifest already exists, validate that any status values in the existing manifest are consistent with the forward-only state machine before writing the updated manifest. For each phase present in both the old and new manifest:

      **Valid transitions** (allowed):
      - Draft -> In Progress
      - In Progress -> Complete
      - Draft -> Cancelled
      - In Progress -> Cancelled
      - Any status -> same status (no change)

      **Invalid transitions** (rejected):
      - In Progress -> Draft
      - Complete -> Draft
      - Complete -> In Progress
      - Complete -> Cancelled
      - Cancelled -> Draft
      - Cancelled -> In Progress
      - Cancelled -> Complete

      **Note**: Complete is NOT an active state. Both Complete -> Cancelled and Cancelled -> Complete are invalid.

      If the splitting skill would set a status that requires an invalid transition (e.g., a phase marked "Complete" by the developer would be overwritten with "Draft" by a fresh re-run), report an error and **STOP**:
      ```
      ERROR: Invalid status transition for Phase {N} ({slug}): {old status} -> {new status}.
      Status transitions must be forward-only: Draft -> In Progress -> Complete. Active states (Draft, In Progress) may transition to Cancelled. Backward transitions and transitions from terminal states (Complete, Cancelled) are not permitted.
      ```

      **Implementation detail**: The splitting skill itself only ever sets status to "Draft" (for new phases) or preserves existing values (per step 7d). Invalid transitions arise when a developer manually sets a status value in the manifest and then the splitting skill re-runs. The validation catches cases where the developer set an invalid transition (e.g., moving a Complete phase back to Draft) before the manifest is written, providing an early error rather than silently accepting an invalid state.

   g. **Idempotency**: Re-running on an unchanged spec with unchanged child specs must produce an identical manifest table.

8. **Report results**:
   - List each child spec directory created or refreshed
   - Show the manifest table
   - If any directory names were truncated, repeat the truncation warnings
   - If this was a re-run, note which children had their derived sections refreshed and which were unchanged
   - If any refresh orphaned a phase-local `FR-P{N}-###` / `SC-P{N}-###` entry, list the affected IDs (per step 6e)
   - If phases were added, list the new child spec directories created
   - If phases were removed, list the phases marked as "Cancelled" and confirm their directories were preserved on disk

## Idempotency

Running `/speckit-split` multiple times on the same unchanged parent spec and child specs must produce identical results:
- No duplicate child directories
- Manifest table is identical after each run
- Derived child sections regenerate byte-identically when the parent's `## Phases` section is unchanged
- Authored child content (`## Phase Boundary`, phase-local `FR-P{N}-###` / `SC-P{N}-###`) is never touched

## Error Reference

| Condition | Behavior |
|-----------|----------|
| `plan.md` or `tasks.md` missing | ERROR from the prerequisite check (`--require-tasks`): run `/speckit-plan` and/or `/speckit-tasks` first — split requires the whole-feature plan and tasks before decomposing |
| No `## Phases` section in spec.md | ERROR: suggest running `/speckit-phase` |
| More than 10 phases | ERROR: suggest consolidating phases |
| Directory name exceeds 200 characters | WARNING: truncate slug, create directory, warn developer |
| Phase numbers not sequential | ERROR: report which numbers are missing or out of order |
| Duplicate story assignments | ERROR: report which stories appear in multiple phases |
| Invalid status transition | ERROR: report the phase, current status, and attempted new status; explain allowed transitions |
| Removed phase with Complete status | ERROR: invalid transition Complete -> Cancelled; explain that completed phases cannot be cancelled |
| Removed phase (active status) | Mark as Cancelled in manifest, preserve child directory on disk |
| Added phase (not in manifest) | Create new child spec directory, add to manifest with status Draft |
| Refresh orphans a phase-local requirement | WARNING: refresh the Inherited Scope table, list the affected `FR-P{N}-###` / `SC-P{N}-###` IDs, leave authored content untouched |
