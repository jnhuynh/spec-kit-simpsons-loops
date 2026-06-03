---
description: Detect deployment boundaries in a spec's user stories and generate phase annotations.
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Outline

Analyze the user stories in an existing `spec.md` for natural deployment boundaries and generate the `## Phases` section. This command runs after `/speckit.specify` has created the spec and before Homer clarifies it.

## Instructions

1. **Resolve the feature directory**: Run `bash .specify/scripts/bash/check-prerequisites.sh --json --paths-only` from repo root via Bash tool. Parse the JSON output for `FEATURE_DIR` and `FEATURE_SPEC`. If the script exits non-zero, display its output and stop.

2. **Read `spec.md`**: Read the spec file at `FEATURE_SPEC`. If it does not exist, display an error and stop.

3. **Parse user stories**: Locate the `## User Scenarios & Testing` section and extract all user stories from it (their titles, descriptions, and acceptance scenarios).

4. **Detect deployment boundary signals** across all user stories:
   - **Migration signals**: schema change, migration, expand-and-contract, alter table, new columns, database restructuring
   - **Integration signals**: API key, webhook, OAuth, payment provider, external service, third-party dependency
   - **Infrastructure signals**: shared service, middleware, message queue, cache invalidation, infrastructure provisioning
   - **Scope signals**: 4+ user stories with distinct concern areas (e.g., backend data, external integration, user-facing UI)

5. **Assign each story to exactly one phase** using vertical-slice grouping by product surface:

   a. **Identify product surfaces**: Group stories by the product surface, domain, or concern area they affect (e.g., payments, user profiles, notifications). Use story titles, descriptions, and the entities/data they reference to determine grouping.

   b. **Order surfaces by dependency**: If surface B depends on surface A (e.g., notifications depend on payment events), surface A's phases come first. Independent surfaces are ordered by risk (higher risk first) as a tiebreaker.

   c. **Slice each surface vertically**: Within each product surface, assign phases in deployment dependency order -- foundational changes (migrations, infrastructure) in one phase, then dependent features (integrations, services) and user-facing work (UI, endpoints) in the next phase. Each surface should be fully deployable before the next surface begins.

   d. **Merge thin layers**: If a surface has only one story or its foundational and UI layers are trivially small, merge them into a single phase rather than creating two phases with one story each.

   e. **Result**: A feature touching N product surfaces produces up to 2N phases (foundation + feature per surface), ordered so each surface is complete before the next starts. The collective set of surfaces forms the full feature.

6. **Determine release strategy per phase**:
   - **"dark launch with gradual reveal"**: for phases containing stories with migration signals, integration signals, or infrastructure signals (high-risk changes touching shared systems)
   - **"direct release"**: for phases containing only low-risk additive work (new endpoints, UI additions, documentation) with no migration, integration, or infrastructure signals

7. **Single-concern features**: If **none** of the signals above are detected (all stories are low-risk additive work), generate a single phase containing all stories with release strategy "direct release". Do not artificially split straightforward work into multiple phases.

8. **Write the `## Phases` section** into `spec.md` using the results from steps 4-7. Place this section between `## User Scenarios & Testing` (after all its subsections) and `## Requirements`. If a `## Phases` section already exists (populated or placeholder), replace it entirely. If no `## Phases` section exists, insert a new one at the correct position.

   Format each phase as a subsection:

   ```markdown
   ## Phases

   ### Phase {N}: {slug}
   **Stories**: {comma-separated story references, e.g., "User Story 1, User Story 3"}
   **Release Strategy**: {dark launch with gradual reveal | direct release}
   **Rationale**: {explanation of why this phase boundary exists}
   ```

   **Constraints**:
   - Phase numbers MUST be sequential starting from 1 with no gaps
   - Maximum 10 phases per spec -- if the analysis produces more than 10, consolidate related phases until the count is 10 or fewer
   - Each user story MUST be assigned to exactly one phase -- no story appears in multiple phases and no story is omitted
   - Phase slugs MUST be valid kebab-case (lowercase alphanumeric and hyphens, e.g., `expand-schema`, `payment-integration`)
   - Single-concern features produce exactly one phase, not zero phases

9. **Report results**: Output the number of phases generated, each phase's slug and release strategy, and confirm the section was written to spec.md.
