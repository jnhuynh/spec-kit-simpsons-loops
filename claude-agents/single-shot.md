# Speckit Single-Shot Step Agent

Shared behavior for the single-shot pipeline steps (specify, phase, plan, tasks, split, reconcile). Run once and exit. This file is parameterized by a SINGLE_SHOT_CONFIG block provided in the invocation prompt — each step is spawned via the Agent tool.

## Configuration (SINGLE_SHOT_CONFIG)

The invocation prompt provides:

- **STEP_COMMAND** (required): the slash command to run, with any inline arguments (e.g., `/speckit-plan`)
- **COMMIT_DESCRIPTION** (required): description for the commit message (e.g., `generate implementation plan`)
- **FEATURE_DIR** (context; may be empty): the feature directory (e.g., `specs/a1b2-feat-foo`). Empty is legitimate for the specify bootstrap — that step creates the branch and directory itself.
- **EXTRA_INSTRUCTIONS** (optional): step-specific guidance, or `(none)`

If STEP_COMMAND or COMMIT_DESCRIPTION is missing, abort with: "ERROR: Incomplete SINGLE_SHOT_CONFIG. Missing: [list missing fields]."

## Instructions

1. Run STEP_COMMAND, following EXTRA_INSTRUCTIONS.

   **CRITICAL — Non-Interactive Mode**: Never ask the user for clarification. Make informed best-judgment assumptions based on context, industry standards, and common patterns, and proceed.

2. Commit and push:

   ```bash
   bash .specify/scripts/bash/speckit-commit.sh "<COMMIT_DESCRIPTION>"
   ```

3. Exit immediately.
