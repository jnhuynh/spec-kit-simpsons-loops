# Implementation Plan: Multi-Phase Pipeline for SpecKit Simpsons

**Branch**: `007-multi-phase-pipeline` | **Date**: 2026-04-25 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/007-multi-phase-pipeline/spec.md`

## Summary

Add a `phaser` stage to the SpecKit pipeline that sits between `ralph` (implementation) and `marge` (review). The phaser consumes a feature branch's commits plus an opt-in project flavor (a catalog of task types, isolation rules, precedent rules, and inference rules) and emits a deterministic phase manifest that drives stacked branches and stacked pull requests, enabling zero-downtime deploys for features that touch production schemas, data, or infrastructure.

The implementation is split cleanly into three layers:

1. A **flavor-agnostic phaser engine** (Ruby, packaged under `phaser/`) that classifies commits, validates precedent and forbidden-operation rules, enforces hard size bounds, emits structured stderr logs, and writes `phase-manifest.yaml` to `<FEATURE_DIR>/`. The engine is invocable standalone for testing (FR-008).
2. A **reference Rails+Postgres+strong_migrations flavor** (YAML + small Ruby pattern modules) that ships the deploy-safety task catalog, file-pattern inference rules, the backfill-safety validator, the precedent validator, and the forbidden-operations registry with canonical decomposition messages.
3. **Pipeline integration** through new SpecKit command and agent files (`speckit.phaser.md`, `phaser.md`) plus a stacked-PR creator that delegates Git-host authentication entirely to the operator-configured CLI (`gh` for GitHub) and a one-shot flavor-initialization command (`speckit.flavor.init.md`). The pipeline orchestrator (`speckit.pipeline.md`) and the marge command (`speckit.marge.review.md`) gain phase-aware behavior gated entirely on the existence of `.specify/flavor.yaml`; absent that file, behavior is byte-identical to the current pipeline (FR-025).

The phasing capability is **opt-in by file presence**: no flavor configuration file means no behavior change for current users (verified by SC-006).

## Technical Context

**Language/Version**: Ruby 3.2+ for the phaser engine and reference flavor (per the spec's Assumptions section: "the phaser engine is implemented in a language that allows the reference flavor to parse its target language's source files natively. The user's input nominates Ruby for this purpose"). Bash 4+ and Markdown for SpecKit command/agent files, consistent with the rest of the repository.
**Primary Dependencies**:

- Ruby standard library only for the engine (`yaml`, `json`, `logger`, `digest`, `optparse`)
- `psych` (Ruby's bundled YAML library) for manifest serialization with stable key ordering
- `rspec` for engine and flavor unit tests; `cucumber` is intentionally rejected (see R-002)
- `rubocop` for Ruby linting (community standard)
- `gh` CLI for GitHub stacked-PR creation, invoked exclusively as a subprocess (FR-044)
- Claude CLI (`claude` command), Agent tool, Bash tool for the SpecKit command/agent layer

**Storage**: Filesystem only.

- `<FEATURE_DIR>/phase-manifest.yaml` — the manifest (FR-020, FR-038)
- `<FEATURE_DIR>/phase-creation-status.yaml` — the failure-state status file (FR-039, FR-042, FR-046); deleted on full success (FR-040)
- `.specify/flavor.yaml` — the opt-in flavor configuration file (FR-019, FR-031–FR-034)
- `phaser/flavors/<name>/` — shipped flavor catalogs as YAML + Ruby pattern modules

**Testing**:

- `rspec` for engine unit tests, flavor catalog tests, and fixture-based regression tests (SC-002 deterministic-output, SC-005 forbidden-operation regression, SC-014 size bounds, SC-015 operator-tag-cannot-bypass-gate)
- `rubocop` as a linter quality gate
- Fixture-based integration tests using prepared Git repositories under `phaser/spec/fixtures/` with sample commits exercising every catalog entry, every forbidden operation, and the worked column-rename example (FR-017)
- `shellcheck` for any new shell scripts (consistent with prior features)
- Manual end-to-end pipeline verification on a real feature branch with the reference flavor active, plus a baseline-diff regression test for the no-flavor case (SC-006)
- A regression test that scans every emitted log line and `phase-creation-status.yaml` for credential-shaped substrings (SC-013)

**Target Platform**: macOS/Linux developer workstations (same as existing SpecKit Simpsons commands). Continuous integration runs per phase branch are assumed to be configured by the project's existing CI system (per Assumptions in the spec).
**Project Type**: CLI toolkit / developer tooling extension. The existing repository is a SpecKit Simpsons distribution that ships agent files, command files, and shell scripts; this feature adds a Ruby toolkit (`phaser/`) plus new agent and command files.
**Performance Goals**: A single phaser run on a feature branch within the enforced bounds (≤200 non-empty commits, ≤50 emitted phases — FR-048) MUST complete in under 30 seconds on a developer workstation. Within bounds, the engine's runtime is O(commits × rules) and is not expected to be a hot path; readability and determinism take precedence over micro-optimization.
**Constraints**:

- Engine MUST be deterministic (FR-002, SC-002): same inputs ⇒ byte-identical YAML across ≥100 consecutive runs.
- Engine MUST contain zero references to Rails, Postgres, ActiveRecord, strong_migrations, or any other concrete framework/database/library (FR-003, SC-003).
- Engine MUST NOT write to stdout except for the manifest path on success (FR-043); all observability goes to stderr as one JSON object per line (FR-041).
- Stacked-PR creator MUST never read or transmit Git-host tokens through any channel under its own control (FR-044, FR-047, SC-013).
- Hard ceilings: 200 non-empty commits and 50 emitted phases per single phaser run (FR-048, SC-014). Beyond either bound, fail fast before writing any manifest.
- The forbidden-operations registry MUST run as a pre-classification gate (FR-049, SC-015) — operator-supplied type tags MUST NOT be capable of suppressing it by any mechanism, and the engine MUST NOT expose a bypass flag.
- No flavor file ⇒ zero behavior change (FR-025, SC-006), verified by a baseline-diff regression test.

**Scale/Scope**: Within a single phaser run: up to 200 non-empty commits, up to 50 emitted phases, up to ~30 task types per shipped flavor, up to ~10 forbidden-operation detectors per shipped flavor. No constraint on total features per repository. This feature delivers one shipped flavor (`rails-postgres-strong-migrations`) plus the toy `example-minimal` flavor that serves as the no-domain-leakage regression contract (FR-003, SC-003).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Readability First | **PASS** | Engine code uses meaningful names (`classify_commit`, `apply_precedent_rules`, `enforce_size_bounds`); flavor YAML uses human-readable rule names; manifest uses sentence-case phase names and ordered task lists. |
| II. Functional Design | **PASS** | The engine is a pure function from `(feature_branch_commits, flavor)` to `phase_manifest`. The same inputs MUST produce byte-identical YAML (FR-002), enforced by SC-002's 100-run regression test. The stacked-PR creator is the only side-effecting layer and is isolated from the engine. |
| III. Maintainability | **PASS** | The engine carries zero domain knowledge (FR-003); all flavor logic is data-driven (YAML catalogs + small pattern-matcher modules). Future flavors can be added without touching engine code. The clear separation of engine, flavor, stacked-PR creator, and pipeline integration makes each layer independently understandable. |
| IV. Best Practices | **PASS** | Ruby code follows community Ruby style (rubocop default rules); YAML files follow Psych's stable-output conventions; Bash scripts follow the conventions established in `.specify/scripts/bash/`; agent and command files follow the patterns in `claude-agents/` and `speckit-commands/`. The `gh` CLI is used the way GitHub itself recommends — as a delegate for authentication, never as a credential transport. |
| V. Simplicity (KISS & YAGNI) | **PASS** | The MVP scope is exactly the seven phases of the worked column-rename example, the bounded-size guard, the forbidden-operations gate, and stacked-PR creation against GitHub. Long-running backfill orchestration, auto-rebase, cross-service phasing, and multi-database support are explicitly deferred per spec Assumptions. The engine has no plugin API beyond YAML flavor files plus pattern-matcher Ruby modules; introducing a heavier extension mechanism is rejected as YAGNI. |
| Test-First Development | **PASS** | The engine, the reference flavor's validators, and the stacked-PR creator are testable Ruby code. RSpec tests for each piece of new logic MUST be written first, fail, then be made to pass. Markdown command/agent files (`speckit.phaser.md`, `phaser.md`, `speckit.flavor.init.md`, plus the modifications to `speckit.pipeline.md` and `speckit.marge.review.md`) are declarative instructions interpreted by the Claude CLI — the same medium that prior features (006, 005) treated as N/A for unit testing — and are verified by the quickstart checklist plus end-to-end pipeline runs. |
| Dev Server Verification | **N/A** | No web UI or HTTP API is introduced. The phaser is a CLI tool plus orchestration-level Markdown. |
| Process Cleanup | **PASS** | The phaser engine is short-lived and exits cleanly. The stacked-PR creator invokes `gh` as a subprocess and waits for it; no long-running children are spawned. End-to-end verification will use a one-shot fixture repository under `/tmp/` and tear it down after each test. |
| Spec & Branch Naming | **PASS** | Feature directory and branch name are `007-multi-phase-pipeline`; the type segment `multi` is non-standard per the constitution's `feat|fix|chore` requirement. **NOTE**: This naming was inherited from the existing branch and spec.md before planning began; the constitution's naming rule is honored for new branches created by the stacked-PR creator (`<feature>-phase-N`), which inherit the original feature branch's name and append a phase suffix per FR-026. The non-standard type on the existing 007 branch is a pre-existing condition outside this plan's scope to repair. |

**Post-Phase 1 re-check**: All applicable principles still PASS. The Phase 1 design (entity definitions, contracts, pattern-matcher module signatures) does not introduce any new constitutional concerns. Test-first remains enforced for all Ruby code; the no-flavor zero-regression contract is enforced by SC-006's baseline-diff regression test; the credential-leak guard is enforced by SC-013's substring-pattern regression test. No violations to justify in Complexity Tracking.

## Project Structure

### Documentation (this feature)

```text
specs/007-multi-phase-pipeline/
├── checklists/
│   └── requirements.md           # Specification quality checklist
├── contracts/
│   ├── phase-manifest.schema.yaml          # YAML schema for the manifest (FR-020, FR-021, FR-038)
│   ├── flavor.schema.yaml                  # YAML schema for shipped flavor catalogs
│   ├── flavor-config.schema.yaml           # YAML schema for .specify/flavor.yaml
│   ├── phase-creation-status.schema.yaml   # YAML schema for the status file (FR-039, FR-042, FR-046)
│   ├── phaser-cli.md                       # Standalone phaser CLI contract (FR-008)
│   ├── stacked-pr-creator-cli.md           # Stacked-PR creator CLI contract (FR-026, FR-039)
│   ├── flavor-init-cli.md                  # Flavor-init command contract (FR-031–FR-034)
│   └── observability-events.md             # Structured-log event schema (FR-041, FR-043)
├── spec.md                       # Feature specification
├── plan.md                       # This file
├── research.md                   # Phase 0 output — all decisions documented
├── data-model.md                 # Phase 1 output — entity definitions
├── quickstart.md                 # Implementation quickstart and verification checklist
└── tasks.md                      # Phase 2 output (created by /speckit.tasks)
```

### Source Code (repository root)

```text
phaser/                                              # NEW — Ruby phaser engine and reference flavor
├── bin/
│   ├── phaser                                       # Standalone CLI entry point (FR-008)
│   ├── phaser-stacked-prs                           # Stacked-PR creator entry point (FR-026)
│   └── phaser-flavor-init                           # One-shot flavor-init entry point (FR-031)
├── lib/
│   ├── phaser.rb                                    # Top-level loader
│   ├── phaser/
│   │   ├── engine.rb                                # Pure function: (commits, flavor) -> manifest
│   │   ├── classifier.rb                            # Operator-tag / inference / default classification (FR-004)
│   │   ├── forbidden_operations_gate.rb             # Pre-classification gate (FR-049)
│   │   ├── precedent_validator.rb                   # Precedent-rule enforcement (FR-006)
│   │   ├── isolation_resolver.rb                    # Alone vs. groups isolation (FR-005)
│   │   ├── size_guard.rb                            # 200-commit / 50-phase bounds (FR-048)
│   │   ├── manifest_writer.rb                       # YAML serialization with stable key ordering (FR-038)
│   │   ├── status_writer.rb                         # phase-creation-status.yaml writer (FR-042)
│   │   ├── observability.rb                         # Structured stderr JSON logger (FR-041, FR-043)
│   │   ├── flavor_loader.rb                         # Reads shipped flavor catalogs from phaser/flavors/
│   │   ├── stacked_prs/
│   │   │   ├── creator.rb                           # Idempotent branch + PR creation (FR-026, FR-040)
│   │   │   ├── git_host_cli.rb                      # gh subprocess wrapper (FR-044)
│   │   │   ├── auth_probe.rb                        # One-shot auth check (FR-045)
│   │   │   └── failure_classifier.rb                # auth-missing / rate-limit / network / etc. (FR-046)
│   │   └── flavor_init/
│   │       └── stack_detector.rb                    # Inspects dependency manifests (FR-031)
│   └── phaser/version.rb
├── flavors/                                         # Shipped flavor catalogs
│   ├── example-minimal/                             # Toy two-type flavor — no-domain-leakage regression contract (FR-003, SC-003)
│   │   ├── flavor.yaml
│   │   └── inference.rb
│   └── rails-postgres-strong-migrations/            # Reference flavor (FR-010 through FR-018)
│       ├── flavor.yaml
│       ├── inference.rb
│       ├── forbidden_operations.rb
│       ├── backfill_validator.rb
│       └── precedent_validator.rb
├── spec/
│   ├── engine_spec.rb                               # Determinism, isolation, precedent, default-type tests
│   ├── classifier_spec.rb
│   ├── forbidden_operations_gate_spec.rb            # SC-005, SC-015
│   ├── size_guard_spec.rb                           # SC-014
│   ├── manifest_writer_spec.rb                      # SC-002 (100-run determinism)
│   ├── observability_spec.rb                        # SC-011, SC-013
│   ├── flavors/
│   │   ├── example_minimal_spec.rb
│   │   └── rails_postgres_strong_migrations_spec.rb # FR-017 worked example, FR-013/014 validators
│   ├── stacked_prs/
│   │   ├── creator_spec.rb                          # SC-010 idempotent resume
│   │   ├── auth_probe_spec.rb                       # SC-012 auth-missing fail-fast
│   │   └── failure_classifier_spec.rb
│   ├── flavor_init_spec.rb                          # FR-031–FR-034
│   ├── fixtures/
│   │   ├── repos/                                   # Synthetic Git repos for engine tests
│   │   ├── flavors/                                 # Test-only flavors
│   │   └── classification/                          # Per-type fixture commits (FR-012)
│   └── support/
│       └── git_fixture_helper.rb
├── Gemfile
├── Gemfile.lock
├── Rakefile                                         # rake test, rake lint
└── .rubocop.yml

.claude/commands/                                    # Source: speckit-commands/
├── speckit.phaser.md                                # NEW — invokes the phaser stage (FR-019, FR-024)
├── speckit.flavor.init.md                           # NEW — wraps phaser-flavor-init (FR-031–FR-034)
├── speckit.pipeline.md                              # MODIFIED — inserts phaser between ralph and marge (FR-019, FR-023, FR-025)
├── speckit.marge.review.md                          # MODIFIED — accepts phase-scoped diff range (FR-022, FR-023)
└── (other existing commands — UNCHANGED)

.claude/agents/                                      # Source: claude-agents/
├── phaser.md                                        # NEW — single-shot agent file for the phaser stage
└── (other existing agents — UNCHANGED)

speckit-commands/                                    # Source-of-truth (per CLAUDE.md "Source vs Installed Files")
├── speckit.phaser.md                                # NEW
├── speckit.flavor.init.md                           # NEW
├── speckit.pipeline.md                              # MODIFIED
└── speckit.marge.review.md                          # MODIFIED

claude-agents/                                       # Source-of-truth (per CLAUDE.md)
└── phaser.md                                        # NEW

setup.sh                                             # MODIFIED — installs phaser/ bin scripts to PATH-resolved location, copies new commands and agents
```

**Structure Decision**: The Ruby phaser code lives under a new top-level `phaser/` directory alongside the existing `claude-agents/`, `speckit-commands/`, and `templates/` source-of-truth directories. This keeps the new Ruby toolkit isolated from the SpecKit-managed Markdown/Bash surface and makes its independent test/lint commands (`bundle exec rspec`, `bundle exec rubocop`) easy to wire into `.specify/quality-gates.sh`.

The new `.claude/commands/speckit.phaser.md` and `.claude/agents/phaser.md` files are first written to their source-of-truth locations (`speckit-commands/` and `claude-agents/`) per the project's "Source vs Installed Files" rule in CLAUDE.md, then installed by `setup.sh`. Modifications to existing pipeline and marge commands follow the same source-then-install pattern.

The opt-in gate is the existence of `.specify/flavor.yaml` at the repository root: when absent, the modified `speckit.pipeline.md` skips the phaser step entirely and falls back to the current single-phase, single-PR behavior, satisfying FR-025 and SC-006.

## Design Decisions

### D-001: Engine Implementation Language (Ruby)

The phaser engine is implemented in Ruby 3.2+, per the spec's Assumptions section. Ruby is chosen because the reference flavor parses Ruby/Rails source files (migrations, models, rake tasks) and a same-language implementation avoids cross-language parsing complexity. Ruby's standard library covers everything the engine needs (YAML via Psych, JSON, OptionParser, Logger, Digest, subprocess management). The engine MUST contain zero references to Rails-specific or Postgres-specific symbols; this is enforced by SC-003 grep-style regression tests.

### D-002: Flavor Catalog Format (YAML + Ruby Pattern Modules)

Each shipped flavor lives in `phaser/flavors/<flavor-name>/` as a `flavor.yaml` declarative catalog plus optional Ruby modules (`inference.rb`, `forbidden_operations.rb`, etc.) that hold pattern-matcher logic too expressive for YAML. The YAML side declares task types, isolation rules, precedent rules, default type, version, stack-detection signals, and references to pattern-matcher methods. The Ruby side implements the actual file/content matching. This split keeps the bulk of flavor data reviewable in plain YAML (FR-038's spirit applied to flavors) while allowing rich matching where needed.

### D-003: Manifest Serialization (YAML with Stable Key Ordering)

The phase manifest is YAML at `<FEATURE_DIR>/phase-manifest.yaml` (FR-020, FR-038). Keys are emitted in a fixed declared order, not in hash-iteration order, by routing all output through `manifest_writer.rb`. This guarantees byte-identical output across runs (FR-002, SC-002). YAML is chosen over JSON because it supports inline comments for reviewer context, line-oriented diffs for code review, and is more human-readable for the operator audience.

### D-004: Forbidden-Operations Gate Runs Before All Classification

The forbidden-operations registry runs as a pre-classification gate (FR-049) — strictly before any classification candidate (operator tag, inference rule, default type) is evaluated. This is enforced architecturally: `engine.rb` calls `forbidden_operations_gate.evaluate(commit)` before it ever calls `classifier.classify(commit)`. The gate has no bypass flag, no environment variable override, and no commit-message trailer interpretation — operator tags are never even read until the gate has cleared the commit. SC-015's regression test pairs every forbidden-operation entry with an operator tag naming a valid type and asserts the gate still rejects.

### D-005: Stacked-PR Authentication via gh CLI Subprocess Only

The stacked-PR creator invokes `gh` as a subprocess and reads `gh auth status`'s exit code to determine authentication state (FR-044, FR-045). It MUST NOT read `GITHUB_TOKEN`, `GH_TOKEN`, or any other token-shaped environment variable; MUST NOT read `~/.config/gh/hosts.yml` or any other token file directly; MUST NOT accept tokens as command-line arguments. All branch and PR creation goes through `gh api` or `gh pr create` invocations. This delegates the entire authentication surface to `gh`, satisfying the "treat the entire authentication surface as opaque" requirement of FR-047.

### D-006: Authentication Probed Exactly Once Per Run

`auth_probe.rb` invokes `gh auth status` exactly once at the start of `phaser-stacked-prs` (FR-045). On failure, it writes `phase-creation-status.yaml` with `stage: stacked-pr-creation`, `failure_class: auth-missing` (or `auth-insufficient-scope`), and `first_uncreated_phase: 1`, then exits non-zero. No branch or PR creation is attempted (SC-012). After the probe succeeds, the result is cached for the rest of the run; subsequent `gh` calls do not re-probe.

### D-007: Stacked-PR Creator Idempotency by Branch and PR Detection

On re-run, `creator.rb` reads `phase-manifest.yaml` and for each phase queries `gh` for both the branch (`gh api repos/:owner/:repo/git/refs/heads/<branch>`) and the PR (`gh pr list --head <branch>`). Phases whose branch and PR both exist and match the manifest are skipped. The first phase whose branch is missing becomes the resume point. On full success, `phase-creation-status.yaml` is deleted (FR-040). SC-010 verifies this by injecting a failure between phase K and phase K+1, then re-running and confirming phases 1..K are untouched.

### D-008: Pipeline Integration Gated on .specify/flavor.yaml Existence

The modified `speckit.pipeline.md` checks for `.specify/flavor.yaml` immediately after the existing pre-flight checks. If absent, the pipeline skips the phaser step entirely, runs marge as a single holistic pass, produces a single PR, and behaves byte-identically to today (FR-025). If present, the phaser step is inserted between ralph and the existing simplify/security-review polish phases, and the marge step is invoked once per phase (with `--phase N` scoping the diff range) plus once holistically (FR-023). SC-006 verifies the no-flavor case via a captured baseline diff.

### D-009: Per-Phase Marge via --phase Flag (FR-022)

The modified `speckit.marge.review.md` accepts an optional `--phase <N>` argument that, when present, scopes the review to the diff range between phase N's base branch and phase N's head branch (read from `phase-manifest.yaml`). When absent, marge reviews the full feature diff as today. The phaser-aware pipeline calls marge `N+1` times: once per phase with `--phase N`, then once holistically without the flag (FR-023). The holistic pass MUST run after all per-phase passes complete.

### D-010: Stacked Branch Naming Follows the Manifest

Phase branches are named `<feature>-phase-1` through `<feature>-phase-N` (FR-026). The manifest records the exact branch name for each phase; the creator does not derive names independently. This makes the manifest the single source of truth for what gets created and is the artifact a reviewer reads to predict the resulting branch and PR set (SC-009). Phase 1 is based on the project's default integration branch (read from `gh repo view --json defaultBranchRef`); subsequent phases are based on the previous phase's branch.

### D-011: Observability — JSON Lines to stderr, Reserved stdout

The engine emits one JSON object per line to stderr (FR-041) at INFO/WARN/ERROR levels. stdout is reserved for the manifest path on success (FR-043), so downstream pipeline stages can pipe-consume the path without parsing log noise. The `commit-classified`, `phase-emitted`, `commit-skipped-empty-diff`, and `validation-failed` event schemas are defined in `contracts/observability-events.md`. Every event includes `level`, `timestamp` (ISO-8601 UTC), and `event` plus event-specific fields. SC-011 verifies the stderr stream is parseable as JSON lines end-to-end.

### D-012: Status File Reused Across Failure Modes With a stage Field

`<FEATURE_DIR>/phase-creation-status.yaml` is reused by both the phaser engine (FR-042) and the stacked-PR creator (FR-039). A required top-level `stage` field (`phaser-engine` or `stacked-pr-creation`) distinguishes which subsystem failed. This single-file convention reduces operator cognitive load — there is exactly one place to look after any phaser-related failure. The file is deleted on full success of the failing stage (FR-040).

### D-013: Hard Size Bounds Enforced Before Manifest Write (FR-048)

`size_guard.rb` runs after empty-diff filtering (FR-009) but before classification. If non-empty commit count > 200 or projected phase count > 50 (computed by simulating the worst-case grouping), the engine fails fast, emits exactly one `validation-failed` ERROR record with `failing_rule: feature-too-large`, persists the same payload to the status file with `stage: phaser-engine`, and exits non-zero. No manifest is written. SC-014 verifies both bounds.

### D-014: Flavor-Init Stack Detection Via Per-Flavor Signal Declarations (FR-031)

Each shipped flavor's `flavor.yaml` declares its own stack-detection signals (e.g., for the Rails flavor: presence of `Gemfile.lock` containing `pg`, plus `strong_migrations`). `flavor-init` iterates shipped flavors, runs each one's signals against the project, and counts matches. Exactly one match → suggest that flavor (FR-032). Zero matches → "no flavor matched" (FR-033). More than one match → ambiguity error listing the matching flavors (an edge case not explicitly in the spec but a natural consequence of a multi-flavor world; documented in the flavor-init contract). Existing `.specify/flavor.yaml` → refuse unless `--force` (FR-034).

### D-015: Setup Script Installs phaser/bin Entry Points

`setup.sh` is modified to install `phaser/bin/phaser`, `phaser/bin/phaser-stacked-prs`, and `phaser/bin/phaser-flavor-init` to a PATH-resolved location (or symlink them from a stable location), and to copy `speckit.phaser.md`, `speckit.flavor.init.md`, and `phaser.md` to the installed `.claude/` directories. The existing source-vs-installed convention is preserved (CLAUDE.md "Source vs Installed Files" section).

### D-016: Engine Exposes No Bypass Mechanism for the Forbidden-Operations Gate

Per FR-049's explicit prohibition, the engine code MUST NOT contain any flag, environment variable, commit-message trailer, or configuration option that lets an operator suppress the forbidden-operations gate. This is enforced by both code review and a regression test that greps the engine source for credential-style bypass patterns and asserts the bypass surface is empty. The only way to add a forbidden operation back as a permitted task is to remove it from the flavor's registry — a deliberate flavor-edit action that goes through normal review.

## Complexity Tracking

No constitution violations to justify — all applicable principles pass.

The Spec & Branch Naming "PASS with note" entry above is acknowledgement of a pre-existing branch-naming condition inherited before this plan began; it is not a new violation introduced by this design and is outside this plan's scope to repair.
