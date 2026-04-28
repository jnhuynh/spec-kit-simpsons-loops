# migrations

Migration-safety pack. Enforces the per-phase deployability contract for multi-phase features (`plan.md` contains a `## Deploy Phases` section). Loaded automatically by Marge's check-pack discovery loop when this file is present (FR-009, FR-023). Every cataloged pattern (M1-M8 production-breaking, S1-S4 structural-consistency) is emitted at `high` severity per the FR-010 severity-uniformity contract. The pack MAY emit `medium`, `low`, or `informational` findings for advisory observations outside the M*/S* catalog (e.g., stylistic guidance on migration scripts), but every cataloged entry MUST be `high`.

For single-phase features (no `## Deploy Phases` section in `plan.md`), the M1-M8 production-breaking patterns still apply to schema-touching diffs in the conventional way, but the per-phase gating semantics (FR-018) collapse to a single pull request. The S1-S4 structural-consistency patterns are no-ops for single-phase features except for **S4** (phase-trailer-without-deploy-phases), which catches the inconsistency between a single-phase plan and a feature branch carrying `Phase:` trailers.

---

## M1. NOT NULL column added without default

Rule: A schema change introducing a `NOT NULL` column without a default value breaks existing INSERTs from prior-phase code that does not yet write the new column. Either add the column nullable first (later phase tightens to `NOT NULL` after backfill) or supply a default the database can apply to existing rows and to inserts that omit the column.

**Severity:** HIGH.

Signal: a migration on added/modified lines contains an `ADD COLUMN` whose definition includes `NOT NULL` without a `DEFAULT` clause, AND the column does not also appear in a same-phase code change writing it from every existing INSERT path. Patterns to grep:

- `ADD COLUMN \w+ \w+ NOT NULL` without a following `DEFAULT`
- ORM equivalents: `add_column ..., null: false` without `default:`; `AddColumn(... nullable: false)` without a default; `t.string ..., null: false` without `default:`

Fix suggestion: split the change across phases — earlier phase adds the column nullable; the same or a later phase backfills existing rows; a later phase tightens to `NOT NULL` (and optionally drops the default). Cite the offending phase number in the Phase column.

---

## M2. Column dropped while prior-phase code still reads it

Rule: A `DROP COLUMN` (or equivalent) in phase K must not occur while phase K-1's running code still reads the column. The four-step expand-contract pattern requires that reads be switched off the column in an earlier phase before the column is dropped.

**Severity:** HIGH.

Signal: the diff for phase K removes a column AND prior-phase application code (the diff for phase K-1 or earlier, or unchanged code that already shipped) contains a read of that column. Patterns to grep:

- `ALTER TABLE \w+ DROP COLUMN` / `remove_column` / `DropColumn` on added/modified lines in phase K
- A prior-phase or unchanged source file containing `SELECT \w*\b<col>\b`, `\.<col>\b`, `<col>:` (ORM attribute access), or `<col>=` (read of the column attribute) — where `<col>` is the dropped column

Fix suggestion: move the column drop to a phase that runs after every read of the column has been switched to the replacement (or removed entirely). The minimum sequence for a rename is: add new column → dual-write + backfill → switch reads → drop old column.

---

## M3. Column renamed in a single phase

Rule: A column rename executed in a single phase (`ALTER TABLE ... RENAME COLUMN`) is unsafe for zero-downtime deploys: prior-phase code still references the old name. Renames must use the four-step expand-contract pattern: add new column → dual-write + backfill → switch reads → drop old column. Each step is its own phase.

**Severity:** HIGH.

Signal: a single phase's diff contains `ALTER TABLE \w+ RENAME COLUMN \w+ TO \w+` (or ORM equivalents `rename_column`, `RenameColumn`) AND no other phase contains a corresponding `ADD COLUMN <new>` or dual-write step. Patterns to grep:

- `RENAME COLUMN` on added/modified lines
- `rename_column` / `RenameColumn` ORM calls

Fix suggestion: replace the rename with the four-step expand-contract pattern. Cite the four phases in the fix suggestion: phase K adds the new column nullable; phase K+1 dual-writes both columns and backfills historical rows; phase K+2 switches reads to the new column; phase K+3 drops the old column.

---

## M4. Long-transaction backfill on a hot table

Rule: A backfill that updates every row of a high-write-volume table inside a single transaction holds row locks (or a table lock, depending on the database) for the duration of the transaction, blocking concurrent traffic. Backfills on hot tables must be batched and committed in chunks.

**Severity:** HIGH.

Signal: a backfill script or migration on added/modified lines performs `UPDATE <table> SET <col> = <expr>` or equivalent without a `WHERE` clause that bounds the row count, AND the table is plausibly hot (heuristic: the table appears in API request handlers, background workers, or high-traffic code paths in the same diff or in unchanged code). Patterns to grep:

- `UPDATE \w+ SET` without a chunked-iteration pattern (`LIMIT`, `BETWEEN`, `id < ... AND id >= ...`)
- ORM batch operations missing chunk size (`Model.update_all(...)` without `find_in_batches` / `each_slice`)

Fix suggestion: rewrite the backfill to iterate in chunks (e.g., `WHERE id BETWEEN ? AND ?` with batch size 1000-10000) and commit each chunk separately. Mention the table's traffic profile so the reviewer can confirm the heuristic.

Tag `NEEDS_HUMAN` when the table's traffic profile is not visible from the diff.

---

## M5. Missing index for a new read path

Rule: A schema change that introduces a new query path (a new `WHERE` predicate, `JOIN`, `ORDER BY`, or foreign-key lookup) must include a covering index. Adding a new read path without an index causes table scans under production load.

**Severity:** HIGH.

Signal: the diff adds a new query (in application code or in a migration's `CREATE VIEW` / `CREATE FUNCTION`) that filters or joins on a column, AND no `CREATE INDEX` on that column appears in the same phase or an earlier phase's migration. Patterns to grep:

- New `WHERE \w+ =` / `WHERE \w+ IN` / `JOIN ... ON` / `ORDER BY \w+` clauses on added lines
- ORM scope/filter additions: `where(<col>: ...)`, `.filter(<col>=...)`, `.find_by(<col>: ...)`
- Migration `CREATE INDEX` lookups against the migration history

Fix suggestion: add a `CREATE INDEX` (or `add_index` / equivalent) on the queried column in the same phase that introduces the read path, or in an earlier phase. Cite the column and table.

---

## M6. Schema change and dependent code in the same phase

Rule: A phase that contains both a schema change AND application code that depends on the new schema cannot be deployed safely. The schema and the dependent code must ship in separate phases: schema first (phase K), code switch later (phase K+1 or beyond), so prior-phase running code keeps working during the deploy window of phase K.

**Severity:** HIGH.

Signal: phase K's diff contains both a migration (`db/migrate/`, `migrations/`, `prisma/migrations/`, `schema.rb`, etc.) AND application code that reads or writes the migrated column / table on the new contract. Patterns to grep:

- A migration file added in phase K's commits
- An application source file in phase K's commits referencing the new column/table on the new contract (e.g., reading `users.email` after phase K renamed `email_address` to `email`)

Fix suggestion: split the phase. The schema change moves to phase K; the code switch moves to phase K+1. If the code is a dual-write (writing both old and new columns), it MAY share phase K with the schema add — but the read switch and the drop MUST be later phases.

---

## M7. Removed function/endpoint with prior-phase callers

Rule: A removed function or HTTP endpoint must not have callers in prior-phase code that is still running. Removing a public surface (function, endpoint, RPC method) in phase K while phase K-1 deployed code still calls it produces 5xx responses or deserialization failures during the phase K deploy window.

**Severity:** HIGH.

Signal: phase K's diff removes a function definition / endpoint route / RPC handler, AND a prior-phase or unchanged source file contains a call site for that symbol. Patterns to grep:

- A line removed in phase K matching `^(export\s+)?(async\s+)?function \w+`, `^def \w+`, `@(app|router)\.(get|post|put|delete|patch)\("[^"]+"`, `rpc \w+`
- Call sites in unchanged or prior-phase code: bare-name function calls, route URLs, RPC method names

Fix suggestion: deprecate the function/endpoint in an earlier phase (mark it as `@deprecated` and route callers to the replacement); only remove it in a later phase after every prior-phase deploy has been retired. Cite the call site path.

---

## M8. Per-phase deployability

Rule: For each phase K in 1..N, the state `main + phases 1..K` must be a valid production state in which phase K-1's running code keeps working. Phase K cannot ship a change that breaks phase K-1's deployed code, even transiently.

**Severity:** HIGH.

Signal: a holistic check that combines M1-M7 outputs and adds a deploy-order simulation. Traverse phases in deploy order, simulating the running code at each phase boundary — for phase K, the running code is the union of unchanged code + all phase 1..K-1 changes, and the new code being deployed is phase K. If any of M1, M2, M6, M7 fires for phase K, M8 also fires for phase K (the per-phase deployability invariant is violated). M8 also catches patterns the other rules miss: a phase that simultaneously requires the old contract (in unchanged code) and the new contract (in same-phase code) without a dual-write/dual-read shim, or any other change that breaks a behavior the running code depends on at the phase K boundary.

Fix suggestion: split phase K into two or more phases such that each phase boundary preserves the running code's contract. Cite the specific behavior that breaks at the phase K boundary.

Tag `NEEDS_HUMAN` when the deployability check requires non-trivial reasoning about request flow or data invariants.

---

## S1. Orphan phase tag

Rule: A `[phase-N]` tag in `tasks.md` or a `Phase: N` git trailer that references a phase number not declared in the plan's `## Deploy Phases` section. The phase number is "orphan" because no Deploy Phase entry exists for it.

**Severity:** HIGH.

Signal: parse the integer phase numbers declared in `plan.md`'s `## Deploy Phases` section (the set of `### Phase K:` headings). For each `[phase-N]` tag in `tasks.md` and each `Phase: N` trailer in `git log origin/main..HEAD`, confirm `N` is in the declared set. Patterns to grep:

- `tasks.md`: `\[phase-(\d+)\]` — collect every integer
- `git log origin/main..HEAD --format='%(trailers:key=Phase,valueonly)'` — collect every integer

Fix suggestion: either declare the missing phase in `plan.md`'s `## Deploy Phases` section, or correct the offending tag/trailer to reference an existing phase. Cite the offending tag's task ID or the offending commit's SHA. Set the Phase column to the integer of the orphan tag.

---

## S2. Non-contiguous phases

Rule: The set of phase numbers observed across `tasks.md` tags and commit trailers must be contiguous starting at 1 (no gaps). For example, observing `Phase: 1` and `Phase: 3` with no `Phase: 2` is a gap.

**Severity:** HIGH.

Signal: collect the integer phase numbers from `[phase-N]` tags in `tasks.md` and `Phase: N` trailers from `git log origin/main..HEAD`. Compute the set of integers, find the maximum N, and flag if any integer in `1..N` is missing from the set. Patterns to grep are the same as S1.

Fix suggestion: either add the missing-phase work (commits and tasks) to the feature, or renumber the phases to be contiguous starting at 1. Set the Phase column to the integer of the missing phase (e.g., `2` for the example above).

---

## S3. Malformed `Phase:` trailer

Rule: A commit body contains a `Phase:` trailer whose value cannot be parsed as a positive integer (1-or-more). Empty values, non-numeric values (`Phase: one`), zero (`Phase: 0`), and negative values (`Phase: -1`) are malformed.

**Severity:** HIGH.

Signal: parse `git log origin/main..HEAD --format='%H %(trailers:key=Phase,valueonly)'` and flag any non-empty trailer value that does not match `^[1-9][0-9]*$`. Empty trailers (no `Phase:` line at all) are NOT malformed — they are simply untrailerd commits and default to phase 1 per FR-014.

Fix suggestion: rewrite the offending commit message to set `Phase: <positive-integer>` matching the intended phase. Cite the commit SHA. Set the Phase column to the literal `-` because the malformed trailer cannot be attributed to a specific phase; this triggers the global-gate semantics of FR-018.

---

## S4. Phase-trailer-without-deploy-phases

Rule: The plan artifact has no `## Deploy Phases` section (single-phase per FR-002) but the feature branch contains one or more commits carrying a `Phase:` trailer. This is a structural inconsistency: the plan signals single-phase mode but the implementation history disagrees.

**Severity:** HIGH.

Signal: confirm `plan.md` does NOT contain the line `## Deploy Phases` (case-sensitive, exact heading). Then parse `git log origin/main..HEAD --format='%(trailers:key=Phase,valueonly)'` and flag if any commit carries a non-empty `Phase:` trailer.

Fix suggestion: either add a `## Deploy Phases` section to `plan.md` (if the feature is genuinely multi-phase), or rewrite the offending commits to drop the `Phase:` trailer (if the feature is genuinely single-phase). Cite the offending commit SHAs. Set the Phase column to the literal `-` because the inconsistency cannot be attributed to a specific phase; this triggers the global-gate semantics of FR-018.

---

## Confidence guidance

- 95-100: M1 `ADD COLUMN ... NOT NULL` regex match without `DEFAULT`; M3 `RENAME COLUMN` regex match in a single phase; S1 / S2 deterministic set-comparison results; S3 trailer fails the `^[1-9][0-9]*$` regex; S4 confirmed plan-vs-trailer mismatch.
- 85-95: M2 column-drop with a documented prior-phase reader; M6 schema + dependent code in the same phase commits; M7 removed symbol with a documented call site.
- 70-85: M4 long-transaction backfill (table-traffic heuristic); M5 missing index (read-path inference); M8 per-phase deployability (compositional reasoning).
- <70: drop unless `--strict`.

## NEEDS_HUMAN tagging

Tag `NEEDS_HUMAN` for findings that require domain knowledge or non-trivial reasoning the static analysis cannot reliably make:

- M4 when the table's traffic profile is not visible from the diff.
- M8 when the deployability check requires reasoning about request flow or data invariants beyond pattern matching.
- Any advisory finding outside the M1-M8 / S1-S4 catalog (these are emitted as `medium` / `low` / `informational` rather than `high` and may be tagged `NEEDS_HUMAN` per the reviewer's discretion).

The M1-M3, M5-M7, and S1-S4 patterns are mechanical enough to NOT tag `NEEDS_HUMAN` — Marge's loop should remediate them or surface them to gate the split step.
