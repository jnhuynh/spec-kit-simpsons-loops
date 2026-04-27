# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'stringio'
require 'tmpdir'
require 'yaml'
require 'phaser'

# Specs for SC-015 — the operator-tag-cannot-bypass-gate regression that
# pairs every entry in the shipped `rails-postgres-strong-migrations`
# flavor's forbidden-operations registry with a commit carrying an
# operator-supplied `Phase-Type:` trailer that names a different VALID
# task type from FR-010's catalog (feature 007-multi-phase-pipeline; T045,
# FR-015, FR-016, FR-041, FR-042, FR-049, SC-015, D-016, spec.md "Edge
# Cases" item on the operator-tag/forbidden-operations interaction).
#
# Position in the engine pipeline (per quickstart.md "Pattern:
# Pre-Classification Gate Discipline"):
#
#   empty-diff filter (FR-009)
#     -> forbidden-operations gate (FR-049)        <-- THIS spec
#     -> classifier (FR-004, consumer of Phase-Type per FR-016)
#     -> precedent validator (FR-006)
#     -> reference-flavor validators (FR-013, FR-014, FR-018)
#     -> size guard (FR-048)
#     -> isolation resolver (FR-005)
#     -> manifest writer (FR-002, FR-038)
#
# Why a dedicated bypass-attempt spec on top of T044's per-identifier
# regression and T022's gate-level bypass-surface contract:
#
#   T022 (`spec/forbidden_operations_gate_spec.rb`) pins the gate's
#   bypass-surface invariants AT THE UNIT LEVEL — no `skip:` / `force:`
#   keyword on the constructor, no environment-variable consultation, no
#   honour for a `Phaser-Skip-Forbidden:` trailer. Those invariants are
#   structural: the gate does not LOOK at trailers at all, so any
#   operator-tag bypass attempt is by construction inert at the gate
#   level.
#
#   T044 (`spec/flavors/rails_postgres_strong_migrations/
#   forbidden_operations_spec.rb`) pins each registry entry's CANONICAL
#   DECOMPOSITION MESSAGE against an offending commit that carries NO
#   operator tag — the per-identifier regression SC-005 mandates.
#
#   T045 (this spec) sits one level above both: it pins the
#   externally observable contract SC-015 mandates — a commit whose diff
#   matches a forbidden-operation detector AND whose message carries a
#   `Phase-Type:` trailer naming a valid (non-forbidden) task type from
#   FR-010 MUST be rejected through the engine's pre-classification gate
#   with the registry's canonical decomposition message, MUST NOT cause
#   a `phase-manifest.yaml` to be written, MUST persist the failure to
#   `<feature_dir>/phase-creation-status.yaml` with `stage:
#   phaser-engine`, and MUST exit through the same `validation-failed`
#   ERROR record path as an untagged offending commit. This is the SAME
#   contract a curious operator would probe by hand: "what happens if I
#   tell the phaser my direct rename is a `schema add-nullable-column`?
#   Does the safety gate go away?"
#
# Contract (SC-015, spec.md "Edge Cases" / spec.md User Story 2
# Acceptance Scenario 5, FR-049):
#
#   "A regression test pairing every entry in the reference flavor's
#    forbidden-operations registry with a commit that carries an
#    operator-supplied type tag naming a valid task type (other than
#    the forbidden operation itself) verifies that the phaser engine
#    still rejects each such commit through the pre-classification gate,
#    emits the registry's canonical decomposition message, writes no
#    phase manifest, and persists the failure to
#    `<FEATURE_DIR>/phase-creation-status.yaml` with `stage:
#    phaser-engine`; verifying that FR-016's operator-tag override
#    cannot suppress the FR-015/FR-049 forbidden-operations gate."
#
# Determinism contract (FR-002, SC-002):
#
#   * The bypass-attempt task type is selected per-identifier at
#     example-definition time so each (forbidden-identifier,
#     attempted-bypass-type) pair is its own example. A regression
#     failure points at "the gate let
#     `direct-column-rename` slip through when tagged as `schema
#     add-nullable-column`" rather than at "1/N examples failed".
#
#   * The bypass-attempt task type is the FIRST valid task type in
#     FR-010's catalog that is not the forbidden operation itself, with
#     a stable preference for `schema add-nullable-column` (the
#     canonical "safe schema change" tag an operator would plausibly
#     reach for when trying to slip a forbidden change past the gate).
#
#   * Each per-identifier example builds an independent feature_dir so
#     manifest/status-file assertions are hermetic and do not leak
#     across examples.
#
# Logging / status-file contract (FR-041, FR-042,
# contracts/observability-events.md `validation-failed`,
# contracts/phase-creation-status.schema.yaml):
#
#   * On rejection the engine emits exactly one `validation-failed`
#     ERROR record with `failing_rule`, `forbidden_operation`,
#     `decomposition_message`, and `commit_hash` populated from the
#     matching registry entry.
#   * The same payload (minus the envelope fields) is persisted to
#     `phase-creation-status.yaml` via `StatusWriter#write(stage:
#     'phaser-engine', ...)`.
#   * No `commit-classified` INFO record is emitted for the offending
#     commit — the gate runs BEFORE the classifier, so the classifier is
#     never invoked.
#
# What this spec deliberately does NOT cover:
#
#   * Detector-shape semantics (file_glob vs. content_regex vs.
#     module_method dispatch) are pinned by the gate's unit spec
#     (T022) and the per-identifier regression (T044).
#   * The full validation-failed payload field-list is pinned by T044.
#     Here we assert the engine + status-writer wiring carries the gate
#     output through the engine's outer rescue path unchanged.
#   * The flavor's wider catalog (task types, isolation, inference,
#     precedent rules, backfill validator, safety-assertion validator)
#     is pinned by sibling specs.
#
# This spec MUST observe failure (red) before T050 ships
# `flavor.yaml`, T052 ships `forbidden_operations.rb`, and T055 wires
# the flavor through the loader (the test-first requirement in
# CLAUDE.md "Test-First Development"). Until then,
# `Phaser::FlavorLoader#load('rails-postgres-strong-migrations')`
# raises `Phaser::FlavorNotFoundError` and every example below fails at
# the `let(:flavor)` resolution step.
RSpec.describe 'rails-postgres-strong-migrations operator-tag cannot bypass gate (SC-015)' do # rubocop:disable RSpec/DescribeClass
  # Canonical forbidden-operation identifiers FR-015 enumerates; mirrors
  # T044's `required_forbidden_identifiers`. Reproduced here verbatim so
  # a registry-level rename has to come through both specs and a
  # divergence between the two checklists is impossible to introduce
  # silently.
  let(:required_forbidden_identifiers) do
    %w[
      direct-column-type-change
      direct-column-rename
      non-concurrent-index
      direct-add-not-null-column
      direct-add-foreign-key
      add-column-with-volatile-default
      drop-column-without-code-cleanup
    ].freeze
  end

  # Per-identifier fixtures: the offending diff that trips the registry's
  # detector AND the operator-tag the offending commit carries. Each
  # `phase_type_tag` is a valid task type from FR-010's catalog (pinned
  # by `catalog_spec.rb`) that is NOT the forbidden operation itself —
  # the canonical "I'll just call my direct rename a safe schema add and
  # the safety gate will go away" bypass attempt SC-015 protects against.
  #
  # The chosen `phase_type_tag` for each identifier is the most plausible
  # cover-story tag an operator would reach for: a "safe" schema or code
  # change in the same broad category as the forbidden operation. Pinning
  # the bypass-attempt tag per-identifier (rather than rotating through
  # the full catalog) keeps the failure messages specific without
  # exploding the example count.
  #
  # The diff fixtures mirror T044's `forbidden_fixtures` so the same
  # detectors trip the same commits — the only difference here is the
  # operator tag riding on the commit message. Identical detector inputs
  # let us assert the gate's decision is unchanged BY THE TAG.
  let(:bypass_attempt_fixtures) do
    {
      'direct-column-type-change' => {
        path: 'db/migrate/20260425000001_change_users_email_to_text.rb',
        hunks: ["@@ -0,0 +1 @@\n+    change_column :users, :email, :text\n"],
        phase_type_tag: 'schema add-nullable-column'
      },
      'direct-column-rename' => {
        path: 'db/migrate/20260425000002_rename_users_email.rb',
        hunks: ["@@ -0,0 +1 @@\n+    rename_column :users, :email, :email_address\n"],
        phase_type_tag: 'schema add-nullable-column'
      },
      'non-concurrent-index' => {
        path: 'db/migrate/20260425000003_add_index_users_email.rb',
        hunks: ["@@ -0,0 +1 @@\n+    add_index :users, :email\n"],
        phase_type_tag: 'schema add-concurrent-index'
      },
      'direct-add-not-null-column' => {
        path: 'db/migrate/20260425000004_add_required_email_to_users.rb',
        hunks: ["@@ -0,0 +1 @@\n+    add_column :users, :email, :string, null: false\n"],
        phase_type_tag: 'schema add-nullable-column'
      },
      'direct-add-foreign-key' => {
        path: 'db/migrate/20260425000005_add_fk_users_to_orgs.rb',
        hunks: ["@@ -0,0 +1 @@\n+    add_foreign_key :users, :orgs\n"],
        phase_type_tag: 'schema add-foreign-key-without-validation'
      },
      'add-column-with-volatile-default' => {
        path: 'db/migrate/20260425000006_add_seen_at_to_users.rb',
        hunks: [
          "@@ -0,0 +1 @@\n+    add_column :users, :seen_at, :datetime, " \
          "default: -> { 'now()' }\n"
        ],
        phase_type_tag: 'schema add-column-with-static-default'
      },
      'drop-column-without-code-cleanup' => {
        path: 'db/migrate/20260425000007_drop_legacy_email_from_users.rb',
        hunks: ["@@ -0,0 +1 @@\n+    remove_column :users, :legacy_email\n"],
        phase_type_tag: 'schema drop-column-with-cleanup-precedent'
      }
    }.freeze
  end

  let(:flavor) do
    Phaser::FlavorLoader.new.load('rails-postgres-strong-migrations')
  end

  # Pinned clock so `generated_at` and `timestamp` are reproducible for
  # determinism assertions (FR-002, SC-002). Mirrors `engine_spec.rb`.
  let(:fixed_clock) { -> { '2026-04-25T12:00:00.000Z' } }

  # StringIO collects every stderr byte the engine emitted so examples
  # can parse the JSON-line records and assert the gate's rejection
  # surfaced through the canonical `validation-failed` ERROR path.
  let(:stderr_io) { StringIO.new }

  # Per-example temp directory for the engine's manifest + status-file
  # output. Each example operates inside its own feature_dir so writes
  # are isolated and the `around` hook reliably tears down. Mirrors the
  # convention in `spec/engine_spec.rb`.
  attr_reader :feature_dir

  around do |example|
    Dir.mktmpdir('phaser-sc015-spec') do |tmp|
      @feature_dir = tmp
      example.run
    end
  end

  # Build a fully-wired engine pointed at the per-example feature_dir
  # with a fresh observability/status_writer/manifest_writer. The engine
  # uses the SHIPPED FlavorLoader-validated flavor (above) so the
  # forbidden_operations gate is constructed from the registry that
  # actually ships in `flavor.yaml` — not a hand-crafted in-memory copy.
  def build_engine
    Phaser::Engine.new(
      feature_dir: feature_dir,
      feature_branch: 'feature-007-sc-015',
      default_branch: 'main',
      observability: Phaser::Observability.new(stderr: stderr_io, now: fixed_clock),
      status_writer: Phaser::StatusWriter.new(now: fixed_clock),
      manifest_writer: Phaser::ManifestWriter.new,
      clock: fixed_clock
    )
  end

  # Build a Phaser::Commit whose single FileChange exercises the
  # registry's detector for `identifier`, AND carries a `Phase-Type:`
  # trailer naming a valid task type other than the forbidden operation
  # itself. The hash is derived from the identifier so the
  # validation-failed payload's `commit_hash` is reproducible across runs
  # (FR-002, SC-002).
  def build_bypass_attempt_commit(identifier)
    fixture = bypass_attempt_fixtures.fetch(identifier)
    Phaser::Commit.new(
      hash: stable_hash_for(identifier),
      subject: "Trigger #{identifier} with operator tag",
      message_trailers: { 'Phase-Type' => fixture.fetch(:phase_type_tag) },
      diff: Phaser::Diff.new(
        files: [
          Phaser::FileChange.new(
            path: fixture.fetch(:path),
            change_kind: :added,
            hunks: fixture.fetch(:hunks)
          )
        ]
      ),
      author_timestamp: '2026-04-25T12:00:00Z'
    )
  end

  # 40-char hex hash deterministically derived from the identifier so
  # the validation-failed payload's `commit_hash` is reproducible
  # across runs (FR-002, SC-002). Mirrors T044's helper.
  def stable_hash_for(identifier)
    seed = identifier.bytes.sum.to_s(16)
    seed.rjust(40, identifier[0]).slice(0, 40)
  end

  # Convenience: find the canonical registry entry for `identifier` in
  # the shipped flavor's forbidden_operations list. Used to assert the
  # rejection's payload matches the registry's source-of-truth message.
  def registry_entry(identifier)
    flavor.forbidden_operations.find { |entry| entry.fetch('identifier') == identifier }
  end

  def manifest_path
    File.join(feature_dir, 'phase-manifest.yaml')
  end

  def status_path
    File.join(feature_dir, 'phase-creation-status.yaml')
  end

  # Convenience: read every JSON-line record the engine emitted to
  # stderr in the order they were emitted. Mirrors `engine_spec.rb`.
  def emitted_records
    stderr_io.string.each_line.map { |line| JSON.parse(line) }
  end

  describe 'sanity prerequisites for SC-015' do
    it 'ships every required forbidden-operation identifier (handshake with T044)' do
      shipped = flavor.forbidden_operations.map { |entry| entry.fetch('identifier') }

      expect(shipped).to include(*required_forbidden_identifiers)
    end

    it 'pairs every required forbidden identifier with a bypass-attempt fixture' do
      expect(bypass_attempt_fixtures.keys).to match_array(required_forbidden_identifiers)
    end

    it 'tags every bypass-attempt fixture with a VALID task type from FR-010 (per SC-015)' do
      shipped_task_type_names = flavor.task_types.map(&:name)

      bypass_attempt_fixtures.each do |identifier, fixture|
        attempted_tag = fixture.fetch(:phase_type_tag)

        expect(shipped_task_type_names).to(
          include(attempted_tag),
          "expected the bypass-attempt tag #{attempted_tag.inspect} for #{identifier.inspect} to be a " \
          'valid task type from FR-010 (per SC-015 — the test must use a VALID type name to prove the ' \
          "gate rejects it anyway); shipped task types: #{shipped_task_type_names.inspect}"
        )
      end
    end

    it 'tags every bypass-attempt fixture with a task type OTHER than the forbidden operation itself' do
      bypass_attempt_fixtures.each do |identifier, fixture|
        attempted_tag = fixture.fetch(:phase_type_tag)

        expect(attempted_tag).not_to(
          eq(identifier),
          "expected the bypass-attempt tag for #{identifier.inspect} to be a DIFFERENT task type " \
          '(per SC-015 — "naming a valid task type other than the forbidden operation itself")'
        )
      end
    end
  end

  describe 'engine rejection through the pre-classification gate (FR-049, SC-015)' do
    %w[
      direct-column-type-change
      direct-column-rename
      non-concurrent-index
      direct-add-not-null-column
      direct-add-foreign-key
      add-column-with-volatile-default
      drop-column-without-code-cleanup
    ].each do |identifier|
      context "when an operator tags a #{identifier} commit with a different valid task type" do # rubocop:disable RSpec/MultipleMemoizedHelpers
        # The seven memoized helpers (`flavor`, `fixed_clock`,
        # `stderr_io`, `bypass_attempt_fixtures`,
        # `required_forbidden_identifiers`, `offending_commit`,
        # `engine`) are each load-bearing for the engine-level
        # bypass-attempt assertions: the first five carry the per-spec
        # configuration shared with T044's per-identifier regression and
        # `engine_spec.rb`, and the last two compose the per-example
        # subject (the operator-tagged offending commit + the wired
        # engine). Splitting them would obscure the one-to-one mapping
        # between the SC-015 contract and the test body.
        let(:offending_commit) { build_bypass_attempt_commit(identifier) }
        let(:engine) { build_engine }

        it 'is rejected with Phaser::ForbiddenOperationError despite the operator tag' do
          expect { engine.process([offending_commit], flavor) }
            .to raise_error(Phaser::ForbiddenOperationError) do |error|
              expect(error.forbidden_operation).to(
                eq(identifier),
                "expected the gate to reject #{identifier} despite the operator tag " \
                "#{bypass_attempt_fixtures.fetch(identifier).fetch(:phase_type_tag).inspect}; " \
                "got #{error.forbidden_operation.inspect}"
              )
            end
        end

        it "emits the registry's canonical decomposition message verbatim (FR-015, SC-008, SC-015)" do
          expect { engine.process([offending_commit], flavor) }
            .to raise_error(Phaser::ForbiddenOperationError) do |error|
              entry = registry_entry(identifier)
              skip "registry entry for #{identifier} not shipped" if entry.nil?

              expect(error.decomposition_message).to eq(entry.fetch('decomposition_message'))
            end
        end

        it 'writes NO phase manifest (gate halts the engine before manifest assembly)' do
          expect { engine.process([offending_commit], flavor) }
            .to raise_error(Phaser::ForbiddenOperationError)

          expect(File.file?(manifest_path)).to(
            be(false),
            "expected no phase manifest at #{manifest_path} after the gate rejected #{identifier}; " \
            'a manifest written under a forbidden-operation rejection means the gate failed to halt the engine'
          )
        end

        it 'persists the failure to phase-creation-status.yaml with stage: phaser-engine (FR-042)' do
          expect { engine.process([offending_commit], flavor) }
            .to raise_error(Phaser::ForbiddenOperationError)

          expect(File.file?(status_path)).to(
            be(true),
            "expected phase-creation-status.yaml at #{status_path} after the gate rejected #{identifier}"
          )
          status = YAML.load_file(status_path)
          expect(status['stage']).to eq('phaser-engine')
        end

        it "records the gate's identifier as forbidden_operation in the status file (FR-042)" do
          expect { engine.process([offending_commit], flavor) }
            .to raise_error(Phaser::ForbiddenOperationError)

          status = YAML.load_file(status_path)
          expect(status['forbidden_operation']).to eq(identifier)
        end

        it 'records the canonical decomposition_message in the status file (FR-042, FR-015)' do
          expect { engine.process([offending_commit], flavor) }
            .to raise_error(Phaser::ForbiddenOperationError)

          entry = registry_entry(identifier)
          skip "registry entry for #{identifier} not shipped" if entry.nil?

          status = YAML.load_file(status_path)
          expect(status['decomposition_message']).to eq(entry.fetch('decomposition_message'))
        end

        it 'records the offending commit_hash in the status file (FR-042, FR-041)' do
          expect { engine.process([offending_commit], flavor) }
            .to raise_error(Phaser::ForbiddenOperationError)

          status = YAML.load_file(status_path)
          expect(status['commit_hash']).to eq(stable_hash_for(identifier))
        end

        it 'emits exactly one validation-failed ERROR record on stderr (FR-041)' do
          expect { engine.process([offending_commit], flavor) }
            .to raise_error(Phaser::ForbiddenOperationError)

          validation_failures = emitted_records.select { |r| r['event'] == 'validation-failed' }
          expect(validation_failures.length).to(
            eq(1),
            "expected exactly one validation-failed ERROR record for #{identifier}; " \
            "got #{validation_failures.length}: #{validation_failures.inspect}"
          )
        end

        it "surfaces the registry's identifier and decomposition_message in the ERROR record (FR-041)" do
          expect { engine.process([offending_commit], flavor) }
            .to raise_error(Phaser::ForbiddenOperationError)

          entry = registry_entry(identifier)
          skip "registry entry for #{identifier} not shipped" if entry.nil?

          record = emitted_records.find { |r| r['event'] == 'validation-failed' }
          skip 'no validation-failed record emitted' if record.nil?

          expect(record['forbidden_operation']).to eq(identifier)
          expect(record['decomposition_message']).to eq(entry.fetch('decomposition_message'))
        end

        it 'emits NO commit-classified INFO record (gate runs before the classifier per FR-049)' do
          # The classifier is the only consumer of `Phase-Type` per FR-016
          # / FR-004; if it runs at all the engine emits a
          # `commit-classified` INFO record per non-empty commit (SC-011).
          # The presence of any such record for the offending commit
          # would prove the gate ran AFTER the classifier — a direct
          # SC-015 / FR-049 violation since the operator-tag would then
          # have had a chance to influence classification before the
          # safety gate fired.
          expect { engine.process([offending_commit], flavor) }
            .to raise_error(Phaser::ForbiddenOperationError)

          classified_records = emitted_records.select { |r| r['event'] == 'commit-classified' }
          expect(classified_records).to(
            be_empty,
            "expected no commit-classified records for #{identifier} (gate must run before classifier); " \
            "got #{classified_records.inspect}"
          )
        end
      end
    end
  end
end
