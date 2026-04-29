# Plan Generation Agent - Spec Kit Integration

Generate a technical implementation plan from the spec. This is a **single-shot** agent — run once and exit.

## Feature Directory

The feature directory is provided via the `-p` prompt when this agent is invoked. Extract the path from the prompt (e.g., "Feature directory: specs/a1b2-feat-foo").

## Instructions

Run `/speckit.plan` to generate the implementation plan. This will read the spec and produce a `plan.md` in the feature directory.

## Multi-Phase Detection (FR-001, FR-002, FR-003)

After `/speckit.plan` produces `plan.md`, evaluate the spec against the multi-phase heuristics below. If **any** heuristic fires, augment the generated `plan.md` with a `## Deploy Phases` section in the canonical machine-parseable format pinned by FR-001 (see "Canonical format" below). If **none** fire, leave `plan.md` untouched — absence of the section is the sole signal for single-phase mode per FR-002.

### Heuristics

A feature requires multi-phase rollout when **any** of the following conditions hold:

1. **Schema migration combined with reads/writes on the same data** — the spec describes a database schema change (column add/drop/rename, table split/merge, type change, index add/drop on a hot table) AND code that reads or writes the affected data. A single phase cannot land both safely because the running service must keep working while the schema migrates.
2. **Breaking API change** — the spec changes the shape, contract, or semantics of an API endpoint or RPC method that has live callers. A single phase cannot land both the new contract and migrate every caller atomically.
3. **Multi-service rollout coordination** — the spec spans two or more services that must roll out in a specific order to avoid a window where the system is incoherent (e.g., a producer must add a new field before a consumer can read it).

If none of these heuristics fire, the feature is single-phase. Default to single-phase whenever the heuristics are ambiguous; the cost of an unnecessary phase split is high (extra PRs, extra reviewer effort) while the cost of catching a missed multi-phase boundary later is low (the author can re-run the plan agent).

### Canonical format (FR-001)

Every multi-phase `plan.md` MUST render the `## Deploy Phases` section in the canonical format below. The split step parses this format directly — no alternative rendering is accepted.

```markdown
## Deploy Phases

### Phase 1: <short title>

**Goal**: <single-paragraph statement of the phase's intent>

**Post-deploy production state**: <single-paragraph description of the production state after this phase merges and deploys>

### Phase 2: <short title>

**Goal**: <single-paragraph statement of the phase's intent>

**Post-deploy production state**: <single-paragraph description of the production state after this phase merges and deploys>
```

Rules:

- The section heading MUST be exactly `## Deploy Phases` (level 2, no trailing punctuation).
- Each phase entry MUST start with a level-3 heading of the form `### Phase K: <title>` where `K` is the integer phase number.
- Phase numbers MUST start at 1 and be totally ordered and contiguous (no gaps).
- Each phase entry MUST contain both labelled fields `**Goal**: <text>` and `**Post-deploy production state**: <text>` on their own lines (or starting on their own lines).
- Field values are copied verbatim into the corresponding pull-request body sections by the split step (FR-016); write them as deployable, reviewer-facing prose rather than internal notes.
- Single-phase features MUST NOT emit a `## Deploy Phases` section. Absence is the signal per FR-002.

### Worked example (column rename — four-phase expand-contract)

```markdown
## Deploy Phases

### Phase 1: Add new column (additive, backward-compatible)

**Goal**: Schema in place; old code continues to work unchanged.

**Post-deploy production state**: `users.email` exists, nullable, all rows NULL. `users.email_address` remains the source of truth for reads and writes.

### Phase 2: Dual-write + backfill

**Goal**: New writes populate both columns. Historical rows backfilled in a non-blocking job.

**Post-deploy production state**: `users.email` populated for all rows; reads still use `users.email_address`.

### Phase 3: Switch reads

**Goal**: Reader code switched to `users.email`. Both columns continue to be written.

**Post-deploy production state**: `users.email` is the read source of truth; `users.email_address` is still written but no longer read.

### Phase 4: Drop old column

**Goal**: Stop writing `users.email_address`; drop it.

**Post-deploy production state**: `users.email_address` is gone; `users.email` is the sole column.
```

Use this four-phase pattern as the default template for column-rename features. Adapt the count and titles for other migration shapes (e.g., a NOT NULL add typically needs three phases: add nullable, backfill, alter to NOT NULL).

## Commit and exit

After the plan is generated (and the `## Deploy Phases` section is appended when the heuristics fire), commit and push:

```bash
git add -A && type=$(git branch --show-current | cut -f 2 -d '-') && scope=$(git branch --show-current | cut -f 3- -d '-') && ticket=$(git branch --show-current | cut -f 1 -d '-') && git commit -m "$type($scope): [$ticket] generate implementation plan"
git push origin $(git branch --show-current)
```
