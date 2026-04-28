# Ralph Build Mode - Spec Kit Integration

Execute **one task** from tasks.md per iteration. Each iteration runs with FRESH CONTEXT.

> **Note:** Batching happens at planning time via composite tasks in tasks.md, not at runtime.

## Feature Directory & Quality Gates

The feature directory and quality gates are provided via the `-p` prompt when this agent is invoked. Extract:
- **Feature directory**: the path (e.g., "Feature directory: specs/a1b2-feat-foo")
- **Quality gates**: the commands to run for validation (e.g., "Quality gates: npm test && npm run lint")

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
2. Run the quality gates provided in the `-p` prompt — **MUST pass before proceeding**

If validation fails:

- Fix immediately
- Re-run validation
- Do NOT mark complete until gates pass

## Phase 3: Commit & Exit

1. Mark task `- [x]` in tasks.md
2. **Detect the task's phase tag** (multi-phase feature support):
   - Inspect the just-completed task's entry in `tasks.md` for a `[phase-N]` tag (e.g., `[phase-2]`).
   - If the task entry carries `[phase-N]`, set `PHASE=N` (an integer).
   - If the task entry has no `[phase-N]` tag, leave `PHASE` unset — the commit message MUST NOT include a `Phase:` trailer in this case. Do NOT silently default to `Phase: 1` in the commit text; an absent tag means an absent trailer.
   - This applies uniformly: single-phase features (no `## Deploy Phases` section in `plan.md`, no `[phase-N]` tags in `tasks.md`) produce commits without the trailer; multi-phase features produce one trailer per task whose value matches the task's tag.
3. Commit (do NOT push — see Guardrails):
   ```bash
   git add -A
   type=$(git branch --show-current | cut -f 2 -d '-')
   scope=$(git branch --show-current | cut -f 3- -d '-')
   ticket=$(git branch --show-current | cut -f 1 -d '-')
   subject="$type($scope): [$ticket] [task summary]"

   # Multi-phase: append a Phase: N git trailer (RFC 5322) when the task carries [phase-N].
   # Use --trailer so git interpret-trailers / git log --format='%(trailers:key=Phase,valueonly)'
   # parse it deterministically. Omit the flag entirely when the task has no phase tag.
   if [ -n "${PHASE:-}" ]; then
     git commit -m "$subject" --trailer "Phase: $PHASE"
   else
     git commit -m "$subject"
   fi
   ```
4. **Do NOT push.** All implementation work for a multi-phase feature MUST occur on a single feature branch end to end before any pull request is opened (FR-008). The split step (`/speckit.split`) is responsible for creating phase branches and opening pull requests after Marge review completes; pushing the integrated feature branch from Ralph is not part of the loop. Per CLAUDE.md "Git Discipline", pushing is gated behind explicit user permission.
5. Exit immediately — you will restart with fresh context for the next task

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
