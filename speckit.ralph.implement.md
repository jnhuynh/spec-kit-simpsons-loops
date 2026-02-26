---
description: Generate Ralph loop prompt and print the bash command to run task-by-task implementation.
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Goal

Resolve the feature directory, generate the Ralph loop prompt (with quality gates), and print the bash command to run task-by-task implementation. Each loop iteration implements one task, runs quality gates, commits, and exits. The loop continues until all tasks are complete.

## Execution Steps

### Step 1: Resolve Feature Directory

- If `$ARGUMENTS` contains a directory path, use it as `FEATURE_DIR`
- Otherwise, run `.specify/scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks` from repo root and parse JSON output for `FEATURE_DIR`

### Step 2: Analyze Tasks

1. Count incomplete tasks (`- [ ]` lines) in `FEATURE_DIR/tasks.md`
2. Count completed tasks (`- [x]` lines)
3. Exit early if nothing to do

### Step 3: Extract Quality Gates

> **PLACEHOLDER** — Replace the command below with your project's quality gates before running Ralph.

```bash
echo "PLACEHOLDER: Update this quality gate in speckit.ralph.implement.md before using Ralph." && exit 1
```

### Step 4: Generate Prompt

1. Read `.specify/templates/ralph-prompt.template.md`
2. Substitute `{FEATURE_DIR}` and `{QUALITY_GATES}`
3. Write or overwrite to `.specify/.ralph-prompt.md`

### Step 5: Print Command

Calculate max iterations: `incomplete_tasks + 10`

Print the bash command for the user to execute in a code block, and also emit the structured tag for pipeline extraction:

```
.specify/scripts/bash/ralph-loop.sh .specify/.ralph-prompt.md <MAX> <FEATURE_DIR>/tasks.md
```

`<shell-command>.specify/scripts/bash/ralph-loop.sh .specify/.ralph-prompt.md <MAX> <FEATURE_DIR>/tasks.md</shell-command>`

Replace `<MAX>` and `<FEATURE_DIR>` with the actual values in both the code block and the tag.
