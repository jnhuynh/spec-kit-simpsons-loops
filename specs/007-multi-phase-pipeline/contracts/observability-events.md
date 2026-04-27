# Contract: Observability Event Schema

**Implements**: FR-041, FR-043. Verified by SC-011 and SC-013.

The phaser engine and stacked-PR creator emit structured events to **stderr only**. Every event is a single JSON object, terminated by `\n`. stdout is reserved for downstream-consumable structured output (the manifest path on engine success, the run summary on creator success). No event payload field MAY contain credential material (FR-047, SC-013).

## Common Fields

Every event includes:

| Field | Type | Description |
|---|---|---|
| `level` | enum: `INFO` \| `WARN` \| `ERROR` | Log level. |
| `timestamp` | ISO-8601 UTC string | When the event was emitted, with millisecond precision. |
| `event` | string | Event name (one of those defined below). |

## Phaser Engine Events

### `commit-classified` (INFO)

Emitted once per non-empty commit after classification succeeds.

| Field | Type | Description |
|---|---|---|
| `commit_hash` | string (40-char hex) | Source commit SHA. |
| `task_type` | string | The assigned type. |
| `source` | enum: `operator-tag` \| `inference` \| `default` | Which classification path won. |
| `rule_name` | string (optional) | Set when `source = inference`; the winning rule's name. |
| `isolation` | enum: `alone` \| `groups` | Copied from the assigned task type. |
| `precedents_consulted` | array of string (optional) | Names of precedent rules that were checked for this commit. |

Example:

```json
{"level":"INFO","timestamp":"2026-04-25T12:00:01.123Z","event":"commit-classified","commit_hash":"abc1234567890abcdef1234567890abcdef12345","task_type":"schema add-nullable-column","source":"inference","rule_name":"add-nullable-column-via-migration","isolation":"alone"}
```

### `phase-emitted` (INFO)

Emitted once per phase as the phase is added to the manifest.

| Field | Type | Description |
|---|---|---|
| `phase_number` | integer (1-indexed) | Phase position in the manifest. |
| `branch_name` | string | The phase's branch name. |
| `base_branch` | string | The phase's base branch. |
| `tasks` | array of object | Ordered tasks in this phase. Each entry: `{commit_hash, task_type}`. |

### `commit-skipped-empty-diff` (WARN)

Emitted once per commit skipped under FR-009 (empty diff).

| Field | Type | Description |
|---|---|---|
| `commit_hash` | string (40-char hex) | Source commit SHA. |
| `reason` | string | `empty-diff` (constant). |

### `validation-failed` (ERROR)

Emitted exactly once when the engine fails on validation. The same payload (minus `level`, `timestamp`, `event`) is persisted to `<feature-dir>/phase-creation-status.yaml` (FR-042).

| Field | Type | Description |
|---|---|---|
| `commit_hash` | string (optional) | Set for commit-attributable failures (forbidden operation, precedent, backfill-safety, unknown type tag). Not set for `feature-too-large`. |
| `failing_rule` | string | The rule name that rejected the commit or feature. Examples: forbidden-operation detector name, precedent rule name, `backfill-safety`, `unknown-type-tag`, `feature-too-large`. |
| `missing_precedent` | string (optional) | Set on precedent failures; the predecessor type that was missing. |
| `forbidden_operation` | string (optional) | Set on forbidden-operation failures; the detector identifier. |
| `decomposition_message` | string (optional) | Set on forbidden-operation and `feature-too-large` failures; the canonical operator-facing message. |
| `commit_count` | integer (optional) | Set on `feature-too-large`; non-empty commit count. |
| `phase_count` | integer (optional) | Set on `feature-too-large`; projected phase count. |

## Stacked-PR Creator Events

### `auth-probe-result` (INFO)

Emitted once after `gh auth status` completes.

| Field | Type | Description |
|---|---|---|
| `host` | string | Git host name (e.g., `github.com`). |
| `authenticated` | boolean | Whether the CLI reports an authenticated identity. |
| `scopes` | array of string | Scopes the authenticated identity holds (e.g., `[repo, workflow]`). |

### `phase-skipped-existing` (INFO)

Emitted when a phase's branch and PR both exist with the manifest's expected base branch.

| Field | Type | Description |
|---|---|---|
| `phase_number` | integer | Phase position. |
| `branch_name` | string | The phase's branch name. |
| `pr_number` | integer | The existing PR number. |
| `reason` | string | `branch+pr-already-exist` (constant). |

### `phase-branch-created` (INFO)

Emitted after a phase's branch is created.

| Field | Type | Description |
|---|---|---|
| `phase_number` | integer | Phase position. |
| `branch_name` | string | The created branch. |
| `base_branch` | string | The branch this was based on. |
| `commits` | integer | Number of commits in this phase. |

### `phase-pr-created` (INFO)

Emitted after a phase's PR is created.

| Field | Type | Description |
|---|---|---|
| `phase_number` | integer | Phase position. |
| `pr_number` | integer | The created PR's number. |
| `pr_url` | string | The PR's URL. |
| `linked_to_previous_pr` | boolean | True for phases 2..N (FR-027); false for phase 1. |

### `phase-creation-failed` (ERROR)

Emitted exactly once on creator failure.

| Field | Type | Description |
|---|---|---|
| `phase_number` | integer | The phase that failed (or 1 for auth-probe failures). |
| `failure_class` | enum (per FR-046) | One of `auth-missing`, `auth-insufficient-scope`, `rate-limit`, `network`, `other`. |
| `gh_exit_code` | integer | The `gh` subprocess's exit code. |
| `summary` | string | First line of `gh`'s stderr, scanned for credentials and rejected if any pattern matches. |

## Credential-Leak Guard (FR-047, SC-013)

Before any event is written to stderr, every string-typed field value is scanned for the following patterns. If any match, the field is replaced with `[REDACTED:credential-pattern-match]` and a separate `WARN` event `credential-pattern-redacted` is emitted with the field name (but not the matching value).

Patterns:

- GitHub personal access token prefixes: `ghp_`, `gho_`, `ghu_`, `ghs_`, `ghr_`
- Bearer-token headers: `Bearer\s+\S+`
- Authorization headers: `Authorization:\s*\S+`
- Cookie headers: `Cookie:\s*\S+`

The same scan is applied to every byte written to `phase-creation-status.yaml`. SC-013 verifies the scan via a regression test that constructs synthetic failure modes deliberately containing credential-shaped strings and asserts they never reach the output.

## stdout Separation (FR-043)

| Stream | Engine | Stacked-PR Creator |
|---|---|---|
| stdout | Manifest path on success; empty otherwise | JSON run summary on success; empty otherwise |
| stderr | All observability events | All observability events |

This separation MUST hold whether the binary is invoked standalone (FR-008) or as part of the pipeline (FR-019).
