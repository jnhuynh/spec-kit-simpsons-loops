---
description: Generates Ralph loop documention so we can trigger Bash Ralph Loop to implement each task defined in tasks.md in a fresh Claude Code instance.
---

### Step 1: Load Feature Context

Run prerequisite script to identify:

- FEATURE_DIR: Path to active feature (e.g., specs/002-feat-backend-auth)
- Available documentation files

### Step 2: Analyze Tasks

1. Count incomplete tasks (`- [ ]` lines)
2. Count completed tasks (`- [x]` lines)
3. Exit early if nothing to do

### Step 3: Extract Quality Gates

Run the following commands from the `mobile/` directory:

```bash
cd mobile && npm run lint && npm run typecheck && npm test
```

### Step 4: Generate Prompt

1. Read `.specify/templates/ralph-prompt.template.md`
2. Substitute `{FEATURE_DIR}` and `{QUALITY_GATES}`
3. Write or overwrite to `.specify/.ralph-prompt.md`

### Step 5: Generate Bash command for manual execution Loop

Calculate max iterations: `incomplete_tasks + 10`
Print command for user `.specify/scripts/bash/ralph-loop.sh .specify/ralph-prompt.md {MAX} {FEATURE_DIR}/tasks.md`
