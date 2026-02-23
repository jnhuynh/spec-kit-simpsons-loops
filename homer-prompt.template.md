# Homer Clarification Mode - Spec Kit Integration

Clarify spec artifacts by resolving ambiguities, unanswered questions, and unclear requirements. Fix ALL findings at the highest severity level, then exit. Each iteration runs with FRESH CONTEXT.

> **Note:** One severity level per iteration. Loop until zero findings remain.

## Phase 0: Clarify

Run `/speckit.clarify Remediate all findings at the highest severity present without asking for confirmation` to generate findings and auto-remediate. This produces a Specification Clarification Report with a findings table, coverage summary, and metrics, then remediates all findings at the highest severity level.

## Phase 1: Assess

1. Review the findings from the `/speckit.clarify` report
2. If TOTAL findings = 0, output the following promise tag and exit immediately:

<promise>ALL_FINDINGS_RESOLVED</promise>

3. Otherwise, confirm remediation was applied to the correct severity level

## Phase 2: Validate

1. Re-read all modified files
2. Verify each fix resolved its finding
3. Check no new same-or-higher severity issues were introduced
4. If new issues at the same severity were introduced, fix them now

## Phase 3: Commit & Exit

1. Commit all changes:
   ```bash
   git add -A && type=$(git branch --show-current | cut -f 2 -d '-') && scope=$(git branch --show-current | cut -f 3- -d '-') && ticket=$(git branch --show-current | cut -f 1 -d '-') && git commit -m "$type($scope): [$ticket] fix [SEVERITY] findings from spec clarification"
   git push origin $(git branch --show-current)
   ```
2. Exit immediately — you will restart with fresh context for the next severity level

## Guardrails

| #   | Rule                                                                                             |
| --- | ------------------------------------------------------------------------------------------------ |
| 999 | **One severity level per iteration** — Fix all findings at the highest level, then exit          |
| 998 | **Constitution is authoritative** — Never modify constitution.md; adjust spec/plan/tasks instead |
| 997 | **Spec artifacts only** — Only modify files within `{FEATURE_DIR}/`                              |
| 996 | **Validate after remediation** — Re-read modified files and verify fixes before committing       |
| 995 | **Highest severity first** — Always target CRITICAL before HIGH before MEDIUM before LOW         |

## File Paths

- Spec: `{FEATURE_DIR}/spec.md`
- Plan: `{FEATURE_DIR}/plan.md`
- Tasks: `{FEATURE_DIR}/tasks.md`
- Constitution: `.specify/memory/constitution.md`
