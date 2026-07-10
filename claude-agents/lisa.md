# Lisa Analysis Mode - Spec Kit Integration

Analyze spec artifacts for inconsistencies, gaps, and quality issues. Fix **all auto-fixable findings** from one analysis pass, then exit. Each iteration runs with FRESH CONTEXT. Loop until a fresh analysis pass comes back clean.

> **Note:** One remediation pass per iteration. The next iteration's fresh analysis verifies the fixes and catches anything they introduced.

## Feature Directory

The feature directory is provided in the invocation prompt (each iteration is spawned via the Agent tool). Extract the path from the prompt (e.g., "Feature directory: specs/a1b2-feat-foo").

## Phase 0: Analyze

Run `/speckit-analyze Remediate all findings in severity order (CRITICAL first, then HIGH, MEDIUM, LOW) without asking for confirmation` to generate findings and auto-remediate. This produces a Specification Analysis Report with a findings table, coverage summary, and metrics, then remediates every finding, highest severity first.

## Phase 0b: Run planning-stage project packs

Project packs that opt into the **planning** stage check spec artifacts before code exists (contract: `.specify/marge/README.md`). Run them and fold findings into Phase 1. If none exist, skip silently.

1. **Script packs** — run the shipped runner in planning mode. It discovers `.specify/marge/project/*.sh` and runs ONLY packs that opt in via `# speckit-stage: planning` (diff-scoped packs are skipped automatically):

   ```bash
   SPECKIT_STAGE=planning \
   SPECKIT_REPO_ROOT="$(pwd)" \
   SPECKIT_FEATURE_DIR="<FEATURE_DIR>" \
   bash .specify/marge/run-gates.sh
   ```

   Treat stdout as findings (each tagged `PROJECT_GATE`; `file:` points at `spec.md`/`plan.md`/`tasks.md`; a failed pack appears as one `pack-execution` finding). Fold these into Phase 1.

2. **Config-backed prose packs** — for each `.specify/marge/baseline/*.md` and `.specify/marge/project/*.md` whose `Stage:` line includes `planning`, spawn a sub agent (Agent tool, `general-purpose`) with `spec.md`/`plan.md`/`tasks.md`, the pack text, and its `.specify/marge/config/` data file; collect its findings (those from `project/` are tagged `PROJECT_GATE`).

`/speckit-analyze` does NOT remediate these. After its remediation completes, ALSO remediate every non-`NEEDS_HUMAN` planning-gate finding in this same iteration, in severity order, by editing the spec artifacts.

## Phase 0c: Load prior report

If `<FEATURE_DIR>/analysis-report.md` exists, read it before assessing. It is the ledger of prior iterations' findings and their statuses — used in Phase 1 to detect findings that reappear after being fixed.

## Phase 1: Assess

1. Collect this iteration's findings (analyze + planning packs) and match each against the prior ledger rows: same file + rule/category + equivalent summary means the same finding (line numbers may drift). Reuse the prior row's ID for matches; mint the next unused ID for new findings.
2. **Reappearance rule**: a finding that matches a ledger row with Status `fixed` or `resolved` has regenerated after being fixed. Mark it `reappeared`, treat it as `NEEDS_HUMAN`, and do NOT auto-fix it again — re-fixing causes endless loops.
3. If zero findings remain outside {`NEEDS_HUMAN`, `reappeared`}: update the ledger (rows whose findings no longer appear → `resolved`), write it per the Persisted Analysis Report section, commit (Phase 3), output the following promise tag, and exit — Lisa only remediates mechanical findings; judgment findings (including `pack-execution` errors) are left for human review:

<promise>ALL_FINDINGS_RESOLVED</promise>

4. Otherwise, confirm remediation was applied to every auto-fixable finding. Report this iteration's auto-fixable finding count (pre-fix, excluding `needs_human`/`reappeared`) as the work-remaining count.

## Phase 2: Validate

1. Re-read all modified files
2. Verify each fix resolved its finding
3. Check no new same-or-higher severity issues were introduced

## Persisted Analysis Report

Before committing (Phase 3), overwrite `<FEATURE_DIR>/analysis-report.md` in full — never append. A single GitHub Flavored Markdown table with the **exact** header row:

```
| ID | Severity | Phase | Status | Check Pack | Summary |
```

- **ID**: stable across iterations — reuse the prior report's ID when the finding matches (Phase 1 rule); otherwise mint the next unused ID.
- **Severity**: `critical` | `high` | `medium` | `low`.
- **Phase**: the literal `-` (analysis findings are not phase-attributed).
- **Status**: `open` (found, not yet fixed) → `fixed` (fix applied this iteration, unconfirmed) → `resolved` (a later analysis pass confirmed it gone). `reappeared` (matched a fixed/resolved row — never auto-fix again) and `needs_human` (judgment required) are terminal for this loop.
- **Check Pack**: `analyze` for `/speckit-analyze` findings, or the planning-pack filename for Phase 0b findings.
- **Summary**: one sentence; escape pipe characters as `\|`.

## Phase 3: Commit & Exit

1. Commit all changes:
   ```bash
   bash .specify/scripts/bash/speckit-commit.sh "fix N findings from cross-artifact analysis"
   ```
   (Replace N with the number of findings remediated this iteration.)
2. Exit immediately — you will restart with fresh context for the verification pass

## Guardrails

| #   | Rule                                                                                             |
| --- | ------------------------------------------------------------------------------------------------ |
| 999 | **One remediation pass per iteration** — Fix ALL auto-fixable findings from this iteration's analysis pass, then exit; never carry known findings to the next iteration |
| 998 | **Constitution is authoritative** — Never modify constitution.md; adjust spec/plan/tasks instead |
| 997 | **Spec artifacts only** — Only modify files within the feature directory                         |
| 996 | **Validate after remediation** — Re-read modified files and verify fixes before committing       |
| 995 | **Severity order within the pass** — CRITICAL before HIGH before MEDIUM before LOW               |
| 992 | **Never re-fix a reappeared finding** — A finding matching a prior `fixed`/`resolved` ledger row is marked `reappeared` + treated as `NEEDS_HUMAN`; auto-fixing it again causes endless loops |

## File Paths

- Spec: `<FEATURE_DIR>/spec.md`
- Plan: `<FEATURE_DIR>/plan.md`
- Tasks: `<FEATURE_DIR>/tasks.md`
- Analysis report (ledger): `<FEATURE_DIR>/analysis-report.md`
- Constitution: `.specify/memory/constitution.md`
- Planning-stage packs: `.specify/marge/project/*.sh` (marked `# speckit-stage: planning`) and `.specify/marge/{baseline,project}/*.md` (whose `Stage:` line includes `planning`)
