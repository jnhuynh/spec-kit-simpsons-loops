# Contract: `<FEATURE_DIR>/split-report.md`

## Purpose

Persist the split step's outcome to a deterministic, machine-readable artifact that the pipeline orchestrator and re-running humans can read to determine what happened on a given run without re-invoking the split step (FR-019a).

## Producer

The split step (`speckit-commands/speckit.split.md` and `claude-agents/split.md`). The report is overwritten on every split-step run.

## Consumer

- The pipeline orchestrator (`speckit-commands/speckit.pipeline.md`) reads the report to determine the split step's outcome and decide whether to surface a failure or success message.
- Humans iterating on a feature read the report to see which phases shipped, which were gated, and which failed.

## File location

`<FEATURE_DIR>/split-report.md` where `<FEATURE_DIR>` is the resolved feature directory.

## Format

A standard Markdown file. The machine-readable surface is **exactly one** GitHub Flavored Markdown (GFM) table with the column headers below in this exact order:

```markdown
| Phase | Status | Branch | PR URL | Reason |
```

Cells use pipe (`|`) characters escaped as `\|` so that `awk -F '|'` parses cleanly. The file MAY contain additional human-readable prose before and after the table. Consumers MUST locate the table by its **exact** header row and parse rows until the next blank line or end of file.

## Schema

| Column | Type | Allowed values | Notes |
|---|---|---|---|
| `Phase` | Integer or `single` | Integer phase number (multi-phase); literal `single` (single-phase) | Single-phase features always emit one row with `Phase` = `single`. |
| `Status` | Enum | `created`, `updated`, `unchanged`, `skipped-merged`, `gated`, `failed` | One terminal status per row per run. |
| `Branch` | String or `-` | `NNNN-<type>-<slug>-phaseK` (multi-phase); feature branch name (single-phase); literal `-` (only when the run failed before resolving the branch name) | The branch name is determined deterministically from the feature branch name and phase number. |
| `PR URL` | String or `-` | Pull-request URL when one exists; literal `-` when omitted | Required for `created` and `updated` rows. Optional for `unchanged` (when URL was not re-fetched). Always `-` for `gated`, `skipped-merged` (unless the merged PR's URL is preserved), and `failed` (when the failure prevented PR resolution). |
| `Reason` | String or `-` | Single-sentence human-readable explanation, or literal `-` | Required (non-`-`) for `skipped-merged`, `gated`, `failed`. Optional for `created`, `updated`, `unchanged`. Pipe characters escaped as `\|`. |

## Status definitions

| Status | When |
|---|---|
| `created` | The phase branch did not exist on the remote; this run created the branch and opened a new pull request. PR URL is the newly-opened PR. |
| `updated` | The phase branch existed on the remote; this run rebuilt it (force-pushed via `--force-with-lease`) and/or rewrote the PR title/body. PR URL is the existing PR. |
| `unchanged` | The phase branch's commit SHAs already matched the recomputed phase branch SHAs AND the existing PR title and body already matched the recomputed values. No force-push, no `gh pr edit`. PR URL is the existing PR if available. |
| `skipped-merged` | The phase branch's pull request was already merged into `origin/main`; the split step skipped rebuild to protect shipped history (FR-017). Reason cites the merged state. |
| `gated` | The phase has an unresolved high-severity finding in `<FEATURE_DIR>/review-report.md`; the split step refused to open or update the pull request (FR-018). Reason cites the gating finding's ID and summary. |
| `failed` | The split step failed fast on this phase per FR-017's fail-fast rule. Reason cites the failure (e.g., `gh pr create` exit code, cherry-pick conflict, fetch failure). |

## Examples

### Multi-phase 4-phase fresh run, all created

```markdown
# Split Report — 008-feat-multi-phase-deploys

Run completed successfully. Four phase pull requests opened in deploy order.

| Phase | Status  | Branch                              | PR URL                               | Reason |
| ----- | ------- | ----------------------------------- | ------------------------------------ | ------ |
| 1     | created | 008-feat-multi-phase-deploys-phase1 | https://github.com/org/repo/pull/123 | -      |
| 2     | created | 008-feat-multi-phase-deploys-phase2 | https://github.com/org/repo/pull/124 | -      |
| 3     | created | 008-feat-multi-phase-deploys-phase3 | https://github.com/org/repo/pull/125 | -      |
| 4     | created | 008-feat-multi-phase-deploys-phase4 | https://github.com/org/repo/pull/126 | -      |
```

### Multi-phase re-run with no changes

```markdown
| Phase | Status    | Branch                              | PR URL                               | Reason |
| ----- | --------- | ----------------------------------- | ------------------------------------ | ------ |
| 1     | unchanged | 008-feat-multi-phase-deploys-phase1 | https://github.com/org/repo/pull/123 | -      |
| 2     | unchanged | 008-feat-multi-phase-deploys-phase2 | https://github.com/org/repo/pull/124 | -      |
| 3     | unchanged | 008-feat-multi-phase-deploys-phase3 | https://github.com/org/repo/pull/125 | -      |
| 4     | unchanged | 008-feat-multi-phase-deploys-phase4 | https://github.com/org/repo/pull/126 | -      |
```

### Multi-phase run gated by a phase-2 finding

```markdown
| Phase | Status    | Branch                              | PR URL                               | Reason |
| ----- | --------- | ----------------------------------- | ------------------------------------ | ------ |
| 1     | unchanged | 008-feat-multi-phase-deploys-phase1 | https://github.com/org/repo/pull/123 | -      |
| 2     | gated     | 008-feat-multi-phase-deploys-phase2 | -                                    | F003 (high, M3 rename in single phase) is open against phase 2. |
| 3     | gated     | 008-feat-multi-phase-deploys-phase3 | -                                    | Downstream of gated phase 2; resolve F003 then re-run. |
| 4     | gated     | 008-feat-multi-phase-deploys-phase4 | -                                    | Downstream of gated phase 2; resolve F003 then re-run. |
```

### Multi-phase failure on phase 3

```markdown
| Phase | Status  | Branch                              | PR URL                               | Reason |
| ----- | ------- | ----------------------------------- | ------------------------------------ | ------ |
| 1     | updated | 008-feat-multi-phase-deploys-phase1 | https://github.com/org/repo/pull/123 | -      |
| 2     | updated | 008-feat-multi-phase-deploys-phase2 | https://github.com/org/repo/pull/124 | -      |
| 3     | failed  | 008-feat-multi-phase-deploys-phase3 | -                                    | Cherry-pick conflict on commit ab12cd34: tests/conftest.py both modified. Resolve manually then re-run /speckit.split. |
```

Phase 4 is not enumerated because the run halted on phase 3 (fail-fast per FR-017). On the next idempotent re-run after the conflict is resolved, phases 1 and 2 will report `unchanged`, phase 3 will be re-attempted, and phase 4 will be processed.

### Single-phase happy path

```markdown
| Phase  | Status  | Branch                  | PR URL                               | Reason |
| ------ | ------- | ----------------------- | ------------------------------------ | ------ |
| single | created | 001-consistency-cleanup | https://github.com/org/repo/pull/127 | -      |
```

### Single-phase gated

```markdown
| Phase  | Status | Branch                  | PR URL | Reason |
| ------ | ------ | ----------------------- | ------ | ------ |
| single | gated  | 001-consistency-cleanup | -      | F001 (high) is open in review-report.md. |
```

### Fetch failure (no rows beyond the failed row)

```markdown
| Phase  | Status | Branch | PR URL | Reason |
| ------ | ------ | ------ | ------ | ------ |
| single | failed | -      | -      | Failed to fetch origin/main: fatal: unable to access 'https://github.com/org/repo.git/': Could not resolve host: github.com |
```

The Phase column shows `single` in this case because the split step failed before detecting multi-phase; the single failed row signals the run did not progress past the fetch step.

## Validation rules

- The table MUST have the exact header row `| Phase | Status | Branch | PR URL | Reason |` in that order. Any deviation is a contract violation.
- Pipe characters in cell values MUST be escaped as `\|`.
- Empty cells MUST use the literal `-` rather than an empty cell, except where the schema explicitly allows a string.
- The file MUST be overwritten in full on every split-step run; never appended to.
- The pipeline orchestrator MUST treat absence of the file after a split-step invocation as a split-step failure.

## Parsing recipe (pipeline orchestrator)

The pipeline orchestrator reads the report via:

```bash
awk -F '|' '
  /^\| Phase \| Status \| Branch \| PR URL \| Reason \|/ {
    in_table = 1
    next
  }
  in_table && /^\| --- / { next }
  in_table && /^$/        { in_table = 0; next }
  in_table {
    phase  = trim($2)
    status = trim($3)
    branch = trim($4)
    url    = trim($5)
    reason = trim($6)
    # Emit per-phase outcome for orchestrator processing.
    print phase, status, branch, url, reason
  }
'
```

The exact awk script lives in the split step's command/agent files; this contract specifies the parsing semantics.

## Postconditions

After a successful split-step invocation:

- The file exists at `<FEATURE_DIR>/split-report.md`.
- The table contains exactly one row per phase enumerated by the run (or one row with `Phase` = `single`).
- The Status column carries one of the six allowed values per row.
- A concise human-readable summary of the same outcomes is mirrored to stdout.

After a failed split-step invocation (e.g., the agent crashed before writing the file):

- The file MAY be missing or stale from a prior run.
- The pipeline orchestrator MUST treat absence as a failure and surface that to the author.
