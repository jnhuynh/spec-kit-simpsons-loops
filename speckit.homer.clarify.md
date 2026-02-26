---
description: Run iterative spec clarification and remediation (Homer loop) on spec.md until all findings are resolved.
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Goal

Resolve the feature directory, verify artifacts, and print the bash command to run the Homer loop for iterative spec clarification and remediation. Each loop iteration clarifies spec artifacts, fixes the single highest-severity finding, commits, and exits. The loop continues until zero findings remain.

## Execution Steps

### Step 1: Resolve Feature Directory

- If `$ARGUMENTS` contains a directory path, use it as `FEATURE_DIR`
- Otherwise, run `.specify/scripts/bash/check-prerequisites.sh --json` from repo root and parse JSON output for `FEATURE_DIR`

### Step 2: Verify Artifacts

Confirm `spec.md` exists in `FEATURE_DIR`.

If missing, abort with guidance: "Run /speckit.specify first"

### Step 3: Print Command

Default max iterations: **10** (4 severity levels + buffer).

Print the bash command for the user to execute in a code block, and also emit the structured tag for pipeline extraction:

```
.specify/scripts/bash/homer-loop.sh <FEATURE_DIR> 10
```

`<shell-command>.specify/scripts/bash/homer-loop.sh <FEATURE_DIR> 10</shell-command>`

Replace `<FEATURE_DIR>` with the actual resolved path in both the code block and the tag.
