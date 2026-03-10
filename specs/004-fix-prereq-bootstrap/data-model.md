# Data Model: Fix Prerequisite Bootstrap Ordering

This feature is a bug fix on shell scripts and markdown command files. There are no traditional data entities (databases, APIs, classes). The "data model" here describes the key data flows and state transitions in the pipeline bootstrap process.

## Entity: Pipeline Invocation State

Represents the state of the pipeline at startup, before any step executes.

| Field | Type | Description |
|-------|------|-------------|
| `FROM_STEP` | string (enum) | Starting step: `specify`, `homer`, `plan`, `tasks`, `lisa`, `ralph`, or empty (auto-detect) |
| `DESCRIPTION` | string | Feature description text (required when `FROM_STEP=specify`) |
| `SPEC_DIR_ARG` | string | Explicit spec directory argument (optional) |
| `FEATURE_DIR` | string | Resolved feature directory path (e.g., `specs/004-fix-prereq-bootstrap`) |
| `is_bootstrapping` | boolean (derived) | True when `FROM_STEP=specify` or `DESCRIPTION` is non-empty and no spec.md exists |

## Entity: Feature Directory Resolution

The process of converting startup arguments into a `FEATURE_DIR` path.

| Resolution Mode | Trigger | Validation | Source |
|----------------|---------|------------|--------|
| Explicit directory | `spec-dir` argument provided | Directory must exist | CLI argument |
| Branch auto-detect (existing) | No `spec-dir`, on feature branch, spec dir exists | Directory must exist | `git branch` + filesystem scan |
| Branch auto-detect (bootstrap) | No `spec-dir`, on feature branch, no spec dir, bootstrapping | No existence check | `git branch` name only |
| `check-prerequisites.sh --json` | `speckit.pipeline.md` without bootstrap flags | Full validation (dir + plan.md) | Script output |
| `check-prerequisites.sh --paths-only` | `speckit.pipeline.md` with bootstrap flags | No validation | Script output |

## State Transitions

```text
Pipeline Start
  │
  ├── is_bootstrapping=true
  │     │
  │     ├── resolve FEATURE_DIR (no existence check)
  │     ├── run specify step (creates branch, dir, spec.md)
  │     ├── run homer step (spec.md now exists, validated)
  │     └── continue normally...
  │
  └── is_bootstrapping=false
        │
        ├── resolve FEATURE_DIR (with existence check)
        ├── validate artifacts for starting step
        └── continue normally...
```

## Relationship Map

```text
speckit.pipeline.md ──calls──> check-prerequisites.sh
  │                               │
  │ (bootstrap: --paths-only)     │ (normal: --json)
  │                               │
  └──> specify agent ──calls──> create-new-feature.sh
         │                          │
         │ creates:                 │ creates:
         ├── feature branch         ├── branch
         ├── specs/NNN-name/        ├── directory
         └── specs/NNN-name/spec.md └── spec.md

pipeline.sh
  │
  ├── resolve_feature_dir()
  │     ├── explicit dir (exists check)
  │     ├── branch auto-detect (exists check)
  │     └── branch auto-detect (bootstrap, NO exists check) ← NEW
  │
  └── specify step → create-new-feature.sh → creates artifacts
```
