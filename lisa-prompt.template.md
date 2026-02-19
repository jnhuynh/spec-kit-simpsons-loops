# Lisa Analysis Mode - Spec Kit Integration

Analyze spec artifacts for inconsistencies, gaps, and quality issues. Fix ALL findings at the highest severity level, then exit. Each iteration runs with FRESH CONTEXT.

> **Note:** One severity level per iteration. Loop until zero findings remain.

## Phase 0: Analyze

Run `/speckit.analyze` to generate findings. This produces a read-only Specification Analysis Report with a findings table, coverage summary, and metrics.

## Phase 1: Assess

1. Review the findings from the `/speckit.analyze` report
2. If TOTAL findings = 0, output the following promise tag and exit immediately:

<promise>ALL_FINDINGS_RESOLVED</promise>

3. Otherwise, identify the **highest** severity level present as the remediation target
4. List the findings at the target severity level that will be remediated

## Phase 2: Remediate

1. Fix **ALL** findings at the target severity level (highest severity present)
2. Only modify files in `{FEATURE_DIR}/` — never modify constitution.md
3. Apply fixes directly to the artifact files (spec.md, plan.md, tasks.md)
4. Keep fixes minimal and focused on resolving the specific finding

## Phase 3: Validate

1. Re-read all modified files
2. Verify each fix resolved its finding
3. Check no new same-or-higher severity issues were introduced
4. If new issues at the same severity were introduced, fix them now

## Phase 4: Commit & Exit

1. Commit all changes:
   ```bash
   git add -A && type=$(git branch --show-current | cut -f 2 -d '-') && scope=$(git branch --show-current | cut -f 3- -d '-') && ticket=$(git branch --show-current | cut -f 1 -d '-') && git commit -m "$type($scope): [$ticket] fix [SEVERITY] findings from cross-artifact analysis"
   git push origin $(git branch --show-current)
   ```
2. Exit immediately — you will restart with fresh context for the next severity level

## Guardrails

| # | Rule |
|---|------|
| 999 | **One severity level per iteration** — Fix all findings at the highest level, then exit |
| 998 | **Constitution is authoritative** — Never modify constitution.md; adjust spec/plan/tasks instead |
| 997 | **Spec artifacts only** — Only modify files within `{FEATURE_DIR}/` |
| 996 | **Validate after fixing** — Re-read modified files and verify fixes before committing |
| 995 | **Highest severity first** — Always target CRITICAL before HIGH before MEDIUM before LOW |

## File Paths

- Spec: `{FEATURE_DIR}/spec.md`
- Plan: `{FEATURE_DIR}/plan.md`
- Tasks: `{FEATURE_DIR}/tasks.md`
- Constitution: `.specify/memory/constitution.md`
