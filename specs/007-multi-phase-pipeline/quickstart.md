# Quickstart: Multi-Phase Pipeline for SpecKit Simpsons

**Branch**: `007-multi-phase-pipeline` | **Date**: 2026-04-25

This document is the implementer's playbook for building the phaser stage. It restates the design decisions in build-order, lists the files that change in each phase, and ends with a verification checklist that must be satisfied before the feature is declared complete.

## Implementation Order

The work is organized into five phases. Each phase corresponds to a Priority level in spec.md (P1 through P5), then a sixth integration phase that wires everything together. Test-first applies throughout: each Ruby file's RSpec tests are written and observed to fail before the implementation is written.

### Phase 1: Flavor-Agnostic Phaser Engine (User Story 1, P1)

**Goal**: A pure-Ruby engine that consumes `(commits, flavor) ⇒ phase_manifest` and contains zero domain knowledge (FR-003).

**Files**:

- `phaser/lib/phaser.rb` — top-level loader.
- `phaser/lib/phaser/engine.rb` — `process(feature_branch, flavor)` entry point.
- `phaser/lib/phaser/classifier.rb` — operator-tag → inference → default cascade (FR-004).
- `phaser/lib/phaser/forbidden_operations_gate.rb` — pre-classification gate (FR-049).
- `phaser/lib/phaser/precedent_validator.rb` — precedent enforcement (FR-006).
- `phaser/lib/phaser/isolation_resolver.rb` — alone vs. groups grouping (FR-005).
- `phaser/lib/phaser/size_guard.rb` — 200-commit / 50-phase bounds (FR-048).
- `phaser/lib/phaser/manifest_writer.rb` — stable-key-order YAML emit (FR-038, FR-002).
- `phaser/lib/phaser/status_writer.rb` — `phase-creation-status.yaml` writer (FR-042).
- `phaser/lib/phaser/observability.rb` — JSON-line stderr logger (FR-041, FR-043).
- `phaser/lib/phaser/flavor_loader.rb` — reads and schema-validates flavors.
- `phaser/bin/phaser` — CLI entry point per `contracts/phaser-cli.md`.
- `phaser/flavors/example-minimal/{flavor.yaml,inference.rb}` — toy two-type flavor for SC-003.
- `phaser/spec/{engine_spec.rb,classifier_spec.rb,forbidden_operations_gate_spec.rb,size_guard_spec.rb,manifest_writer_spec.rb,observability_spec.rb,engine_no_domain_leakage_spec.rb}`.
- `phaser/spec/fixtures/repos/example-minimal/` — synthetic Git repo for the engine tests.
- `phaser/{Gemfile,Rakefile,.rubocop.yml}`.

**Acceptance**: All four acceptance scenarios in spec.md User Story 1 pass; SC-002 (100-run determinism), SC-003 (no domain leakage), SC-014 (size bounds) pass.

### Phase 2: Reference Rails+Postgres+strong_migrations Flavor (User Story 2, P2)

**Goal**: A complete, ready-to-use flavor catalog with file-pattern inference, backfill-safety validator, precedent validator, and forbidden-operations registry.

**Files**:

- `phaser/flavors/rails-postgres-strong-migrations/flavor.yaml` — the catalog (every type from FR-010, isolation from FR-011, inference rules from FR-012, precedent rule from FR-014, forbidden-operations registry from FR-015).
- `phaser/flavors/rails-postgres-strong-migrations/inference.rb` — pattern-matcher methods for AST-aware classification.
- `phaser/flavors/rails-postgres-strong-migrations/forbidden_operations.rb` — detector methods for direct-rename, direct-type-change, non-concurrent index, etc.
- `phaser/flavors/rails-postgres-strong-migrations/backfill_validator.rb` — rejects backfill commits lacking batching/throttling/transaction-safety (FR-013).
- `phaser/flavors/rails-postgres-strong-migrations/precedent_validator.rb` — rejects column-drop without prior ignore + reference-removal (FR-014).
- `phaser/flavors/rails-postgres-strong-migrations/safety_assertion_validator.rb` — enforces the `Safety-Assertion:` trailer on irreversible schema operations and records the cited SHAs on the manifest's task entry for audit (FR-018, plan.md D-017).
- `phaser/spec/flavors/rails_postgres_strong_migrations_spec.rb` — exercises every catalog entry, every forbidden operation, the backfill validator, the precedent validator, and the column-rename worked example (FR-017).
- `phaser/spec/flavors/rails_postgres_strong_migrations/safety_assertion_validator_spec.rb` — pairs every irreversible task type with missing-block, mismatched-precedent, and correctly-cited fixture commits (FR-018).
- `phaser/spec/fixtures/repos/users-email-rename/` — the seven-commit fixture for FR-017 / SC-001.
- `phaser/spec/fixtures/classification/` — per-type fixture commits for FR-012.

**Acceptance**: All eight acceptance scenarios in spec.md User Story 2 pass; SC-001 (column-rename produces 7 phases), SC-004 (≥90% inference coverage), SC-005 (every forbidden operation has a regression test), SC-015 (operator-tag-cannot-bypass-gate) pass.

### Phase 3: Pipeline Integration (User Story 3, P3)

**Goal**: The phaser slots into the SpecKit pipeline between ralph and marge; marge runs per-phase plus holistically; absent flavor file ⇒ no behavior change.

**Files**:

- `claude-agents/phaser.md` — single-shot agent file that invokes `phaser` and commits the manifest.
- `speckit-commands/speckit.phaser.md` — wraps the phaser agent.
- `speckit-commands/speckit.pipeline.md` — modified: detect `.specify/flavor.yaml`, insert phaser step, invoke marge per-phase + holistic.
- `speckit-commands/speckit.marge.review.md` — modified: accept `--phase <N>` to scope review (FR-022).
- `setup.sh` — modified: install new commands and agent (R-017).
- `.claude/agents/phaser.md` and `.claude/commands/speckit.phaser.md` — installed copies.
- `phaser/spec/pipeline_no_flavor_baseline_spec.rb` — captured-baseline regression test for SC-006.

**Acceptance**: All four acceptance scenarios in spec.md User Story 3 pass; SC-006 (no-flavor zero-regression) and SC-008 (precise error messages) pass.

### Phase 4: Stacked Branches and Stacked Pull Requests (User Story 4, P4)

**Goal**: Stacked branches and PRs are auto-created from the manifest; failures are recoverable.

**Files**:

- `phaser/lib/phaser/stacked_prs/creator.rb` — idempotent branch + PR creation (FR-026, FR-040).
- `phaser/lib/phaser/stacked_prs/git_host_cli.rb` — `gh` subprocess wrapper (FR-044).
- `phaser/lib/phaser/stacked_prs/auth_probe.rb` — one-shot `gh auth status` probe (FR-045).
- `phaser/lib/phaser/stacked_prs/failure_classifier.rb` — classifies gh exit codes / stderr into `failure_class` (FR-046).
- `phaser/bin/phaser-stacked-prs` — CLI entry point per `contracts/stacked-pr-creator-cli.md`.
- `phaser/spec/stacked_prs/{creator_spec.rb,auth_probe_spec.rb,failure_classifier_spec.rb}`.
- `phaser/spec/credential_leak_scan_spec.rb` — SC-013 regression test.
- Modification to `speckit-commands/speckit.pipeline.md` to invoke `phaser-stacked-prs` after marge succeeds.

**Acceptance**: All four acceptance scenarios in spec.md User Story 4 pass; SC-009 (manifest predicts the PR set), SC-010 (idempotent resume), SC-012 (auth-missing fail-fast), SC-013 (credential-leak-free) pass.

### Phase 5: One-Shot Flavor-Init Command (User Story 5, P5)

**Goal**: A maintainer can opt a project into phasing with one command and one confirmation.

**Files**:

- `phaser/lib/phaser/flavor_init/stack_detector.rb` — evaluates per-flavor stack-detection signals.
- `phaser/bin/phaser-flavor-init` — CLI entry point per `contracts/flavor-init-cli.md`.
- `speckit-commands/speckit.flavor.init.md` — wraps `phaser-flavor-init` for the SpecKit command surface.
- `phaser/spec/flavor_init_spec.rb` — tests for FR-031 through FR-034 plus the multi-match case (R-015).
- `setup.sh` — modified: install the new command (R-017).

**Acceptance**: All four acceptance scenarios in spec.md User Story 5 pass; SC-007 (one-command opt-in) passes.

### Phase 6: Quality Gates and Documentation Wiring

**Goal**: The new Ruby code is wired into the project's quality gates and the active-technologies surface is updated.

**Files**:

- `.specify/quality-gates.sh` — add `(cd phaser && bundle exec rspec)` and `(cd phaser && bundle exec rubocop)` gated on `phaser/` presence (R-018).
- `CLAUDE.md` — add active-technologies entry for Ruby 3.2+, RSpec, rubocop (auto-updated by `.specify/scripts/bash/update-agent-context.sh claude`).

**Acceptance**: `bash .specify/quality-gates.sh` exits 0 on a clean implementation; CLAUDE.md shows the new active-technologies entry.

## Key Patterns

### Pattern: Test-First for Engine Logic

Every Ruby file in `phaser/lib/phaser/` and `phaser/lib/phaser/stacked_prs/` MUST have its RSpec tests written first. The cycle for each file:

1. Write `phaser/spec/<file>_spec.rb` with at minimum one `describe` block and one failing `it`.
2. Run `cd phaser && bundle exec rspec spec/<file>_spec.rb` and observe the failure.
3. Write the minimum implementation in `phaser/lib/phaser/<file>.rb` to pass the test.
4. Add additional `it` blocks one at a time, each preceded by failure observation.

This is enforced by code review and by the constitution's Test-First Development principle.

### Pattern: Pre-Classification Gate Discipline (FR-049)

The forbidden-operations gate is the FIRST thing the engine does for every commit, after the empty-diff filter. The structure is non-negotiable:

```ruby
# In engine.rb#process_commit
def process_commit(commit, flavor)
  return :skip if commit.diff.empty?                              # FR-009
  forbidden = flavor.forbidden_operations_gate.evaluate(commit)
  raise ForbiddenOperationError.new(commit, forbidden) if forbidden
  classifier.classify(commit, flavor)                              # FR-004
end
```

The classifier is never called when the gate rejects a commit. There is no flag, environment variable, or commit-message trailer that can suppress the gate (D-016).

### Pattern: Manifest Writer for Stable Output

All YAML output for the manifest goes through `manifest_writer.rb#write(manifest, path)`. The writer:

1. Builds an explicitly ordered Hash matching the schema in `contracts/phase-manifest.schema.yaml`.
2. Calls `Psych.dump(hash, line_width: -1, header: false)` to emit YAML.
3. Writes atomically (temp file + rename) so a crash mid-write never leaves a corrupt file.

Tests for `manifest_writer_spec.rb` include the SC-002 100-run determinism check.

### Pattern: gh Subprocess Wrapper (FR-044, FR-047)

All `gh` invocations go through `git_host_cli.rb#run(args, capture: true)`. The wrapper:

1. Invokes `Open3.capture3('gh', *args)` with no environment variable additions or removals.
2. Captures stdout, stderr, and status.
3. Scans stderr's first line for credential patterns before returning it to callers.
4. Never logs or persists the raw stderr beyond that first sanitized line.

The wrapper is the only place in the codebase that calls `gh`. Direct `system('gh ...')` calls are forbidden by code review and a grep-based regression test.

### Pattern: Status File Reuse (D-012)

`status_writer.rb#write(stage:, failure_class:, **payload)` writes `phase-creation-status.yaml` with the appropriate `stage` discriminator. The same writer is used by the engine and the stacked-PR creator. On full success, the writing module also exposes `delete_if_present(path)` for the caller to invoke.

### Pattern: Conditional Pipeline Behavior (FR-025)

The modified `speckit.pipeline.md` checks for `.specify/flavor.yaml` immediately after the existing pre-flight checks. The check is a single Bash test:

```bash
test -f .specify/flavor.yaml && echo "PHASER_ENABLED" || echo "PHASER_DISABLED"
```

When `PHASER_DISABLED`, all phaser-related logic is skipped; the pipeline runs marge once holistically as today. When `PHASER_ENABLED`, the phaser step is inserted and marge runs per-phase + holistic. SC-006's baseline-diff regression test verifies the disabled path is byte-identical to the pre-feature pipeline.

## Verification Checklist

This checklist enumerates the acceptance evidence required before declaring the feature complete. Each item maps to one or more acceptance scenarios from spec.md and one or more measurable outcomes from the Success Criteria.

### Engine (User Story 1, P1)

- [ ] `phaser` CLI runs against the example-minimal flavor and a synthetic feature branch, producing a manifest.
- [ ] Re-running the same input 100 consecutive times produces a byte-identical manifest (SC-002).
- [ ] Running `grep -REni 'rails|activerecord|postgres|strong_migrations|migration|gemfile' phaser/lib/` returns zero hits (SC-003).
- [ ] An untagged commit matching no inference rule is assigned the example-minimal flavor's default type.
- [ ] A commit violating a precedent rule causes the engine to exit non-zero with a `validation-failed` ERROR record naming the offending commit.
- [ ] A feature branch with 201 non-empty commits causes a `feature-too-large` rejection before any manifest is written (SC-014).
- [ ] A flavor + commit set that would emit 51 phases causes a `feature-too-large` rejection before any manifest is written (SC-014).
- [ ] The engine emits at least one `commit-classified` log per non-empty commit and one `phase-emitted` per phase (SC-011).

### Reference Flavor (User Story 2, P2)

- [ ] The shipped fixture for `users.email → users.email_address` produces exactly seven phases (SC-001, FR-017).
- [ ] Every entry in the forbidden-operations registry has a regression test that produces the canonical decomposition message (SC-005).
- [ ] At least 90% of commits in the shipped fixture set are classified correctly without operator tags (SC-004).
- [ ] An operator-supplied type tag overrides the inference layer's classification (FR-016) — verified by a test commit that carries a tag and a diff that would inference-match a different type.
- [ ] A commit performing a forbidden operation BUT carrying an operator-supplied valid-type tag is still rejected by the pre-classification gate (SC-015) — verified for every entry in the registry.
- [ ] A backfill commit lacking batching is rejected with an error naming the missing safeguard (FR-013).
- [ ] A column-drop commit without prior ignore + reference-removal is rejected with an error naming the missing precedents (FR-014).
- [ ] An irreversible-schema-operation commit (column drop, table drop, concurrent index drop, remove ignored-columns directive) is rejected by the safety-assertion-block validator when the commit message lacks a `Safety-Assertion:` trailer or fenced safety-assertion block, or when the cited SHA is not a valid precedent for the subject type; on success, the cited SHA is recorded on the manifest's task entry for audit (FR-018).

### Pipeline Integration (User Story 3, P3)

- [ ] With `.specify/flavor.yaml` present, the pipeline runs the phaser step after the existing simplify/security-review polish phases and immediately before marge (order: `ralph → simplify → security-review → phaser → marge`), so any commits created by the polish phases are classified into the manifest.
- [ ] With a manifest of N phases, the pipeline invokes marge N+1 times: once per phase with `--phase N`, then once holistically.
- [ ] The holistic marge pass runs after all per-phase passes complete.
- [ ] When the phaser stage fails, the pipeline halts and does NOT invoke marge.
- [ ] With `.specify/flavor.yaml` absent, the pipeline output is byte-identical to the captured pre-feature baseline (SC-006).
- [ ] The phase manifest is committed to the feature branch as `<FEATURE_DIR>/phase-manifest.yaml`.

### Stacked Branches and PRs (User Story 4, P4)

- [ ] For an N-phase manifest on `<feature>`, branches `<feature>-phase-1` through `<feature>-phase-N` are created with the correct base-branch chain (FR-026).
- [ ] One PR is opened per phase with rationale, rollback plan, and (for non-first phases) a link to the previous phase's PR (FR-027).
- [ ] Each phase branch triggers its own CI independently (FR-028).
- [ ] Phase N+1's PR opens as soon as phase N is merged (FR-029).
- [ ] When `gh auth status` reports unauthenticated, the creator exits non-zero before any branch is created and writes the status file with `failure_class: auth-missing` and `first_uncreated_phase: 1` (SC-012).
- [ ] When creation fails between phase K and phase K+1, the creator leaves phases 1..K intact, writes the status file with `first_uncreated_phase: K+1`, and exits non-zero (SC-010).
- [ ] A re-run after the failure above completes phases K+1..N without recreating phases 1..K and deletes the status file on success (SC-010).
- [ ] No log line and no status file byte contains a credential-shaped substring across all failure-mode fixtures (SC-013).

### Flavor-Init (User Story 5, P5)

- [ ] In a Rails+Postgres+strong_migrations project, the command suggests the rails-postgres-strong-migrations flavor and writes `.specify/flavor.yaml` on confirmation (SC-007).
- [ ] In a project with no recognizable stack, the command exits non-zero with `no flavor matched` and writes no file (FR-033).
- [ ] When `.specify/flavor.yaml` already exists, the command refuses to overwrite without `--force` (FR-034).
- [ ] With `--force`, the command overwrites the existing file (FR-034).
- [ ] When multiple shipped flavors match, the command exits non-zero with the matching list and instructs the operator to pass `--flavor <name>` (R-015).

### Quality Gates and Documentation

- [ ] `bash .specify/quality-gates.sh` exits 0.
- [ ] `cd phaser && bundle exec rspec` exits 0.
- [ ] `cd phaser && bundle exec rubocop` exits 0.
- [ ] `CLAUDE.md` lists the new active technologies (Ruby 3.2+, RSpec, rubocop) under the 007 feature.
- [ ] `setup.sh` is idempotent: a second invocation produces no diff.
- [ ] No straggling processes or containers from any test run remain (`ps aux | grep phaser` is clean; `docker ps` is clean).
