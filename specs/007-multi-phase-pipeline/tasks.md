---
description: "Dependency-ordered task list for the Multi-Phase Pipeline feature"
---

# Tasks: Multi-Phase Pipeline for SpecKit Simpsons

**Input**: Design documents from `/home/jama/Projects/spec-kit-simpsons-loops/specs/007-multi-phase-pipeline/`
**Prerequisites**: plan.md (loaded), spec.md (loaded), research.md (loaded), data-model.md (loaded), contracts/ (loaded), quickstart.md (loaded)

**Tests**: Test tasks ARE included. The project constitution (`CLAUDE.md`) mandates Test-First Development for all new logic, and the spec/plan list explicit RSpec regression tests for every Success Criterion (SC-001..SC-015).

**Organization**: Tasks are grouped by user story (US1..US5) so each story can be implemented and tested independently. Within each story, tests are written first, then implementation.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story (US1..US5); omitted for Setup, Foundational, and Polish phases
- All file paths are absolute and rooted under `/home/jama/Projects/spec-kit-simpsons-loops/`

## Path Conventions

- Ruby phaser code: `phaser/` at repo root (per plan.md "Project Structure")
- SpecKit command source-of-truth: `speckit-commands/` (installed copies live in `.claude/commands/`)
- SpecKit agent source-of-truth: `claude-agents/` (installed copies live in `.claude/agents/`)
- Always edit source files; never the installed `.claude/` copies (per CLAUDE.md "Source vs Installed Files")

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create the empty `phaser/` Ruby project skeleton that every subsequent task builds on.

- [x] T001 Create `phaser/` directory layout per plan.md (`phaser/bin/`, `phaser/lib/phaser/`, `phaser/lib/phaser/stacked_prs/`, `phaser/lib/phaser/flavor_init/`, `phaser/flavors/`, `phaser/spec/`, `phaser/spec/fixtures/repos/`, `phaser/spec/fixtures/flavors/`, `phaser/spec/fixtures/classification/`, `phaser/spec/support/`) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/`
- [x] T002 Create `phaser/Gemfile` declaring Ruby 3.2+ and dev dependencies (`rspec`, `rubocop`, `psych`) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/Gemfile`
- [x] T003 [P] Create `phaser/Rakefile` with `rake test` (runs `bundle exec rspec`) and `rake lint` (runs `bundle exec rubocop`) tasks at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/Rakefile`
- [x] T004 [P] Create `phaser/.rubocop.yml` adopting community defaults at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/.rubocop.yml`
- [x] T005 [P] Create `phaser/spec/spec_helper.rb` and `phaser/spec/support/git_fixture_helper.rb` (loads `Phaser::`, configures RSpec, exposes `make_fixture_repo` helper) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/spec/spec_helper.rb` and `/home/jama/Projects/spec-kit-simpsons-loops/phaser/spec/support/git_fixture_helper.rb`
- [x] T006 Run `bundle install` inside `/home/jama/Projects/spec-kit-simpsons-loops/phaser/` to generate `phaser/Gemfile.lock`
- [x] T007 [P] Create `phaser/lib/phaser/version.rb` defining `Phaser::VERSION = '0.1.0'` at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/lib/phaser/version.rb`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core types, the value-object surface, the schema-validated flavor loader, and the stable-key-order YAML manifest writer. Every user story depends on these.

**CRITICAL**: No user story work begins until this phase is complete.

- [x] T008 [P] Write RSpec test for `Phaser::Commit`, `Phaser::Diff`, `Phaser::FileChange` value objects (constructible with required fields, immutable, `empty?` returns true on zero-file diff per FR-009) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/spec/value_objects_spec.rb`
- [x] T009 [P] Write RSpec test for `Phaser::ClassificationResult`, `Phaser::Phase`, `Phaser::Task`, `Phaser::PhaseManifest` value objects (per data-model.md field tables) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/spec/manifest_value_objects_spec.rb`
- [x] T010 Implement `Phaser::Commit`, `Phaser::Diff`, `Phaser::FileChange` using `Data.define` (Ruby 3.2+) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/lib/phaser/commit.rb`, `/home/jama/Projects/spec-kit-simpsons-loops/phaser/lib/phaser/diff.rb`, `/home/jama/Projects/spec-kit-simpsons-loops/phaser/lib/phaser/file_change.rb` — make T008 pass
- [x] T011 Implement `Phaser::ClassificationResult`, `Phaser::Phase`, `Phaser::Task`, `Phaser::PhaseManifest` using `Data.define` at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/lib/phaser/classification_result.rb`, `/home/jama/Projects/spec-kit-simpsons-loops/phaser/lib/phaser/phase.rb`, `/home/jama/Projects/spec-kit-simpsons-loops/phaser/lib/phaser/task.rb`, `/home/jama/Projects/spec-kit-simpsons-loops/phaser/lib/phaser/phase_manifest.rb` — make T009 pass
- [x] T012 [P] Write RSpec test for `Phaser::Observability` JSON-line stderr logger (asserts INFO/WARN/ERROR records emit one JSON object per line with `level`, `timestamp`, `event`; asserts no output goes to stdout per FR-043; verifies all event-type schemas from `contracts/observability-events.md`) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/spec/observability_spec.rb`
- [x] T013 Implement `Phaser::Observability` (single-clock injection point for `timestamp`, JSON-lines emit to stderr only, methods `log_commit_classified`, `log_phase_emitted`, `log_commit_skipped_empty_diff`, `log_validation_failed`) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/lib/phaser/observability.rb` — make T012 pass
- [x] T014 [P] Write RSpec test for `Phaser::ManifestWriter` (asserts byte-identical YAML output across 100 consecutive runs per SC-002; asserts fixed key ordering per FR-038; asserts atomic write via temp file + rename per quickstart.md "Pattern: Manifest Writer") at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/spec/manifest_writer_spec.rb`
- [x] T015 Implement `Phaser::ManifestWriter` (builds explicitly ordered Hash matching `contracts/phase-manifest.schema.yaml`, calls `Psych.dump(hash, line_width: -1, header: false)`, writes atomically) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/lib/phaser/manifest_writer.rb` — make T014 pass
- [x] T016 [P] Write RSpec test for `Phaser::StatusWriter` (asserts `phase-creation-status.yaml` is written with stable key ordering, `stage` discriminator, all field combinations from `contracts/phase-creation-status.schema.yaml`; asserts `delete_if_present` removes the file; asserts no credential-shaped substrings ever appear per FR-047) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/spec/status_writer_spec.rb`
- [x] T017 Implement `Phaser::StatusWriter` (`write(stage:, failure_class:, **payload)` and `delete_if_present(path)` methods) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/lib/phaser/status_writer.rb` — make T016 pass
- [x] T018 [P] Write RSpec test for `Phaser::FlavorLoader` schema validation against `contracts/flavor.schema.yaml` (asserts well-formed flavors load; malformed flavors raise descriptive errors at load time per data-model.md "Validation rules"; asserts unknown-flavor-name from `.specify/flavor.yaml` produces a clear error listing shipped flavors) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/spec/flavor_loader_spec.rb`
- [x] T019 Implement `Phaser::FlavorLoader` (reads `phaser/flavors/<name>/flavor.yaml`, validates against schema, requires referenced Ruby modules, returns a `Phaser::Flavor` value object) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/lib/phaser/flavor_loader.rb` — make T018 pass
- [x] T020 Create top-level loader `Phaser` module at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/lib/phaser.rb` requiring all foundational files (commit, diff, file_change, classification_result, phase, task, phase_manifest, observability, manifest_writer, status_writer, flavor_loader, version)

**Checkpoint**: Foundational layer ready — user story implementation can now begin in parallel.

---

## Phase 3: User Story 1 - Phaser Engine Validates and Splits Tasks Using a Pluggable Flavor (Priority: P1) MVP

**Goal**: A pure-Ruby, flavor-agnostic phaser engine that consumes `(commits, flavor)` and produces a deterministic `phase-manifest.yaml`, with a toy `example-minimal` flavor that proves no domain knowledge leaks into the engine.

**Independent Test**: Run `phaser/bin/phaser` against a synthetic feature branch with the `example-minimal` flavor; verify the manifest is byte-identical across runs, that precedent and isolation rules are honored, that an untagged commit is assigned the flavor's default type, and that `grep -REni 'rails|activerecord|postgres|strong_migrations|migration|gemfile' phaser/lib/` returns zero hits.

### Tests for User Story 1 (Test-First — write and observe failure before implementing)

- [x] T021 [P] [US1] Write RSpec test for `Phaser::Classifier` operator-tag → inference → default cascade (FR-004; asserts operator tag wins over inference; asserts inference wins over default; asserts unknown operator tag raises with `failing_rule: unknown-type-tag` per FR-007 and data-model.md error table) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/spec/classifier_spec.rb`
- [x] T022 [P] [US1] Write RSpec test for `Phaser::ForbiddenOperationsGate` (FR-049 pre-classification gate; asserts gate runs before classifier; asserts no flag/env-var/trailer can suppress per D-016; asserts `validation-failed` ERROR record + status-file payload format) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/spec/forbidden_operations_gate_spec.rb`
- [x] T023 [P] [US1] Write RSpec test for `Phaser::PrecedentValidator` (FR-006; asserts subject task in strictly later phase than predecessor; asserts missing predecessor produces `validation-failed` ERROR naming offending commit and missing predecessor) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/spec/precedent_validator_spec.rb`
- [x] T024 [P] [US1] Write RSpec test for `Phaser::IsolationResolver` (FR-005; asserts `alone` tasks get own phase; asserts `groups` tasks may share a phase subject to precedent rules; asserts deterministic phase ordering with commit-hash tie-breaker per R-005) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/spec/isolation_resolver_spec.rb`
- [x] T025 [P] [US1] Write RSpec test for `Phaser::SizeGuard` (FR-048; asserts >200 non-empty commits triggers `feature-too-large` rejection before any manifest write; asserts >50 projected phases triggers same rejection; asserts empty-diff commits per FR-009 do not count toward bound; verifies SC-014) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/spec/size_guard_spec.rb`
- [x] T026 [US1] Write RSpec test for `Phaser::Engine#process` integration (asserts full pipeline: empty-diff filter → forbidden-ops gate → classifier → precedent validator → isolation resolver → manifest writer; asserts non-empty commits per FR-009; asserts deterministic output; asserts `phase-emitted` and `commit-classified` log records per SC-011) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/spec/engine_spec.rb`
- [x] T027 [P] [US1] Write RSpec regression test for no-domain-leakage (greps every file under `phaser/lib/phaser/` and `phaser/bin/` for `Rails`, `ActiveRecord`, `Postgres`, `postgresql`, `strong_migrations`, `migration`, `pg`, `Gemfile`; excludes `phaser/flavors/`; asserts zero hits per SC-003 and R-006) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/spec/engine_no_domain_leakage_spec.rb`
- [x] T028 [P] [US1] Write RSpec test for `phaser/bin/phaser` CLI contract (per `contracts/phaser-cli.md`; asserts stdout receives manifest path on success; asserts stderr receives JSON-line logs per FR-043; asserts non-zero exit on validation failure) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/spec/bin/phaser_cli_spec.rb`
- [x] T029 [P] [US1] Create synthetic Git fixture repo for example-minimal engine tests (5 commits exercising both task types, precedent rule, and a non-matching commit that gets the default type) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/spec/fixtures/repos/example-minimal/` (built via `git_fixture_helper.rb`)

### Implementation for User Story 1

- [x] T030 [P] [US1] Implement `Phaser::Classifier` (operator-tag from commit-message trailer wins; then inference rules in declared precedence order with alphabetical tie-break per FR-036; then `default_type` per FR-004) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/lib/phaser/classifier.rb` — make T021 pass
- [x] T031 [P] [US1] Implement `Phaser::ForbiddenOperationsGate` (`evaluate(commit)` returns the matching detector or nil; raises `Phaser::ForbiddenOperationError` carrying detector name, identifier, and decomposition_message; NO bypass mechanism per D-016) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/lib/phaser/forbidden_operations_gate.rb` — make T022 pass
- [x] T032 [P] [US1] Implement `Phaser::PrecedentValidator` (validates classified-commit list against flavor's precedent rules; raises `Phaser::PrecedentError` naming offending commit and missing predecessor) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/lib/phaser/precedent_validator.rb` — make T023 pass
- [x] T033 [P] [US1] Implement `Phaser::IsolationResolver` (groups commits into ordered phases honoring `alone`/`groups` and precedent rules; commit-hash tie-breaker for determinism) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/lib/phaser/isolation_resolver.rb` — make T024 pass
- [x] T034 [P] [US1] Implement `Phaser::SizeGuard` (counts non-empty commits, simulates worst-case phase projection, raises `Phaser::SizeBoundError` with `commit_count`/`phase_count` payload before any manifest write) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/lib/phaser/size_guard.rb` — make T025 pass
- [x] T035 [US1] Implement `Phaser::Engine#process(feature_branch_commits, flavor)` orchestrating the call sequence per quickstart.md "Pattern: Pre-Classification Gate Discipline": empty-diff filter → forbidden-ops gate → classifier → precedent validator → size guard → isolation resolver → manifest writer. On any error, persist payload via `StatusWriter` with `stage: phaser-engine` per FR-042. At `/home/jama/Projects/spec-kit-simpsons-loops/phaser/lib/phaser/engine.rb` — make T026 pass
- [x] T036 [US1] Implement `phaser/bin/phaser` CLI entry point (parses args via OptionParser per `contracts/phaser-cli.md`; reads commits from `git log` of the feature branch; loads flavor via `FlavorLoader`; invokes `Engine`; writes manifest path to stdout on success) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/bin/phaser` (chmod +x) — make T028 pass
- [x] T037 [P] [US1] Author `phaser/flavors/example-minimal/flavor.yaml` (two task types, one precedent rule, one inference rule, default type, version) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/flavors/example-minimal/flavor.yaml`
- [x] T038 [P] [US1] Author `phaser/flavors/example-minimal/inference.rb` (single pattern-matcher method referenced by the YAML inference rule) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/flavors/example-minimal/inference.rb`
- [x] T039 [US1] Add 100-iteration determinism check to `phaser/spec/manifest_writer_spec.rb` exercising the example-minimal fixture (verifies SC-002 end-to-end through the engine, not just the writer) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/spec/manifest_writer_spec.rb`

**Checkpoint**: User Story 1 fully functional. The engine, the example-minimal flavor, and the standalone CLI all work; SC-002, SC-003, SC-014, SC-011 (engine portion) all green.

---

## Phase 4: User Story 2 - Reference Flavor for Rails + Postgres + strong_migrations (Priority: P2)

**Goal**: A complete reference flavor with the full deploy-safety task catalog, file-pattern inference, backfill-safety validator, precedent validator, and forbidden-operations registry that decomposes unsafe operations into safe sequences.

**Independent Test**: Run the phaser stage against fixtures exercising every catalog type, every forbidden operation, and the column-rename worked example; verify every fixture is classified correctly, every forbidden operation is rejected with the canonical decomposition message, every backfill-safety violation is caught, and the column-rename example produces exactly seven ordered phases without operator intervention (FR-017, SC-001).

### Tests for User Story 2

- [x] T040 [P] [US2] Write RSpec test for the reference flavor's catalog completeness (asserts every task type listed in FR-010 is present in `flavor.yaml` with the isolation declared in FR-011) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/spec/flavors/rails_postgres_strong_migrations/catalog_spec.rb`
- [x] T041 [P] [US2] Write RSpec test for the reference flavor's file-pattern inference layer (≥90% of fixture commits classified correctly without operator tags per SC-004; FR-012) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/spec/flavors/rails_postgres_strong_migrations/inference_spec.rb`
- [x] T042 [P] [US2] Write RSpec test for the reference flavor's backfill-safety validator (FR-013; rejects commits lacking batching, throttling, or `disable_ddl_transaction!`; error names the missing safeguard) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/spec/flavors/rails_postgres_strong_migrations/backfill_validator_spec.rb`
- [x] T043 [P] [US2] Write RSpec test for the reference flavor's column-drop precedent validator (FR-014; rejects column-drop without prior `ignore` directive AND prior reference-removal; error names both missing precedents) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/spec/flavors/rails_postgres_strong_migrations/precedent_validator_spec.rb`
- [x] T044 [P] [US2] Write RSpec test for the reference flavor's forbidden-operations registry (FR-015; SC-005: every entry has a regression test producing the canonical decomposition message; covers direct column-type change, direct rename, non-concurrent index, direct not-null add, direct foreign-key add, column add with volatile default, column drop without code cleanup) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/spec/flavors/rails_postgres_strong_migrations/forbidden_operations_spec.rb`
- [x] T045 [P] [US2] Write RSpec test for SC-015 (operator-tag-cannot-bypass-gate): pair every entry in the registry with a commit carrying an operator tag naming a different valid type; assert the gate still rejects each one at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/spec/flavors/rails_postgres_strong_migrations/operator_tag_cannot_bypass_gate_spec.rb`
- [x] T046 [US2] Write RSpec test for the column-rename worked example (FR-017; loads the seven-commit fixture and asserts exactly seven ordered phases per SC-001 and R-016) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/spec/flavors/rails_postgres_strong_migrations/column_rename_worked_example_spec.rb`
- [x] T046b [P] [US2] Write RSpec test for the reference flavor's safety-assertion-block validator (FR-018, plan.md D-017): for every irreversible task type declared by the flavor (column drop, table drop, concurrent index drop, remove ignored-columns directive), assert (a) a commit lacking a `Safety-Assertion:` trailer or fenced safety-assertion block is rejected with `validation-failed` ERROR `failing_rule: safety-assertion-missing` naming the offending commit; (b) a commit whose assertion cites a SHA that is not a valid precedent (per the flavor's precedent rules) is rejected with `failing_rule: safety-assertion-precedent-mismatch` naming the offending commit and the cited SHA; (c) a commit whose assertion correctly cites the precedent commit is accepted and the cited SHA is recorded on the manifest's task entry for audit at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/spec/flavors/rails_postgres_strong_migrations/safety_assertion_validator_spec.rb`
- [x] T047 [P] [US2] Create per-type classification fixture set (one or more commits per task type listed in FR-010; used by T041's inference test) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/spec/fixtures/classification/rails_postgres_strong_migrations/`
- [x] T048 [P] [US2] Create the seven-commit Git fixture repo for the column-rename worked example (per R-016: add nullable column → ignored-columns directive → dual-write → batched throttled backfill → switch reads → remove references → remove ignore directive AND drop column) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/spec/fixtures/repos/users-email-rename/` (built via `git_fixture_helper.rb`)
- [x] T049 [P] [US2] Create forbidden-operation fixture commits (one commit per registry entry, plus operator-tag-bypass-attempt variants for SC-015) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/spec/fixtures/classification/rails_postgres_strong_migrations_forbidden/`

### Implementation for User Story 2

- [x] T050 [US2] Author `phaser/flavors/rails-postgres-strong-migrations/flavor.yaml` declaring every task type from FR-010 with isolation per FR-011, all inference rules, the precedent rule for column-drop, the forbidden-operations registry with canonical decomposition messages, stack-detection signals (per R-015), and version `0.1.0` at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/flavors/rails-postgres-strong-migrations/flavor.yaml` — make T040 pass
- [x] T051 [P] [US2] Implement `Phaser::Flavors::RailsPostgresStrongMigrations::Inference` pattern-matcher methods (file-glob, content-regex, and AST-aware checks via Prism for migration detection) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/flavors/rails-postgres-strong-migrations/inference.rb` — make T041 pass
- [x] T052 [P] [US2] Implement `Phaser::Flavors::RailsPostgresStrongMigrations::ForbiddenOperations` detector methods (one per registry entry; each returns a stable identifier and the canonical decomposition message) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/flavors/rails-postgres-strong-migrations/forbidden_operations.rb` — make T044 and T045 pass
- [x] T053 [P] [US2] Implement `Phaser::Flavors::RailsPostgresStrongMigrations::BackfillValidator` (rejects backfill rake tasks lacking `find_each`/`in_batches` AND a sleep-throttle AND `disable_ddl_transaction!`; rejection error names the missing safeguard) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/flavors/rails-postgres-strong-migrations/backfill_validator.rb` — make T042 pass
- [x] T054 [P] [US2] Implement `Phaser::Flavors::RailsPostgresStrongMigrations::PrecedentValidator` for column-drop (asserts the dropped column has prior `ignored_columns` directive commit AND prior reference-removal commit; error names both missing precedents per FR-014) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/flavors/rails-postgres-strong-migrations/precedent_validator.rb` — make T043 pass
- [x] T054b [P] [US2] Implement `Phaser::Flavors::RailsPostgresStrongMigrations::SafetyAssertionValidator` (FR-018, plan.md D-017): consume the flavor's `irreversible_task_types` list from `flavor.yaml`; for each classified commit whose type is in that list, parse the commit message for a `Safety-Assertion:` trailer or fenced ` ```safety-assertion ` block; verify each cited 40-char SHA refers to an earlier commit on the feature branch whose classified type is one of the precedent types declared by the flavor for the subject type; raise `Phaser::SafetyAssertionError` with `failing_rule: safety-assertion-missing` (no block at all) or `safety-assertion-precedent-mismatch` (cited SHA is not a valid precedent), naming the offending commit and the cited SHAs; on success, attach the cited SHAs to the corresponding `Task` entry so they are persisted in the manifest for audit at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/flavors/rails-postgres-strong-migrations/safety_assertion_validator.rb` — make T046b pass
- [x] T055 [US2] Wire the reference flavor's optional Ruby modules (`inference_module`, `forbidden_module`, `validators` list — including `safety_assertion_validator` per T054b) through `flavor_loader.rb` so the engine resolves and invokes them per the YAML declarations — extend `/home/jama/Projects/spec-kit-simpsons-loops/phaser/lib/phaser/flavor_loader.rb` and re-run T018, T040..T046b to confirm no regressions

**Checkpoint**: User Story 2 fully functional. Reference flavor classifies every catalog entry; SC-001, SC-004, SC-005, SC-015 green; FR-018 audit-trail safety-assertion-block validator green; the column-rename example produces exactly seven phases without operator input.

---

## Phase 5: User Story 3 - Phaser Integrated as a Real Pipeline Stage with Per-Phase and Holistic Review (Priority: P3)

**Goal**: The phaser slots into the SpecKit pipeline as a normal stage between ralph (implement) and marge (review). Marge runs once per phase scoped to that phase's diff range, then once holistically. With no flavor file present, behavior is byte-identical to today.

**Independent Test**: Run the full pipeline on a feature branch in a project with the Rails flavor configured; verify phase manifest committed to the spec directory, per-phase review passes observable, holistic review pass runs after per-phase passes. Then delete the flavor configuration and re-run on a different branch; verify behavior matches pre-feature pipeline byte-for-byte (SC-006).

### Tests for User Story 3

- [x] T056 [P] [US3] Write RSpec test for the no-flavor zero-regression contract (captures pipeline output on a fixture branch with no `.specify/flavor.yaml`; asserts byte-identical match against a stored baseline per SC-006) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/spec/pipeline_no_flavor_baseline_spec.rb`
- [x] T057 [P] [US3] Write a shellcheck-validated test scaffold that exercises the pipeline command's flavor-file detection branch (asserts the `test -f .specify/flavor.yaml` gate per quickstart.md "Pattern: Conditional Pipeline Behavior") at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/spec/pipeline_flavor_gate_spec.rb`

### Implementation for User Story 3

- [x] T058 [US3] Author `claude-agents/phaser.md` single-shot agent file (invokes `phaser/bin/phaser` via Bash, captures manifest path from stdout, commits the manifest to the feature branch, returns; on non-zero exit propagates failure to the pipeline per FR-024) at `/home/jama/Projects/spec-kit-simpsons-loops/claude-agents/phaser.md`
- [x] T059 [US3] Author `speckit-commands/speckit.phaser.md` command file wrapping the phaser agent (per FR-019) at `/home/jama/Projects/spec-kit-simpsons-loops/speckit-commands/speckit.phaser.md`
- [x] T060 [US3] Modify `speckit-commands/speckit.marge.review.md` to accept `--phase <N>` argument; when present, read `<FEATURE_DIR>/phase-manifest.yaml`, resolve phase N's `branch_name` and `base_branch`, and scope the review to `git diff <base_branch>...<branch_name>` (FR-022, R-012); when absent, review the full feature diff at `/home/jama/Projects/spec-kit-simpsons-loops/speckit-commands/speckit.marge.review.md`
- [x] T061 [US3] Modify `speckit-commands/speckit.pipeline.md` to (a) check `test -f .specify/flavor.yaml` immediately after pre-flight; (b) when present, insert the phaser step **after** the existing simplify/security-review polish phases and **before** marge per FR-019 and per plan.md D-008 (so the order becomes `ralph → simplify → security-review → phaser → marge`), so that any commits created by the polish phases are classified into the manifest rather than left unclassified on the branch; (c) invoke marge `N+1` times per FR-023 (once per phase with `--phase N`, then once holistically); (d) when absent, skip phaser and run marge once holistically per FR-025; (e) halt the pipeline without invoking marge if phaser fails per FR-024 at `/home/jama/Projects/spec-kit-simpsons-loops/speckit-commands/speckit.pipeline.md`
- [x] T062 [US3] Modify `setup.sh` to copy `claude-agents/phaser.md` to `.claude/agents/phaser.md`, `speckit-commands/speckit.phaser.md` to `.claude/commands/speckit.phaser.md`, and re-copy the modified `speckit.pipeline.md` and `speckit.marge.review.md` to their installed locations (preserves source-vs-installed convention) at `/home/jama/Projects/spec-kit-simpsons-loops/setup.sh`
- [x] T063 [US3] Run `bash setup.sh` from repo root to refresh `.claude/agents/phaser.md`, `.claude/commands/speckit.phaser.md`, `.claude/commands/speckit.pipeline.md`, and `.claude/commands/speckit.marge.review.md` from their source-of-truth files
- [x] T064 [US3] Capture the no-flavor pipeline baseline output for SC-006's regression test (run pipeline on the example-minimal fixture branch with `.specify/flavor.yaml` absent; store the captured stdout/stderr under `phaser/spec/fixtures/baselines/pipeline-no-flavor.txt`) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/spec/fixtures/baselines/pipeline-no-flavor.txt` — make T056 pass

**Checkpoint**: User Story 3 fully functional. With flavor present, marge runs N+1 times; without it, output is byte-identical to baseline (SC-006); SC-008 (precise error messages) verified through the engine error chain.

---

## Phase 6: User Story 4 - Stacked Branches and Stacked Pull Requests Auto-Created from the Phase Manifest (Priority: P4)

**Goal**: After the phaser produces a manifest, stacked branches and PRs are auto-created. Authentication is delegated entirely to the operator's `gh` CLI. Failures partway through are recoverable via idempotent re-runs. No log line or status file ever contains credential material.

**Independent Test**: Run the phaser stage with stacked-PR creation enabled on a multi-phase feature; verify expected branches exist with correct base relationships, one PR per phase with rationale and rollback plan, dependency links between PRs, independent CI per branch, and clean recovery from injected mid-run failures (SC-010, SC-012, SC-013).

### Tests for User Story 4

- [x] T065 [P] [US4] Write RSpec test for `Phaser::StackedPrs::AuthProbe` (FR-045; asserts exactly one `gh auth status` invocation per run; asserts fail-fast on `auth-missing` with status file `failure_class: auth-missing`, `first_uncreated_phase: 1` per SC-012; asserts fail-fast on `auth-insufficient-scope`) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/spec/stacked_prs/auth_probe_spec.rb`
- [x] T066 [P] [US4] Write RSpec test for `Phaser::StackedPrs::FailureClassifier` (FR-046; asserts each `gh` exit code/stderr maps to the correct `failure_class`: `auth-missing`, `auth-insufficient-scope`, `rate-limit`, `network`, `other`) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/spec/stacked_prs/failure_classifier_spec.rb`
- [x] T067 [P] [US4] Write RSpec test for `Phaser::StackedPrs::GitHostCli` subprocess wrapper (asserts `Open3.capture3('gh', ...)` is the only `gh` invocation path per quickstart.md "Pattern: gh Subprocess Wrapper"; asserts no env-var token reads; asserts stderr-credential sanitization) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/spec/stacked_prs/git_host_cli_spec.rb`
- [x] T068 [P] [US4] Write RSpec test for `Phaser::StackedPrs::Creator` idempotency (SC-010; injects failure between phase K and phase K+1 of an N-phase manifest; asserts phases 1..K untouched, status file written with `first_uncreated_phase: K+1`; re-run completes phases K+1..N and deletes status file per FR-040) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/spec/stacked_prs/creator_spec.rb`
- [x] T069 [P] [US4] Write RSpec test for `phaser/bin/phaser-stacked-prs` CLI contract (per `contracts/stacked-pr-creator-cli.md`) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/spec/bin/phaser_stacked_prs_cli_spec.rb`
- [x] T070 [P] [US4] Write the credential-leak regression test (SC-013; scans every log line and every byte of every `phase-creation-status.yaml` produced by failure-mode fixtures for `ghp_`, `gho_`, `ghu_`, `ghs_`, `ghr_`, `Bearer `, base64 cookie patterns; asserts zero matches; verifies FR-047) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/spec/credential_leak_scan_spec.rb`
- [x] T071 [P] [US4] Write a grep-based regression test asserting `phaser/lib/` contains no direct `system('gh ...')` or backtick-`gh` calls — the only `gh` invocation path is `Phaser::StackedPrs::GitHostCli` (per quickstart.md "Pattern: gh Subprocess Wrapper") at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/spec/stacked_prs/gh_invocation_isolation_spec.rb`

### Implementation for User Story 4

- [x] T072 [P] [US4] Implement `Phaser::StackedPrs::GitHostCli` (single `Open3.capture3('gh', *args)` wrapper; sanitizes stderr first line for credential patterns before returning to callers; never additions/removals to subprocess env) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/lib/phaser/stacked_prs/git_host_cli.rb` — make T067 pass
- [x] T073 [US4] Implement `Phaser::StackedPrs::FailureClassifier` (maps `gh` exit codes and stderr substrings to one of `auth-missing`, `auth-insufficient-scope`, `rate-limit`, `network`, `other`; never inspects token values) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/lib/phaser/stacked_prs/failure_classifier.rb` — make T066 pass
- [x] T074 [US4] Implement `Phaser::StackedPrs::AuthProbe` (single `gh auth status` invocation; caches result for the run; on failure writes `phase-creation-status.yaml` with `stage: stacked-pr-creation`, the classified `failure_class`, and `first_uncreated_phase: 1`; exits non-zero before any branch creation) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/lib/phaser/stacked_prs/auth_probe.rb` — make T065 pass
- [x] T075 [US4] Implement `Phaser::StackedPrs::Creator` (reads `phase-manifest.yaml`; for each phase, queries `gh` for branch and PR existence; skips phases whose branch+PR already exist with correct base; resumes at first uncreated phase; on full success deletes `phase-creation-status.yaml` per FR-040; on failure writes status file with `stage: stacked-pr-creation`, `failure_class`, `first_uncreated_phase: K+1` per FR-039) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/lib/phaser/stacked_prs/creator.rb` — make T068 pass
- [x] T076 [US4] Implement `phaser/bin/phaser-stacked-prs` CLI entry point (per `contracts/stacked-pr-creator-cli.md`; parses `--feature-dir`, invokes `AuthProbe` then `Creator`) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/bin/phaser-stacked-prs` (chmod +x) — make T069 pass
- [x] T077 [US4] Modify `speckit-commands/speckit.pipeline.md` to invoke `phaser/bin/phaser-stacked-prs` after marge succeeds across all phases; gated on the same `.specify/flavor.yaml` check that gates the phaser stage at `/home/jama/Projects/spec-kit-simpsons-loops/speckit-commands/speckit.pipeline.md`
- [x] T078 [US4] Re-run `bash setup.sh` to refresh the installed `.claude/commands/speckit.pipeline.md` from the modified source

**Checkpoint**: User Story 4 fully functional. SC-009 (manifest predicts PR set), SC-010 (idempotent resume), SC-012 (auth-missing fail-fast), SC-013 (credential-leak-free) green.

---

## Phase 7: User Story 5 - One-Shot Flavor Initialization Command (Priority: P5)

**Goal**: A maintainer can opt a project into phasing with a single command and one confirmation.

**Independent Test**: Run the command in three repositories: a Rails+Postgres+strong_migrations project (suggests rails flavor, writes `.specify/flavor.yaml` on confirmation), a project with no recognizable stack (`no flavor matched`), and a project that already has a flavor configuration (refusal-to-overwrite by default; success with `--force`).

### Tests for User Story 5

- [x] T079 [P] [US5] Write RSpec test for `Phaser::FlavorInit::StackDetector` (FR-031; iterates shipped flavors, evaluates each one's `stack_detection.signals` per data-model.md StackDetection table; returns matching flavor list) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/spec/flavor_init/stack_detector_spec.rb`
- [x] T080 [P] [US5] Write RSpec test for `phaser/bin/phaser-flavor-init` CLI per `contracts/flavor-init-cli.md` (FR-032 single-match → suggest + confirm + write; FR-033 zero-match → `no flavor matched` non-zero; FR-034 existing file → refuse without `--force`, overwrite with; R-015 multi-match → list and instruct `--flavor <name>`) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/spec/bin/phaser_flavor_init_cli_spec.rb`

### Implementation for User Story 5

- [x] T081 [US5] Implement `Phaser::FlavorInit::StackDetector` (loads each shipped flavor's stack-detection signals via `FlavorLoader`, evaluates `file_present` and `file_contains` checks against the project root, returns the list of matching flavors) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/lib/phaser/flavor_init/stack_detector.rb` — make T079 pass
- [x] T082 [US5] Implement `phaser/bin/phaser-flavor-init` CLI entry point (parses `--force` and optional `--flavor <name>`; invokes `StackDetector`; prompts for confirmation on single match; writes `.specify/flavor.yaml` with the chosen flavor name; refuses to overwrite without `--force`) at `/home/jama/Projects/spec-kit-simpsons-loops/phaser/bin/phaser-flavor-init` (chmod +x) — make T080 pass
- [x] T083 [US5] Author `speckit-commands/speckit.flavor.init.md` command file wrapping `phaser/bin/phaser-flavor-init` for the SpecKit command surface at `/home/jama/Projects/spec-kit-simpsons-loops/speckit-commands/speckit.flavor.init.md`
- [x] T084 [US5] Modify `setup.sh` to also copy `speckit-commands/speckit.flavor.init.md` to `.claude/commands/speckit.flavor.init.md` and to install the `phaser/bin/phaser-flavor-init` entry point per R-017 at `/home/jama/Projects/spec-kit-simpsons-loops/setup.sh`
- [x] T085 [US5] Re-run `bash setup.sh` from repo root to install `.claude/commands/speckit.flavor.init.md` and the new `phaser/bin/` entry point

**Checkpoint**: User Story 5 fully functional. SC-007 (one-command opt-in) green.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Quality-gate wiring, documentation, and final verification across all stories.

- [x] T086 [P] Update `.specify/quality-gates.sh` to run `(cd phaser && bundle exec rspec)` and `(cd phaser && bundle exec rubocop)` gated on `phaser/` directory existence per R-018 at `/home/jama/Projects/spec-kit-simpsons-loops/.specify/quality-gates.sh`
- [x] T087 [P] Run `bash .specify/scripts/bash/update-agent-context.sh claude` to refresh the active-technologies entry in `CLAUDE.md` for Ruby 3.2+, RSpec, rubocop per quickstart.md Phase 6 at `/home/jama/Projects/spec-kit-simpsons-loops/CLAUDE.md`
- [x] T088 [P] Run `bundle exec rubocop -A` inside `/home/jama/Projects/spec-kit-simpsons-loops/phaser/` to auto-correct any style issues, then re-run `bundle exec rubocop` and assert exit 0
- [x] T089 [P] Run `shellcheck` against the modified `setup.sh` and `.specify/quality-gates.sh` and assert zero errors
- [x] T090 Run `bash .specify/quality-gates.sh` from `/home/jama/Projects/spec-kit-simpsons-loops/` and assert exit 0 (verifies all tests pass and lint is clean across both Bash and Ruby surfaces)
- [x] T091 Walk the verification checklist in `/home/jama/Projects/spec-kit-simpsons-loops/specs/007-multi-phase-pipeline/quickstart.md` end-to-end and tick each box; on any failure, file a follow-up task and resolve before declaring complete
- [x] T092 Verify process hygiene per CLAUDE.md "Process Hygiene": `ps aux | grep phaser` is clean; `ps aux | grep rspec` is clean; `docker ps` is clean (no leftover containers from any test run); no orphan dev servers from this session
- [x] T093 Verify `setup.sh` is idempotent: run it twice in a row and `git diff` shows no changes after the second run

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately.
- **Foundational (Phase 2)**: Depends on Setup — BLOCKS all user stories.
- **User Story 1 (Phase 3, P1)**: Depends on Foundational. The MVP. Required by US3 (pipeline integration assumes a working engine) and US4 (stacked-PR creator reads the manifest the engine produces).
- **User Story 2 (Phase 4, P2)**: Depends on Foundational and US1's engine. The reference flavor exercises the engine end-to-end with a real-world catalog.
- **User Story 3 (Phase 5, P3)**: Depends on US1 (engine + CLI exist). The reference flavor (US2) is convenient for end-to-end demos but US3 can be exercised against the toy `example-minimal` flavor too.
- **User Story 4 (Phase 6, P4)**: Depends on US1 (manifest exists). Independent of US2/US3 in implementation, but the SC-010 fixture is easier to construct against the seven-phase column-rename example from US2.
- **User Story 5 (Phase 7, P5)**: Depends on Foundational only (it reads shipped flavors via `FlavorLoader`). Most parallelizable story.
- **Polish (Phase 8)**: Depends on every story being complete.

### Within Each User Story

- Tests are written and observed to FAIL before implementation per the constitution's Test-First Development principle.
- Value objects and pure functions before orchestrators.
- Library code before CLI entry points.
- Source-of-truth files (`speckit-commands/`, `claude-agents/`) before `setup.sh` install runs.

### Parallel Opportunities Within a Story

- All [P] tests within a story phase can be written in parallel (they touch different `_spec.rb` files).
- All [P] implementation tasks within a story phase can be implemented in parallel (they touch different `lib/` files).
- The two pattern modules (`inference.rb`, `forbidden_operations.rb`) and two validators (`backfill_validator.rb`, `precedent_validator.rb`) of the reference flavor can be implemented by four developers in parallel (T051..T054).
- The five tests in US4 (T065..T071) can be written in parallel; the four implementation files (T072..T075) can also be implemented in parallel because each file is independent.

### Parallel Opportunities Across Stories

- Once Foundational completes:
  - Developer A: US1 → US3
  - Developer B: US2
  - Developer C: US4
  - Developer D: US5
- US2, US4, US5 do not depend on each other (only on US1's engine + Foundational), so three developers can work in parallel after US1 lands.

---

## Parallel Example: User Story 1 Implementation Burst

```bash
# After T021..T029 (US1 tests + fixtures) are written and failing, the
# following four implementation tasks can run in parallel:
Task: "T030 [US1] Implement Phaser::Classifier in phaser/lib/phaser/classifier.rb"
Task: "T031 [US1] Implement Phaser::ForbiddenOperationsGate in phaser/lib/phaser/forbidden_operations_gate.rb"
Task: "T032 [US1] Implement Phaser::PrecedentValidator in phaser/lib/phaser/precedent_validator.rb"
Task: "T033 [US1] Implement Phaser::IsolationResolver in phaser/lib/phaser/isolation_resolver.rb"
Task: "T034 [US1] Implement Phaser::SizeGuard in phaser/lib/phaser/size_guard.rb"

# T035 (Engine) and T036 (CLI) sequentially follow because Engine depends on
# all five components above and the CLI depends on the Engine.
```

## Parallel Example: User Story 2 Reference-Flavor Burst

```bash
# After T040..T049 are written and failing, the four flavor modules can be
# implemented in parallel:
Task: "T051 [US2] Implement RailsPostgresStrongMigrations::Inference in phaser/flavors/rails-postgres-strong-migrations/inference.rb"
Task: "T052 [US2] Implement RailsPostgresStrongMigrations::ForbiddenOperations in phaser/flavors/rails-postgres-strong-migrations/forbidden_operations.rb"
Task: "T053 [US2] Implement RailsPostgresStrongMigrations::BackfillValidator in phaser/flavors/rails-postgres-strong-migrations/backfill_validator.rb"
Task: "T054 [US2] Implement RailsPostgresStrongMigrations::PrecedentValidator in phaser/flavors/rails-postgres-strong-migrations/precedent_validator.rb"

# T055 (flavor_loader.rb wiring) follows sequentially because it integrates the
# four modules above through the YAML catalog.
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1 (Setup) — empty Ruby project skeleton.
2. Complete Phase 2 (Foundational) — value objects, observability, manifest writer, status writer, flavor loader.
3. Complete Phase 3 (User Story 1) — engine + example-minimal flavor + standalone CLI.
4. **STOP and VALIDATE**: Run `phaser/bin/phaser` against the example-minimal fixture; verify deterministic output, no domain leakage, size bounds enforced. SC-002, SC-003, SC-014 green at this point.
5. Demo to a maintainer; collect feedback before investing in the reference flavor.

### Incremental Delivery

1. Setup + Foundational → foundation ready.
2. Add US1 → standalone phaser engine demoable (MVP).
3. Add US2 → real-world Rails flavor; column-rename produces seven phases; SC-001/SC-004/SC-005/SC-015 green.
4. Add US3 → end-to-end pipeline integration; no-flavor zero-regression verified (SC-006).
5. Add US4 → stacked PRs auto-created; SC-009/SC-010/SC-012/SC-013 green.
6. Add US5 → one-command opt-in (SC-007 green).
7. Phase 8 (Polish) → quality gates wired, CLAUDE.md updated, idempotent setup verified.

### Parallel Team Strategy

After Foundational lands:

1. Developer A picks up US1 (the critical path; everything depends on the engine).
2. Once US1's engine surface is stable enough for the reference flavor to call:
   - Developer B starts US2 (reference flavor).
   - Developer C starts US4 (stacked PRs — depends only on the manifest schema, not on a specific flavor).
   - Developer D starts US5 (flavor-init — depends only on `FlavorLoader`).
3. Developer A continues with US3 (pipeline integration) once US1 lands.
4. Phase 8 is shared cleanup; whoever finishes their story first picks up the polish tasks.

---

## Notes

- Every Ruby file in `phaser/lib/` and `phaser/lib/phaser/stacked_prs/` follows test-first per quickstart.md "Pattern: Test-First for Engine Logic": write `_spec.rb`, observe failure, implement, observe pass, then add the next `it` block.
- Source-of-truth files (`speckit-commands/`, `claude-agents/`) are always edited; `.claude/` copies are refreshed by `setup.sh`. Tasks that modify `setup.sh` are followed immediately by a `bash setup.sh` invocation to keep the installed copies current.
- All commits during this work follow the project's Git Discipline: `type(scope): [ticket] description` with `ticket = 007`, `scope = multi-phase-pipeline`, `type = feat|fix|chore`. One logical change per commit.
- Process hygiene (CLAUDE.md): no orphan processes, no leftover containers, no stale dev servers. Verified in T092.
- The forbidden-operations gate (T031, FR-049, D-016) MUST NOT be invocable through any flag, environment variable, or commit-message trailer. T031's tests assert the bypass surface is empty.
- Credential-leak guard (T070, FR-047, SC-013) is the single backstop that protects against accidentally serializing tokens. Runs across every fixture in CI.
