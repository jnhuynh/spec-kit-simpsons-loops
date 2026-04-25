# Contract: `phaser-stacked-prs` Stacked-PR Creator CLI

**Implements**: FR-026 through FR-030, FR-039, FR-040, FR-044 through FR-047.
**Binary**: `phaser/bin/phaser-stacked-prs`

## Synopsis

```
phaser-stacked-prs --feature-dir <path> [--remote <name>]
phaser-stacked-prs --help
phaser-stacked-prs --version
```

## Arguments

| Argument | Required | Description |
|---|---|---|
| `--feature-dir <path>` | yes | Path to the feature spec directory containing `phase-manifest.yaml`. |
| `--remote <name>` | no | Git remote to push branches to. Default: `origin`. |
| `--help` | no | Print usage and exit 0. |
| `--version` | no | Print version and exit 0. |

The creator does NOT accept any token, credential, or authentication argument (FR-044). All authentication is delegated to the operator-configured `gh` CLI.

## Exit Codes

| Code | Meaning |
|---|---|
| 0 | Success. All phases have branches and PRs. Status file deleted (FR-040). |
| 1 | Stacked-PR creation failure (network, rate limit, unexpected gh error). Status file written with `stage: stacked-pr-creation`. Phases created in this run are left intact (FR-039). |
| 2 | Authentication failure (`gh` not authenticated or missing required scope). Status file written with `failure_class: auth-missing` or `auth-insufficient-scope` and `first_uncreated_phase: 1`. No branches created (FR-045, SC-012). |
| 3 | Operational error (manifest missing, manifest schema invalid, gh binary not on PATH). No status file written. |
| 64 | Usage error. |

## stdout

On success: a JSON object summarizing the run, one line:

```
{"phases_created": [3,4,5], "phases_skipped_existing": [1,2], "manifest": "/path/to/phase-manifest.yaml"}
```

On any non-success exit, stdout MUST be empty.

## stderr

One JSON object per line. Event types specific to the stacked-PR creator (in addition to the engine events):

| Event | Level | Payload |
|---|---|---|
| `auth-probe-result` | INFO | `host`, `authenticated` (bool), `scopes` (list) |
| `phase-skipped-existing` | INFO | `phase_number`, `branch_name`, `pr_number`, `reason: branch+pr-already-exist` |
| `phase-branch-created` | INFO | `phase_number`, `branch_name`, `base_branch`, `commits` |
| `phase-pr-created` | INFO | `phase_number`, `pr_number`, `pr_url`, `linked_to_previous_pr` (bool) |
| `phase-creation-failed` | ERROR | `phase_number`, `failure_class`, `gh_exit_code`, `summary` (sanitized) |

No event payload field MAY contain a credential (FR-047, SC-013). The `gh` subprocess's stderr is captured but only the first line (typically a summary message) is forwarded into the `summary` field, and that line is scanned for credential patterns before serialization.

## Side Effects

1. Reads `<feature-dir>/phase-manifest.yaml`.
2. Probes `gh auth status` exactly once (FR-045).
3. For each phase in manifest order: queries existence of branch + PR; if both exist with the manifest's expected base branch, skips; otherwise creates the branch (`gh api repos/:owner/:repo/git/refs`) and PR (`gh pr create`).
4. On full success: deletes `<feature-dir>/phase-creation-status.yaml` (FR-040).
5. On failure: writes `<feature-dir>/phase-creation-status.yaml` with the appropriate `stage`, `failure_class`, and `first_uncreated_phase` (FR-039).

## Idempotency

A re-run after partial failure (FR-040, SC-010):

- Reads the manifest fresh.
- For each phase, queries `gh` for the branch and PR. If both exist with the expected base branch, the phase is reported as `phase-skipped-existing` and the run proceeds.
- The first phase whose branch is missing (or whose PR is missing or has the wrong base) becomes the resume point.
- Existing branches and PRs are NEVER deleted or modified (FR-039).

## Authentication Surface (FR-044, FR-047)

The creator MUST NOT:

- Read any environment variable whose name contains `TOKEN`, `KEY`, `SECRET`, or `PASSWORD`.
- Read `~/.config/gh/hosts.yml`, `~/.netrc`, or any other token-bearing config file directly.
- Accept tokens as command-line arguments.
- Pass tokens to subprocesses through environment variables under its own control.

Authentication is exclusively probed via `gh auth status` and exclusively used by `gh` subprocess invocations. The creator treats the entire authentication surface as opaque (FR-047).

## Examples

```bash
phaser-stacked-prs --feature-dir specs/007-multi-phase-pipeline

# Re-run after partial failure — picks up at first_uncreated_phase
phaser-stacked-prs --feature-dir specs/007-multi-phase-pipeline
```
