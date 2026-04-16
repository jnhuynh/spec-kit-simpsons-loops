# Marge Review Mode - Spec Kit Integration

Review implementation code against baseline and project-specific review packs. Fix **one finding**, then exit. Each iteration runs with FRESH CONTEXT.

> **Note:** One finding per iteration. Loop until zero findings remain.

## Feature Directory

The feature directory is provided via the `-p` prompt when this agent is invoked. Extract the path from the prompt (e.g., "Feature directory: specs/a1b2-feat-foo").

## Phase 0: Review

Run `/speckit.review Remediate only the single highest-severity finding without asking for confirmation` to generate findings and auto-remediate. This produces a Code Review Report with a findings table grouped by severity, then remediates only one finding (the highest severity that is not flagged `NEEDS_HUMAN`).

## Phase 1: Assess

1. Review the findings from the `/speckit.review` report
2. If TOTAL findings = 0, output the following promise tag and exit immediately:

<promise>ALL_FINDINGS_RESOLVED</promise>

3. If every remaining finding is flagged `NEEDS_HUMAN`, output the same promise tag and exit — Marge only auto-fixes mechanical findings; design-judgment findings are left for human review
4. Otherwise, confirm remediation was applied to exactly one finding

## Phase 2: Validate

1. Re-read all modified files
2. Verify the fix resolved its finding
3. Check no new same-or-higher severity issues were introduced
4. Run `bash .specify/quality-gates.sh` — if it exits non-zero, treat as a failed fix and revert

## Phase 3: Commit & Exit

1. Commit all changes:
   ```bash
   git add -A && type=$(git branch --show-current | cut -f 2 -d '-') && scope=$(git branch --show-current | cut -f 3- -d '-') && ticket=$(git branch --show-current | cut -f 1 -d '-') && git commit -m "$type($scope): [$ticket] fix [SEVERITY] finding from code review"
   git push origin $(git branch --show-current)
   ```
2. Exit immediately — you will restart with fresh context for the next finding

## Guardrails

| #   | Rule                                                                                                |
| --- | --------------------------------------------------------------------------------------------------- |
| 999 | **One finding per iteration** — Fix one finding, then exit                                         |
| 998 | **Constitution is authoritative** — Never modify `.specify/memory/constitution.md`                 |
| 997 | **Diff scope only** — Only modify lines the feature branch already touches; never fix pre-existing issues |
| 996 | **Validate after remediation** — Re-read modified files AND pass quality gates before committing    |
| 995 | **Highest severity first** — Always target CRITICAL before HIGH before MEDIUM before LOW            |
| 994 | **Mechanical fixes only** — Skip `NEEDS_HUMAN` findings; they require human judgment                |

## File Paths

- Spec: `<FEATURE_DIR>/spec.md`
- Plan: `<FEATURE_DIR>/plan.md`
- Tasks: `<FEATURE_DIR>/tasks.md`
- Constitution: `.specify/memory/constitution.md`
- Review packs: `.specify/marge/checks/*.md`
- Project guidelines: `CLAUDE.md` (repo root)
- Quality gates: `.specify/quality-gates.sh`
