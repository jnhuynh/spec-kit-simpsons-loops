# Contract: Splitting Skill (`speckit.split.md`)

## Invocation

```
/speckit.split
```

Run from within a project that has a phase-annotated spec. The command detects the current feature directory from the active branch or prompts the user.

## Input

- Parent spec.md with a `## Phases` section containing phase annotations
- Existing child spec directories (if re-running)

## Output

### On First Run

1. Creates one child spec directory per phase under `specs/`:
   - Directory name: `{parent-directory-name}--p{N}-{phase-slug}`
   - Each directory contains a `spec.md` with standard SpecKit structure
2. Appends a `## Manifest` section to the parent spec.md with a tracking table
3. Reports: number of children created, directory names, manifest location

### On Re-Run (Idempotent)

1. Updates existing child specs based on changes in phase annotations and earlier child specs
2. Creates new child spec directories for added phases
3. Preserves directories for removed phases but marks them Cancelled in manifest
4. Inserts conflict markers in child specs where manual edits conflict with propagated changes
5. Updates the manifest table
6. Reports: what changed, any conflicts flagged

## Error Conditions

| Condition | Behavior |
|-----------|----------|
| No `## Phases` section in spec.md | ERROR: "No phase annotations found. Run `/speckit.specify` to generate phase annotations." |
| More than 10 phases | ERROR: "Maximum 10 phases exceeded ({N} found). Consolidate phases before splitting." |
| Directory name exceeds 200 characters | WARNING: Truncates slug, creates directory, warns developer |
| Invalid status transition in manifest | ERROR: "{status1} -> {status2} is not a valid transition for phase {N}" |

## Idempotency Guarantee

Running `/speckit.split` N times on an unchanged parent spec and unchanged child specs produces the same result as running it once:

- No duplicate child directories
- Manifest table is identical after each run
- Existing child spec content is unchanged when no upstream changes exist

## Child Spec Independence

Each generated child spec must be independently executable through the full SpecKit pipeline:

```
/speckit.plan -> /speckit.tasks -> /speckit.homer.clarify -> /speckit.lisa.analyze -> /speckit.ralph.implement -> /speckit.marge.review
```

Child specs must not contain references to sibling specs that would block pipeline execution.
