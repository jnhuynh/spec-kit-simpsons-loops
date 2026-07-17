# Marge Review Mode - Spec Kit Integration

Review implementation code against baseline and project-specific review packs. Fix **all auto-fixable findings** from one review pass, then exit. Each iteration runs with FRESH CONTEXT. Loop until a fresh review pass comes back clean.

> **Note:** One remediation pass per iteration. The next iteration's fresh review verifies the fixes and catches anything they introduced.

## Feature Directory

The feature directory is provided in the invocation prompt (each iteration is spawned via the Agent tool). Extract the path from the prompt (e.g., "Feature directory: specs/a1b2-feat-foo").

## Findings Ledger

This loop persists finding identity across iterations per `.claude/agents/findings-ledger.md` with this LEDGER_CONFIG:

- **REPORT_FILE**: `<FEATURE_DIR>/review-report.md`
- **PHASE_VALUE**: integer phase number when the finding is attributable to one phase of a multi-phase feature; else `-`
- **CHECK_PACK_VALUE**: source pack filename

## Phase 0: Load ledger

Per the ledger protocol §1: if `<FEATURE_DIR>/review-report.md` exists, read it FIRST and build the exclusion list (rows with Status `fixed`, `resolved`, `reappeared`, or `needs_human`). This must happen before the review runs — remediation must never touch a finding that regenerated after being fixed.

## Phase 1: Review

Run `/speckit-review Remediate all auto-fixable findings in severity order without asking for confirmation` to generate findings and auto-remediate. If Phase 0 produced an exclusion list, append it to the invocation:

> Known findings — report but do NOT remediate (they reappeared after being fixed, or need human judgment):
> - <file> — <rule> — <summary>   (one line per exclusion)

This produces a Code Review Report with a findings table grouped by severity, then remediates every finding not flagged `NEEDS_HUMAN` and not on the exclusion list, in severity order (CRITICAL, HIGH, MEDIUM, LOW).

## Phase 2: Assess

1. Match this iteration's findings against the ledger per protocol §2: reuse IDs; a match against a `fixed`/`resolved` row becomes `reappeared` (treated as `NEEDS_HUMAN`, never auto-fixed); new findings get new IDs.
2. If zero findings remain outside {`NEEDS_HUMAN`, `reappeared`}: update the ledger (absent findings → `resolved`), write it per protocol §4, commit (Phase 4), output the following promise tag, and exit:

<promise>ALL_FINDINGS_RESOLVED</promise>

3. Otherwise, confirm remediation was applied to every auto-fixable finding. Report this iteration's auto-fixable finding count (pre-fix, excluding `needs_human`/`reappeared`) as the work-remaining count.

## Phase 3: Validate

1. Re-read all modified files
2. Verify each fix resolved its finding
3. Check no new same-or-higher severity issues were introduced
4. Run `bash .specify/quality-gates-fast.sh` (or `bash .specify/quality-gates.sh` if the fast gate does not exist) **once, after all fixes** — if it exits non-zero, repair or revert the offending fix(es) and re-run until it passes. Never commit a red gate. A reverted fix is recorded `open` in the ledger (protocol §2) — it stays auto-fixable next iteration. The fast gate scopes checks to changed files for quick per-iteration feedback; the orchestrator runs the full gate (`.specify/quality-gates.sh`) once after the loop terminates.

## Phase 4: Commit & Exit

1. Write the ledger per protocol §4 (overwrite `<FEATURE_DIR>/review-report.md` in full), then commit all changes:
   ```bash
   bash .specify/scripts/bash/speckit-commit.sh "fix N findings from code review"
   ```
   (Replace N with the number of findings remediated this iteration.)
2. Exit immediately — you will restart with fresh context for the verification pass

## Guardrails

| #   | Rule                                                                                                |
| --- | --------------------------------------------------------------------------------------------------- |
| 999 | **One remediation pass per iteration** — Fix ALL auto-fixable findings from this iteration's review pass, then exit; never carry auto-fixable findings to the next iteration |
| 998 | **Constitution is authoritative** — Never modify `.specify/memory/constitution.md`                 |
| 997 | **Diff scope only** — Only modify lines the feature branch already touches; never fix pre-existing issues |
| 996 | **Validate after remediation** — Re-read modified files AND pass quality gates before committing    |
| 995 | **Severity order within the pass** — CRITICAL before HIGH before MEDIUM before LOW                  |
| 994 | **Mechanical fixes only** — Skip `NEEDS_HUMAN` findings; they require human judgment                |
| 993 | **Coordinated multi-file fixes** — When a finding requires changes across multiple files (e.g., extracting a duplicated helper into a shared module and updating all call sites), make ALL related changes for it in this iteration. One finding = one logical finding, not one file edit. |
| 992 | **Never re-fix a reappeared finding** — Ledger loaded BEFORE the review runs; findings matching `fixed`/`resolved` rows are excluded from remediation and marked `reappeared` + `NEEDS_HUMAN` (re-fixing causes endless loops) |

## File Paths

- Spec: `<FEATURE_DIR>/spec.md`
- Plan: `<FEATURE_DIR>/plan.md`
- Tasks: `<FEATURE_DIR>/tasks.md`
- Review report (ledger): `<FEATURE_DIR>/review-report.md`
- Ledger protocol: `.claude/agents/findings-ledger.md`
- Constitution: `.specify/memory/constitution.md`
- Baseline review packs: `.specify/marge/baseline/*.md`
- Project packs: `.specify/marge/project/*.md` (prose) and `.specify/marge/project/*.sh` (script) — findings tagged `PROJECT_GATE`
- Project pack config data: `.specify/marge/config/`
- Project guidelines: `CLAUDE.md` (repo root)
- Quality gates (fast, per-iteration): `.specify/quality-gates-fast.sh`
- Quality gates (full, end-of-loop): `.specify/quality-gates.sh`
