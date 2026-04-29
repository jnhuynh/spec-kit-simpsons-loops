# Data Model: Multi-Phase Deploy Support

This feature introduces no new database tables, no new persistent state stores, and no new in-memory data structures. It introduces **nine named entities** that live entirely in Markdown files and Git refs (matching the "Key Entities" list in spec.md). They are documented here so the implementation can refer to a single canonical definition.

## Entities

### Deploy Phase

A named step in a phased rollout, declared in `plan.md` under a `## Deploy Phases` section.

| Attribute | Type | Description |
|---|---|---|
| `phase_number` | Integer (1..N) | Position in the deploy sequence; phases are totally ordered and contiguous |
| `goal` | String (free text) | Single-paragraph statement of the phase's intent |
| `post_deploy_state` | String (free text) | Description of the production state after this phase merges and deploys |

**Validation rules**:

- Phase numbers MUST start at 1 and be contiguous (no gaps). A gap is detected by the migration-safety check pack as **S2** (non-contiguous phases) and emitted as `high` severity.
- A `## Deploy Phases` section MUST contain at least one phase entry. A section with zero phases is malformed.
- Each phase entry MUST contain both a goal and a post-deploy-state description. Missing fields are caught by the plan agent at generation time and flagged by Marge during review.

**Storage**: `plan.md` `## Deploy Phases` section. Each phase entry MUST use the canonical machine-parseable format pinned by FR-001: a third-level heading `### Phase K: <title>` followed by two labelled fields `**Goal**: <goal text>` and `**Post-deploy production state**: <post-deploy text>`. The split step parses this format to extract goal and post-deploy text verbatim into the FR-016 PR body sections; the plan template (`.specify/templates/plan-template.md` after T006) MUST render every phase entry in this format.

**Canonical example** (normative — every multi-phase plan MUST use this format):

```markdown
## Deploy Phases

### Phase 1: Add new column (additive, backward-compatible)

**Goal**: Schema in place; old code continues to work unchanged.

**Post-deploy production state**: `users.new_pii` exists, nullable, all rows NULL.

### Phase 2: Dual-write + backfill

**Goal**: New writes populate both columns. Historical rows backfilled.

**Post-deploy production state**: `users.new_pii` populated for all rows; reads still use old column.
```

The split step extracts each phase's goal text by locating the line `**Goal**: <text>` inside the corresponding `### Phase K:` block and copying `<text>` verbatim. The post-deploy text is extracted analogously from `**Post-deploy production state**: <text>`. Field values that span multiple paragraphs continue until the next labelled field, the next `### Phase K:` heading, or the end of the `## Deploy Phases` section.

---

### Phase Tag

A marker `[phase-N]` attached to a task in `tasks.md` indicating which deploy phase the task belongs to.

| Attribute | Type | Description |
|---|---|---|
| `phase_number` | Integer (1..N) | References a phase declared in the plan's "Deploy Phases" section |

**Validation rules**:

- A phase tag MUST reference a phase number declared in the plan's "Deploy Phases" section. An orphan tag (e.g., `[phase-5]` when only phases 1..4 are declared) is detected by the migration-safety check pack as **S1** (orphan phase tag) and emitted as `high` severity.
- Phase tags appear inline in tasks.md task bullets, e.g., `- [ ] T001 [phase-1] Add migration in db/migrations/...`.
- For single-phase features (no `## Deploy Phases` section), tasks MUST NOT carry phase tags (FR-022 backward compatibility).

**Storage**: `tasks.md` task bullets, in the inline form `[phase-N]`.

---

### Phase Trailer

A Git trailer of the form `Phase: N` attached to a commit message indicating which deploy phase the commit belongs to.

| Attribute | Type | Description |
|---|---|---|
| `phase_number` | Integer (1..N) | The phase the commit belongs to |

**Validation rules**:

- The trailer is set by the implementation agent (Ralph) based on the task's phase tag (FR-006).
- Commits without a `Phase:` trailer default to phase 1 for grouping purposes (FR-014). The split step does not look at neighboring commits — defaulting is deterministic per-commit.
- A malformed `Phase:` trailer (non-integer or empty value) is detected by the migration-safety check pack as **S3** and emitted as `high` severity with Phase column `-` (global gate).
- A `Phase:` trailer present on a commit when the plan has no `## Deploy Phases` section is detected as **S4** (phase-trailer-without-deploy-phases) and emitted as `high` severity with Phase column `-` (global gate).

**Storage**: Git commit messages, parsed via `git log origin/main..HEAD --format='%H %(trailers:key=Phase,valueonly)'`.

**Example commit message**:

```
feat(users): [NNNN] add new_pii column to users table

T001 — schema migration adding nullable column.

Phase: 1
```

---

### Migration-Safety Check Pack

A Marge check pack file (`migrations.md`) that the review agent loads to evaluate per-phase migration safety.

| Attribute | Type | Description |
|---|---|---|
| `path` | String | `.specify/marge/checks/migrations.md` |
| `check_ids` | List of strings | M1-M8 (production-breaking patterns) plus S1-S4 (structural-consistency patterns) |
| `severity_for_cataloged` | Enum | `high` for every M*/S* entry per the FR-010 severity contract |

**Validation rules**:

- Loaded automatically by Marge's existing check-pack discovery loop when the file is present (FR-009, FR-023).
- Every FR-010-cataloged pattern MUST emit at `high` severity (per the severity-uniformity clarification).
- May emit `medium`, `low`, or `informational` findings for advisory observations outside the catalog.

**Storage**: `.specify/marge/checks/migrations.md`. Seeded into downstream consumer projects idempotently by `setup.sh` (FR-024).

---

### Phase Branch

A stacked Git branch produced by the split step, named `NNNN-<type>-<slug>-phaseK`.

| Attribute | Type | Description |
|---|---|---|
| `name` | String | `NNNN-<type>-<slug>-phaseK` where `NNNN-<type>-<slug>` is the feature branch name and `K` is the phase number |
| `base_branch` | String | `origin/main` for K=1; `NNNN-<type>-<slug>-phase(K-1)` for K>1 |
| `commits` | List of Git SHAs | The commits cherry-picked from the feature branch for this phase, in deploy order |

**Validation rules**:

- Created or updated by the split step via `git reset --hard <base>` then `git cherry-pick <phase-commits>`, then `git push --force-with-lease`.
- Phase branches are pipeline-managed artifacts: humans MUST NOT commit directly to them.
- Existing phase branches are identified by the deterministic naming convention; a remote branch matching `NNNN-<type>-<slug>-phaseK` is treated as an existing phase branch to update.
- A phase branch whose pull request is already merged into `origin/main` is treated as immutable; the split step skips rebuilding it and emits a `skipped-merged` row in the split report (FR-017).

**Storage**: Git remote refs (`refs/heads/NNNN-<type>-<slug>-phaseK` on the GitHub remote).

---

### Phase Pull Request

A pull request produced by the split step for each phase branch, forming a stack with the correct base-branch chain.

| Attribute | Type | Description |
|---|---|---|
| `branch` | String | The phase branch name (`NNNN-<type>-<slug>-phaseK`) |
| `base` | String | `main` for K=1; `NNNN-<type>-<slug>-phase(K-1)` for K>1 |
| `title` | String | `[Phase K/N] <feature-branch-name>` for multi-phase; `<feature-branch-name>` for single-phase (FR-016) |
| `body` | String | Generated GFM document per the FR-016 template (see Design Decisions D-008 in plan.md) |

**Validation rules**:

- Title and body are pipeline-managed: the split step recomputes them on every run and overwrites via `gh pr edit --title --body` when they differ from `gh pr view --json title,body`.
- Human edits to title or body WILL be overwritten on the next split-step run; reviewers MUST use PR review comments rather than editing the description.
- For single-phase features, exactly one pull request is opened against `main` (FR-019), matching today's behavior.

**Storage**: GitHub repository (managed via `gh pr create` and `gh pr edit`).

---

### Per-Phase Finding

A review finding tagged with the phase number that introduced the issue. Used by the split step to gate which pull requests it is willing to open (FR-011, FR-018).

| Attribute | Type | Description |
|---|---|---|
| `id` | String | Stable per-finding identifier the review step assigns (matches the `ID` column of the Review Report row) |
| `severity` | Enum | `high`, `medium`, `low`, `informational`; only `high` gates the split step |
| `phase` | Integer or `-` | Integer phase number for findings attributable to a single phase (multi-phase); literal `-` for single-phase features OR for structural inconsistencies the migration-safety check pack cannot attribute (S3, S4) |
| `status` | Enum | `open`, `resolved`; the split step treats anything other than `resolved` as gating |
| `check_pack` | String | Source check pack filename (informational; not used for gating) |
| `summary` | String | Single-sentence description |

**Validation rules**:

- A Per-Phase Finding is **not** a standalone artifact; it is a row of the Review Report (see below). This entry exists in the data model because spec.md lists it under "Key Entities" so the implementation can reason about gating semantics by name; the canonical schema and storage are the Review Report's table rows.
- For multi-phase features, the Phase column carries the integer phase number for findings attributable to a single phase, or `-` for structural inconsistencies. For single-phase features, every finding's Phase column is `-` per FR-012a.
- The split step's gating contract (FR-018) operates on Per-Phase Findings via the Review Report parser; it does not introduce any other access path.

**Storage**: As a row of `<FEATURE_DIR>/review-report.md` (see Review Report below). No separate file or in-memory representation.

---

### Review Report

A persisted artifact at `<FEATURE_DIR>/review-report.md` produced by the review step (Marge) on every run.

| Attribute | Type | Description |
|---|---|---|
| `path` | String | `<FEATURE_DIR>/review-report.md` |
| `findings` | List of finding rows | One row per finding, with the columns specified by FR-012a |

**Schema** (machine-readable surface):

A single GitHub Flavored Markdown table with the **exact** column headers in this order:

```markdown
| ID | Severity | Phase | Status | Check Pack | Summary |
```

Per-row column rules:

| Column | Type | Allowed values |
|---|---|---|
| `ID` | String | Stable per-finding identifier the review step assigns and reuses across runs against the same branch state |
| `Severity` | Enum | `high`, `medium`, `low`, `informational` |
| `Phase` | Integer or `-` | Integer phase number for multi-phase findings attributable to a single phase; literal `-` for single-phase features OR for structural inconsistencies that cannot be attributed (S3 malformed trailer, S4 phase-trailer-without-deploy-phases) |
| `Status` | Enum | `open`, `resolved` |
| `Check Pack` | String | Source check pack filename (informational; not used for gating) |
| `Summary` | String | Single-sentence human-readable description; pipe characters escaped as `\|` |

**Validation rules**:

- The file is overwritten on every Marge run.
- Consumers MUST locate the table by its exact header row and parse rows until the next blank line or end of file.
- The split step treats any finding whose Status is anything other than `resolved` as gating per FR-018.
- Pipe characters in cell values MUST be escaped as `\|` so `awk -F '|'` parses cleanly.

**Storage**: `<FEATURE_DIR>/review-report.md`.

---

### Split Report

A persisted artifact at `<FEATURE_DIR>/split-report.md` produced by the split step on every run.

| Attribute | Type | Description |
|---|---|---|
| `path` | String | `<FEATURE_DIR>/split-report.md` |
| `phases` | List of phase rows | One row per phase enumerated by the run, with the columns specified by FR-019a |

**Schema** (machine-readable surface):

A single GitHub Flavored Markdown table with the **exact** column headers in this order:

```markdown
| Phase | Status | Branch | PR URL | Reason |
```

Per-row column rules:

| Column | Type | Allowed values |
|---|---|---|
| `Phase` | Integer or `single` | Integer phase number for multi-phase; literal `single` for single-phase features |
| `Status` | Enum | `created`, `updated`, `unchanged`, `skipped-merged`, `gated`, `failed` |
| `Branch` | String or `-` | Phase branch name (`NNNN-<type>-<slug>-phaseK` multi-phase, feature branch name single-phase); literal `-` only when the run failed before resolving the branch name |
| `PR URL` | String or `-` | Pull-request URL when one exists; literal `-` when omitted (gated/failed entries with no PR; unchanged entries when URL was not re-fetched) |
| `Reason` | String or `-` | Single-sentence explanation. Required (non-`-`) for `skipped-merged`, `gated`, `failed`. Optional for `created`, `updated`, `unchanged` |

**Validation rules**:

- The file is overwritten on every split-step run.
- Consumers MUST locate the table by its exact header row and parse rows until the next blank line or end of file.
- Pipe characters in cell values MUST be escaped as `\|`.
- The pipeline orchestrator MUST treat absence of `<FEATURE_DIR>/split-report.md` after a split-step invocation as a split-step failure.

**Storage**: `<FEATURE_DIR>/split-report.md`.

## Status state machines

### Review-finding status (Status column of review-report.md)

```
[new finding]
     |
     v
   open  ─────(subsequent review pass confirms issue is gone)─────▶  resolved
     │                                                                 │
     │ (issue still present in subsequent run)                         │ (terminal in this run)
     ▼                                                                 │
   open  (row persists with same ID; gating continues)                 │
                                                                       ▼
                                                                  [no further transitions in this run]
```

- New findings emit as `open`.
- A finding transitions to `resolved` only when a subsequent Marge run, against the same branch state, confirms the underlying issue is gone.
- The split step's gating rule (FR-018) treats anything other than `resolved` as gating.

### Split-step phase status (Status column of split-report.md)

A phase transitions to exactly one terminal status per run:

| Status | When |
|---|---|
| `created` | The phase branch did not exist on the remote; this run created the branch and opened a new pull request |
| `updated` | The phase branch existed on the remote; this run rebuilt it (force-pushed via `--force-with-lease`) and/or rewrote PR title/body |
| `unchanged` | The phase branch's commit SHAs already matched the recomputed phase branch SHAs AND the existing PR title and body already matched the recomputed values; no force-push and no `gh pr edit` were required |
| `skipped-merged` | The phase branch's pull request was already merged into `origin/main`; the split step skipped rebuild to protect shipped history (FR-017) |
| `gated` | The phase has an unresolved high-severity finding in `review-report.md`; the split step refused to open or update the pull request (FR-018). For multi-phase, a Phase-`-` finding gates every phase in the run |
| `failed` | The split step failed fast on this phase per FR-017's fail-fast rule (e.g., `gh pr create` returned an error, cherry-pick conflict, fetch failure) |

The status set is closed; every phase row carries exactly one of these values per run.

## Cross-entity relationships

```
plan.md
  └─ ## Deploy Phases ──── (presence) ─────▶ multi-phase mode
                            (absence) ─────▶ single-phase mode (today's behavior)
                            │
                            └─ defines ──▶ Deploy Phase entries (1..N)

tasks.md
  └─ tasks ──── tagged with ──▶ Phase Tag ──── references ──▶ Deploy Phase
       (multi-phase only; FR-004)

git commits on feature branch
  └─ each commit ──── may carry ──▶ Phase Trailer ──── references ──▶ Deploy Phase
       (multi-phase only; FR-006)

.specify/marge/checks/migrations.md ──── loaded by ──▶ Marge ──── emits ──▶ Review Report rows
                                                           (FR-009, FR-011, FR-012a)

Review Report ──── read by ──▶ split step ──── gates ──▶ Phase Pull Request creation/update
                                                  (FR-018)

split step ──── reads ──▶ Phase Trailer (via git log) ──── groups commits into ──▶ Phase Branch
       │                                                          (FR-013, FR-015)
       │
       └──── writes ──▶ Split Report (FR-019a)
```

## Backward compatibility

For single-phase features (no `## Deploy Phases` section in `plan.md`):

- **Phase Tag**: not present in tasks.md.
- **Phase Trailer**: not present on commits (FR-007).
- **Phase Branch**: not created; only the feature branch exists.
- **Phase Pull Request**: exactly one is opened against `main`, matching today's behavior (FR-019).
- **Review Report**: still produced (FR-012a applies uniformly), but the Phase column carries `-` for every row.
- **Split Report**: contains exactly one row with `Phase` = `single`.

Every existing single-phase feature in `specs/` continues to work unchanged after this feature ships (FR-022).
