# Phaser Agent - Spec Kit Integration

Run the phaser engine over the current feature branch's commits and commit the resulting phase manifest. This is a **single-shot** agent — run once and exit.

## Feature Directory

The feature directory is provided via the `-p` prompt when this agent is invoked. Extract the path from the prompt (e.g., "Feature directory: specs/a1b2-feat-foo").

## Prerequisites

This agent assumes:

- The current working directory is the repository root.
- The feature branch is checked out.
- A flavor configuration file exists at `.specify/flavor.yaml` (the pipeline gates this stage on that file's presence per FR-025; if it is absent, the pipeline does not invoke this agent at all).
- The `phaser/bin/phaser` entry point is executable and on the repository (per `contracts/phaser-cli.md`).

## Instructions

Invoke the phaser CLI via Bash, scoped to the feature directory provided in the prompt. Capture stdout (the absolute manifest path on success) and stderr (the JSON-line observability stream). Per the CLI contract, stdout MUST contain exactly one line — the manifest path — when the engine exits 0; on any non-zero exit, stdout is empty and the failure payload is persisted by the engine to `<FEATURE_DIR>/phase-creation-status.yaml` with `stage: phaser-engine`.

Run the following Bash command, substituting `<FEATURE_DIR>` with the feature directory extracted from the prompt:

```bash
manifest_path=$(phaser/bin/phaser --feature-dir <FEATURE_DIR>)
phaser_status=$?
```

### On success (exit 0)

1. Verify `$manifest_path` is a single existing file path that resolves under `<FEATURE_DIR>/phase-manifest.yaml`.
2. Stage and commit the manifest to the feature branch:

   ```bash
   git add "$manifest_path" && type=$(git branch --show-current | cut -f 2 -d '-') && scope=$(git branch --show-current | cut -f 3- -d '-') && ticket=$(git branch --show-current | cut -f 1 -d '-') && git commit -m "$type($scope): [$ticket] generate phase manifest"
   git push origin $(git branch --show-current)
   ```

3. Print the manifest path so the pipeline orchestrator can pick it up, then exit 0.

### On failure (non-zero exit)

Per FR-024, the pipeline MUST halt without invoking the review step when the phaser stage fails. This agent's responsibility is to surface the failure clearly and propagate the non-zero status to the caller.

1. Read `<FEATURE_DIR>/phase-creation-status.yaml` (the engine wrote the failure payload here per FR-042; it includes `stage: phaser-engine`, the offending commit hash, the failing rule name, and — for forbidden operations — the canonical decomposition message).
2. Print the contents of the status file so the operator can see the failure without scrolling through stderr logs.
3. Do NOT commit or push anything. Do NOT delete or modify the status file (the next pipeline run will overwrite it on a fresh attempt; per FR-040 it is only deleted on full success of the failing stage).
4. Exit with the same non-zero status the phaser CLI returned, so the pipeline orchestrator halts before invoking marge.

## Guardrails

| #   | Rule                                                                                          |
| --- | --------------------------------------------------------------------------------------------- |
| 999 | **Single-shot** — Invoke the phaser once and exit; never loop                                 |
| 998 | **Propagate exit code** — On non-zero phaser exit, exit with the same code (FR-024)           |
| 997 | **No bypass** — Never pass any flag or environment variable that suppresses validation gates  |
| 996 | **Manifest only** — Only commit `phase-manifest.yaml`; do not stage other files               |
| 995 | **No log scraping** — Failure payloads come from `phase-creation-status.yaml`, not from stderr |

## File Paths

- Feature directory: `<FEATURE_DIR>` (provided in prompt)
- Manifest: `<FEATURE_DIR>/phase-manifest.yaml`
- Status file (on failure): `<FEATURE_DIR>/phase-creation-status.yaml`
- Phaser CLI: `phaser/bin/phaser`
- CLI contract: `specs/007-multi-phase-pipeline/contracts/phaser-cli.md`
