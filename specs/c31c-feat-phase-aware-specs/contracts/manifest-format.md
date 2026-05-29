# Contract: Manifest Section Format

## Location

Appended to the end of the parent spec.md by the splitting skill.

## Table Format

```markdown
## Manifest

| Phase | Directory | Description | Status | Release Strategy |
|-------|-----------|-------------|--------|------------------|
| P1: {slug} | {parent}--p1-{slug} | {brief description} | Draft | {strategy} |
| P2: {slug} | {parent}--p2-{slug} | {brief description} | Draft | {strategy} |
```

## Column Definitions

| Column | Type | Description |
|--------|------|-------------|
| Phase | `P{N}: {slug}` | Phase number and descriptive slug |
| Directory | String | Child spec directory name (relative to `specs/`) |
| Description | Free text | One-line summary of the phase scope |
| Status | Enum | One of: `Draft`, `In Progress`, `Complete`, `Cancelled` |
| Release Strategy | String | `dark launch with gradual reveal` or `direct release` |

## Status Values and Transitions

### Valid Statuses

- **Draft**: Initial state after splitting. No work has started.
- **In Progress**: Developer has begun working on this phase.
- **Complete**: Phase implementation and review are finished.
- **Cancelled**: Phase was removed from the plan or abandoned.

### Valid Transitions

```
Draft -> In Progress        (developer starts work)
In Progress -> Complete     (developer finishes work)
Draft -> Cancelled          (phase removed before work begins)
In Progress -> Cancelled    (phase abandoned during work)
```

### Invalid Transitions

All backward transitions are rejected:
- Complete -> Draft
- Complete -> In Progress
- Cancelled -> Draft
- Cancelled -> In Progress
- Cancelled -> Complete

## Update Rules

- The splitting skill creates the manifest on first split
- The splitting skill updates the manifest on re-run (adds new phases, marks removed phases as Cancelled)
- Developers update the Status column manually
- The splitting skill preserves manually-set status values during re-runs
- The splitting skill validates status transitions: if a re-run would require an invalid transition, it reports an error
