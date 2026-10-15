# Ralph Build Mode - Spec Kit Integration

Execute **one task** from tasks.md per iteration. Each iteration runs with FRESH CONTEXT.

> **Note:** Batching happens at planning time via composite tasks in tasks.md, not at runtime.

## Feature Directory & Quality Gates

The feature directory and quality gates are provided in the invocation prompt (each iteration is spawned via the Agent tool). Extract:
- **Feature directory**: the path (e.g., "Feature directory: specs/a1b2-feat-foo")
- **Quality gates**: the per-iteration command to run for validation. The orchestrator passes the **fast** gate (`bash .specify/quality-gates-fast.sh`) when available, which scopes checks to changed files for quick feedback. If only the full gate exists, it passes that instead. The orchestrator runs the **full** gate (`bash .specify/quality-gates.sh`) once after the loop terminates — do not run it yourself per iteration.

## Phase 0: Orient

0a. **Read tasks.md** - Report the total count of incomplete tasks (`- [ ]`) across the whole file as the work-remaining count in your final output — the orchestrator's stall detection depends on it.

0b. If NO incomplete tasks remain (no `- [ ]` in tasks.md), output the following promise tag and exit immediately:

<promise>ALL_TASKS_COMPLETE</promise>

0c. **Resolve the current PR group** - If tasks.md has a `## Pull Request Plan` section, parse its table and take the **lowest-numbered PR group that still has an incomplete task**. That is the current group, and it is the only work this iteration may touch. Report its PR number and task range in your final output.

   Walk the table **by PR number, not by file order**. A group's task IDs are often not contiguous (`T022-T023, T028-T031`), so the first incomplete task in the *file* frequently belongs to a later group — picking that one would start PR 3 while PR 2 is still open.

   If there is no such section (an older tasks.md, or a split parent spec), treat all tasks as one group.

0d. **Pick the task** - The next incomplete task **within the current group**, in task-ID order.

0e. **Verify not already done** - Search codebase for existing implementation

## Phase 1: Implement

Run `/speckit-implement Only implement <TASK_ID>, and no other task`, naming the task ID resolved in Phase 0d. This handles implementation, validation, and quality gates.

Name the ID explicitly — do not say "the next incomplete task". When PR groups interleave with file order, the next incomplete task in the file can belong to a later group.

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
3. **PR boundary check** - Re-read tasks.md. If the current PR group (from Phase 0c) now has no incomplete tasks and a **higher-numbered** PR group still has some, this is a PR boundary. Output the following halt tag, followed by the PR number just finished, its task range, the remaining groups with their ranges, and the line `Open it with /speckit-pr.`:

   <promise>PR_BOUNDARY_REACHED</promise>

   Then exit. The loop stops here so the finished group can be opened as a pull request, reviewed and merged before the next group starts.

4. Otherwise exit immediately — you will restart with fresh context for the next task

## Guardrails

| #   | Rule                                                                         |
| --- | ---------------------------------------------------------------------------- |
| 999 | **One task per iteration** — Implement one task, then exit                   |
| 998 | **Tests MUST pass** — Never proceed with failing code                        |
| 997 | **Verify not implemented** — Search codebase before implementing             |
| 996 | **Follow existing patterns** — Match codebase conventions                    |
| 995 | **Exit on complexity** — If unexpectedly hard, finish and exit               |
| 994 | **Mark complete immediately** — Update tasks.md right after validation       |
| 993 | **Sub agent discipline** — Spawn as many sub agents as you like to read and search; run builds and tests in one at a time, never in parallel |
| 992 | **Stay inside the PR group** — Never implement a task from a later PR group, even a trivial or blocking-looking one. The boundary exists so the current group ships reviewable on its own |

## File Paths

- Tasks: `<FEATURE_DIR>/tasks.md`
- Spec: `<FEATURE_DIR>/spec.md`
- Plan: `<FEATURE_DIR>/plan.md`
- Constitution: `.specify/memory/constitution.md`
