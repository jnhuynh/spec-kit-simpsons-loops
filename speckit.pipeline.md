---
description: Run the full SpecKit pipeline (homer, plan, tasks, lisa, ralph) after spec is complete.
---

## User Input

```text
$ARGUMENTS
```

## Overview

Run the automated SpecKit pipeline from spec clarification through implementation. This command assumes `/speckit.specify` has already been completed interactively and a `spec.md` exists in the feature's spec directory.

The pipeline runs these steps in sequence:

1. **homer** — Iterative spec clarification & remediation
2. **plan** — Generate technical implementation plan
3. **tasks** — Generate dependency-ordered task list
4. **lisa** — Cross-artifact consistency analysis
5. **ralph** — Task-by-task implementation with quality gates

## Instructions

1. **Determine the spec directory**:
   - If `$ARGUMENTS` is provided and non-empty, use it as the spec directory path or `--from` option
   - Otherwise, auto-detect from the current git branch name (extract the 4-char prefix and find the matching `specs/<prefix>-*` directory)

2. **Validate spec exists**:
   - Confirm that `spec.md` exists in the resolved spec directory
   - If not found, inform the user they need to run `/speckit.specify` first

3. **Print the command** (do NOT execute it):

   Build and display the shell command the user should run manually:

   ```
   .specify/scripts/bash/pipeline.sh $ARGUMENTS
   ```

   Include any arguments the user passed (e.g., `--from homer`, spec dir path).

   Print the command in a code block so the user can copy-paste it into their terminal.

## Examples

- `/speckit.pipeline` — Auto-detect spec dir from current branch, run full pipeline
- `/speckit.pipeline specs/a1b2-feat-user-auth` — Run pipeline for specific spec
- `/speckit.pipeline --from homer` — Start from homer step (auto-detect spec dir)
- `/speckit.pipeline --from ralph specs/a1b2-feat-user-auth` — Resume ralph for specific spec
