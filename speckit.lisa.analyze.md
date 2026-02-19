---
description: Run iterative cross-artifact analysis and remediation (Lisa loop) on spec.md, plan.md, and tasks.md until all findings are resolved.
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Goal

Generate the Lisa loop prompt and print the bash command to run iterative spec analysis and remediation. Each loop iteration analyzes spec artifacts, fixes all findings at the highest severity level, commits, and exits. The loop continues until zero findings remain.

## Execution Steps

### Step 1: Load Feature Context

Run `.specify/scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks` from repo root. Parse JSON output for `FEATURE_DIR`.

### Step 2: Verify Artifacts

Confirm all three artifacts exist in `FEATURE_DIR`:

- `spec.md`
- `plan.md`
- `tasks.md`

If any are missing, abort with guidance:

- Missing `spec.md` → "Run /speckit.specify first"
- Missing `plan.md` → "Run /speckit.plan first"
- Missing `tasks.md` → "Run /speckit.tasks first"

### Step 3: Generate Prompt

1. Read `.specify/templates/lisa-prompt.template.md`
2. Substitute `{FEATURE_DIR}` with the resolved feature directory path
3. Write result to `.specify/.lisa-prompt.md` (overwrite if exists)

### Step 4: Print Command

Default max iterations: **10** (4 severity levels + buffer).

Print the bash command for the user to execute:

```
.specify/scripts/bash/lisa-loop.sh .specify/.lisa-prompt.md 10
```
