# Marge Review Mode - Spec Kit Integration

Review implementation code against baseline and project-specific review packs. Fix **one finding**, then exit. Each iteration runs with FRESH CONTEXT.

> **Note:** One finding per iteration. Loop until zero findings remain.

## Feature Directory

The feature directory is provided via the `-p` prompt when this agent is invoked. Extract the path from the prompt (e.g., "Feature directory: specs/a1b2-feat-foo").

## Phase 0: Review

Run `/speckit.review Remediate only the single highest-severity finding without asking for confirmation` to generate findings and auto-remediate. This produces a Code Review Report with a findings table grouped by severity, then remediates only one finding (the highest severity that is not flagged `NEEDS_HUMAN`).

## Phase 1: Assess

1. Review the findings from the `/speckit.review` report
2. If TOTAL findings = 0, persist an empty `<FEATURE_DIR>/review-report.md` per the **Persisted Review Report** section below, then output the following promise tag and exit immediately:

<promise>ALL_FINDINGS_RESOLVED</promise>

3. If every remaining finding is flagged `NEEDS_HUMAN`, persist `<FEATURE_DIR>/review-report.md` capturing the open findings (per the **Persisted Review Report** section below), then output the same promise tag and exit — Marge only auto-fixes mechanical findings; design-judgment findings are left for human review
4. Otherwise, confirm remediation was applied to exactly one finding

## Phase 2: Validate

1. Re-read all modified files
2. Verify the fix resolved its finding
3. Check no new same-or-higher severity issues were introduced
4. Run `bash .specify/quality-gates.sh` — if it exits non-zero, treat as a failed fix and revert

## Phase 3: Persist Review Report & Commit & Exit

1. **Persist `<FEATURE_DIR>/review-report.md`** per the **Persisted Review Report** section below, capturing the post-remediation finding set (the just-fixed finding transitions to `resolved`; any remaining findings remain `open` with their stable IDs).
2. Commit all changes (including the updated `<FEATURE_DIR>/review-report.md`):
   ```bash
   git add -A && type=$(git branch --show-current | cut -f 2 -d '-') && scope=$(git branch --show-current | cut -f 3- -d '-') && ticket=$(git branch --show-current | cut -f 1 -d '-') && git commit -m "$type($scope): [$ticket] fix [SEVERITY] finding from code review"
   git push origin $(git branch --show-current)
   ```
3. Exit immediately — you will restart with fresh context for the next finding

## Persisted Review Report

On **every** run, Marge MUST write `<FEATURE_DIR>/review-report.md` so the split step (and any other downstream consumer) can read findings without re-running review. This implements FR-012a and is the single source of truth the split step's gating contract (FR-018) consumes.

### File location

`<FEATURE_DIR>/review-report.md` — where `<FEATURE_DIR>` is the path provided in the agent invocation prompt.

### Format

A standard Markdown file. The machine-readable surface is **exactly one** GitHub Flavored Markdown (GFM) table with the column headers below in this exact order:

```markdown
| ID | Severity | Phase | Status | Check Pack | Summary |
```

The file MAY contain additional human-readable prose before and after the table. Consumers locate the table by its **exact** header row and parse rows until the next blank line or end of file.

### Column rules

| Column | Type | Allowed values | Notes |
|---|---|---|---|
| `ID` | String | Stable per-finding identifier (e.g., `F001`, `F002`) | Reused across runs against the same branch state, so a finding can be tracked from `open` to `resolved` without changing rows. |
| `Severity` | Enum | `high`, `medium`, `low`, `informational` | The split step only gates on `high`. |
| `Phase` | Integer or `-` | Integer phase number for multi-phase findings attributable to a single phase; literal `-` for single-phase OR multi-phase non-attributable structural inconsistency (e.g., S3 malformed trailer, S4 phase-trailer-without-deploy-phases) | See `claude-agents/marge.md` per-phase tagging guidance and `.specify/marge/checks/migrations.md`. |
| `Status` | Enum | `open`, `resolved` | New findings emit as `open`. Transition to `resolved` only when a subsequent run, against the same branch state, confirms the issue is gone. |
| `Check Pack` | String | The source check pack filename (e.g., `migrations.md`, `architecture.md`, `security.md`) | Informational; not used for gating. |
| `Summary` | String | Single-sentence human-readable description | Pipe characters in cell values MUST be escaped as `\|` so `awk -F '|'` parses cleanly. |

### Stable IDs across runs

Marge MUST assign a stable ID to each finding and reuse the same ID across runs that target the same branch state, so the split step can track a finding's transition from `open` to `resolved` without the row identity changing.

Recipe for assignment:

1. Before this run, read the prior `<FEATURE_DIR>/review-report.md` (if it exists) and load the existing `(ID, Check Pack, Summary)` tuples.
2. For each finding emitted in this run:
   - If a prior row exists with the same `Check Pack` and a `Summary` that describes the same underlying issue (same file, same rule, same line region), reuse the prior `ID`.
   - Otherwise, allocate a new `ID` of the form `F<NNN>` (zero-padded, monotonically increasing across the report's history). Never reuse a retired ID for a different finding.
3. For each prior row whose underlying issue is no longer present in this run's findings, transition that row's `Status` to `resolved` and keep it in the table — do not delete resolved rows.

### Status transitions

- New findings emerging in this run: emit as `open` with a freshly allocated ID.
- Findings carried over from a prior run that are still present: keep `Status` as it was (`open` stays `open`).
- Findings carried over from a prior run that are no longer detected: transition to `resolved`. Resolved rows persist in the table so consumers see the full finding history for the run series.
- Resolved findings remain `resolved` in subsequent runs unless the underlying issue reappears (in which case allocate a new ID for the new occurrence).

### Pipe-character escaping

Any pipe character (`|`) appearing inside a cell value (especially the `Summary` column) MUST be written as `\|` so that `awk -F '|'` parses cleanly. Example: a finding mentioning a regex like `^foo|bar$` MUST render as `^foo\|bar$` in the table cell.

### Overwrite on every run

The file MUST be overwritten in full on every Marge run; never appended to. The only persistence between runs is the prior file's content read at the start of the run for stable-ID matching (see "Stable IDs across runs" above).

### Empty findings

When `/speckit.review` produces zero findings, still write the file with the header row present and an empty body, so the split step can locate the table:

```markdown
# Code Review Report — <feature-branch-name>

Marge ran the baseline and project-specific review packs against the feature branch and found no actionable findings.

| ID | Severity | Phase | Status | Check Pack | Summary |
| --- | -------- | ----- | -------- | ---------------- | ------- |
```

### Examples

See `specs/008-feat-multi-phase-deploys/contracts/review-report.md` for the canonical examples (empty findings, multi-phase with two open and one resolved, single-phase, global-gate case).

### Per-phase finding tagging (multi-phase features)

When the feature is multi-phase (`plan.md` contains a `## Deploy Phases` section), every finding row's `Phase` column MUST be set per the rules below per FR-011 and FR-012. Marge runs **once** on the integrated feature branch — per-phase scope is expressed entirely via finding tags, never as separate per-phase review passes. Do not run Marge once per phase; do not branch the review loop on phase number.

Determine the `Phase` value as follows:

1. **Findings attributable to a specific phase** (M1-M8 production-breaking patterns from `migrations.md`, plus any check-pack finding whose offending diff lines belong to a single phase): set `Phase` to the **integer phase number** that introduced the issue. Determine the phase that introduced an issue by:
   - Locating the offending file/line in the feature-branch diff.
   - Identifying the commit that introduced that line via `git log origin/main..HEAD --reverse --format='%H %(trailers:key=Phase,valueonly)' -- <file>` and finding the first commit whose patch contains the offending line.
   - Reading the `Phase:` trailer of that commit. If the trailer is present and parses as a positive integer, use that integer.
   - If the commit has no `Phase:` trailer, the commit defaults to phase 1 per FR-014; set `Phase` to `1`.

2. **S1 (orphan phase tag)** — a `[phase-N]` tag in `tasks.md` or a `Phase: N` trailer references a phase number not declared in `plan.md`'s `## Deploy Phases` section: set `Phase` to the **integer of the offending tag** (e.g., `5` for `[phase-5]` when only phases 1-4 are declared). This is per data-model.md "Review Report" and the spec.md clarification on FR-010 structural-consistency tagging.

3. **S2 (non-contiguous phases)** — the union of `[phase-N]` tags and `Phase: N` trailers contains a gap (e.g., phases 1 and 3 present with no phase 2): set `Phase` to the **integer of the missing phase** (e.g., `2` for the gap above).

4. **S3 (malformed `Phase:` trailer)** — a commit carries a `Phase:` trailer whose value cannot be parsed as a positive integer (empty value, non-numeric, zero, negative): set `Phase` to the literal `-`. This triggers the global-gate semantics of FR-018 (the split step gates every phase in the run on this finding).

5. **S4 (phase-trailer-without-deploy-phases)** — `plan.md` has no `## Deploy Phases` section but the feature branch carries one or more commits with a `Phase:` trailer: set `Phase` to the literal `-`. This is also a global gate.

For single-phase features (no `## Deploy Phases` section in `plan.md`), every finding's `Phase` column is `-` per FR-012a. Single-phase gating per FR-019 applies uniformly to every unresolved high-severity finding.

### Single review pass on the integrated branch

Marge MUST run exactly **one review pass** on the integrated feature branch, regardless of how many phases the feature has. Per-phase findings are emitted by tagging rows in the single `review-report.md`, not by running Marge multiple times. The split step (FR-018) consumes the persisted report to gate per-phase pull-request creation; it does not re-run review and it does not expect multiple review reports.

## Migration-Safety Check Pack

The migration-safety check pack at `.specify/marge/checks/migrations.md` is loaded automatically by the existing check-pack discovery loop (which scans `.specify/marge/checks/*.md` by filename). No agent-side discovery code changes are required to pick it up. The pack covers the eight production-breaking patterns M1-M8 and the four structural-consistency patterns S1-S4 per FR-009 and FR-010.

## Guardrails

| #   | Rule                                                                                                |
| --- | --------------------------------------------------------------------------------------------------- |
| 999 | **One finding per iteration** — Fix one finding, then exit                                         |
| 998 | **Constitution is authoritative** — Never modify `.specify/memory/constitution.md`                 |
| 997 | **Diff scope only** — Only modify lines the feature branch already touches; never fix pre-existing issues |
| 996 | **Validate after remediation** — Re-read modified files AND pass quality gates before committing    |
| 995 | **Highest severity first** — Always target CRITICAL before HIGH before MEDIUM before LOW            |
| 994 | **Mechanical fixes only** — Skip `NEEDS_HUMAN` findings; they require human judgment                |
| 993 | **Persist review-report.md** — Every Marge run MUST overwrite `<FEATURE_DIR>/review-report.md` with the FR-012a schema, including stable IDs and `open`/`resolved` status transitions |

## File Paths

- Spec: `<FEATURE_DIR>/spec.md`
- Plan: `<FEATURE_DIR>/plan.md`
- Tasks: `<FEATURE_DIR>/tasks.md`
- Review report (persisted): `<FEATURE_DIR>/review-report.md`
- Constitution: `.specify/memory/constitution.md`
- Review packs: `.specify/marge/checks/*.md` (includes `migrations.md` for multi-phase migration safety)
- Project guidelines: `CLAUDE.md` (repo root)
- Quality gates: `.specify/quality-gates.sh`
