---
description: Run the phaser engine over the current feature branch's commits and commit the resulting phase manifest (single-shot stage).
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Pre-Flight Check

Before doing anything else, verify that the required utility scripts are installed:

1. Check if `.specify/scripts/bash/check-prerequisites.sh` exists (use the Bash tool: `test -f .specify/scripts/bash/check-prerequisites.sh && echo "EXISTS" || echo "MISSING"`)
2. If **MISSING**, display this error and **STOP** — do not proceed with any execution:

```
ERROR: Required utility script not found.

Missing: .specify/scripts/bash/check-prerequisites.sh

This script is required for feature directory resolution and prerequisite validation.
To install it, run the SpecKit setup command:

  /speckit.setup

```

3. If **EXISTS**, proceed to the agent file check below.

## Agent File Check

Verify that the required agent file exists before invoking the phaser. Check using the Bash tool:

```bash
test -f ".claude/agents/phaser.md" && echo "phaser.md: EXISTS" || echo "phaser.md: MISSING"
```

If **MISSING**, display this error and **STOP** — do not proceed with execution:

```
ERROR: Required agent file not found.

Missing: .claude/agents/phaser.md

This agent file is required for the phaser stage to execute. It defines the
single-shot behavior of the phaser engine invocation. Ensure the file is present at:
  .claude/agents/phaser.md
```

If **EXISTS**, proceed to the flavor configuration check below.

## Flavor Configuration Check

Per FR-019 and FR-025, the phaser stage is gated entirely on the presence of `.specify/flavor.yaml`. Check using the Bash tool:

```bash
test -f ".specify/flavor.yaml" && echo "flavor.yaml: EXISTS" || echo "flavor.yaml: MISSING"
```

If **MISSING**, display this message and **STOP** with a non-error exit (this is the expected no-flavor path per FR-025):

```
No .specify/flavor.yaml found. The phaser stage is opt-in per FR-019 and is
skipped when no flavor configuration file exists. To opt this project into
phasing, run:

  /speckit.flavor.init
```

If **EXISTS**, proceed to the phaser CLI check below.

## Phaser CLI Check

Verify that the phaser CLI entry point exists and is executable. Check using the Bash tool:

```bash
test -x "phaser/bin/phaser" && echo "phaser CLI: EXECUTABLE" || echo "phaser CLI: MISSING_OR_NOT_EXECUTABLE"
```

If **MISSING_OR_NOT_EXECUTABLE**, display this error and **STOP**:

```
ERROR: Phaser CLI entry point not found or not executable.

Expected: phaser/bin/phaser (executable)

The phaser CLI is required for this stage. Ensure the phaser/ Ruby toolkit is
installed and the entry point is executable (chmod +x phaser/bin/phaser).
```

If **EXECUTABLE**, proceed to the Goal section below.

## Goal

Invoke the phaser engine via a single-shot sub agent that classifies the feature branch's commits, validates them against the active flavor's rules, writes `phase-manifest.yaml` to the feature directory, and commits the manifest. This command is a **single-shot wrapper** — it spawns one sub agent, waits for it to return, and exits. Per FR-024, on phaser failure this command propagates the non-zero status so the pipeline halts before invoking marge.

## Execution Steps

### Step 1: Parse Arguments

Parse `$ARGUMENTS` for the following (optional):

- **`spec-dir`**: A directory path (e.g., `specs/007-multi-phase-pipeline`). If provided, use it as `FEATURE_DIR`.

**Parsing rules**:
- A token that looks like a directory path (contains `/` or matches a known `specs/` pattern) is treated as `spec-dir`.
- If not provided, resolve the feature directory in Step 2.

### Step 2: Resolve Feature Directory

- If `spec-dir` was parsed from `$ARGUMENTS`, use it as `FEATURE_DIR`.
- Otherwise, run `bash .specify/scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks` from the repo root and parse the JSON output for `FEATURE_DIR`. **Error handling**: If the script exits with a non-zero status (e.g., missing feature dir, invalid branch), display the script's stderr/stdout output to the user and **STOP** — do not proceed with execution.

### Step 3: Spawn Phaser Sub Agent

Spawn a single fresh-context sub agent using the **Agent tool**:

- **subagent_type**: `general-purpose`
- **prompt**: Compose a prompt containing:
  - Instruct the agent to read and follow `.claude/agents/phaser.md`
  - Provide: `Feature directory: <FEATURE_DIR>`

The phaser agent is single-shot per its own guardrails. Do **NOT** loop. Wait for the sub agent to return before continuing.

### Step 4: Interpret Sub Agent Result

Per `.claude/agents/phaser.md` and `contracts/phaser-cli.md`:

- **On success (sub agent reports the manifest path and exits 0)**: The agent has already committed `phase-manifest.yaml` to the feature branch. Print the manifest path to stdout for the pipeline orchestrator to pick up, then exit 0.
- **On failure (sub agent propagates a non-zero phaser exit)**: The phaser engine has written `<FEATURE_DIR>/phase-creation-status.yaml` with `stage: phaser-engine` and the failure payload (FR-042). Read and print the contents of that status file so the operator can see the failure (offending commit hash, failing rule name, and — for forbidden operations — the canonical decomposition message). Per FR-024, exit with a non-zero status so any pipeline orchestrator that invoked this command halts before invoking marge.

**Failure handling**: If the sub agent itself crashes, times out, or errors before reaching either the success or failure path above, abort and report the failure context (agent type: phaser, error message). Do NOT retry — phaser sub agent failures are treated as deterministic.

### Step 5: Report Results

After the sub agent returns, report:

- The resolved `FEATURE_DIR`.
- The active flavor name (from `.specify/flavor.yaml`).
- The outcome (one of: **success** — manifest written and committed; **validation-failure** — phaser engine rejected one or more commits; **failure** — sub agent crashed or errored).
- On success: the absolute manifest path.
- On validation-failure: the failure payload from `<FEATURE_DIR>/phase-creation-status.yaml`.

## Examples

- `/speckit.phaser` — Auto-detect spec dir from current branch, run the phaser stage once.
- `/speckit.phaser specs/007-multi-phase-pipeline` — Run the phaser stage against the named spec directory.
