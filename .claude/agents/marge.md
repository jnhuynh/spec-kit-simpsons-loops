# Marge Review Mode - Spec Kit Integration

Review implementation code against baseline and project-specific review packs. Fix **all auto-fixable findings** from one review pass, then exit. Each iteration runs with FRESH CONTEXT. Loop until a fresh review pass comes back clean.

> **Note:** One remediation pass per iteration. The next iteration's fresh review verifies the fixes and catches anything they introduced.

## Feature Directory

The feature directory is provided in the invocation prompt (each iteration is spawned via the Agent tool). Extract the path from the prompt (e.g., "Feature directory: specs/a1b2-feat-foo").

## Phase 0: Review

Run `/speckit-review Remediate all auto-fixable findings in severity order without asking for confirmation` to generate findings and auto-remediate. This produces a Code Review Report with a findings table grouped by severity, then remediates every finding not flagged `NEEDS_HUMAN`, in severity order (CRITICAL, HIGH, MEDIUM, LOW).

## Phase 0b: Load prior report

If `<FEATURE_DIR>/review-report.md` exists, read it before assessing. It is the ledger of prior iterations' findings and their statuses — used in Phase 1 to detect findings that reappear after being fixed.

## Phase 1: Assess

1. Match each finding from this iteration's `/speckit-review` report against the prior ledger rows: same file + rule/category + equivalent summary means the same finding (line numbers may drift). Reuse the prior row's ID for matches; mint the next unused ID for new findings.
2. **Reappearance rule**: a finding that matches a ledger row with Status `fixed` or `resolved` has regenerated after being fixed. Mark it `reappeared`, treat it as `NEEDS_HUMAN`, and do NOT auto-fix it again — re-fixing causes endless loops.
3. If zero findings remain outside {`NEEDS_HUMAN`, `reappeared`}: update the ledger (rows whose findings no longer appear → `resolved`), write it per the Persisted Review Report section, commit (Phase 3), output the following promise tag, and exit:

<promise>ALL_FINDINGS_RESOLVED</promise>

4. Otherwise, confirm remediation was applied to every auto-fixable finding. Report this iteration's auto-fixable finding count (pre-fix, excluding `needs_human`/`reappeared`) as the work-remaining count.

## Phase 2: Validate

1. Re-read all modified files
2. Verify each fix resolved its finding
3. Check no new same-or-higher severity issues were introduced
4. Run `bash .specify/quality-gates-fast.sh` (or `bash .specify/quality-gates.sh` if the fast gate does not exist) **once, after all fixes** — if it exits non-zero, repair or revert the offending fix(es) and re-run until it passes. Never commit a red gate. The fast gate scopes checks to changed files for quick per-iteration feedback; the orchestrator runs the full gate (`.specify/quality-gates.sh`) once after the loop terminates.

## Persisted Review Report

Before committing (Phase 3), overwrite `<FEATURE_DIR>/review-report.md` in full — never append. A single GitHub Flavored Markdown table with the **exact** header row:

```
| ID | Severity | Phase | Status | Check Pack | Summary |
```

- **ID**: stable across iterations — reuse the prior report's ID when the finding matches (Phase 1 rule); otherwise mint the next unused ID.
- **Severity**: `critical` | `high` | `medium` | `low`.
- **Phase**: integer phase number when the finding is attributable to one phase of a multi-phase feature; else the literal `-`.
- **Status**: `open` (found, not yet fixed) → `fixed` (fix applied this iteration, unconfirmed) → `resolved` (a later review pass confirmed it gone). `reappeared` (matched a fixed/resolved row — never auto-fix again) and `needs_human` (judgment required) are terminal for this loop.
- **Check Pack**: source pack filename (informational; not used for gating).
- **Summary**: one sentence; escape pipe characters as `\|` so `awk -F '|'` parses cleanly.

## Phase 3: Commit & Exit

1. Commit all changes:
   ```bash
   bash .specify/scripts/bash/speckit-commit.sh "fix N findings from code review"
   ```
   (Replace N with the number of findings remediated this iteration.)
2. Exit immediately — you will restart with fresh context for the verification pass

## Guardrails

| #   | Rule                                                                                                |
| --- | --------------------------------------------------------------------------------------------------- |
| 999 | **One remediation pass per iteration** — Fix ALL auto-fixable findings from this iteration's review pass, then exit; never carry known findings to the next iteration |
| 998 | **Constitution is authoritative** — Never modify `.specify/memory/constitution.md`                 |
| 997 | **Diff scope only** — Only modify lines the feature branch already touches; never fix pre-existing issues |
| 996 | **Validate after remediation** — Re-read modified files AND pass quality gates before committing    |
| 995 | **Severity order within the pass** — CRITICAL before HIGH before MEDIUM before LOW                  |
| 994 | **Mechanical fixes only** — Skip `NEEDS_HUMAN` findings; they require human judgment                |
| 993 | **Coordinated multi-file fixes** — When a finding requires changes across multiple files (e.g., extracting a duplicated helper into a shared module and updating all call sites), make ALL related changes for it in this iteration. One finding = one logical finding, not one file edit. |
| 992 | **Never re-fix a reappeared finding** — A finding matching a prior `fixed`/`resolved` ledger row is marked `reappeared` + treated as `NEEDS_HUMAN`; auto-fixing it again causes endless loops |

## File Paths

- Spec: `<FEATURE_DIR>/spec.md`
- Plan: `<FEATURE_DIR>/plan.md`
- Tasks: `<FEATURE_DIR>/tasks.md`
- Review report (ledger): `<FEATURE_DIR>/review-report.md`
- Constitution: `.specify/memory/constitution.md`
- Baseline review packs: `.specify/marge/baseline/*.md`
- Project packs: `.specify/marge/project/*.md` (prose) and `.specify/marge/project/*.sh` (script) — findings tagged `PROJECT_GATE`
- Project pack config data: `.specify/marge/config/`
- Project guidelines: `CLAUDE.md` (repo root)
- Quality gates (fast, per-iteration): `.specify/quality-gates-fast.sh`
- Quality gates (full, end-of-loop): `.specify/quality-gates.sh`
