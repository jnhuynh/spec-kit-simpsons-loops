# frozen_string_literal: true

require 'phaser'

# Specs for the shipped `rails-postgres-strong-migrations` flavor's
# forbidden-operations registry at `phaser/flavors/
# rails-postgres-strong-migrations/flavor.yaml` (and the optional
# `forbidden_operations.rb` module the catalog references for
# `module_method` detectors) — feature 007-multi-phase-pipeline; T044,
# T050, T052, FR-015, FR-041, FR-042, FR-049, SC-005, SC-008,
# data-model.md "ForbiddenOperation".
#
# Position in the engine pipeline (per quickstart.md "Pattern:
# Pre-Classification Gate Discipline"):
#
#   empty-diff filter (FR-009)
#     -> forbidden-operations gate (FR-049)        <-- THIS spec
#     -> classifier (FR-004)
#     -> precedent validator (FR-006)
#     -> reference-flavor validators (FR-013, FR-014, FR-018)
#     -> size guard (FR-048)
#     -> isolation resolver (FR-005)
#     -> manifest writer (FR-002, FR-038)
#
# Contract (FR-015, spec.md User Story 2 Acceptance Scenario 5):
#
#   "The reference flavor MUST ship a registry of forbidden operations
#    (such as direct column-type change, direct rename, non-concurrent
#    index, direct not-null add, direct foreign-key add, column add
#    with volatile default, and column drop without code cleanup) and
#    MUST reject any commit performing one of them with a canonical
#    decomposition message that lists the safe sequence of replacement
#    tasks for that forbidden operation."
#
# SC-005 is the externally measurable bar pinned by THIS spec:
#
#   "Every entry in the forbidden-operations registry has a regression
#    test that produces the canonical decomposition message when the
#    forbidden operation is encountered."
#
# This spec's job is therefore two-fold:
#
#   1. Pin the registry's COMPLETENESS — the seven entries FR-015
#      enumerates by name MUST all be present on the shipped flavor's
#      `forbidden_operations` list, identified by stable identifier
#      strings the operator-facing tooling can refer to without parsing
#      free-form rule names. A missing identifier means the registry
#      ships with a deploy-safety hole.
#
#   2. Pin the per-entry DECOMPOSITION-MESSAGE contract — for every
#      identifier above, build a commit whose diff trips the matching
#      detector, run the commit through the production
#      `Phaser::ForbiddenOperationsGate` instantiated from the shipped
#      flavor's registry, assert (a) the gate returns the right entry,
#      (b) the canonical decomposition message on that entry is the
#      one surfaced through `Phaser::ForbiddenOperationError`, and
#      (c) the message is non-empty and lists at least one safe
#      replacement task name (so a future contributor cannot satisfy
#      the contract by emitting "decomposition: TODO"). SC-005 mandates
#      a "regression test that produces the canonical decomposition
#      message"; we do exactly that, per identifier, in one example
#      each so a regression failure points at the broken identifier
#      unambiguously.
#
# What this spec deliberately does NOT cover:
#
#   * SC-015 (operator-tag-cannot-bypass-gate) lives in T045's
#     `operator_tag_cannot_bypass_gate_spec.rb`. The registry-level
#     bypass-surface contract (D-016 — no `skip:` / `force:` / `allow:`
#     keyword on the gate itself) is already pinned by
#     `spec/forbidden_operations_gate_spec.rb` (T022) and is not
#     re-asserted here to avoid two parallel checklists drifting apart.
#
#   * Detector-shape semantics (file_glob vs. content_regex vs.
#     module_method dispatch) are pinned by the gate's unit spec
#     (T022). This spec asserts the registry's BEHAVIOUR end-to-end,
#     not the detector dispatch mechanics.
#
#   * The flavor's wider catalog (task types, isolation, inference,
#     precedent rules) is pinned by sibling specs
#     (`catalog_spec.rb`, `inference_spec.rb`,
#     `precedent_validator_spec.rb`, `backfill_validator_spec.rb`).
#     This spec only loads the flavor to read its
#     `forbidden_operations` list.
#
# Determinism contract (FR-002, SC-002):
#
#   * Each per-identifier example builds an independent commit so the
#     order in which they run is irrelevant.
#   * The fixture commits use stable, pinned 40-char hex hashes so a
#     regression failure's payload (commit_hash) is reproducible.
#
# This spec MUST observe failure (red) before T050 ships
# `flavor.yaml` and T052 ships `forbidden_operations.rb` (the
# test-first requirement in CLAUDE.md "Test-First Development"). Until
# then, `Phaser::FlavorLoader#load('rails-postgres-strong-migrations')`
# raises `Phaser::FlavorNotFoundError` (or, once the catalog skeleton
# lands, the per-identifier examples observe the gate returning nil for
# the offending fixture commits because the registry is empty).
RSpec.describe 'rails-postgres-strong-migrations forbidden-operations registry' do # rubocop:disable RSpec/DescribeClass
  # Canonical identifiers FR-015 enumerates. Reproduced here verbatim
  # so a registry-level rename has to come through this spec, NOT
  # through a silent edit to `flavor.yaml`. The chosen identifier
  # strings mirror the convention pinned by
  # `spec/forbidden_operations_gate_spec.rb`'s `direct-column-rename`
  # fixture — kebab-case nouns naming the unsafe operation.
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

  # Per-identifier fixture descriptors. Each entry names:
  #
  #   * `path`  — the file path the offending commit's diff touches.
  #               Chosen so the path-shape (`db/migrate/*.rb`) trips a
  #               detector kind the registry is expected to use for
  #               that identifier (file_glob, path_regex, or
  #               content_regex's path_glob). The flavor's authors
  #               (T050/T052) decide whether the registry's detector is
  #               file_glob or content_regex; the fixture's hunk text
  #               below is shaped so EITHER detector kind matches.
  #
  #   * `hunks` — a one-or-two line excerpt of the unsafe Ruby a real
  #               offending migration would contain. Each excerpt is
  #               the canonical "smoking gun" the registry's detector
  #               is expected to look for (e.g. `change_column ...`
  #               for direct column-type change). Keeping the hunks
  #               minimal makes failures easy to diff against the
  #               flavor's regex.
  #
  #   * `safe_replacement_keywords` — at least one substring that any
  #               reasonable canonical decomposition message would
  #               contain. The keyword list is intentionally flexible
  #               (case-insensitive, OR semantics — at least one match
  #               required) so this spec does NOT pin the prose;
  #               authors can refine wording without breaking the
  #               regression. The keywords ARE pinned where the
  #               replacement-task SEQUENCE is part of the contract
  #               (e.g. "dual-write" + "backfill" + "switch reads"
  #               for column rename).
  let(:forbidden_fixtures) do
    {
      'direct-column-type-change' => {
        path: 'db/migrate/20260425000001_change_users_email_to_text.rb',
        hunks: ["@@ -0,0 +1 @@\n+    change_column :users, :email, :text\n"],
        safe_replacement_keywords: ['add column', 'backfill']
      },
      'direct-column-rename' => {
        path: 'db/migrate/20260425000002_rename_users_email.rb',
        hunks: ["@@ -0,0 +1 @@\n+    rename_column :users, :email, :email_address\n"],
        safe_replacement_keywords: %w[add dual-write backfill switch drop]
      },
      'non-concurrent-index' => {
        path: 'db/migrate/20260425000003_add_index_users_email.rb',
        hunks: ["@@ -0,0 +1 @@\n+    add_index :users, :email\n"],
        safe_replacement_keywords: %w[concurrently disable_ddl_transaction]
      },
      'direct-add-not-null-column' => {
        path: 'db/migrate/20260425000004_add_required_email_to_users.rb',
        hunks: ["@@ -0,0 +1 @@\n+    add_column :users, :email, :string, null: false\n"],
        safe_replacement_keywords: ['nullable', 'backfill', 'check constraint']
      },
      'direct-add-foreign-key' => {
        path: 'db/migrate/20260425000005_add_fk_users_to_orgs.rb',
        hunks: ["@@ -0,0 +1 @@\n+    add_foreign_key :users, :orgs\n"],
        safe_replacement_keywords: ['validate:', 'not valid']
      },
      'add-column-with-volatile-default' => {
        path: 'db/migrate/20260425000006_add_seen_at_to_users.rb',
        hunks: [
          "@@ -0,0 +1 @@\n+    add_column :users, :seen_at, :datetime, " \
          "default: -> { 'now()' }\n"
        ],
        safe_replacement_keywords: %w[without backfill default]
      },
      'drop-column-without-code-cleanup' => {
        path: 'db/migrate/20260425000007_drop_legacy_email_from_users.rb',
        hunks: ["@@ -0,0 +1 @@\n+    remove_column :users, :legacy_email\n"],
        safe_replacement_keywords: ['ignored_columns', 'remove references']
      }
    }.freeze
  end

  let(:flavor) do
    Phaser::FlavorLoader.new.load('rails-postgres-strong-migrations')
  end

  # The production gate, instantiated from the shipped flavor's
  # registry. Mirrors how the engine wires the gate in
  # `Phaser::Engine#process` (T035). The `forbidden_module` is wired
  # only when the flavor declares one; reference-flavor authors are
  # expected to use a mix of declarative (file_glob / content_regex /
  # path_regex) and imperative (module_method, via
  # `Phaser::Flavors::RailsPostgresStrongMigrations::ForbiddenOperations`)
  # detectors per T052.
  let(:gate) do
    Phaser::ForbiddenOperationsGate.new(
      forbidden_operations: flavor.forbidden_operations,
      forbidden_module: resolve_forbidden_module(flavor.forbidden_module)
    )
  end

  # Build a Phaser::Commit whose single FileChange exercises the
  # registry's detector for `identifier`. The hash is derived from the
  # identifier so each fixture commit's hash is stable but distinct
  # across the per-identifier examples below.
  def build_offending_commit(identifier, fixtures)
    fixture = fixtures.fetch(identifier)
    Phaser::Commit.new(
      hash: stable_hash_for(identifier),
      subject: "Trigger #{identifier}",
      message_trailers: {},
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
  # across runs (FR-002, SC-002).
  def stable_hash_for(identifier)
    seed = identifier.bytes.sum.to_s(16)
    seed.rjust(40, identifier[0]).slice(0, 40)
  end

  # Resolve the flavor's `forbidden_module` string (e.g.
  # "Phaser::Flavors::RailsPostgresStrongMigrations::ForbiddenOperations")
  # to the actual constant. Returns nil when the flavor does not
  # declare a module — the gate constructor accepts nil for the
  # all-declarative case.
  def resolve_forbidden_module(name)
    return nil if name.nil? || name.empty?

    name.split('::').inject(Object) { |const, part| const.const_get(part) }
  end

  describe 'FR-015 registry completeness (SC-005 prerequisite)' do
    it 'declares every required forbidden-operation identifier' do
      shipped = flavor.forbidden_operations.map { |entry| entry.fetch('identifier') }

      expect(shipped).to include(*required_forbidden_identifiers)
    end

    it 'declares each forbidden-operation identifier exactly once (no duplicates)' do
      shipped = flavor.forbidden_operations.map { |entry| entry.fetch('identifier') }

      expect(shipped).to eq(shipped.uniq)
    end

    it 'declares a non-empty canonical decomposition_message on every registry entry (FR-015)' do
      flavor.forbidden_operations.each do |entry|
        identifier = entry.fetch('identifier')
        message = entry.fetch('decomposition_message')

        expect(message).to be_a(String).and(satisfy { |m| !m.strip.empty? }),
                           "expected #{identifier.inspect} to ship a non-empty decomposition_message"
      end
    end

    it 'declares a stable name on every registry entry (used as failing_rule per FR-041)' do
      flavor.forbidden_operations.each do |entry|
        identifier = entry.fetch('identifier')
        name = entry.fetch('name')

        expect(name).to be_a(String).and(satisfy { |n| !n.strip.empty? }),
                        "expected #{identifier.inspect} to ship a non-empty rule name"
      end
    end
  end

  describe 'SC-005 per-identifier regression (canonical decomposition message)' do
    # Iterating identifiers at example-definition time is intentional:
    # each identifier becomes its own context with three named
    # examples so a regression failure points at "it's
    # `add-column-with-volatile-default`'s detector that broke", not
    # "1/21 examples failed."
    %w[
      direct-column-type-change
      direct-column-rename
      non-concurrent-index
      direct-add-not-null-column
      direct-add-foreign-key
      add-column-with-volatile-default
      drop-column-without-code-cleanup
    ].each do |identifier|
      context "when a commit performs #{identifier}" do
        it "is rejected by the gate with the registry's canonical decomposition message" do
          commit = build_offending_commit(identifier, forbidden_fixtures)
          matched_entry = gate.evaluate(commit)

          expect(matched_entry).not_to(
            be_nil,
            "expected the registry to reject #{identifier} via its detector; the gate returned nil " \
            '— the detector for this identifier is missing or broken'
          )
          expect(matched_entry.fetch('identifier')).to(
            eq(identifier),
            "expected the gate to match #{identifier} but it matched " \
            "#{matched_entry.fetch('identifier').inspect} (registry order or overlapping detectors)"
          )
        end

        it 'exposes the canonical decomposition message via Phaser::ForbiddenOperationError (FR-015, SC-008)' do
          commit = build_offending_commit(identifier, forbidden_fixtures)
          matched_entry = gate.evaluate(commit)

          # Skip the message contract assertion when the registry
          # didn't match — the prior example already records that
          # failure and pinning the message here too would just emit
          # a noisier traceback for the same root cause.
          skip "registry did not match #{identifier}" if matched_entry.nil?

          error = Phaser::ForbiddenOperationError.new(commit: commit, entry: matched_entry)
          canonical_message = matched_entry.fetch('decomposition_message')

          expect(error.decomposition_message).to eq(canonical_message)
          expect(error.forbidden_operation).to eq(identifier)
          expect(error.commit_hash).to eq(commit.hash)
        end

        it 'names at least one safe replacement task in the decomposition message' do
          commit = build_offending_commit(identifier, forbidden_fixtures)
          matched_entry = gate.evaluate(commit)
          skip "registry did not match #{identifier}" if matched_entry.nil?

          message = matched_entry.fetch('decomposition_message').downcase
          required_keywords = forbidden_fixtures.fetch(identifier).fetch(:safe_replacement_keywords)

          # OR semantics — the canonical message must mention at
          # least one safe replacement keyword (e.g. "dual-write" or
          # "concurrently"). A message that ships with NONE of the
          # expected keywords is almost certainly a TODO placeholder
          # that satisfies the schema but fails the operator-facing
          # contract FR-015 / SC-008 demand.
          matched_keyword = required_keywords.find { |kw| message.include?(kw.downcase) }

          expect(matched_keyword).not_to(
            be_nil,
            "expected the canonical decomposition message for #{identifier} to mention " \
            "at least one of #{required_keywords.inspect}, got: #{message.inspect}"
          )
        end
      end
    end
  end

  describe 'validation-failed payload integration (FR-041, FR-042)' do
    it 'serializes every registry rejection to the four-field forbidden-operation payload shape' do
      required_forbidden_identifiers.each do |identifier|
        commit = build_offending_commit(identifier, forbidden_fixtures)
        matched_entry = gate.evaluate(commit)

        next if matched_entry.nil? # surfaced by the per-identifier specs above

        error = Phaser::ForbiddenOperationError.new(commit: commit, entry: matched_entry)
        payload = error.to_validation_failed_payload

        expect(payload.keys).to(
          contain_exactly(:commit_hash, :failing_rule, :forbidden_operation, :decomposition_message),
          "expected #{identifier} payload to expose only the four forbidden-operation keys, " \
          "got #{payload.keys.inspect}"
        )
        expect(payload[:forbidden_operation]).to eq(identifier)
        expect(payload[:decomposition_message]).to eq(matched_entry.fetch('decomposition_message'))
      end
    end
  end
end
