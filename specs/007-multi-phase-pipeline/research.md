# Research: Multi-Phase Pipeline for SpecKit Simpsons

**Branch**: `007-multi-phase-pipeline` | **Date**: 2026-04-25

This document records the technical decisions made during Phase 0 of planning. Every NEEDS CLARIFICATION marker has been resolved here or by reference to the spec's Clarifications and Assumptions sections. The spec went through `/speckit.clarify` and resolved seven clarification questions before planning began; those answers are quoted verbatim where relevant rather than re-litigated.

## R-001: Engine Implementation Language

**Decision**: Ruby 3.2+.

**Rationale**: The spec's Assumptions section nominates Ruby on the grounds that "the reference flavor parses its target language's source files natively." Since the reference flavor inspects Rails migrations, models, and rake tasks, a same-language implementation avoids cross-language parsing complexity and lets the reference flavor use Ruby's built-in parser (`Ripper`, `Prism`) when it needs to inspect commit content beyond simple file-pattern matching. Ruby's standard library (Psych for YAML, JSON, OptionParser, Logger, Digest, Open3 for subprocess) covers every requirement of the engine and stacked-PR creator. Ruby 3.2+ is chosen for `Data.define` (immutable value objects for the manifest entities), pattern matching on hashes (idiomatic for classification result handling), and the `Prism` parser availability.

**Alternatives considered**:

- **Bash + jq + yq**: Rejected. The forbidden-operations registry, precedent validator, and backfill-safety validator would need to invoke a real parser to be reliable; layering that on top of Bash adds complexity without compensating benefit. Bash is also a poor fit for the determinism guarantee of FR-002 — sorted-hash output and stable YAML emission are easier in Ruby.
- **Python**: Functionally equivalent, but the spec's user input nominated Ruby and the reference flavor inspects Ruby code; using Python would force the reference flavor to shell out for parsing or duplicate Ruby's syntax knowledge in a Python parser library.
- **Go**: Single static binary is appealing but Go's YAML libraries do not produce stable key ordering by default and the reference flavor's Ruby-source inspection would need either a Ruby parser library port or a Ruby subprocess.

## R-002: Test Framework

**Decision**: RSpec for engine, flavor, and stacked-PR creator unit and integration tests. Cucumber is intentionally rejected.

**Rationale**: RSpec is the de facto Ruby testing standard, integrates cleanly with `bundle exec`, supports fixture helpers, and produces machine-readable output for the quality-gates wrapper. The engine's regression tests are inherently table-driven (every type, every forbidden operation, every fixture commit) and RSpec's `describe`/`it` structure plus shared examples keep them readable.

**Alternatives considered**:

- **Cucumber/Gherkin**: Rejected. The acceptance scenarios in spec.md are already in given/when/then form, but introducing a Gherkin layer adds an indirection (the .feature file plus the step definitions) without giving the engine logic a clearer expression than RSpec's `describe`/`it` already provides. The existing SpecKit Simpsons quality-gates surface uses plain test runners; matching that pattern keeps the project consistent.
- **Minitest**: Functionally equivalent but RSpec's matchers (`match`, `include`, `change`, `raise_error.with_message`) are more expressive for the assertion-heavy regression tests.

## R-003: Flavor Catalog Format

**Decision**: Each shipped flavor lives in `phaser/flavors/<name>/` as a `flavor.yaml` declarative catalog plus optional Ruby modules (`inference.rb`, `forbidden_operations.rb`, `backfill_validator.rb`, `precedent_validator.rb`) for richer pattern matching.

**Rationale**: A pure-YAML flavor would force pattern matching to be expressed as regex strings, which is fragile for the reference flavor's needs (e.g., detecting that a backfill rake task lacks batching requires AST-aware checks, not regex). A pure-Ruby flavor would make catalogs hard to review and would lower the bar for accidental engine-coupling. The split keeps the bulk of catalog data (task type names, isolation rules, precedent edges, default type, version, stack-detection signals) in plain YAML for reviewers and audit, while pattern-matcher methods sit in small Ruby modules that the YAML references by name (`inference_module: Phaser::Flavors::RailsPostgresStrongMigrations::Inference`).

**Alternatives considered**:

- **Pure YAML with regex strings**: Rejected. AST-aware checks for backfill safety and forbidden operations cannot be expressed as regex without false positives.
- **Pure Ruby DSL** (e.g., `flavor do; type :foo, isolation: :alone; end`): Rejected. Less reviewable for non-Ruby readers; harder to lint and schema-validate.
- **JSON Schema-validated YAML**: Adopted as a quality gate. The flavor.yaml is validated against `contracts/flavor.schema.yaml` as part of `bundle exec rspec`; this gives early failure on malformed flavors without forcing every catalog field into Ruby.

## R-004: Manifest Serialization (YAML, Stable Key Ordering)

**Decision**: The phase manifest is YAML at `<FEATURE_DIR>/phase-manifest.yaml`. Keys are emitted in a fixed declared order via a single writer module (`manifest_writer.rb`); hash iteration order is never relied on. The full key ordering is specified in `contracts/phase-manifest.schema.yaml`.

**Rationale**: FR-038 requires "human-readable and reviewable" with "stable key ordering across runs"; FR-002 requires byte-identical output across re-runs. Psych (Ruby's bundled YAML library) preserves insertion order in Ruby 3.x, so emitting an explicitly ordered Hash via Psych guarantees stability. YAML is preferred over JSON for the manifest because YAML supports inline comments (reviewers can annotate phase rationale), produces line-oriented diffs in code review tools, and is more readable for the operator audience that has to act on the file.

**Alternatives considered**:

- **JSON**: Rejected. No comment support; less readable; identical ordering guarantees but worse for reviewers.
- **TOML**: Rejected. Poor support for nested ordered lists of heterogeneous entries (phases each containing tasks each containing fields).

## R-005: Determinism Strategy

**Decision**: Determinism is enforced at three points and verified by a single 100-iteration regression test.

1. **Classification**: When multiple inference rules match a commit, the engine selects the rule with the highest declared precedence; ties are broken alphabetically by rule name (FR-036).
2. **Phase ordering**: Phases are emitted in commit-order subject to precedent and isolation rules; the topological-sort tie-breaker is commit hash.
3. **YAML emission**: All manifest output flows through `manifest_writer.rb`, which builds an explicitly ordered Hash before handing to Psych. Timestamps are written with millisecond precision and pulled from a single clock injection point so tests can pin them.

**Rationale**: FR-002 and SC-002 require byte-identical output across at least 100 consecutive runs. Without a single-point clock injection, generation timestamps would alone defeat the regression test; without explicit hash ordering, Ruby's Hash iteration would suffice in practice but is fragile across Ruby versions. The three-point discipline plus a deterministic-output regression test gives a strong guarantee.

**Alternatives considered**:

- **Stripping the timestamp from the manifest**: Rejected. FR-021 requires the generation timestamp to appear in the manifest; the test pins the clock instead.
- **Sorting all hashes before emit**: Rejected. The desired key order is semantic, not alphabetic (e.g., `flavor_name` before `flavor_version` before `phases`); explicit ordering preserves human readability.

## R-006: No-Domain-Leakage Enforcement (SC-003)

**Decision**: A regression test (`engine_no_domain_leakage_spec.rb`) greps every file under `phaser/lib/phaser/` for the literal strings `Rails`, `ActiveRecord`, `Postgres`, `postgresql`, `strong_migrations`, `migration`, `pg`, `Gemfile`, plus a configurable additional list. Any match (case-insensitive, word-boundary aware) fails the test. The grep also runs against `phaser/bin/`. The reference flavor's directory (`phaser/flavors/rails-postgres-strong-migrations/`) is excluded from the scan.

**Rationale**: FR-003 forbids the engine from carrying any concrete framework, database, or library knowledge. SC-003 requires zero such references. A grep-based regression test is the simplest mechanism that catches accidental coupling during development and survives refactors. The configurable additional list lets future flavors add their own forbidden-string list to the scan without modifying the test.

**Alternatives considered**:

- **Code review only**: Rejected. Manual enforcement degrades over time; SC-003 explicitly demands a measurable check.
- **AST-based scan via Prism**: Considered but rejected as over-engineered for an MVP; a simple grep is sufficient and easier to debug when it fails.

## R-007: Pre-Classification Forbidden-Operations Gate (FR-049)

**Decision**: The forbidden-operations gate runs as the first step of `engine.rb#process_commit`, strictly before any classification candidate (operator tag, inference rule, default type) is considered. The engine's call sequence is:

```ruby
def process_commit(commit, flavor)
  return :skip if commit.diff.empty?                              # FR-009
  forbidden = flavor.forbidden_operations_gate.evaluate(commit)
  raise ForbiddenOperationError.new(commit, forbidden) if forbidden
  classifier.classify(commit, flavor)                              # operator-tag / inference / default
end
```

The classifier is never invoked when the gate rejects the commit. The engine source contains no flag, environment variable, or commit-message trailer that lets the gate be skipped (D-016, FR-049 explicit prohibition). The clarification answer in spec.md is quoted as the authoritative requirement.

**Rationale**: The clarification session resolved this exactly: "The forbidden-operations registry is a deploy-safety guard that MUST run as a pre-classification validation pass over every commit's diff content, BEFORE any classification decision (operator-tag, inference, or default-type) is made... The operator-tag override (FR-004, FR-016) governs precedence ONLY between competing classification candidates and MUST NOT be capable of suppressing a forbidden-operations rejection." The architectural placement of the gate before classification is the only way to honor this without relying on careful code-review discipline.

**Verification**: SC-015's regression test pairs every entry in the registry with a commit that carries an operator-supplied type tag naming a different valid type and asserts the gate still rejects.

**Alternatives considered**:

- **Run the gate as part of classification**: Rejected. This was the original natural design; the clarification explicitly prohibits it because it would let operator tags suppress the gate by clever ordering.
- **Run the gate after classification but before manifest write**: Rejected for the same reason; the spec requires the gate to fire before any classification candidate is considered.

## R-008: Hard Size Bounds (FR-048, SC-014)

**Decision**: `size_guard.rb` runs after empty-diff filtering and before classification. It enforces:

- **Commit bound**: Non-empty commits ≤ 200. Empty-diff commits skipped under FR-009 do not count.
- **Phase bound**: Projected phase count ≤ 50. Projected count is computed by a worst-case simulation: every "alone"-isolation classified commit becomes its own phase; "groups" commits are collapsed into the minimum number of phases consistent with precedent rules.

On either bound exceeded, the engine emits exactly one `validation-failed` ERROR record with `failing_rule: feature-too-large`, payload fields `commit_count` and `phase_count`, and `decomposition_message: "Feature exceeds bounds (max 200 non-empty commits, max 50 phases). Split into smaller specs."`. The same payload is persisted to `phase-creation-status.yaml` with `stage: phaser-engine`. No manifest is written.

**Rationale**: The clarification session set these specific bounds with the explicit goal of pushing operators toward smaller, reviewable features rather than producing unreviewable mega-stacks. The phase bound is computed by simulation rather than by classifying first and counting, because the simulation is fast (O(commits)) and avoids the cost of full classification on inputs that will be rejected anyway. Empty-diff exclusion from the commit bound matches the clarification's exact wording.

**Verification**: SC-014's two regression tests construct (a) a synthetic 201-non-empty-commit branch and (b) a flavor-and-commits combination that would emit 51 phases, and assert both fail fast before any manifest is written.

**Alternatives considered**:

- **Soft warnings instead of hard failures**: Rejected. The clarification was explicit: fail fast, no manifest written, exit non-zero, error message instructs operator to split.
- **Different default bounds** (e.g., 100 commits / 20 phases): Considered. The chosen 200/50 are wider than the typical case but tight enough to catch obvious mega-features.

## R-009: Stacked-PR Authentication Model (FR-044, FR-045, FR-047)

**Decision**: The stacked-PR creator delegates the entire authentication surface to the operator-configured `gh` CLI (or its documented equivalent for non-GitHub hosts). It MUST NOT:

- Read any environment variable whose name contains `TOKEN`, `KEY`, `SECRET`, or `PASSWORD`.
- Read `~/.config/gh/hosts.yml` or any other token-bearing config file directly.
- Accept tokens via command-line arguments.
- Pass tokens to subprocesses through environment variables under its own control.

The creator invokes `gh auth status` exactly once at startup (`auth_probe.rb`). On exit code 0, the result is cached and the run proceeds. On non-zero exit code, the creator inspects stderr to classify the failure (`failure_classifier.rb`):

| Probe condition | failure_class |
|---|---|
| `gh` not authenticated | `auth-missing` |
| Authenticated but missing `repo` scope | `auth-insufficient-scope` |
| HTTP 429 from `gh api` (rate limit) | `rate-limit` |
| DNS / TCP / TLS error from `gh api` | `network` |
| Any other failure | `other` |

The probe failure or any later branch/PR creation failure is recorded in `phase-creation-status.yaml` with `stage: stacked-pr-creation`, the appropriate `failure_class`, and `first_uncreated_phase` (1 for probe failures, the actual phase number for mid-run failures). On a fail-fast probe exit, no branches and no PRs are created (SC-012).

A separate regression test (SC-013) scans every emitted log line and every byte of every `phase-creation-status.yaml` produced by failure-mode fixtures for substrings matching common credential patterns:

- GitHub personal access token prefixes (`ghp_`, `gho_`, `ghu_`, `ghs_`, `ghr_`)
- Bearer-token headers (`Bearer `)
- Base64-encoded session cookies (`Cookie:` headers)

Any match fails the test.

**Rationale**: The clarification session was explicit: "The stacked-PR creator MUST delegate authentication entirely to the operator-configured Git-host CLI... and MUST NOT read tokens from environment variables, files, or process arguments directly... Tokens, secrets, or any substring that could plausibly contain a credential MUST NEVER appear in any log line, status file, or error message." Treating the auth surface as fully opaque is the only design that honors all three requirements together.

**Alternatives considered**:

- **Read `GITHUB_TOKEN` directly**: Rejected per FR-044's explicit prohibition.
- **Probe per-phase**: Rejected; the clarification specifies "exactly once."
- **Separate status files per failure mode**: Rejected; D-012's single-file design with a `stage` field reduces operator cognitive load.

## R-010: Stacked-PR Creator Idempotency (FR-040, SC-010)

**Decision**: On every run, the creator reads `phase-manifest.yaml` and for each phase queries `gh` for both the branch and the PR:

```bash
gh api repos/:owner/:repo/git/refs/heads/<feature>-phase-<N>
gh pr list --head <feature>-phase-<N> --state all --json number,baseRefName
```

Phases whose branch exists AND whose PR exists with the correct base branch are skipped. The first phase whose branch is missing (or whose PR is missing or has the wrong base) becomes the resume point. The creator never deletes or modifies existing branches or PRs. On full success of all phases, `phase-creation-status.yaml` is deleted (FR-040).

**Rationale**: FR-040 requires re-runs to be idempotent and to detect existing artifacts by name. Querying `gh` is the source of truth for what exists on the host; relying on `phase-creation-status.yaml`'s `first_uncreated_phase` field as the only resume signal would fail when the file is missing or stale. The base-branch check catches the case where a manual rebase happened between runs and the existing PR no longer points where the manifest expects.

**Verification**: SC-010 injects a failure between phase K and phase K+1 of an N-phase manifest, asserts phases 1..K are intact and K+1's branch does not exist, then re-runs and asserts the run completes without re-creating phases 1..K.

**Alternatives considered**:

- **Trust `phase-creation-status.yaml` exclusively**: Rejected. The file can be missing (first-run-after-failure-without-status-file) or stale (operator manually created some branches).
- **Delete and recreate failed phases**: Rejected. FR-039 explicitly requires that already-created branches and PRs be left untouched.

## R-011: Pipeline Integration Strategy (FR-019, FR-023, FR-025)

**Decision**: The opt-in gate is the existence of `.specify/flavor.yaml` at the repository root, checked by the modified `speckit.pipeline.md` immediately after the existing pre-flight checks. Behavior:

- **No file**: Skip the phaser step, run marge as a single holistic pass, behave byte-identically to today (FR-025, SC-006).
- **File exists**: Insert the phaser step between ralph and the existing simplify/security-review polish phases. After phaser succeeds, invoke marge `N+1` times: once per phase with `--phase N` (FR-022), then once holistically without the flag (FR-023). The holistic pass MUST run after all per-phase passes complete.

The phaser step itself is a single-shot agent (`.claude/agents/phaser.md`) that invokes the `phaser` CLI via Bash, captures the manifest path from stdout, commits the manifest to the feature branch, and returns. On non-zero exit, the pipeline halts and does not invoke marge (FR-024). The status file (`<FEATURE_DIR>/phase-creation-status.yaml`) is preserved for diagnostic purposes.

The stacked-PR creator runs after marge succeeds across all phases. It is gated on the same `.specify/flavor.yaml` check.

**Rationale**: Gating on file existence — rather than a configuration flag — aligns with the spec's "opt-in" framing and gives the cleanest backward-compatibility story. SC-006 verifies the no-flavor case via a captured baseline-diff regression test that runs the full pipeline against a known-good fixture branch and asserts the output matches a stored baseline.

**Alternatives considered**:

- **CLI flag `--with-phaser`**: Rejected. Would force opt-in users to remember the flag on every invocation; the file-existence gate is more ergonomic.
- **A new top-level command `/speckit.phaser-pipeline`**: Rejected. Two pipelines diverging over time would be a maintenance burden; a single pipeline with conditional behavior is simpler.

## R-012: Per-Phase Marge Diff Scoping (FR-022)

**Decision**: The modified `.claude/commands/speckit.marge.review.md` accepts an optional `--phase <N>` argument. When present, marge:

1. Reads `<FEATURE_DIR>/phase-manifest.yaml` to find phase N's `branch_name` and `base_branch`.
2. Computes the diff range as `git diff <base_branch>...<branch_name>`.
3. Reviews only that diff range; ignores commits outside the range.

When absent, marge reviews the full feature diff as today (the holistic pass).

**Rationale**: FR-022 requires marge to "accept a directive to scope its review to the diff range between two specified phase boundaries." A `--phase N` argument that resolves the boundaries from the manifest is more ergonomic than two raw commit-hash arguments and matches how the pipeline knows what it wants to review (by phase number). The `git diff base...head` form (three dots) gives the symmetric difference, which is the conventional review-diff range.

**Alternatives considered**:

- **`--from <commit> --to <commit>`**: Rejected. More verbose; the pipeline would have to read the manifest and pass commit hashes itself when it could just pass the phase number.
- **Separate `marge-phase` command**: Rejected. Two commands diverging over time is a maintenance burden; a single command with an optional flag is simpler.

## R-013: Observability Event Schema (FR-041, FR-043)

**Decision**: The phaser engine emits one JSON object per line to stderr at INFO/WARN/ERROR levels. Every event includes:

```json
{"level": "INFO|WARN|ERROR", "timestamp": "<ISO-8601-UTC>", "event": "<event-name>", ...payload}
```

Defined event types and payloads (full schemas in `contracts/observability-events.md`):

| event | level | payload fields |
|---|---|---|
| `commit-classified` | INFO | `commit_hash`, `task_type`, `source` (`operator-tag` or rule name), `isolation`, optional `precedents_consulted` |
| `phase-emitted` | INFO | `phase_number`, `branch_name`, `base_branch`, ordered `tasks` |
| `commit-skipped-empty-diff` | WARN | `commit_hash`, `reason` |
| `validation-failed` | ERROR | `commit_hash` (when applicable), `failing_rule`, `missing_precedent` or `forbidden_operation` (whichever applies), `decomposition_message` (when failure is a forbidden operation or `feature-too-large`) |

stdout is reserved for the manifest path on success (`/path/to/phase-manifest.yaml\n`); no observability output ever goes to stdout (FR-043). This separation holds whether the phaser is invoked standalone (FR-008) or as part of the pipeline (FR-019).

**Rationale**: FR-041 specifies the event types and payload fields verbatim from the clarification answer; this decision adopts that schema and pins it in `contracts/observability-events.md`. JSON-lines format is parseable by `jq`, by line-oriented test harnesses, and by streaming log aggregators.

**Verification**: SC-011's regression test pipes the engine's stderr through a JSON-line parser and asserts every line parses, that at least one `commit-classified` record exists per non-empty commit, and that exactly one `validation-failed` record exists on validation failure.

**Alternatives considered**:

- **Plain-text logs**: Rejected. Not machine-parseable; SC-011 requires a JSON-line parser to be applicable.
- **Single JSON document at the end**: Rejected. Streaming JSON lines lets operators tail the engine in real time and survives partial output on crash.

## R-014: Status File Format (FR-039, FR-042, FR-046)

**Decision**: `<FEATURE_DIR>/phase-creation-status.yaml` is a YAML file with the following top-level keys (full schema in `contracts/phase-creation-status.schema.yaml`):

```yaml
stage: phaser-engine | stacked-pr-creation
timestamp: <ISO-8601-UTC>
failure_class: validation | auth-missing | auth-insufficient-scope | rate-limit | network | other
first_uncreated_phase: <integer>     # only when stage=stacked-pr-creation
commit_hash: <hex>                   # only when stage=phaser-engine and applicable
failing_rule: <string>               # only when stage=phaser-engine
missing_precedent: <string>          # only on precedent failures
forbidden_operation: <string>        # only on forbidden-operation failures
decomposition_message: <string>      # only on forbidden-operation or feature-too-large failures
commit_count: <integer>              # only on feature-too-large failures
phase_count: <integer>               # only on feature-too-large failures
```

The file is written via `status_writer.rb` to ensure consistent formatting and key ordering. On any subsequent fully successful re-run of the failing stage, the file is deleted (FR-040, FR-042).

**Rationale**: A single reusable status file with a `stage` discriminator (D-012) reduces operator cognitive load — there is exactly one place to look after any phaser-related failure. The schema covers every failure mode enumerated in FR-039, FR-042, FR-046, and FR-048.

**Alternatives considered**:

- **Separate files per stage** (`phaser-status.yaml`, `stacked-pr-status.yaml`): Rejected per D-012.
- **JSON instead of YAML**: Rejected. The manifest is YAML; using YAML for the status file too keeps the operator surface uniform.

## R-015: Flavor-Init Stack Detection (FR-031)

**Decision**: Each shipped flavor's `flavor.yaml` declares its own stack-detection signals as a list of file-presence and file-content checks. Example for the Rails flavor:

```yaml
stack_detection:
  signals:
    - type: file_present
      path: Gemfile.lock
      required: true
    - type: file_contains
      path: Gemfile.lock
      pattern: 'pg \('
      required: true
    - type: file_contains
      path: Gemfile.lock
      pattern: 'strong_migrations \('
      required: true
```

`phaser-flavor-init` iterates shipped flavors, evaluates each one's signals, and counts matches (a flavor matches when all `required: true` signals are satisfied). Outcomes:

- **Exactly one match**: Suggest that flavor, ask for confirmation, on confirmation write `.specify/flavor.yaml` (FR-032).
- **Zero matches**: Print `no flavor matched` and exit non-zero without writing any file (FR-033).
- **More than one match**: Print `Multiple flavors matched: <list>. Specify the desired flavor with --flavor <name>.` and exit non-zero. This case is not explicitly enumerated in the spec but is a natural consequence of supporting multiple shipped flavors and is documented in `contracts/flavor-init-cli.md`.
- **Existing `.specify/flavor.yaml`**: Refuse unless `--force` is supplied; with `--force`, overwrite (FR-034).

**Rationale**: Per-flavor signal declarations keep the detection logic with the flavor that uses it (no global registry to keep in sync). The signal types (`file_present`, `file_contains`) cover the common cases without introducing a full DSL. Supporting other detection types (e.g., `command_succeeds`) is deferred to a follow-up feature when a flavor needs them.

**Alternatives considered**:

- **Hard-coded detection per flavor in Ruby code**: Rejected. Less reviewable; signals belong with the catalog, not in code.
- **Always require operator to pass `--flavor <name>`**: Rejected. Spec User Story 5 explicitly requires auto-detection with confirmation.

## R-016: Worked Example Fixture (FR-017, SC-001)

**Decision**: A fixture under `phaser/spec/fixtures/repos/users-email-rename/` contains a Git repository with the exact commits required to reproduce the worked column-rename example. The fixture's commits, in order:

1. Add `email_address` column as nullable (no default).
2. Add ignored-columns directive for `email`.
3. Dual-write to both `email` and `email_address`.
4. Backfill `email_address` from `email` (batched, throttled, outside transaction).
5. Switch reads to `email_address`.
6. Remove all references to `email`.
7. Remove the ignored-columns directive AND drop the `email` column.

The reference flavor's RSpec test loads this fixture, runs the engine, and asserts exactly seven phases are emitted in the order above with no operator intervention. SC-001 reuses this fixture for the end-to-end pipeline test.

**Rationale**: FR-017 requires "exactly seven ordered phases from this fixture without any operator intervention." A real Git repository fixture (rather than mocked commits) exercises the full engine + flavor pipeline including diff parsing and forbidden-operation gating. Seven phases match the seven canonical steps of the safe column-rename pattern.

**Verification**: A single RSpec `it` block in `rails_postgres_strong_migrations_spec.rb` loads the fixture, runs the engine, and asserts the manifest has exactly seven phases with the expected names and ordered tasks.

**Alternatives considered**:

- **Mocked commit objects**: Rejected. Would not exercise the real diff-reading and forbidden-operation gate paths.
- **Generated-on-demand fixture via a Rake task**: Rejected. A pre-committed fixture is more reproducible and faster.

## R-017: Setup Script Changes

**Decision**: `setup.sh` is modified to:

1. Copy `speckit-commands/speckit.phaser.md` and `speckit-commands/speckit.flavor.init.md` to `.claude/commands/`.
2. Copy `claude-agents/phaser.md` to `.claude/agents/`.
3. Make `phaser/bin/phaser`, `phaser/bin/phaser-stacked-prs`, and `phaser/bin/phaser-flavor-init` executable and either symlink them into a stable location on `PATH` (preferred when the operator's `PATH` includes a SpecKit-managed `bin/` directory) or document that the operator should add `phaser/bin/` to `PATH`.
4. Run `bundle install` inside `phaser/` if `bundle` is available, to fetch the small dependency set (`rspec`, `rubocop`).

Existing setup behavior (copying other commands, agents, and `.specify/` files) is preserved. The script remains idempotent.

**Rationale**: The project's CLAUDE.md "Source vs Installed Files" section makes clear that `.claude/commands/` and `.claude/agents/` are installed copies of the source files; `setup.sh` is the canonical installer. Adding the new files to that script keeps the install process uniform.

**Alternatives considered**:

- **Manual installation instructions in README**: Rejected. The existing convention is automated installation via `setup.sh`; deviating would be inconsistent.
- **Gem-packaged distribution of the phaser engine**: Considered as a future improvement but rejected for the MVP because it would split the SpecKit-managed surface across two installers.

## R-018: Quality Gates for the Ruby Code

**Decision**: `.specify/quality-gates.sh` is updated to include (when the `phaser/` directory exists):

```bash
( cd phaser && bundle exec rspec )
( cd phaser && bundle exec rubocop )
```

The existing gates remain unchanged. The Ruby gates run only when `phaser/` is present, so existing repositories without the phaser feature are unaffected.

**Rationale**: The constitution requires "all tests pass" and "linting passes with zero errors." `rspec` and `rubocop` are the Ruby community standards for those gates and are already declared in `phaser/Gemfile`. Conditioning on directory existence preserves backward compatibility for non-phaser users.

**Alternatives considered**:

- **Always run the gates regardless of directory presence**: Rejected. Would fail on repositories without `phaser/`.
- **A separate `.specify/phaser-quality-gates.sh`**: Rejected. One quality-gates entry point keeps the operator surface uniform.

## Files Requiring Changes

### Add (new files)

| File | Purpose | FRs |
|---|---|---|
| `phaser/bin/phaser` | Standalone phaser CLI entry point | FR-008 |
| `phaser/bin/phaser-stacked-prs` | Stacked-PR creator entry point | FR-026, FR-039 |
| `phaser/bin/phaser-flavor-init` | One-shot flavor-init entry point | FR-031–FR-034 |
| `phaser/lib/phaser.rb` and `phaser/lib/phaser/**/*.rb` | Engine, classifier, gate, validators, writers, stacked-PR creator, flavor-init | FR-001 through FR-049 |
| `phaser/flavors/example-minimal/{flavor.yaml,inference.rb}` | Toy regression flavor | FR-003, SC-003 |
| `phaser/flavors/rails-postgres-strong-migrations/*` | Reference flavor catalog and pattern modules | FR-010 through FR-018 |
| `phaser/spec/**/*_spec.rb` | RSpec tests for engine, flavors, stacked-PR creator, flavor-init | All SC items |
| `phaser/spec/fixtures/**` | Synthetic Git repos and per-type classification fixtures | FR-012, FR-017 |
| `phaser/{Gemfile,Gemfile.lock,Rakefile,.rubocop.yml}` | Ruby project metadata and quality-gate configuration | — |
| `speckit-commands/speckit.phaser.md` | Phaser-stage command file | FR-019, FR-024 |
| `speckit-commands/speckit.flavor.init.md` | Flavor-init command file | FR-031 |
| `claude-agents/phaser.md` | Phaser-stage agent file | FR-019 |
| `specs/007-multi-phase-pipeline/contracts/*.{md,yaml}` | Schemas and CLI contracts | — |

### Modify

| File | Changes | FRs |
|---|---|---|
| `speckit-commands/speckit.pipeline.md` | Insert phaser step between ralph and simplify; gate on `.specify/flavor.yaml` existence; invoke marge per-phase plus holistic; preserve no-flavor zero-regression behavior | FR-019, FR-023, FR-024, FR-025 |
| `speckit-commands/speckit.marge.review.md` | Accept `--phase <N>` to scope review to that phase's diff range | FR-022 |
| `setup.sh` | Install new commands, agents, and `phaser/bin/` entry points | — |
| `.specify/quality-gates.sh` | Add `bundle exec rspec` and `bundle exec rubocop` runs gated on `phaser/` presence | — |
| `CLAUDE.md` | Add active technologies entry for the new feature | — |

### No Changes Needed

| File | Reason |
|---|---|
| `.claude/agents/{specify,homer,plan,tasks,lisa,ralph}.md` | These agents are unaffected by phasing; the pipeline orchestrator is what changes |
| `.claude/commands/speckit.{specify,homer.clarify,plan,tasks,lisa.analyze,ralph.implement}.md` | Same — no per-step behavior change required for non-marge agents |
| `.specify/scripts/bash/*.sh` | Existing utility scripts are unaffected |
| `templates/*` | Existing templates are unaffected |
