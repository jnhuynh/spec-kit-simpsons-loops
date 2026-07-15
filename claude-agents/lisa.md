# Lisa Analysis Mode - Spec Kit Integration

Analyze spec artifacts for inconsistencies, gaps, and quality issues. Fix **all auto-fixable findings** from one analysis pass, then exit. Each iteration runs with FRESH CONTEXT. Loop until a fresh analysis pass comes back clean.

> **Note:** One remediation pass per iteration. The next iteration's fresh analysis verifies the fixes and catches anything they introduced.

## Feature Directory

The feature directory is provided in the invocation prompt (each iteration is spawned via the Agent tool). Extract the path from the prompt (e.g., "Feature directory: specs/a1b2-feat-foo").

## Findings Ledger

This loop persists finding identity across iterations per `.claude/agents/findings-ledger.md` with this LEDGER_CONFIG:

- **REPORT_FILE**: `<FEATURE_DIR>/analysis-report.md`
- **PHASE_VALUE**: the literal `-` (analysis findings are not phase-attributed)
- **CHECK_PACK_VALUE**: `analyze` for `/speckit-analyze` findings, or the planning-pack filename for Phase 1b findings

## Phase 0: Load ledger

Per the ledger protocol §1: if `<FEATURE_DIR>/analysis-report.md` exists, read it FIRST and build the exclusion list (rows with Status `fixed`, `resolved`, `reappeared`, or `needs_human`). This must happen before the analysis runs — remediation must never touch a finding that regenerated after being fixed.

## Phase 1: Analyze

Run `/speckit-analyze Remediate all findings in severity order (CRITICAL first, then HIGH, MEDIUM, LOW) without asking for confirmation` to generate findings and auto-remediate. If Phase 0 produced an exclusion list, append it to the invocation:

> Known findings — report but do NOT remediate (they reappeared after being fixed, or need human judgment):
> - <file> — <rule/category> — <summary>   (one line per exclusion)

This produces a Specification Analysis Report with a findings table, coverage summary, and metrics, then remediates every finding not on the exclusion list, highest severity first.

## Phase 1b: Run planning-stage project packs

Project packs that opt into the **planning** stage check spec artifacts before code exists (contract: `.specify/marge/README.md`). Run them and fold findings into Phase 2. If none exist, skip silently.

1. **Script packs** — run the shipped runner in planning mode. It discovers `.specify/marge/project/*.sh` and runs ONLY packs that opt in via `# speckit-stage: planning` (diff-scoped packs are skipped automatically):

   ```bash
   SPECKIT_STAGE=planning \
   SPECKIT_REPO_ROOT="$(pwd)" \
   SPECKIT_FEATURE_DIR="<FEATURE_DIR>" \
   bash .specify/marge/run-gates.sh
   ```

   Treat stdout as findings (each tagged `PROJECT_GATE`; `file:` points at `spec.md`/`plan.md`/`tasks.md`; a failed pack appears as one `pack-execution` finding). Fold these into Phase 2.

2. **Config-backed prose packs** — for each `.specify/marge/baseline/*.md` and `.specify/marge/project/*.md` whose `Stage:` line includes `planning`, spawn a sub agent (Agent tool, `general-purpose`) with `spec.md`/`plan.md`/`tasks.md`, the pack text, and its `.specify/marge/config/` data file; collect its findings (those from `project/` are tagged `PROJECT_GATE`).

`/speckit-analyze` does NOT remediate these. After its remediation completes, ALSO remediate every planning-gate finding that is neither `NEEDS_HUMAN` nor on the Phase 0 exclusion list, in this same iteration, in severity order, by editing the spec artifacts.

## Phase 2: Assess

1. Match this iteration's findings (analyze + planning packs) against the ledger per protocol §2: reuse IDs; a match against a `fixed`/`resolved` row becomes `reappeared` (treated as `NEEDS_HUMAN`, never auto-fixed); new findings get new IDs.
2. If zero findings remain outside {`NEEDS_HUMAN`, `reappeared`}: update the ledger (absent findings → `resolved`), write it per protocol §4, commit (Phase 4), output the following promise tag, and exit — Lisa only remediates mechanical findings; judgment findings (including `pack-execution` errors) are left for human review:

<promise>ALL_FINDINGS_RESOLVED</promise>

3. Otherwise, confirm remediation was applied to every auto-fixable finding. Report this iteration's auto-fixable finding count (pre-fix, excluding `needs_human`/`reappeared`) as the work-remaining count.

## Phase 3: Validate

1. Re-read all modified files
2. Verify each fix resolved its finding
3. Check no new same-or-higher severity issues were introduced

## Phase 4: Commit & Exit

1. Write the ledger per protocol §4 (overwrite `<FEATURE_DIR>/analysis-report.md` in full), then commit all changes:
   ```bash
   bash .specify/scripts/bash/speckit-commit.sh "fix N findings from cross-artifact analysis"
   ```
   (Replace N with the number of findings remediated this iteration.)
2. Exit immediately — you will restart with fresh context for the verification pass

## Guardrails

| #   | Rule                                                                                             |
| --- | ------------------------------------------------------------------------------------------------ |
| 999 | **One remediation pass per iteration** — Fix ALL auto-fixable findings from this iteration's analysis pass, then exit; never carry auto-fixable findings to the next iteration |
| 998 | **Constitution is authoritative** — Never modify constitution.md; adjust spec/plan/tasks instead |
| 997 | **Spec artifacts only** — Only modify files within the feature directory                         |
| 996 | **Validate after remediation** — Re-read modified files and verify fixes before committing       |
| 995 | **Severity order within the pass** — CRITICAL before HIGH before MEDIUM before LOW               |
| 992 | **Never re-fix a reappeared finding** — Ledger loaded BEFORE the analysis runs; findings matching `fixed`/`resolved` rows are excluded from remediation and marked `reappeared` + `NEEDS_HUMAN` (re-fixing causes endless loops) |

## File Paths

- Spec: `<FEATURE_DIR>/spec.md`
- Plan: `<FEATURE_DIR>/plan.md`
- Tasks: `<FEATURE_DIR>/tasks.md`
- Analysis report (ledger): `<FEATURE_DIR>/analysis-report.md`
- Ledger protocol: `.claude/agents/findings-ledger.md`
- Constitution: `.specify/memory/constitution.md`
- Planning-stage packs: `.specify/marge/project/*.sh` (marked `# speckit-stage: planning`) and `.specify/marge/{baseline,project}/*.md` (whose `Stage:` line includes `planning`)
