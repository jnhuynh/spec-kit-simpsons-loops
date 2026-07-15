# Ralph Build Mode - Spec Kit Integration

Execute **one task** from tasks.md per iteration. Each iteration runs with FRESH CONTEXT.

> **Note:** Batching happens at planning time via composite tasks in tasks.md, not at runtime.

## Feature Directory & Quality Gates

The feature directory and quality gates are provided in the invocation prompt (each iteration is spawned via the Agent tool). Extract:
- **Feature directory**: the path (e.g., "Feature directory: specs/a1b2-feat-foo")
- **Quality gates**: the per-iteration command to run for validation. The orchestrator passes the **fast** gate (`bash .specify/quality-gates-fast.sh`) when available, which scopes checks to changed files for quick feedback. If only the full gate exists, it passes that instead. The orchestrator runs the **full** gate (`bash .specify/quality-gates.sh`) once after the loop terminates — do not run it yourself per iteration.

## Phase 0: Orient

0a. **Read tasks.md** - Find the first incomplete task (`- [ ]`). Report the total count of incomplete tasks (including this one) as the work-remaining count in your final output — the orchestrator's stall detection depends on it.

0b. If NO incomplete tasks remain (no `- [ ]` in tasks.md), output the following promise tag and exit immediately:

<promise>ALL_TASKS_COMPLETE</promise>

0c. **Verify not already done** - Search codebase for existing implementation

## Phase 1: Implement

Run `/speckit-implement Only implement the next incomplete task` to implement the single next incomplete task. This handles implementation, validation, and quality gates.

## Phase 2: Validate

Verify the task was implemented correctly:

1. Re-read the modified files
2. Run the quality gates provided in the invocation prompt — **MUST pass before proceeding**

If validation fails:

- Fix immediately
- Re-run validation
- Do NOT mark complete until gates pass

## Phase 3: Commit & Exit

1. Mark task `- [x]` in tasks.md
2. Commit and push:
   ```bash
   bash .specify/scripts/bash/speckit-commit.sh "[task summary]"
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

- Tasks: `<FEATURE_DIR>/tasks.md`
- Spec: `<FEATURE_DIR>/spec.md`
- Plan: `<FEATURE_DIR>/plan.md`
- Constitution: `.specify/memory/constitution.md`
