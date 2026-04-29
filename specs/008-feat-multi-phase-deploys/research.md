# Research: Multi-Phase Deploy Support

**Branch**: `008-feat-multi-phase-deploys` | **Date**: 2026-04-27

## R-001: Multi-phase detection signal

**Decision**: The presence of a `## Deploy Phases` section in `plan.md` is the sole signal that marks a feature as multi-phase. The pipeline orchestrator and the split step both run `grep -q '^## Deploy Phases$' <FEATURE_DIR>/plan.md` to decide which mode to use. No flag, environment variable, command-line switch, or config file is introduced.

**Rationale**: FR-002 and FR-020 mandate structural detection. Backward compatibility is non-negotiable per FR-022 — every existing single-phase plan in `specs/` lacks the section, so the multi-phase code paths are dead for those features. The structural signal also makes the spec, plan, and tasks artifacts the single source of truth for whether a feature is multi-phase, with no out-of-band state to drift.

**Alternatives considered**:

- **A flag in pipeline command (`--multi-phase`)** — rejected. It introduces an out-of-band state that can disagree with the artifact contents, violates FR-020 ("MUST NOT introduce a separate flag"), and forces every existing pipeline invocation to relearn its argument shape.
- **An environment variable (`SPECKIT_MULTI_PHASE=1`)** — rejected for the same reasons, plus environment variables are invisible at code-review time.
- **A field in `spec.md` front-matter** — rejected. The plan agent decides whether multi-phase is required (FR-003), so the signal belongs in `plan.md`. Splitting it across spec and plan invites drift.

## R-002: Phase trailer commit format

**Decision**: Implementation commits for tasks tagged `[phase-N]` carry a `Phase: N` git trailer per RFC 5322. Ralph appends the trailer when composing the commit message. The split step reads trailers via `git log origin/main..HEAD --format='%H %(trailers:key=Phase,valueonly)'`. Untrailerd commits group into phase 1 deterministically per FR-014 — the split step does not look at neighboring commits.

**Rationale**: Git trailers are the standard mechanism for structured commit metadata (used by `Signed-off-by`, `Co-Authored-By`, and many others). `git interpret-trailers` parses them deterministically, and the `--format='%(trailers:key=Phase,valueonly)'` placeholder is a documented Git feature available since Git 2.32. This avoids inventing an ad-hoc commit-message convention that future tools would need to learn. Defaulting untrailerd commits to phase 1 (rather than inheriting the prior phase) is per the FR-014 clarification recorded in spec.md — it removes a non-deterministic "depends on neighbors" rule.

**Alternatives considered**:

- **Encode phase in the commit subject (e.g., `[phase-1] feat(...): ...`)** — rejected. Conflicts with the existing commit-message convention `type(scope): [ticket] description`, and the subject is not a structured field.
- **Inherit phase from the prior phase-tagged commit** — rejected per FR-014's clarification. Inheritance is non-deterministic across rebases; depending on neighbor commits is a hidden coupling. The clarification explicitly removes this behavior.
- **Encode phase in a separate `.phase` file per commit** — rejected. Out-of-band metadata, painful to grep, no Git tooling support.

## R-003: Stacked branch naming and base-branch chain

**Decision**: For multi-phase features, the split step creates branches named `NNNN-<type>-<slug>-phaseK` where `NNNN-<type>-<slug>` is the feature branch name and `K` is the phase number (FR-015). Phase 1 is based on `origin/main`; phase K>1 is based on phase K-1's branch. Pull requests are opened with `gh pr create --base <base-branch>` to chain the stack: `main <- phase1 <- phase2 <- ... <- phaseN` (FR-016).

**Rationale**: GitHub's `gh pr create --base` is the documented mechanism for stacked PRs. The naming convention extends the existing `NNNN-<type>-<slug>` constitution rule with a `-phaseK` suffix, which fits within GitHub's 244-byte branch-name limit for all realistic phase counts (phase counts of 2-6 are typical; even phase 99 fits trivially). Using the suffix preserves the constitution's branch-naming convention as a strict prefix, so existing tooling that parses branch names (e.g., the commit-message helper `cut -f 2 -d '-'`) keeps working.

**Alternatives considered**:

- **Separate top-level branches per phase (no stack)** — rejected. Loses base-branch chaining; reviewers cannot read phases in deploy order.
- **Sub-branches under a feature branch (`008-feat-foo/phase1`)** — rejected. Slashes in branch names complicate `gh` URLs and break the existing `cut -f` parsing in commit helpers.
- **Numeric suffix only (`-1`, `-2`)** — rejected. Less readable; collides with the existing `NNNN` numeric prefix convention in some grep patterns.

## R-004: Idempotent rebuild via reset + cherry-pick + force-with-lease

**Decision**: When the split step re-runs and a phase's commit set changes (commits added, removed, or amended), the step deterministically rebuilds the phase branch by:

1. `git checkout -B <phase-branch>` (create or reset)
2. `git reset --hard <base>` where base is `origin/main` for phase 1 or the previous phase branch for phase K>1
3. `git cherry-pick <phase-commits>` in deploy order
4. `git push --force-with-lease origin <phase-branch>` (skipped if no SHA change vs. the existing remote ref)

The pull request's title and body are recomputed and overwritten via `gh pr edit --title --body` when they differ from `gh pr view --json title,body` (FR-016, FR-019a).

**Rationale**: FR-017 mandates idempotence. Reset + cherry-pick produces a deterministic branch state from `(base, phase-commits)`, so two runs against the same inputs produce the same SHAs (modulo committer timestamps; see R-008). `--force-with-lease` is the community-standard safe force-push primitive — it refuses to overwrite remote changes the local copy hasn't seen. Phase branches are pipeline-managed artifacts; humans must not commit to them. The only safeguard against rewriting shipped history is FR-017's `skipped-merged` rule.

**Alternatives considered**:

- **Rebase the existing phase branch onto the new base** — rejected. Conflicts with idempotence: rebasing produces commits that depend on the existing phase-branch SHAs, so re-running after the feature branch changes can produce different outputs across runs. Reset + cherry-pick is functional (deterministic from `(base, phase-commits)`) where rebase is stateful.
- **Plain `--force` push** — rejected. Overwrites concurrent remote changes silently. `--force-with-lease` is the safe variant.
- **Merge commits between phases** — rejected. Merge commits make the per-phase diff harder to read in `gh pr view` and break the "each phase is a deployable slice on top of the previous one" mental model.

## R-005: `origin/main` as canonical base

**Decision**: Every reference to "main" in the split step's logic means `origin/main` after `git fetch origin main`. This applies to commit enumeration, phase-1 cherry-pick base, phase-1 reset target during idempotent rebuild, and `skipped-merged` detection (FR-013). The split step never consults the local `main` branch. If `git fetch origin main` itself fails, the split step fails fast with a `failed` row in the split report, before any branch is rebuilt.

**Rationale**: Per the FR-013 clarification recorded in spec.md, using local `main` introduces non-determinism across working copies that have not pulled recently. `origin/main` is the canonical reference reviewers see and `gh pr create` uses for PR base resolution. Fetching at the start of every run keeps the working copy's `origin/main` ref aligned with the remote tip, so two independent working copies running the split step against the same feature branch and remote state produce identical stacks. Failing fast on a fetch error prevents partial rebuilds against a stale base.

**Alternatives considered**:

- **Local `main`** — rejected per FR-013. Non-deterministic when local lags behind remote.
- **A user-supplied `--base` argument** — rejected. Adds optional state, violates the structural-detection model (R-001), and most authors would always pass `main` anyway.
- **Skip the fetch and trust the existing ref** — rejected. Stale `origin/main` produces a stack that disagrees with what reviewers see at PR-open time.

## R-006: Persisted review report as single source of truth for gating

**Decision**: The review step (Marge) writes findings to `<FEATURE_DIR>/review-report.md` on every run, overwriting any prior copy (FR-012a). The machine-readable surface is a single GitHub Flavored Markdown table with columns `| ID | Severity | Phase | Status | Check Pack | Summary |` in that order, one row per finding, with pipe characters in cell values escaped as `\|`. The split step reads the file via `awk -F '|'` to identify unresolved high-severity findings. The split step does NOT independently re-verify any structural invariant from FR-010; the review report is the single source of truth for gating decisions per FR-018.

**Rationale**: Per the clarification on review-report format recorded in spec.md, GFM tables are parseable with `awk -F '|'` (no new dependency) and human-readable in the same surface. Fixing the column order and headers by spec lets the split step's parser be a small awk script. Treating the review report as the single source of truth for gating avoids the pitfall of two parsers disagreeing — only Marge knows how to detect FR-010 violations, and the split step trusts what Marge wrote.

**Alternatives considered**:

- **JSON or YAML format** — rejected. Adds a parsing dependency (`jq` is optional in the existing setup script; `yq` is not present). GFM table is parseable with stock `awk`.
- **Inline gating in the split step (split independently re-runs FR-010 checks)** — rejected. Duplicates Marge's logic, invites the two parsers to disagree, and forces every pipeline run to do the structural checks twice.
- **A separate findings.json artifact alongside review-report.md** — rejected. Two artifacts to keep in sync. The single GFM table satisfies both human and machine readers.

## R-007: Migration-safety check pack severity contract

**Decision**: Every pattern enumerated in FR-010 is emitted at `high` severity (per the clarification on severity assignment recorded in spec.md). The pack covers eight production-breaking patterns:

- **M1**: NOT NULL column added without default (breaks existing INSERTs from old code)
- **M2**: Column dropped while prior-phase code still reads it
- **M3**: Column renamed in a single phase (must be add → dual-write → switch → drop)
- **M4**: Backfill running a long transaction on a hot table (lock risk)
- **M5**: Schema change without index supporting the new read path
- **M6**: Phase contains both schema change AND code that depends on the new schema (must be split — schema in earlier phase, code switch in later phase)
- **M7**: Removed function/endpoint where callers may exist on the previous-phase deploy
- **M8**: Per-phase deployability — for each phase, simulate `main + phases 1..N` and verify old (phase N-1) running code keeps working

Plus four structural-consistency patterns:

- **S1**: Orphan phase tag (a commit's `Phase: N` trailer or a task's `[phase-N]` tag references a phase number not declared in the plan's "Deploy Phases" section)
- **S2**: Non-contiguous phases (the set of phase numbers observed contains a gap, e.g., `Phase: 1` and `Phase: 3` exist with no `Phase: 2`)
- **S3**: Malformed `Phase:` trailer (a commit body contains a `Phase:` trailer whose value cannot be parsed as a positive integer, including empty values)
- **S4**: Phase-trailer-without-deploy-phases (the plan artifact has no "Deploy Phases" section but the feature branch contains commits carrying a `Phase:` trailer)

The pack MAY emit `medium`, `low`, or `informational` findings for advisory observations outside this catalog (e.g., stylistic guidance on migration scripts), but every FR-010-cataloged pattern MUST be `high`.

**Rationale**: The split step's gating rule (FR-018) only triggers on `high`-severity findings (per the clarification on uniform gating recorded in spec.md). Pinning every FR-010 pattern at `high` makes the gating contract uniform: any FR-010 detection blocks the affected phase. Lower-severity findings are surfaced as review comments for the human reviewer to address but do not gate the split step.

**Alternatives considered**:

- **Mixed severity per pattern (e.g., M1 high, M4 medium)** — rejected per the severity-uniformity clarification. Forces authors to learn which patterns gate and which don't; defeats the "uniform gating contract" model.
- **A separate severity field per finding type** — rejected. The persisted review-report format already has a Severity column; adding a "gating" boolean would be redundant since Severity = `high` already encodes gating.

## R-008: Phase pull-request title and body are pipeline-managed

**Decision**: The split step generates each phase pull request's title and body deterministically from the feature branch name and the plan artifact (FR-016, per the clarification on PR title/body in spec.md). For multi-phase features, the title is `[Phase K/N] <feature-branch-name>`. The body is composed of:

1. A first line `Part of <FEATURE_DIR>/spec.md` (relative path).
2. `## Phase Goal` — copied verbatim from the corresponding plan entry's goal text.
3. `## Post-deploy production state` — copied verbatim from the same plan entry.
4. `## Stack` — bullets `- Phase J: NNNN-<type>-<slug>-phaseJ` for J in 1..N, with ` (this PR)` appended for `J == K`.

For single-phase features, title is `<feature-branch-name>` (today's behavior) and body is just the first line.

The split step recomputes title and body on every run, compares against `gh pr view --json title,body`, and overwrites via `gh pr edit --title --body` when they differ. Human edits WILL be overwritten on the next split-step run; reviewers MUST use PR review comments rather than editing the description.

**Rationale**: Pipeline-managed PR fields are how the split step keeps the rendered stack in sync with the plan artifact. Without overwrite, a reviewer's manual edit (or a stale field from a previous phase definition) drifts from the plan, and the PR description no longer reflects the deployable state. The deterministic format also makes the `unchanged` status of FR-019a computable: title and body are inputs to the equality check alongside commit SHAs.

**Alternatives considered**:

- **Generate PR fields once, never overwrite** — rejected. Drift between plan and PR description is exactly what the multi-phase model needs to avoid.
- **Append a generated section to a human-authored body** — rejected. Sentinel-line parsing is fragile; humans edit around the markers; the "what's pipeline-managed vs. human-authored" line blurs.
- **Use a PR template instead of generating the body** — rejected. PR templates only fire at PR-create time; idempotent re-runs need an overwrite mechanism, which `gh pr edit --body` provides directly.

## R-009: Persisted split report mirrors stdout summary

**Decision**: The split step writes `<FEATURE_DIR>/split-report.md` on every run, overwriting any prior copy (FR-019a). The machine-readable surface is a single GFM table with columns `| Phase | Status | Branch | PR URL | Reason |` in that order, one row per phase. Statuses: `created`, `updated`, `unchanged`, `skipped-merged`, `gated`, `failed`. A concise human-readable summary mirrors the table to stdout. The pipeline orchestrator reads the file to determine the split step's outcome without re-running it; absence of the file is treated as a split-step failure.

**Rationale**: Per the clarification on outcome reporting recorded in spec.md, persisting the report keeps the split step's outcome visible after the run completes, which the orchestrator and re-running humans both need. The fixed column order and headers make the report parseable with stock `awk` (matches R-006). The stdout mirror gives the author immediate feedback without a separate file open.

**Alternatives considered**:

- **stdout-only (no persisted file)** — rejected per the clarification. The orchestrator needs to read outcomes after the fact (e.g., to decide whether to attempt a retry); stdout disappears.
- **Append to a single multi-run log** — rejected. Idempotent re-runs should overwrite, not accumulate; a multi-run log mixes outcomes across runs and makes the latest state ambiguous.

## R-010: Per-phase findings via Marge — no separate per-phase review pass

**Decision**: Marge runs once on the integrated feature branch (FR-012). For multi-phase features, every finding is tagged with the phase that introduced the issue (FR-011). The Phase column carries the integer phase number for findings attributable to a single phase, or the literal `-` for structural inconsistencies that cannot be attributed to a specific phase (e.g., malformed `Phase:` trailer per S3, phase-trailer-without-deploy-phases per S4). The split step treats any `high`-severity finding with Phase `-` as gating every phase in the run (a global gate per FR-018).

**Rationale**: Running Marge once on the integrated branch matches today's review model (single review pass per feature). Per-phase scope is expressed via finding tags rather than separate per-phase passes — this avoids K times the review cost for K phases and keeps Marge's existing workflow unchanged. Global gating on Phase `-` findings is the right behavior because structural inconsistencies (malformed trailer, plan mismatch) prevent the split step from making sound per-phase decisions.

**Alternatives considered**:

- **Run Marge K times, once per phase, with per-phase scoped diffs** — rejected. Multiplies review cost by K; loses cross-phase visibility (e.g., M2 spans phases by definition); does not address the structural inconsistencies that Phase `-` covers.
- **Treat structural findings as warnings, not gates** — rejected. A malformed trailer or a plan mismatch produces a malformed PR stack; the split step needs to refuse rather than ship known-broken output.

## R-011: Stage relabel inside multi-phase tasks.md

**Decision**: For multi-phase features, deploy phases are the sole top-level (`##`) organizing structure of `tasks.md` (FR-004). The existing per-story task structure (`Phase 1: Setup`, `Phase 2: Foundational`, `Phase 3+: User Stories`) is preserved as second-level (`###`) "Stage" headings nested inside each top-level deploy phase, using the form `### Stage: Setup`, `### Stage: Foundational`, `### Stage: User Stories` (FR-005, per the Stages clarification recorded in spec.md). Empty stages are omitted. Every task under any stage within deploy-phase K carries `[phase-K]`. For single-phase features, the existing template is preserved unchanged — Setup/Foundational/User Stories remain at the top level, no "Stages" relabel, no `[phase-N]` tags.

**Rationale**: Per the Stages clarification, deploy phases must be the top-level organizing structure for multi-phase features so Ralph can enumerate them by `##`-level grep. The existing Setup/Foundational/User-Stories structure carries useful information (ordering within a phase) and shouldn't be discarded; nesting it as `###` under each deploy phase preserves the information without competing with deploy-phase headings. The `Stage:` prefix disambiguates the two senses of "phase" so authors and tooling don't conflate them. Empty stages are omitted to keep tasks.md compact.

**Alternatives considered**:

- **Discard Setup/Foundational/User-Stories entirely for multi-phase** — rejected per the Stages clarification. The structure carries ordering information (setup before foundational before user-story tasks) that belongs in tasks.md.
- **Keep both at the top level (`## Phase 1`, `## Phase 1 Setup`, `## Phase 1 Foundational`, ...)** — rejected. Quadratic explosion of top-level headings; Ralph and the split step both need to grep by phase, which is harder when phase identity is encoded in heading text rather than nesting.
- **Tag stages with their own marker (e.g., `[stage-setup]`)** — rejected. The phase tag (`[phase-K]`) is the only marker the implementation agent and split step need; stage information is already encoded by the parent `###` heading.

## R-012: No new bash scripts; reuse existing utilities

**Decision**: The split step is implemented entirely in markdown (the new command file `speckit-commands/speckit.split.md` plus the new agent file `claude-agents/split.md`) executing `git`, `gh`, `awk`, `grep`, `sed`, and other standard Unix tools via the Bash tool. No new `.specify/scripts/bash/*.sh` is added. The setup script (`setup.sh`) requires no changes — its existing idempotent check-pack seeding loop picks up `migrations.md` automatically (FR-024). The single global quality gate (`.specify/quality-gates.sh`) applies to the integrated branch as a whole, with no per-phase variants (per Assumptions in spec.md).

**Rationale**: Every existing pipeline step is implemented as a markdown command file driving a Claude agent that calls Bash/Edit/Read tools. Adding a bash script for the split step would diverge from this pattern and require new permission entries in `.claude/settings.local.json`. Reusing the existing markdown-driven model keeps the implementation surface uniform. The setup script's idempotent `cp` loop over `.specify/marge/checks/*.md` already covers the new `migrations.md`, so FR-024 is satisfied without setup-script changes.

**Alternatives considered**:

- **A `.specify/scripts/bash/split.sh` shell script** — rejected. Requires permission entries; diverges from the markdown-driven pipeline pattern; offers no functional benefit since Bash tool can run the same commands inline.
- **Per-phase quality gates** — rejected per Assumptions. Adds complexity without a concrete need; the integrated branch is the canonical implementation surface.
