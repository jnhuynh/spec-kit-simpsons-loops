# Contract: `<FEATURE_DIR>/review-report.md`

## Purpose

Persist the review step's findings to a deterministic, machine-readable artifact that the split step reads to enforce per-phase gating without re-running review (FR-012a, FR-018).

## Producer

Marge (the review step), via `speckit-commands/speckit.marge.review.md` and `claude-agents/marge.md`. The report is overwritten on every Marge run.

## Consumer

The split step (`speckit-commands/speckit.split.md`), which parses the report's findings table to identify unresolved high-severity findings and gate pull-request creation accordingly.

## File location

`<FEATURE_DIR>/review-report.md` where `<FEATURE_DIR>` is the resolved feature directory (e.g., `specs/008-feat-multi-phase-deploys/review-report.md`).

## Format

A standard Markdown file. The machine-readable surface is **exactly one** GitHub Flavored Markdown (GFM) table with the column headers below in this exact order:

```markdown
| ID | Severity | Phase | Status | Check Pack | Summary |
```

Cells use pipe (`|`) characters escaped as `\|` so that `awk -F '|'` parses cleanly. The file MAY contain additional human-readable prose before and after the table. Consumers MUST locate the table by its **exact** header row and parse rows until the next blank line or end of file.

## Schema

| Column | Type | Allowed values | Notes |
|---|---|---|---|
| `ID` | String | Stable per-finding identifier the review step assigns | Reused across runs against the same branch state, so a finding can be tracked from `open` to `resolved` without changing rows. Format is review-step-internal; the split step treats IDs opaquely. |
| `Severity` | Enum | `high`, `medium`, `low`, `informational` | The split step only gates on `high`. Other severities are advisory. |
| `Phase` | Integer or `-` | Integer phase number (multi-phase, attributable findings); literal `-` (single-phase OR multi-phase non-attributable structural inconsistency) | Per the spec.md clarification on FR-010 patterns: S3 (malformed trailer) and S4 (phase-trailer-without-deploy-phases) emit with Phase `-`. |
| `Status` | Enum | `open`, `resolved` | New findings emit as `open`. The review step transitions a finding to `resolved` only when a subsequent run, against the same branch state, confirms the issue is gone. |
| `Check Pack` | String | The source check pack filename (e.g., `migrations.md`, `architecture.md`, `security.md`) | Informational; not used for gating per the FR-018 clarification. |
| `Summary` | String | Single-sentence human-readable description | Pipe characters escaped as `\|`. |

## Gating semantics

The split step's gating contract (FR-018) reads the table and treats:

- **High-severity findings whose Status is anything other than `resolved`** as gating.
- **Multi-phase findings with Phase = integer K**: gate phase K and any phase that depends on phase K (i.e., phases K+1..N inherit the gate transitively because their base branches include phase K's commits).
- **Findings with Phase = `-` and Severity = `high`** (multi-phase only): gate every phase in the run (a global gate). This is how the migration-safety check pack signals structural inconsistencies that cannot be attributed to a single phase (S3, S4).
- **Findings with Phase = `-` and Severity = `high`** (single-phase): gate the single pull request per FR-019.
- **Findings with Severity below `high`**: never gate. Surfaced for the human reviewer.

## Examples

### Empty findings (clean review)

```markdown
# Code Review Report — 008-feat-multi-phase-deploys

Marge ran the baseline and project-specific review packs against the feature branch and found no actionable findings.

| ID | Severity | Phase | Status | Check Pack | Summary |
| --- | -------- | ----- | -------- | ---------------- | ------- |
```

(Empty body. The header row is still present so the split step can locate the table.)

### Multi-phase, two open findings, one resolved

```markdown
# Code Review Report — 008-feat-multi-phase-deploys

Three findings emitted across the integrated branch.

| ID  | Severity | Phase | Status   | Check Pack       | Summary |
| --- | -------- | ----- | -------- | ---------------- | ------- |
| F001 | high     | 2     | open     | migrations.md    | Phase 2 drops `users.email_address` while phase-1 code still reads it (M2). |
| F002 | high     | 3     | resolved | migrations.md    | Phase 3 added a NOT NULL column without default (M1); resolved by adding default. |
| F003 | medium   | 1     | open     | architecture.md  | New helper duplicates existing `format_phone_number` in `src/utils/format.py` (A2). |
```

The split step would gate phase 2 (and phases 3, 4 transitively) on F001. F002 is resolved and does not gate. F003 is below `high` severity and does not gate.

### Single-phase, one open finding

```markdown
# Code Review Report — 001-consistency-cleanup

| ID   | Severity | Phase | Status | Check Pack    | Summary |
| ---- | -------- | ----- | ------ | ------------- | ------- |
| F001 | high     | -     | open   | security.md   | Hardcoded API token in `src/clients/external.py` (S3). |
```

The split step would gate the single pull request on F001 per FR-019.

### Global-gate case (malformed trailer)

```markdown
| ID   | Severity | Phase | Status | Check Pack    | Summary |
| ---- | -------- | ----- | ------ | ------------- | ------- |
| F001 | high     | -     | open   | migrations.md | Commit ab12cd34 has malformed `Phase:` trailer with empty value (S3). |
```

The split step would gate every phase in the run on F001 (global gate per FR-018).

## Validation rules

- The table MUST have the exact header row `| ID | Severity | Phase | Status | Check Pack | Summary |` in that order. Any deviation is a contract violation.
- Pipe characters in cell values MUST be escaped as `\|`.
- Empty cells MUST be either a literal `-` (preferred for non-applicable fields like Phase in single-phase) or empty between pipes (acceptable but discouraged).
- The file MUST be overwritten in full on every Marge run; never appended to.
- Absence of the file MUST cause the split step to refuse to run with the message `Review report not found at <FEATURE_DIR>/review-report.md. Run /speckit.marge.review first.`

## Parsing recipe (split step)

The split step parses the report via:

```bash
# Locate the header row by pattern, then read subsequent rows until blank or EOF.
awk -F '|' '
  /^\| ID \| Severity \| Phase \| Status \| Check Pack \| Summary \|/ {
    in_table = 1
    next
  }
  in_table && /^\| --- / { next }    # skip GFM separator row
  in_table && /^$/        { in_table = 0; next }
  in_table {
    # Trim each field; honor \| escapes in Summary cell.
    id       = trim($2)
    severity = trim($3)
    phase    = trim($4)
    status   = trim($5)
    pack     = trim($6)
    summary  = trim($7)
    # Emit gating decision per FR-018.
    if (severity == "high" && status != "resolved") {
      print "GATE", phase, id, summary
    }
  }
'
```

The exact awk script lives in the split step's command/agent files; this contract specifies the parsing semantics.
