# Speckit Findings Ledger Protocol

Shared ledger contract for loop agents that batch-remediate findings (Marge, Lisa). The ledger carries finding identity across fresh-context iterations so a finding that regenerates after being fixed is escalated to a human instead of being re-fixed forever. This file is parameterized by a LEDGER_CONFIG block in the calling agent file:

- **REPORT_FILE**: the persisted report path (e.g. `<FEATURE_DIR>/review-report.md`)
- **PHASE_VALUE**: what the Phase column holds (integer phase number when attributable, else `-`)
- **CHECK_PACK_VALUE**: what the Check Pack column holds (source pack filename, or `analyze`)

## 1. Load — BEFORE any remediation runs

If REPORT_FILE exists, read it before invoking the analysis/review skill. Build the **exclusion list**: every row whose Status is `fixed`, `resolved`, `reappeared`, or `needs_human`. These are findings that must NOT be auto-remediated this iteration — `fixed`/`resolved` rows because a match means the finding regenerated (re-fixing it causes endless loops), `reappeared`/`needs_human` rows because they are terminal for the loop.

Pass the exclusion list into the skill invocation (file + rule/category + one-line summary per entry) with the instruction: report matching findings but do not remediate them. Ordering is load-bearing: if remediation runs before the ledger is loaded, a reappeared finding gets re-fixed before it can be recognized.

## 2. Match & classify — after the scan

Match each of this iteration's findings against ledger rows: same file + rule/category + equivalent summary means the same finding (line numbers may drift). Reuse the matched row's ID; mint the next unused ID for new findings.

- Match against a `fixed` or `resolved` row → Status `reappeared`. Treat as `NEEDS_HUMAN`; never auto-fix.
- Match against a `reappeared` or `needs_human` row → keep that Status.
- No match → `open`, then `fixed` once its remediation is applied this iteration.
- **Reverted fixes stay `open`**: if a fix is applied but then reverted (e.g. the quality gate failed and the repair path withdrew it), record the row as `open` — the fix did not land, the finding remains auto-fixable next iteration. Only a fix that is still in the working tree at commit time is `fixed`.

## 3. Status lifecycle

`open` (found, no landed fix) → `fixed` (fix applied this iteration, unconfirmed) → `resolved` (a later scan confirmed it gone). `reappeared` (regenerated after a fix — never auto-fix again) and `needs_human` (judgment required) are terminal for the loop. Rows whose findings no longer appear in a scan move `fixed` → `resolved`.

## 4. Write — before every commit

Overwrite REPORT_FILE in full — never append. A single GitHub Flavored Markdown table with the **exact** header row:

```
| ID | Severity | Phase | Status | Check Pack | Summary |
```

- **ID**: stable across iterations (§2 matching rule).
- **Severity**: `critical` | `high` | `medium` | `low`.
- **Phase**: PHASE_VALUE.
- **Status**: per §3.
- **Check Pack**: CHECK_PACK_VALUE (informational).
- **Summary**: one sentence; escape pipe characters as `\|` so the table renders intact.
