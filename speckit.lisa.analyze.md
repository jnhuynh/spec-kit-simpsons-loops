---
description: Print the command to run iterative cross-artifact analysis and remediation (Lisa loop) on spec.md, plan.md, and tasks.md until all findings are resolved.
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Goal

Resolve the feature directory, verify artifacts, and print the bash command to run the Lisa loop for iterative cross-artifact analysis and remediation. Each loop iteration analyzes spec artifacts, fixes the single highest-severity finding, commits, and exits. The loop continues until zero findings remain.

## Execution Steps

### Step 1: Resolve Feature Directory

- If `$ARGUMENTS` contains a directory path, use it as `FEATURE_DIR`
- Otherwise, run `.specify/scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks` from repo root and parse JSON output for `FEATURE_DIR`

### Step 2: Verify Artifacts

Confirm all three artifacts exist in `FEATURE_DIR`:

- `spec.md`
- `plan.md`
- `tasks.md`

If any are missing, abort with guidance:

- Missing `spec.md` → "Run /speckit.specify first"
- Missing `plan.md` → "Run /speckit.plan first"
- Missing `tasks.md` → "Run /speckit.tasks first"

### Step 3: Print Command

Default max iterations: **10** (4 severity levels + buffer).

Print the bash command for the user to execute in a code block, and also emit the structured tag for pipeline extraction:

```
.specify/scripts/bash/lisa-loop.sh <FEATURE_DIR> 10
```

`<shell-command>.specify/scripts/bash/lisa-loop.sh <FEATURE_DIR> 10</shell-command>`

Replace `<FEATURE_DIR>` with the actual resolved path in both the code block and the tag.
