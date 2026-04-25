# Data Model: Multi-Phase Pipeline for SpecKit Simpsons

**Branch**: `007-multi-phase-pipeline` | **Date**: 2026-04-25

This document describes the entities the phaser engine, the reference flavor, the stacked-PR creator, and the flavor-init command operate on. Field-level YAML schemas live alongside this file in `contracts/`.

## Entities

### Flavor

A project-supplied catalog that names the task types, isolation rules, precedent rules, inference rules, default type, forbidden-operations registry, and stack-detection signals for one project's deploy-safety domain. Each shipped flavor lives at `phaser/flavors/<flavor-name>/` as a `flavor.yaml` plus optional Ruby pattern modules.

| Attribute | Type | Description |
|---|---|---|
| `name` | string | Globally unique flavor identifier (e.g., `rails-postgres-strong-migrations`). Matches the directory name. |
| `version` | string (semver) | Version pinned by every manifest the flavor produces (FR-035). |
| `default_type` | string | Task type assigned to commits that match no inference rule (FR-004). MUST be present in `task_types`. |
| `task_types` | list of TaskType | Catalog of all valid task types. |
| `precedent_rules` | list of PrecedentRule | Declares which task types require predecessor types in earlier phases. |
| `inference_rules` | list of InferenceRule | File-pattern or content-pattern rules that classify commits without operator tags. |
| `forbidden_operations` | list of ForbiddenOperation | Pre-classification gate entries (FR-049). |
| `stack_detection` | StackDetection | Signals used by `phaser-flavor-init` to suggest this flavor (FR-031). |
| `inference_module` | string (optional) | Fully-qualified Ruby module name implementing the pattern matcher methods referenced by `inference_rules`. |
| `forbidden_module` | string (optional) | Fully-qualified Ruby module name implementing forbidden-operation detectors. |
| `validators` | list of string (optional) | Fully-qualified Ruby module names implementing extra validators (e.g., backfill-safety, precedent-precision). |
| `allow_parallel_backfills` | boolean (default `false`) | Per-flavor override of the FR-037 "sequential by default" rule. |

**Validation rules**:

- `name` and `version` MUST be present.
- `default_type` MUST be one of the names in `task_types`.
- Every type referenced by `precedent_rules` and `inference_rules` MUST be present in `task_types`.
- The schema is enforced at flavor-load time by `flavor_loader.rb`, validating against `contracts/flavor.schema.yaml`. Schema violations cause an immediate, descriptive load-time error.

### TaskType

A named category of work that carries an isolation rule and may participate in precedent rules.

| Attribute | Type | Description |
|---|---|---|
| `name` | string | Unique within the flavor (e.g., `schema add-nullable-column`). |
| `isolation` | enum: `alone` \| `groups` | `alone` requires the task to occupy its own phase (FR-005); `groups` permits sharing a phase with other `groups`-isolation tasks. |
| `description` | string | Human-readable explanation, surfaced in error messages and the manifest. |

**State transitions**: None — task types are immutable per flavor version.

### PrecedentRule

A flavor-declared statement that a task of one type must appear in a strictly later phase than at least one task of another type.

| Attribute | Type | Description |
|---|---|---|
| `name` | string | Unique within the flavor (e.g., `drop-column-requires-cleanup`). |
| `subject_type` | string | The type that requires a predecessor. |
| `predecessor_type` | string | The type that must appear in an earlier phase. |
| `error_message` | string | Operator-facing message emitted when the rule is violated. |

**Validation rules**:

- Both `subject_type` and `predecessor_type` MUST be names in `flavor.task_types`.
- The relation MUST NOT be reflexive (`subject_type != predecessor_type`).
- The relation graph MUST be acyclic; cycles cause a flavor-load error.

### InferenceRule

A file-pattern or content-pattern rule that classifies a commit without operator intervention.

| Attribute | Type | Description |
|---|---|---|
| `name` | string | Unique within the flavor; used as the tie-breaker on equal precedence (FR-036). |
| `precedence` | integer | Higher number wins when multiple rules match (FR-036). Ties broken alphabetically by `name`. |
| `task_type` | string | The type assigned to commits matching this rule. |
| `match` | Match | The matching specification. |

**Match** is one of:

| Variant | Fields | Semantics |
|---|---|---|
| `file_glob` | `pattern: string` | Matches when any file in the commit's diff matches the glob (e.g., `db/migrate/*.rb`). |
| `path_regex` | `pattern: string` | Matches when any file path in the diff matches the regex. |
| `content_regex` | `path_glob: string`, `pattern: string` | Matches when any file matching `path_glob` contains a hunk matching `pattern`. |
| `module_method` | `method: string` | Delegates to a method on the flavor's `inference_module`; the method receives the commit and returns boolean. Used for AST-aware checks. |

**Validation rules**:

- `task_type` MUST be a name in `flavor.task_types`.
- `precedence` MUST be a non-negative integer.
- For `module_method` matches, the flavor MUST declare an `inference_module` and the named method MUST exist.

### ForbiddenOperation

A flavor-declared operation that is unsafe for production deploys and has no valid task type.

| Attribute | Type | Description |
|---|---|---|
| `name` | string | Unique within the flavor (e.g., `direct-column-rename`). Used as the `failing_rule` value in error records (FR-041). |
| `identifier` | string | Stable identifier used as the `forbidden_operation` field in error records. |
| `detector` | Match | Same shape as InferenceRule's match — describes how to detect the forbidden operation. |
| `decomposition_message` | string | Canonical message emitted when the operation is detected (FR-015). Lists the safe sequence of replacement tasks. |

**State transitions**: The detector is evaluated by `forbidden_operations_gate.rb` BEFORE any classification candidate is selected (FR-049). On match, the engine emits a `validation-failed` ERROR, persists the same payload to `phase-creation-status.yaml`, and exits non-zero. There is no operator override (D-016, SC-015).

### StackDetection

The set of signals used by `phaser-flavor-init` to suggest this flavor when no flavor configuration file exists.

| Attribute | Type | Description |
|---|---|---|
| `signals` | list of Signal | All `required: true` signals must match for the flavor to be considered a candidate. |

**Signal** is one of:

| Variant | Fields | Semantics |
|---|---|---|
| `file_present` | `path: string`, `required: boolean` | Matches when the file exists at the project root. |
| `file_contains` | `path: string`, `pattern: string`, `required: boolean` | Matches when the file exists and contains the pattern (regex). |

### Commit

An input to the phaser engine, derived from a Git revision walk over the feature branch.

| Attribute | Type | Description |
|---|---|---|
| `hash` | string (40-char hex) | Full Git SHA. |
| `subject` | string | Commit subject line. |
| `message_trailers` | map<string, string> | Parsed trailer lines (e.g., `Phase-Type: schema add-nullable-column`). |
| `diff` | Diff | The commit's diff, parsed into file entries with hunks. |
| `author_timestamp` | ISO-8601 UTC string | Used for tie-breaking and observability. |

**Validation rules**:

- Empty-diff commits (merge commits with no conflict resolution, tag-only commits) are skipped before classification (FR-009) and do not count toward the FR-048 size bound.

### Diff

The diff content of a single commit.

| Attribute | Type | Description |
|---|---|---|
| `files` | list of FileChange | One entry per file touched. Empty list means empty diff. |

### FileChange

| Attribute | Type | Description |
|---|---|---|
| `path` | string | Repository-relative path. |
| `change_kind` | enum: `added` \| `modified` \| `deleted` \| `renamed` | Standard Git change kinds. |
| `hunks` | list of string | Raw hunk text, preserved for content-regex and module-method matchers. |

### ClassificationResult

The result of classifying a single commit.

| Attribute | Type | Description |
|---|---|---|
| `commit_hash` | string | Source commit SHA. |
| `task_type` | string | Assigned type. |
| `source` | enum: `operator-tag` \| `inference` \| `default` | Which classification path won (FR-004). |
| `rule_name` | string (optional) | Set when `source = inference`; the name of the winning inference rule. |
| `precedents_consulted` | list of string (optional) | Names of precedent rules that were checked for this commit. |
| `isolation` | enum: `alone` \| `groups` | Copied from the assigned task type. |

### Phase

An ordered group of one or more classified commits that can safely be deployed together as a single unit before the next phase begins.

| Attribute | Type | Description |
|---|---|---|
| `number` | integer (1-indexed) | Position in the manifest. |
| `name` | string | Human-readable phase name (e.g., `Schema: add nullable column email_address`). Sentence-case for readability. |
| `branch_name` | string | Stacked-PR branch name (`<feature>-phase-<N>`) (FR-026). |
| `base_branch` | string | Branch this phase is based on (`main` or `<feature>-phase-<N-1>`) (FR-026). |
| `tasks` | list of Task | Ordered commits in the phase. |
| `ci_gates` | list of string | CI gate names applicable to this phase, copied from the flavor catalog. |
| `rollback_note` | string | Operator-facing rollback guidance derived from the assigned task types. |

### Task

A single classified commit's representation inside a Phase entry of the manifest.

| Attribute | Type | Description |
|---|---|---|
| `id` | string | Stable identifier (`phase-<N>-task-<M>`) for cross-referencing. |
| `task_type` | string | The assigned type name. |
| `commit_hash` | string | Source commit SHA. |
| `commit_subject` | string | Mirror of the commit subject for reviewer convenience. |

### PhaseManifest

The artifact produced by the phaser engine and committed to the feature branch as `<FEATURE_DIR>/phase-manifest.yaml` (FR-020). Full schema in `contracts/phase-manifest.schema.yaml`.

| Attribute | Type | Description |
|---|---|---|
| `flavor_name` | string | The active flavor's `name` (FR-021). |
| `flavor_version` | string | The active flavor's `version` (FR-021, FR-035). |
| `feature_branch` | string | Branch name the phaser ran against (FR-021). |
| `generated_at` | ISO-8601 UTC string | Generation timestamp (FR-021). |
| `phases` | list of Phase | Ordered phases (FR-021). |

**Validation rules**:

- `phases` MUST contain at least one entry on success.
- Phase numbers MUST be 1..N with no gaps.
- Each phase's `base_branch` MUST be either the project's default integration branch (for phase 1) or the previous phase's `branch_name` (for phases 2..N) (FR-026).
- The manifest is serialized in fixed key order via `manifest_writer.rb` (D-003) so the output is byte-identical across re-runs (FR-002, SC-002).

**State transitions**:

- Generated by the phaser engine at the end of a successful run.
- Committed to the feature branch by the `phaser` agent as part of the pipeline (FR-019).
- Read by the stacked-PR creator (`phaser-stacked-prs`) and by the modified `marge` command (`--phase N`) to scope per-phase reviews.
- Re-generated on every phaser re-run (overwrites the previous file); if the regeneration changes any classification, the change is visible in `git diff` for operator review (Edge Cases in spec.md).

### PhaseCreationStatus

The status file written when either the phaser engine (FR-042) or the stacked-PR creator (FR-039) fails. Path: `<FEATURE_DIR>/phase-creation-status.yaml`. Full schema in `contracts/phase-creation-status.schema.yaml`.

| Attribute | Type | Description |
|---|---|---|
| `stage` | enum: `phaser-engine` \| `stacked-pr-creation` | Which subsystem failed. |
| `timestamp` | ISO-8601 UTC string | When the failure was recorded. |
| `failure_class` | enum: `validation` \| `auth-missing` \| `auth-insufficient-scope` \| `rate-limit` \| `network` \| `other` | Failure category (FR-046). `validation` is reserved for `stage: phaser-engine`. |
| `first_uncreated_phase` | integer (optional) | Set when `stage = stacked-pr-creation`; first phase needing creation on re-run (FR-039, FR-040). |
| `commit_hash` | string (optional) | Set when `stage = phaser-engine` and the failure is commit-attributable. |
| `failing_rule` | string (optional) | Set when `stage = phaser-engine`; the name of the rule that rejected the commit. |
| `missing_precedent` | string (optional) | Set on precedent failures. |
| `forbidden_operation` | string (optional) | Set on forbidden-operation failures. |
| `decomposition_message` | string (optional) | Set on forbidden-operation or `feature-too-large` failures. |
| `commit_count` | integer (optional) | Set on `feature-too-large` failures (FR-048). |
| `phase_count` | integer (optional) | Set on `feature-too-large` failures (FR-048). |

**State transitions**:

- Written by `status_writer.rb` on any non-zero exit of the phaser engine or stacked-PR creator.
- Deleted by the failing stage on full success of a subsequent re-run (FR-040, FR-042).
- Never contains credential material (FR-047, SC-013).

### FlavorConfiguration

The opt-in file at `.specify/flavor.yaml` (repository root) that selects which shipped flavor a project uses (FR-019, FR-031). Full schema in `contracts/flavor-config.schema.yaml`.

| Attribute | Type | Description |
|---|---|---|
| `flavor` | string | The shipped flavor's `name`. |

**Validation rules**:

- `flavor` MUST resolve to a directory under `phaser/flavors/`.
- Absence of this file ⇒ phaser stage is skipped, single-PR mode is preserved (FR-025, SC-006).
- Presence with an unknown flavor name ⇒ pipeline halts with a clear error listing shipped flavors (Edge Cases in spec.md).

### ObservabilityEvent

A single structured-log entry emitted to stderr by the phaser engine or stacked-PR creator. Full schemas in `contracts/observability-events.md`.

| Attribute | Type | Description |
|---|---|---|
| `level` | enum: `INFO` \| `WARN` \| `ERROR` | Log level (FR-041). |
| `timestamp` | ISO-8601 UTC string | When the event was emitted (FR-041). |
| `event` | enum: `commit-classified` \| `phase-emitted` \| `commit-skipped-empty-diff` \| `validation-failed` \| (stacked-PR-specific events) | Event name (FR-041). |
| (event-specific payload) | varies | See `contracts/observability-events.md` for per-event schema. |

**Validation rules**:

- Each event is serialized as a single JSON object on a single line (FR-041).
- Every event MUST include `level`, `timestamp`, and `event`.
- No event MAY contain credential material (FR-047, SC-013).

## Relationships

```text
Flavor
  ├── declares ──→ list of TaskType
  ├── declares ──→ list of PrecedentRule (each refers to two TaskType names)
  ├── declares ──→ list of InferenceRule (each refers to one TaskType)
  ├── declares ──→ list of ForbiddenOperation (independent of TaskType — these have NO valid type)
  └── declares ──→ StackDetection (used by flavor-init only)

FlavorConfiguration
  └── selects ──→ one Flavor (by name)

Commit
  ├── filtered by → empty-diff check (FR-009)
  ├── gated by  → ForbiddenOperation registry (FR-049, BEFORE classification)
  ├── classified → ClassificationResult (operator-tag | inference | default; FR-004)
  └── grouped   → Phase (subject to PrecedentRule and isolation)

ClassificationResult
  └── feeds  ──→ Phase assignment (subject to TaskType.isolation and PrecedentRule)

Phase
  ├── contains ──→ ordered list of Task
  ├── has      ──→ branch_name (`<feature>-phase-<N>`)
  └── has      ──→ base_branch (default-branch or previous phase)

PhaseManifest
  ├── pins  ──→ Flavor.name and Flavor.version (FR-035)
  ├── lists ──→ ordered Phases
  └── written to → <FEATURE_DIR>/phase-manifest.yaml

PhaseCreationStatus
  ├── written by → phaser engine (stage=phaser-engine) OR stacked-PR creator (stage=stacked-pr-creation)
  └── deleted on → successful re-run of the failing stage (FR-040)

ObservabilityEvent
  └── stream ──→ stderr (one JSON object per line, FR-041, FR-043)
```

## Error Conditions

The full set of error conditions, mapped to where they are detected, what the error record contains, and what file artifacts result.

| Condition | Detection point | Error record / file | Exit |
|---|---|---|---|
| Operator-supplied type tag is unknown | `classifier.rb` (FR-007) | `validation-failed` ERROR with `failing_rule: unknown-type-tag`, `commit_hash`, message listing valid tags from active flavor | non-zero, no manifest |
| Commit's diff matches a forbidden-operation detector | `forbidden_operations_gate.rb` (FR-049) | `validation-failed` ERROR with `failing_rule: <detector-name>`, `forbidden_operation: <identifier>`, `decomposition_message`, `commit_hash`; same payload to status file with `stage: phaser-engine` | non-zero, no manifest |
| Precedent rule violated | `precedent_validator.rb` (FR-006) | `validation-failed` ERROR with `failing_rule: <rule-name>`, `missing_precedent: <type>`, `commit_hash`; same payload to status file with `stage: phaser-engine` | non-zero, no manifest |
| Backfill commit lacks batching/throttling/transaction-safety | reference flavor's `backfill_validator.rb` (FR-013) | `validation-failed` ERROR with `failing_rule: backfill-safety`, `commit_hash`, message naming the missing safeguard | non-zero, no manifest |
| Feature branch exceeds 200 non-empty commits or projected 50 phases | `size_guard.rb` (FR-048) | `validation-failed` ERROR with `failing_rule: feature-too-large`, `commit_count`, `phase_count`, `decomposition_message`; same payload to status file with `stage: phaser-engine` | non-zero, no manifest |
| Flavor configuration references unknown flavor name | `flavor_loader.rb` (Edge Case in spec.md) | Plain stderr error listing shipped flavors; no `validation-failed` record (this is a configuration error, not a per-commit failure) | non-zero, no manifest |
| `gh` CLI not authenticated | `auth_probe.rb` (FR-045) | Status file with `stage: stacked-pr-creation`, `failure_class: auth-missing`, `first_uncreated_phase: 1` | non-zero, no branches/PRs |
| `gh` CLI authenticated but missing `repo` scope | `auth_probe.rb` (FR-045) | Status file with `stage: stacked-pr-creation`, `failure_class: auth-insufficient-scope`, `first_uncreated_phase: 1` | non-zero, no branches/PRs |
| Stacked-PR creation fails partway (network, rate limit, etc.) | `creator.rb` (FR-039) | Status file with `stage: stacked-pr-creation`, `failure_class: <class>`, `first_uncreated_phase: <K+1>` | non-zero, phases 1..K intact |
| Multiple shipped flavors match during `flavor-init` | `phaser-flavor-init` (R-015) | Plain stderr error listing matching flavors and instructing the operator to pass `--flavor <name>` | non-zero, no `.specify/flavor.yaml` written |
| Flavor configuration file already exists during `flavor-init` (no `--force`) | `phaser-flavor-init` (FR-034) | Plain stderr error advising `--force` to overwrite | non-zero, no overwrite |
| No shipped flavor matches during `flavor-init` | `phaser-flavor-init` (FR-033) | Plain stderr `no flavor matched` | non-zero, no `.specify/flavor.yaml` written |
