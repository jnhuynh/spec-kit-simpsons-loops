# Contract: `phaser` Standalone CLI

**Implements**: FR-008 (engine invocable as a standalone command for testing).
**Binary**: `phaser/bin/phaser`

## Synopsis

```
phaser --feature-dir <path> [--flavor <name>] [--default-branch <branch>] [--clock <ISO-8601>]
phaser --help
phaser --version
```

## Arguments

| Argument | Required | Description |
|---|---|---|
| `--feature-dir <path>` | yes | Path to the feature spec directory (e.g., `specs/007-multi-phase-pipeline`). The phaser writes `phase-manifest.yaml` and (on failure) `phase-creation-status.yaml` here. |
| `--flavor <name>` | no | Override the flavor name. Default: read from `.specify/flavor.yaml`. |
| `--default-branch <branch>` | no | Override the project's default integration branch (used as base for phase 1). Default: `gh repo view --json defaultBranchRef`. |
| `--clock <ISO-8601>` | no | Pin the generation timestamp for deterministic-output regression tests. Used by SC-002. Not for production use. |
| `--help` | no | Print usage and exit 0. |
| `--version` | no | Print engine version and exit 0. |

## Exit Codes

| Code | Meaning |
|---|---|
| 0 | Success. Manifest written. |
| 1 | Validation failure (forbidden operation, precedent violation, feature-too-large, unknown operator tag, backfill-safety, etc.). Status file written. |
| 2 | Configuration error (unknown flavor, missing flavor file, malformed flavor catalog). No status file written (this is a setup error, not a per-commit failure). |
| 3 | Operational error (cannot read Git history, filesystem permission error). No status file written. |
| 64 | Usage error (invalid arguments). |

## stdout

On success, exactly one line: the absolute path to the written manifest, terminated by `\n`. Example:

```
/home/operator/repo/specs/007-multi-phase-pipeline/phase-manifest.yaml
```

On any non-success exit, stdout MUST be empty (FR-043 separation: stdout is reserved for downstream-consumable structured output).

## stderr

One JSON object per line, per FR-041 and `contracts/observability-events.md`. Logs flow regardless of exit status.

## Side Effects

- On success: writes `<feature-dir>/phase-manifest.yaml` (overwriting any existing file) and deletes `<feature-dir>/phase-creation-status.yaml` if present.
- On validation failure: writes `<feature-dir>/phase-creation-status.yaml` with `stage: phaser-engine` and the failure payload (FR-042). Does NOT delete an existing manifest from a prior successful run.
- Reads from the current Git working directory's history; assumes the feature branch is checked out.

## Determinism

For fixed `(--feature-dir, --flavor, --default-branch, --clock, repository state)`, the manifest output is byte-identical across re-runs (FR-002, SC-002). The `--clock` flag exists so the determinism regression test can pin the `generated_at` field.

## Examples

```bash
# Production use within the pipeline
phaser --feature-dir specs/007-multi-phase-pipeline

# Standalone test against a synthetic flavor
phaser --feature-dir /tmp/fixture-feature --flavor example-minimal --clock 2026-04-25T12:00:00Z

# Override default branch
phaser --feature-dir specs/007-multi-phase-pipeline --default-branch develop
```
