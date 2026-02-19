# Ralph Build Mode - Spec Kit Integration

Execute **one task** from tasks.md per iteration. Each iteration runs with FRESH CONTEXT.

> **Note:** Batching happens at planning time via composite tasks in tasks.md, not at runtime.

## Phase 0: Orient

0a. **Read tasks.md** - Find the first incomplete task (`- [ ]`)

0b. If NO incomplete tasks remain (no `- [ ]` in tasks.md), output the following promise tag and exit immediately:

<promise>ALL_TASKS_COMPLETE</promise>

0c. **Verify not already done** - Search codebase for existing implementation

## Phase 1: Implement

Run `/speckit.implement Only implement the next incomplete task` to implement the single next incomplete task. This handles implementation, validation, and quality gates.

## Phase 2: Validate

Verify the task was implemented correctly:

1. Re-read the modified files
2. Run quality gates — **MUST pass before proceeding:**

{QUALITY_GATES}

If validation fails:

- Fix immediately
- Re-run validation
- Do NOT mark complete until gates pass

## Phase 3: Commit & Exit

1. Mark task `- [x]` in tasks.md
2. Commit and push:
   ```bash
   git add -A && type=$(git branch --show-current | cut -f 2 -d '-') && scope=$(git branch --show-current | cut -f 3- -d '-') && ticket=$(git branch --show-current | cut -f 1 -d '-') && git commit -m "$type($scope): [$ticket] [task summary]"
   git push origin $(git branch --show-current)
   ```
3. Exit immediately — you will restart with fresh context for the next task

## Guardrails

| #   | Rule                                                                         |
| --- | ---------------------------------------------------------------------------- |
| 999 | **One task per iteration** — Implement one task, then exit                   |
| 998 | **Tests MUST pass** — Never proceed with failing code                        |
| 997 | **Verify not implemented** — Search codebase before implementing             |
| 996 | **Follow existing patterns** — Match codebase conventions                    |
| 995 | **Exit on complexity** — If unexpectedly hard, finish and exit               |
| 994 | **Mark complete immediately** — Update tasks.md right after validation       |
| 993 | **Subagent discipline** — Up to 500 Sonnet for reads, only 1 for build/tests |

## File Paths

- Tasks: `{FEATURE_DIR}/tasks.md`
- Spec: `{FEATURE_DIR}/spec.md`
- Plan: `{FEATURE_DIR}/plan.md`
- Constitution: `.specify/memory/constitution.md`
