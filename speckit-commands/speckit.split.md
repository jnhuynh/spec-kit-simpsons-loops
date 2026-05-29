---
description: Split a phase-annotated spec into independent child specs, one per phase.
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Outline

1. Run `.specify/scripts/bash/check-prerequisites.sh --json` from repo root and parse FEATURE_DIR from the JSON output. All paths must be absolute. For single quotes in args like "I'm Groot", use escape syntax: e.g 'I'\''m Groot' (or double-quote if possible: "I'm Groot").

2. Read the parent spec at `FEATURE_DIR/spec.md`.

3. **Parse the `## Phases` section** from the parent spec:

   a. Locate the `## Phases` section. If no `## Phases` section exists, report this error and **STOP**:
      ```
      ERROR: No phase annotations found in spec.md.
      Run `/speckit.specify` to generate phase annotations before splitting.
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

6. **For each phase, create or update the child spec directory**:

   a. Compute the child directory name: `{parent-directory-name}--p{N}-{phase-slug}`
      - If the total directory name exceeds 200 characters, truncate the slug portion to fit within 200 characters while preserving `{parent-directory-name}--p{N}-`, and warn the developer about the truncation

   b. Create the directory under `specs/` if it does not exist: `specs/{child-directory-name}/`

   c. **Generate or update the child `spec.md`**:
      - If the child spec does not exist (first run), generate it fresh
      - If the child spec already exists (re-run), run the **reconciliation logic** described in step 6e below

   d. **Child spec content** (for new child specs): Generate a standard SpecKit spec structure populated with the content relevant to this phase. The child spec must be independently processable through the full SpecKit pipeline.

      Structure the child spec as follows:

      ```markdown
      # Feature Specification: {feature name} - Phase {N}: {slug}

      **Feature Branch**: `{parent-branch}--p{N}-{slug}`
      **Created**: {current date}
      **Status**: Draft
      **Parent Spec**: `{parent-directory-name}/spec.md`
      **Phase**: {N} of {total phases}

      ## User Scenarios & Testing *(mandatory)*

      {Include only the user stories assigned to this phase from the Phases section.
       Copy the full user story content (title, description, priority, acceptance scenarios)
       from the parent spec for each assigned story.}

      ## Requirements *(mandatory)*

      ### Functional Requirements

      {Include functional requirements relevant to this phase's stories.
       Relevance is determined by story assignment:
       - Include requirements that directly reference or support the user stories assigned to this phase
       - Requirements not tied to any specific story are included in Phase 1's child spec only
       - Each requirement appears in exactly one child spec}

      ### Key Entities *(include if feature involves data)*

      {Include key entities relevant to this phase, if any}

      ## Success Criteria *(mandatory)*

      ### Measurable Outcomes

      {Include success criteria that validate the requirements included in this phase.
       Success criteria not tied to any specific story are included in Phase 1's child spec only.
       Each criterion appears in exactly one child spec.}

      ## Assumptions

      {Include assumptions relevant to this phase from the parent spec.
       Add an assumption noting this is Phase {N} of a {total}-phase feature,
       with a reference to the parent spec for the overall feature context.}
      ```

      **Independence requirement**: Each child spec must be self-contained. Do not include references to sibling specs that would block pipeline execution. Do not use phrases like "after Phase 1 is complete" in requirements -- instead, state the prerequisite condition directly (e.g., "Given the schema has been expanded with X columns" rather than "After Phase 1 deploys the schema changes").

   e. **Reconciliation logic** (for existing child specs on re-run):

      When a child spec already exists on disk, reconcile it with the current state of the parent spec and earlier child specs. Process phases in order (P1 first, then P2, etc.) so that earlier-phase changes are available when reconciling later phases.

      **Step 1 -- Generate the baseline**: For each child spec, regenerate what the child spec *would* contain if generated fresh from the current parent spec's phase annotations using the same generation logic as step 6d. This regenerated content is the "baseline" -- it represents the expected content without any manual edits.

      **Step 2 -- Detect manual edits**: Compare the baseline (from Step 1) section-by-section against the actual child spec on disk. Use markdown heading boundaries (`##` and `###` level headings) to identify sections. A section where the disk content differs from the baseline has been manually edited by the developer.

      **Step 3 -- Generate updated content for later phases**: For child specs at phase 2 and above, regenerate the child spec content using the **actual content from earlier child specs on disk** (not the baseline). This "updated content" reflects what the child spec should contain given the current state of earlier phases. Compare this updated content against the baseline from Step 1 to identify which sections are affected by earlier-phase changes.

      **Step 4 -- Apply reconciliation per section**:
      - If a section has **no manual edits** (disk matches baseline) AND the updated content differs from the baseline (earlier-phase changes affect this section): **update the section in place** with the updated content from Step 3.
      - If a section has **no manual edits** AND the updated content matches the baseline (no earlier-phase changes): **leave the section unchanged**.
      - If a section has **manual edits** (disk differs from baseline) AND the updated content also differs from the baseline (conflict between manual edits and propagated changes): **insert conflict markers** around the section using the format:
        ```markdown
        <!-- CONFLICT: {description of what changed in the earlier phase that affects this section} -->
        {the existing section content from disk, preserved as-is}
        <!-- END CONFLICT -->
        ```
        The description in the CONFLICT marker must identify which earlier phase changed and what the change affects, so the developer has context for resolution.
      - If a section has **manual edits** AND the updated content matches the baseline (no earlier-phase changes): **leave the section unchanged** (manual edits are preserved, nothing to propagate).

      **Step 5 -- Report conflicts**: After reconciliation, report any conflicts to the developer. For each conflict, include:
      - The child spec file path
      - The section heading where the conflict was inserted
      - A brief description of the conflict (what changed in the earlier phase vs what the developer edited)

      **Phase 1 child specs**: Phase 1 has no earlier phases, so Steps 3-4 simplify to: detect manual edits (Step 2), and preserve the child spec as-is. Phase 1 child specs are never updated by reconciliation -- they serve as input to later phases.

7. **Create or update the `## Manifest` section in the parent spec**:

   a. If no manifest exists, append a `## Manifest` section at the end of the parent spec.

   b. Before the manifest table, include this notice:
      ```markdown
      > **Note**: This spec has been split into phases. Pipeline steps (`/speckit.plan`, `/speckit.tasks`, etc.) should be run on individual child specs listed below, not on this parent spec.
      ```

   c. Generate the manifest table with columns: Phase, Directory, Description, Status, Release Strategy

      ```markdown
      ## Manifest

      > **Note**: This spec has been split into phases. Pipeline steps (`/speckit.plan`, `/speckit.tasks`, etc.) should be run on individual child specs listed below, not on this parent spec.

      | Phase | Directory | Description | Status | Release Strategy |
      |-------|-----------|-------------|--------|------------------|
      | P1: {slug} | {parent}--p1-{slug} | {brief description from rationale} | Draft | {strategy} |
      | P2: {slug} | {parent}--p2-{slug} | {brief description from rationale} | Draft | {strategy} |
      ```

   d. **Status preservation**: If a manifest already exists from a previous run, preserve manually-set status values for existing phases. New phases get status "Draft".

   e. **Status transition validation**: When a manifest already exists, validate that any status values in the existing manifest are consistent with the forward-only state machine before writing the updated manifest. For each phase present in both the old and new manifest:

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

   f. **Idempotency**: Re-running on an unchanged spec with unchanged child specs must produce an identical manifest table.

8. **Report results**:
   - List each child spec directory created or updated
   - Show the manifest table
   - If any directory names were truncated, repeat the truncation warnings
   - If this was a re-run, note which phases were unchanged vs updated

## Idempotency

Running `/speckit.split` multiple times on the same unchanged parent spec and child specs must produce identical results:
- No duplicate child directories
- Manifest table is identical after each run
- Existing child spec content is unchanged when no upstream changes exist

## Error Reference

| Condition | Behavior |
|-----------|----------|
| No `## Phases` section in spec.md | ERROR: suggest running `/speckit.specify` |
| More than 10 phases | ERROR: suggest consolidating phases |
| Directory name exceeds 200 characters | WARNING: truncate slug, create directory, warn developer |
| Phase numbers not sequential | ERROR: report which numbers are missing or out of order |
| Duplicate story assignments | ERROR: report which stories appear in multiple phases |
| Invalid status transition | ERROR: report the phase, current status, and attempted new status; explain allowed transitions |
