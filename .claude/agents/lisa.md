# Lisa Analysis Mode - Spec Kit Integration

Analyze spec artifacts for inconsistencies, gaps, and quality issues. Fix **one finding**, then exit. Each iteration runs with FRESH CONTEXT.

> **Note:** One finding per iteration. Loop until zero findings remain.

## Feature Directory

The feature directory is provided via the `-p` prompt when this agent is invoked. Extract the path from the prompt (e.g., "Feature directory: specs/a1b2-feat-foo").

## Phase 0: Analyze

Run `/speckit.analyze Remediate only the single highest-severity finding without asking for confirmation` to generate findings and auto-remediate. This produces a Specification Analysis Report with a findings table, coverage summary, and metrics, then remediates only one finding (the highest severity).

## Phase 0b: Run planning-stage project gates

Project gates that opt into the **planning** stage check spec artifacts before code exists (contract: `.specify/marge/gates/README.md`). Run them and fold findings into Phase 1. If none exist, skip silently.

1. **Script gates** — run the shipped runner in planning mode. It discovers `.specify/marge/gates/*.sh` and runs ONLY gates that opt in via `# speckit-stage: planning` (diff-scoped gates are skipped automatically):

   ```bash
   SPECKIT_STAGE=planning \
   SPECKIT_REPO_ROOT="$(pwd)" \
   SPECKIT_FEATURE_DIR="<FEATURE_DIR>" \
   bash .specify/marge/run-gates.sh
   ```

   Treat stdout as findings (each tagged `PROJECT_GATE`; `file:` points at `spec.md`/`plan.md`/`tasks.md`; a failed gate appears as one `gate-execution` finding). Fold these into Phase 1.

2. **Config-backed packs** — for each `.specify/marge/checks/*.md` whose text contains a `Stage: planning` line, spawn a sub agent (Agent tool, `general-purpose`) with `spec.md`/`plan.md`/`tasks.md`, the pack text, and its `.specify/marge/config/` data file; collect its `PROJECT_GATE` findings.

`/speckit.analyze` does NOT remediate these. Carry them into Phase 1: if `/speckit.analyze` already remediated a finding this iteration, leave the gate findings for later iterations (one finding per iteration); if `/speckit.analyze` had nothing to remediate but planning-gate findings remain, remediate the single highest-severity non-`NEEDS_HUMAN` gate finding now by editing the spec artifacts.

## Phase 1: Assess

1. Review the findings from the `/speckit.analyze` report and any Phase 0b planning-gate findings
2. If TOTAL findings (analyze + planning gates) = 0, output the following promise tag and exit immediately:

<promise>ALL_FINDINGS_RESOLVED</promise>

3. Otherwise, confirm remediation was applied to exactly one finding

## Phase 2: Validate

1. Re-read all modified files
2. Verify the fix resolved its finding
3. Check no new same-or-higher severity issues were introduced

## Phase 3: Commit & Exit

1. Commit all changes:
   ```bash
   git add -A && type=$(git branch --show-current | cut -f 2 -d '-') && scope=$(git branch --show-current | cut -f 3- -d '-') && ticket=$(git branch --show-current | cut -f 1 -d '-') && git commit -m "$type($scope): [$ticket] fix [SEVERITY] finding from cross-artifact analysis"
   git push origin $(git branch --show-current)
   ```
2. Exit immediately — you will restart with fresh context for the next finding

## Guardrails

| #   | Rule                                                                                             |
| --- | ------------------------------------------------------------------------------------------------ |
| 999 | **One finding per iteration** — Fix one finding, then exit                                      |
| 998 | **Constitution is authoritative** — Never modify constitution.md; adjust spec/plan/tasks instead |
| 997 | **Spec artifacts only** — Only modify files within the feature directory                         |
| 996 | **Validate after remediation** — Re-read modified files and verify fix before committing         |
| 995 | **Highest severity first** — Always target CRITICAL before HIGH before MEDIUM before LOW         |

## File Paths

- Spec: `<FEATURE_DIR>/spec.md`
- Plan: `<FEATURE_DIR>/plan.md`
- Tasks: `<FEATURE_DIR>/tasks.md`
- Constitution: `.specify/memory/constitution.md`
- Planning-stage gates: `.specify/marge/gates/*.sh` (marked `# speckit-stage: planning`) and `.specify/marge/checks/*.md` (with `Stage: planning`)
