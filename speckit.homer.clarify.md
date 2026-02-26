---
description: Run iterative spec clarification and remediation (Homer loop) on spec.md until all findings are resolved.
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Goal

Generate the Homer loop prompt and print the bash command to run iterative spec clarification and remediation. Each loop iteration clarifies spec artifacts, fixes the single highest-severity finding, commits, and exits. The loop continues until zero findings remain.

## Execution Steps

### Step 1: Load Feature Context

Run `.specify/scripts/bash/check-prerequisites.sh --json` from repo root. Parse JSON output for `FEATURE_DIR`.

### Step 2: Verify Artifacts

Confirm `spec.md` exists in `FEATURE_DIR`.

If missing, abort with guidance: "Run /speckit.specify first"

### Step 3: Generate Prompt

1. Read `.specify/templates/homer-prompt.template.md`
2. Substitute `{FEATURE_DIR}` with the resolved feature directory path
3. Write result to `.specify/.homer-prompt.md` (overwrite if exists)

### Step 4: Print Command

Default max iterations: **10** (4 severity levels + buffer).

Print the bash command for the user to execute:

```
.specify/scripts/bash/homer-loop.sh .specify/.homer-prompt.md 10
```
