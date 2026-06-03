# Contract: Phase-Aware Specify (`speckit.specify.md`)

## Scope

Changes to the existing `/speckit.specify` command to add phase-aware spec generation.

## Input

Same as current: a natural language feature description provided as `$ARGUMENTS`.

## Output Change

The generated spec.md gains a new `## Phases` section when the feature description involves multiple deployment concerns. The rest of the spec structure is unchanged.

## Phase Detection Trigger

The specify step evaluates whether the feature description warrants multiple phases. Multi-phase generation triggers when **any** of these signals are present:

- Database migration terms: schema change, migration, expand-and-contract, alter table, new columns
- Third-party integration terms: API key, webhook, OAuth, payment provider, external service
- Infrastructure-touching patterns: shared service, middleware, message queue, cache invalidation
- Large scope: 4+ user stories with distinct concern areas

If **none** of these signals are present (all stories are low-risk additive work), a single phase with `direct release` is generated.

## Phase Section Format

```markdown
## Phases

### Phase {N}: {slug}
**Stories**: {comma-separated story references}
**Release Strategy**: {dark launch with gradual reveal | direct release}
**Rationale**: {explanation of boundary}
```

## Constraints

- Each user story assigned to exactly one phase
- Phase numbers are sequential starting from 1
- Maximum 10 phases
- Phase slugs are kebab-case
- Single-concern features produce a single phase, not zero phases
- The Phases section is placed between User Scenarios and Requirements

## Backward Compatibility

- Specs generated from simple feature descriptions still produce a single phase (no artificial splitting)
- The Phases section is additive; all existing spec sections remain unchanged
- Existing specs without a Phases section continue to work with all pipeline steps
- The splitting skill treats a spec without a Phases section as an error (suggests running `/speckit.specify`)
