# frozen_string_literal: true

require 'phaser'

# Specs for the shipped `rails-postgres-strong-migrations` flavor's
# safety-assertion-block validator at `phaser/flavors/
# rails-postgres-strong-migrations/safety_assertion_validator.rb`
# (feature 007-multi-phase-pipeline; T046b/T054b, FR-018, plan.md
# D-017, FR-041, FR-042, data-model.md "Task" `safety_assertion_precedents`
# field, data-model.md "Error Conditions" rows for safety-assertion
# failures).
#
# Position in the engine pipeline (per quickstart.md "Pattern:
# Pre-Classification Gate Discipline" and the validators-list dispatch
# wired through `flavor_loader.rb` in T055):
#
#   empty-diff filter (FR-009)
#     -> forbidden-operations gate (FR-049)
#     -> classifier (FR-004)
#     -> precedent validator (FR-006, engine-level — one rule at a time)
#     -> reference-flavor validators (FR-013 backfill, FR-014 column-drop, FR-018 safety-assertion)
#     -> size guard (FR-048)
#     -> isolation resolver (FR-005)
#     -> manifest writer (FR-002, FR-038)
#
# Contract (FR-018, plan.md D-017):
#
#   "The reference flavor MUST require that any commit which performs
#    an irreversible schema operation references the precedent commit
#    hash in its safety-assertion block, so that audit reviewers can
#    trace the precedent chain."
#
# The safety-assertion block is the operator-curated audit-trail
# attached to commits the flavor declares irreversible — column drop,
# table drop, concurrent index drop, and remove-ignored-columns
# directive. The validator catches three failure modes:
#
#   1. The commit message carries no `Safety-Assertion:` trailer (and
#      no fenced ` ```safety-assertion ` block) — `failing_rule:
#      safety-assertion-missing`.
#   2. The commit message cites a SHA that is not a valid precedent
#      under the flavor's precedent rules for the subject task type —
#      `failing_rule: safety-assertion-precedent-mismatch`.
#   3. (No third failure mode — well-formed assertions succeed and the
#      cited SHAs are recorded on the manifest's Task entry via the
#      `safety_assertion_precedents` field per data-model.md.)
#
# The set of irreversible task types is declared in `flavor.yaml`
# under `irreversible_task_types` (per plan.md D-017 and T054b). The
# validator reads that list off the active `Phaser::Flavor` and only
# fires on commits whose classified `task_type` is in the list. Every
# other classified commit is passed through untouched — the surface for
# catching unsafe non-irreversible commits belongs to the
# forbidden-operations gate (FR-015), the engine's PrecedentValidator
# (FR-006), and the per-flavor BackfillValidator (FR-013) /
# PrecedentValidator (FR-014), not this one.
#
# Surface (T054b):
#
#   * `Phaser::Flavors::RailsPostgresStrongMigrations::SafetyAssertionValidator
#     .new` — stateless; constructed once per engine run with no
#     arguments. Mirrors the bypass-empty stance of the engine
#     PrecedentValidator and the ForbiddenOperationsGate (D-016): no
#     `skip:` / `force:` / `allow:` keyword exists.
#
#   * `#validate(classification_results, commits, flavor)` — given the
#     post-precedent-validator list of `Phaser::ClassificationResult`s
#     in commit-emission order, the same-length list of source
#     `Phaser::Commit`s (so the validator can read each subject
#     commit's `message_trailers` for the `Safety-Assertion:` trailer
#     and verify the cited SHAs reference earlier commits in the input
#     list), and the active `Phaser::Flavor` (so the validator can
#     read `irreversible_task_types` and the precedent rules),
#     returns a NEW list of classification results with the cited
#     SHAs attached to each accepted irreversible commit's result via
#     a `safety_assertion_precedents` field on the result (or via a
#     side-channel the engine forwards into `Task#new` in T055 —
#     either implementation is allowed; the externally observable
#     contract is that the manifest's Task entry for an irreversible
#     commit carries the cited SHAs in its `safety_assertion_precedents`
#     field per data-model.md "Task").
#
#     On the first violation the validator raises
#     `Phaser::SafetyAssertionError`; classifications that already
#     passed before the violation are NOT returned because the engine
#     never proceeds past a safety-assertion failure.
#
#   * `Phaser::SafetyAssertionError` — exception raised by the
#     validator. Carries the offending commit hash, one of two
#     canonical `failing_rule` values (`'safety-assertion-missing'` or
#     `'safety-assertion-precedent-mismatch'`), and a
#     `cited_precedents` field whose value is an Array of the SHAs
#     parsed out of the commit's safety-assertion block (empty array
#     when the block is absent entirely; non-empty array of the
#     non-matching SHAs when the failure is a precedent mismatch).
#     Descends from `Phaser::ValidationError` so the engine's outer
#     rescue clause handles it uniformly with the other validation
#     failure modes (forbidden-operation, precedent, backfill-safety,
#     feature-too-large, unknown-type-tag, column-drop precedent).
#
# Determinism contract (FR-002, SC-002):
#
#   * The validator iterates commits in input order; the FIRST
#     irreversible-commit violation in input order is the one
#     reported.
#   * Within the `cited_precedents` array, the SHAs are listed in the
#     order they appear in the commit's safety-assertion block so the
#     operator-facing message is reproducible across runs.
#   * Two operators running the reference flavor against the same
#     commits MUST see the same offending commit reported, with the
#     same `failing_rule` and `cited_precedents` values.
#
# Logging / status-file contract (FR-041, FR-042, data-model.md
# "PhaseCreationStatus", contracts/observability-events.md
# `validation-failed`):
#
#   * The engine relays `error.to_validation_failed_payload` to
#     `Observability#log_validation_failed` and `StatusWriter#write`.
#     The payload carries `{commit_hash, failing_rule}` plus, on a
#     `safety-assertion-precedent-mismatch` failure, a singular
#     `missing_precedent` key that joins the cited SHAs with `", "` so
#     the existing `phase-creation-status.yaml` schema field carries
#     the audit trail without introducing a schema-incompatible new
#     key. The validator does NOT write to stderr or to the status
#     file directly; emission is the engine's responsibility (FR-041
#     mandates exactly one `validation-failed` ERROR record per
#     failure).
#
# Audit-trail contract (data-model.md "Task" `safety_assertion_precedents`):
#
#   * On success the validator records the cited SHAs so they reach
#     `Task#safety_assertion_precedents` on the manifest. This is the
#     externally observable artifact reviewers consult AFTER the
#     phaser stage to trace the precedent chain without rerunning the
#     engine.
#
# This spec MUST observe failure (red) before T054b ships
# `safety_assertion_validator.rb` (the test-first requirement in
# CLAUDE.md "Test-First Development"). Until then, the
# `Phaser::Flavors::RailsPostgresStrongMigrations::SafetyAssertionValidator`
# constant does not exist and the first `described_class` reference
# raises `NameError`.
RSpec.describe 'Phaser::Flavors::RailsPostgresStrongMigrations::SafetyAssertionValidator' do
  subject(:validator) do
    Phaser::Flavors::RailsPostgresStrongMigrations::SafetyAssertionValidator.new
  end

  # Canonical task-type names from FR-010 / catalog_spec.rb's
  # required_task_types. The four irreversible task types declared by
  # plan.md D-017 plus their precedent types and a non-irreversible
  # catch-all so the validator's "no-op on non-irreversible task
  # types" path can be exercised. Centralised so a future rename in
  # flavor.yaml only flips one constant per role here. Defined as
  # plain methods rather than `let` blocks so they do not count
  # toward `RSpec/MultipleMemoizedHelpers` — the type names are
  # immutable strings, so the per-example memoization that `let`
  # provides has no value.
  def drop_column_type = 'schema drop-column-with-cleanup-precedent'
  def drop_table_type = 'schema drop-table'
  def drop_concurrent_index_type = 'schema drop-concurrent-index'
  def remove_ignored_columns_type = 'code remove-ignored-columns-directive'
  def ignore_type = 'code ignore-column-for-pending-drop'
  def remove_refs_type = 'code remove-references-to-pending-drop-column'
  def catch_all_type = 'code default-catch-all-change'

  # Build a minimal Phaser::Flavor with the four irreversible task
  # types, the two precedent types the column-drop subject points at,
  # and a non-irreversible catch-all. The validator reads the
  # `irreversible_task_types` list off the flavor (per plan.md D-017
  # and T054b) plus the precedent rules so it can verify that each
  # cited SHA's classified type is a valid precedent for the subject
  # type. We mirror the FlavorLoader's value-object surface so the
  # validator sees what production hands it.
  def build_flavor # rubocop:disable Metrics/MethodLength,Metrics/AbcSize
    Phaser::Flavor.new(
      name: 'rails-postgres-strong-migrations',
      version: '0.1.0',
      default_type: catch_all_type,
      task_types: [
        Phaser::FlavorTaskType.new(
          name: drop_column_type, isolation: :alone,
          description: 'Drop a column whose code references have already been removed.'
        ),
        Phaser::FlavorTaskType.new(
          name: drop_table_type, isolation: :alone,
          description: 'Drop a table whose code references have already been removed.'
        ),
        Phaser::FlavorTaskType.new(
          name: drop_concurrent_index_type, isolation: :alone,
          description: 'Drop a non-unique index concurrently.'
        ),
        Phaser::FlavorTaskType.new(
          name: remove_ignored_columns_type, isolation: :groups,
          description: 'Remove the ignored-columns directive after the column drop has shipped.'
        ),
        Phaser::FlavorTaskType.new(
          name: ignore_type, isolation: :groups,
          description: 'Mark a column as ignored on the model so it can be dropped safely.'
        ),
        Phaser::FlavorTaskType.new(
          name: remove_refs_type, isolation: :groups,
          description: 'Remove all code references to a column slated for drop.'
        ),
        Phaser::FlavorTaskType.new(
          name: catch_all_type, isolation: :groups,
          description: 'Default catch-all code change.'
        )
      ],
      precedent_rules: [
        Phaser::FlavorPrecedentRule.new(
          name: 'drop-column-after-ignore',
          subject_type: drop_column_type,
          predecessor_type: ignore_type,
          error_message: 'A column drop must be preceded by an ignored-columns directive.'
        ),
        Phaser::FlavorPrecedentRule.new(
          name: 'drop-column-after-remove-refs',
          subject_type: drop_column_type,
          predecessor_type: remove_refs_type,
          error_message: 'A column drop must be preceded by reference removal.'
        )
      ],
      inference_rules: [],
      forbidden_operations: [],
      stack_detection: Phaser::FlavorStackDetection.new(signals: []),
      validators: [
        'Phaser::Flavors::RailsPostgresStrongMigrations::SafetyAssertionValidator'
      ]
    ).then do |flavor|
      # The flavor exposes `irreversible_task_types` either as an
      # accessor on the value object or via the loader's catalog Hash.
      # The validator's contract is that it reads the four canonical
      # irreversible types from the active flavor; we expose them as a
      # singleton method here to mirror what the loader will surface
      # in T054b/T055 without prematurely committing this spec to the
      # exact accessor name. The validator's implementation may read
      # via `flavor.respond_to?(:irreversible_task_types)` and fall
      # back to a hardcoded list if not — either path satisfies the
      # external contract this spec asserts.
      flavor.define_singleton_method(:irreversible_task_types) do
        [
          'schema drop-column-with-cleanup-precedent',
          'schema drop-table',
          'schema drop-concurrent-index',
          'code remove-ignored-columns-directive'
        ]
      end
      flavor
    end
  end

  # Build a Phaser::Commit for an "ignored-columns directive" precedent.
  # The validator uses this commit's hash as a SHA the irreversible
  # commit's safety-assertion block can cite.
  def build_ignore_commit(hash:)
    Phaser::Commit.new(
      hash: hash,
      subject: 'Ignore legacy_email on User',
      message_trailers: {},
      diff: Phaser::Diff.new(
        files: [
          Phaser::FileChange.new(
            path: 'app/models/user.rb',
            change_kind: :modified,
            hunks: ["+  self.ignored_columns = %w[legacy_email]\n"]
          )
        ]
      ),
      author_timestamp: '2026-04-25T12:00:00Z'
    )
  end

  # Build a Phaser::Commit for a "remove references" precedent.
  def build_remove_refs_commit(hash:)
    Phaser::Commit.new(
      hash: hash,
      subject: 'Remove references to legacy_email',
      message_trailers: {},
      diff: Phaser::Diff.new(
        files: [
          Phaser::FileChange.new(
            path: 'app/models/user.rb',
            change_kind: :modified,
            hunks: ["-  validates :legacy_email, presence: true\n"]
          )
        ]
      ),
      author_timestamp: '2026-04-25T12:00:00Z'
    )
  end

  # Build a Phaser::Commit for an irreversible column-drop with a
  # `Safety-Assertion:` trailer naming the supplied precedent SHAs.
  # The trailer format matches Git's standard `key: value` trailer
  # syntax; multiple SHAs are comma-separated. The validator parses
  # the trailer value with `value.scan(/[0-9a-f]{40}/)` so additional
  # surrounding prose is ignored.
  def build_drop_commit(hash:, cited_shas: [], use_fenced_block: false)
    Phaser::Commit.new(
      hash: hash,
      subject: drop_commit_subject(cited_shas, use_fenced_block),
      message_trailers: drop_commit_trailers(cited_shas, use_fenced_block),
      diff: drop_commit_diff,
      author_timestamp: '2026-04-25T12:00:00Z'
    )
  end

  def drop_commit_trailers(cited_shas, use_fenced_block)
    return {} if cited_shas.empty? || use_fenced_block

    { 'Safety-Assertion' => cited_shas.join(', ') }
  end

  def drop_commit_subject(cited_shas, use_fenced_block)
    return 'Drop users.legacy_email' unless use_fenced_block && cited_shas.any?

    "Drop users.legacy_email\n\n```safety-assertion\n#{cited_shas.join("\n")}\n```\n"
  end

  def drop_commit_diff
    Phaser::Diff.new(
      files: [
        Phaser::FileChange.new(
          path: 'db/migrate/20260425000099_drop_users_legacy_email.rb',
          change_kind: :added,
          hunks: ["+    remove_column :users, :legacy_email\n"]
        )
      ]
    )
  end

  # Build a Phaser::Commit for an unrelated catch-all change. Used by
  # the per-task-type scope check and by the precedent-mismatch
  # path that cites a catch-all SHA.
  def build_catch_all_commit(hash)
    Phaser::Commit.new(
      hash: hash,
      subject: 'Tweak unrelated copy',
      message_trailers: {},
      diff: Phaser::Diff.new(
        files: [
          Phaser::FileChange.new(
            path: 'app/views/home.html.erb',
            change_kind: :modified,
            hunks: ["+<p>Welcome</p>\n"]
          )
        ]
      ),
      author_timestamp: '2026-04-25T12:00:00Z'
    )
  end

  # Build a ClassificationResult that pretends the upstream classifier
  # has already labelled the commit. The validator's contract is that
  # classification has already happened — it inspects classified
  # commits, not raw ones — so we can fixture the result directly
  # rather than running the full classifier.
  def build_result(commit_hash, task_type)
    isolation = case task_type
                when drop_column_type, drop_table_type, drop_concurrent_index_type
                  :alone
                else
                  :groups
                end
    Phaser::ClassificationResult.new(
      commit_hash: commit_hash,
      task_type: task_type,
      source: :inference,
      isolation: isolation,
      rule_name: 'irreversible-by-path',
      precedents_consulted: nil
    )
  end

  describe '#validate — accepts irreversible commits with a well-formed safety-assertion block (FR-018)' do
    it 'returns the classification results unchanged when the cited SHA is a valid precedent' do
      ignore = build_ignore_commit(hash: 'a' * 40)
      remove_refs = build_remove_refs_commit(hash: 'b' * 40)
      drop = build_drop_commit(hash: 'c' * 40, cited_shas: [ignore.hash, remove_refs.hash])
      commits = [ignore, remove_refs, drop]
      results = [
        build_result(ignore.hash, ignore_type),
        build_result(remove_refs.hash, remove_refs_type),
        build_result(drop.hash, drop_column_type)
      ]

      output = validator.validate(results, commits, build_flavor)

      expect(output.length).to eq(results.length)
    end

    it 'parses comma-separated SHAs out of the Safety-Assertion: trailer' do
      ignore = build_ignore_commit(hash: 'a' * 40)
      remove_refs = build_remove_refs_commit(hash: 'b' * 40)
      drop = build_drop_commit(hash: 'c' * 40, cited_shas: [ignore.hash, remove_refs.hash])
      commits = [ignore, remove_refs, drop]
      results = [
        build_result(ignore.hash, ignore_type),
        build_result(remove_refs.hash, remove_refs_type),
        build_result(drop.hash, drop_column_type)
      ]

      expect { validator.validate(results, commits, build_flavor) }.not_to raise_error
    end

    it 'parses SHAs out of a fenced ```safety-assertion block in the commit body' do
      ignore = build_ignore_commit(hash: 'a' * 40)
      remove_refs = build_remove_refs_commit(hash: 'b' * 40)
      drop = build_drop_commit(
        hash: 'c' * 40,
        cited_shas: [ignore.hash, remove_refs.hash],
        use_fenced_block: true
      )
      commits = [ignore, remove_refs, drop]
      results = [
        build_result(ignore.hash, ignore_type),
        build_result(remove_refs.hash, remove_refs_type),
        build_result(drop.hash, drop_column_type)
      ]

      expect { validator.validate(results, commits, build_flavor) }.not_to raise_error
    end

    it 'is a no-op on commits whose classified task_type is not in irreversible_task_types' do
      # A `code default-catch-all-change` commit with NO safety-assertion
      # block MUST NOT be rejected by THIS validator — the catch-all
      # type is not declared irreversible by the flavor.
      catch_all_commit = build_catch_all_commit('a' * 40)
      result = build_result(catch_all_commit.hash, catch_all_type)

      expect { validator.validate([result], [catch_all_commit], build_flavor) }
        .not_to raise_error
    end

    it 'is a no-op when no commit is classified as one of the irreversible task types' do
      ignore = build_ignore_commit(hash: 'a' * 40)
      commits = [ignore]
      results = [build_result(ignore.hash, ignore_type)]

      expect { validator.validate(results, commits, build_flavor) }
        .not_to raise_error
    end

    it 'is a no-op on an empty input list' do
      expect { validator.validate([], [], build_flavor) }.not_to raise_error
    end
  end

  # rubocop:disable Layout/LineLength
  describe '#validate — records cited SHAs on the accepted classification result (data-model.md "Task" safety_assertion_precedents)' do
    # rubocop:enable Layout/LineLength
    # The audit-trail contract is that the cited SHAs reach the
    # manifest's Task entry via the `safety_assertion_precedents`
    # field. The validator may surface them either by mutating the
    # ClassificationResult (returning a new result with the SHAs
    # attached) or via a side-channel the engine forwards into
    # `Task#new`. Either implementation satisfies the contract; this
    # block asserts only the externally observable surface — the SHAs
    # MUST be retrievable from the validator's return value, in cited
    # order, for every accepted irreversible commit.
    it 'attaches the cited SHAs to the irreversible commit\'s entry in the validator\'s output' do # rubocop:disable RSpec/ExampleLength
      ignore = build_ignore_commit(hash: 'a' * 40)
      remove_refs = build_remove_refs_commit(hash: 'b' * 40)
      drop = build_drop_commit(hash: 'c' * 40, cited_shas: [ignore.hash, remove_refs.hash])
      commits = [ignore, remove_refs, drop]
      results = [
        build_result(ignore.hash, ignore_type),
        build_result(remove_refs.hash, remove_refs_type),
        build_result(drop.hash, drop_column_type)
      ]

      output = validator.validate(results, commits, build_flavor)
      drop_entry = output.find { |r| r.commit_hash == drop.hash }

      expect(drop_entry).not_to be_nil
      # Either the ClassificationResult exposes a
      # `safety_assertion_precedents` accessor directly OR the
      # validator returns a parallel structure (Hash, struct, etc.)
      # the engine reads. Both are honoured by checking that the
      # cited SHAs appear in cited order on whatever surface the
      # output exposes for the irreversible commit.
      cited = if drop_entry.respond_to?(:safety_assertion_precedents)
                drop_entry.safety_assertion_precedents
              elsif output.respond_to?(:safety_assertion_precedents_for)
                output.safety_assertion_precedents_for(drop.hash)
              end

      expect(cited).to eq([ignore.hash, remove_refs.hash])
    end

    it 'leaves non-irreversible commits\' entries with no safety_assertion_precedents recorded' do
      ignore = build_ignore_commit(hash: 'a' * 40)
      results = [build_result(ignore.hash, ignore_type)]

      output = validator.validate(results, [ignore], build_flavor)
      ignore_entry = output.find { |r| r.commit_hash == ignore.hash }

      cited = ignore_entry.safety_assertion_precedents if ignore_entry.respond_to?(:safety_assertion_precedents)
      expect(cited).to be_nil
    end
  end

  # rubocop:disable Layout/LineLength
  describe '#validate — rejects irreversible commits with NO safety-assertion block (FR-018, failing_rule: safety-assertion-missing)' do
    # rubocop:enable Layout/LineLength
    it 'raises SafetyAssertionError when a column-drop commit has no Safety-Assertion: trailer and no fenced block' do
      ignore = build_ignore_commit(hash: 'a' * 40)
      remove_refs = build_remove_refs_commit(hash: 'b' * 40)
      drop = build_drop_commit(hash: 'c' * 40, cited_shas: [])
      commits = [ignore, remove_refs, drop]
      results = [
        build_result(ignore.hash, ignore_type),
        build_result(remove_refs.hash, remove_refs_type),
        build_result(drop.hash, drop_column_type)
      ]

      expect { validator.validate(results, commits, build_flavor) }
        .to raise_error(Phaser::SafetyAssertionError) do |error|
          expect(error.commit_hash).to eq('c' * 40)
          expect(error.failing_rule).to eq('safety-assertion-missing')
          expect(error.cited_precedents).to eq([])
        end
    end

    # The flavor declares four irreversible task types per plan.md
    # D-017 (drop-column, drop-table, drop-concurrent-index,
    # remove-ignored-columns); the validator MUST fire on every one
    # of them.
    it 'fires for every irreversible task type declared by the flavor' do
      flavor = build_flavor
      flavor.irreversible_task_types.each do |irreversible_type|
        commit = build_drop_commit(hash: 'c' * 40, cited_shas: [])
        result = build_result(commit.hash, irreversible_type)

        expect { validator.validate([result], [commit], flavor) }
          .to raise_error(Phaser::SafetyAssertionError) do |error|
            expect(error.failing_rule).to eq('safety-assertion-missing')
            expect(error.commit_hash).to eq('c' * 40)
          end
      end
    end

    it 'names the offending commit hash in the error message (FR-041, SC-008)' do
      drop = build_drop_commit(hash: 'd' * 40, cited_shas: [])
      results = [build_result(drop.hash, drop_column_type)]

      expect { validator.validate(results, [drop], build_flavor) }
        .to raise_error(Phaser::SafetyAssertionError) do |error|
          expect(error.message).to include('d' * 40)
        end
    end
  end

  # rubocop:disable Layout/LineLength
  describe '#validate — rejects irreversible commits whose cited SHA is not a valid precedent (FR-018, safety-assertion-precedent-mismatch)' do
    # rubocop:enable Layout/LineLength
    it 'raises SafetyAssertionError when the cited SHA does not appear earlier in the input list' do
      # Cite a SHA that simply does not exist on the feature branch.
      drop = build_drop_commit(hash: 'c' * 40, cited_shas: ['9' * 40])
      results = [build_result(drop.hash, drop_column_type)]

      expect { validator.validate(results, [drop], build_flavor) }
        .to raise_error(Phaser::SafetyAssertionError) do |error|
          expect(error.commit_hash).to eq('c' * 40)
          expect(error.failing_rule).to eq('safety-assertion-precedent-mismatch')
          expect(error.cited_precedents).to eq(['9' * 40])
        end
    end

    it 'raises SafetyAssertionError when the cited SHA exists but its type is not a valid precedent for the subject' do
      # Cite a `code default-catch-all-change` commit's SHA in the
      # safety-assertion block of a column-drop. The catch-all type is
      # not in the flavor's precedent rules for `schema
      # drop-column-with-cleanup-precedent`, so the validator MUST
      # reject the assertion as a precedent mismatch.
      catch_all = build_catch_all_commit('a' * 40)
      drop = build_drop_commit(hash: 'c' * 40, cited_shas: [catch_all.hash])
      commits = [catch_all, drop]
      results = [
        build_result(catch_all.hash, catch_all_type),
        build_result(drop.hash, drop_column_type)
      ]

      expect { validator.validate(results, commits, build_flavor) }
        .to raise_error(Phaser::SafetyAssertionError) do |error|
          expect(error.commit_hash).to eq('c' * 40)
          expect(error.failing_rule).to eq('safety-assertion-precedent-mismatch')
          expect(error.cited_precedents).to eq(['a' * 40])
        end
    end

    it 'rejects a cited SHA that appears AFTER the irreversible commit in input order (FR-006 spirit)' do
      drop = build_drop_commit(hash: 'a' * 40, cited_shas: ['b' * 40])
      ignore = build_ignore_commit(hash: 'b' * 40)
      commits = [drop, ignore]
      results = [
        build_result(drop.hash, drop_column_type),
        build_result(ignore.hash, ignore_type)
      ]

      expect { validator.validate(results, commits, build_flavor) }
        .to raise_error(Phaser::SafetyAssertionError) do |error|
          expect(error.commit_hash).to eq('a' * 40)
          expect(error.failing_rule).to eq('safety-assertion-precedent-mismatch')
          expect(error.cited_precedents).to eq(['b' * 40])
        end
    end

    it 'names the cited SHAs in the error message (FR-041, SC-008)' do
      drop = build_drop_commit(hash: 'c' * 40, cited_shas: ['9' * 40])
      results = [build_result(drop.hash, drop_column_type)]

      expect { validator.validate(results, [drop], build_flavor) }
        .to raise_error(Phaser::SafetyAssertionError) do |error|
          expect(error.message).to include('9' * 40)
        end
    end
  end

  describe 'determinism — first irreversible commit in input order is the one reported (FR-002, SC-002)' do
    it 'reports the FIRST irreversible commit when multiple irreversible commits fail' do
      first_drop = build_drop_commit(hash: '1' * 40, cited_shas: [])
      second_drop = build_drop_commit(hash: '2' * 40, cited_shas: [])
      commits = [first_drop, second_drop]
      results = [
        build_result(first_drop.hash, drop_column_type),
        build_result(second_drop.hash, drop_column_type)
      ]

      expect { validator.validate(results, commits, build_flavor) }
        .to raise_error(Phaser::SafetyAssertionError) do |error|
          expect(error.commit_hash).to eq('1' * 40)
        end
    end

    it 'lists cited SHAs in the order they appear in the safety-assertion block' do
      ignore = build_ignore_commit(hash: 'a' * 40)
      remove_refs = build_remove_refs_commit(hash: 'b' * 40)
      # Cite remove_refs FIRST in the trailer, ignore SECOND. The
      # validator MUST preserve cited order in its accepted output and
      # in any error payload.
      drop = build_drop_commit(hash: 'c' * 40, cited_shas: [remove_refs.hash, ignore.hash])
      commits = [ignore, remove_refs, drop]
      results = [
        build_result(ignore.hash, ignore_type),
        build_result(remove_refs.hash, remove_refs_type),
        build_result(drop.hash, drop_column_type)
      ]

      output = validator.validate(results, commits, build_flavor)
      drop_entry = output.find { |r| r.commit_hash == drop.hash }
      cited = drop_entry.respond_to?(:safety_assertion_precedents) ? drop_entry.safety_assertion_precedents : nil

      expect(cited).to eq([remove_refs.hash, ignore.hash])
    end
  end

  describe 'bypass-surface contract (no operator override per D-016 spirit)' do
    # Mirrors the ForbiddenOperationsGate's D-016 stance, the
    # backfill validator's bypass-empty contract, and the column-drop
    # precedent validator's bypass-empty contract: no constructor
    # keyword, environment variable, or commit-message trailer (other
    # than the canonical `Safety-Assertion:` trailer the validator
    # itself reads) may suppress the validator's decision. The
    # constellation of trailer names below is intentionally "plausibly
    # bypass-shaped" so a future contributor cannot accidentally
    # honour one of them and silently expand the bypass surface.
    def build_tagged_drop_commit
      Phaser::Commit.new(
        hash: '8' * 40,
        subject: 'Drop legacy_email with bypass attempt',
        message_trailers: {
          'Phase-Type' => 'schema drop-column-with-cleanup-precedent',
          'Phaser-Skip-Safety-Assertion' => 'true',
          'Phaser-Allow-Unsafe-Drop' => 'true'
        },
        diff: Phaser::Diff.new(
          files: [
            Phaser::FileChange.new(
              path: 'db/migrate/20260425000099_drop_users_legacy_email.rb',
              change_kind: :added,
              hunks: ["+    remove_column :users, :legacy_email\n"]
            )
          ]
        ),
        author_timestamp: '2026-04-25T12:00:00Z'
      )
    end

    it 'exposes no constructor option that would skip, force, or allow safety-assertion bypass' do
      keyword_kinds = %i[key keyreq].freeze
      keyword_params = Phaser::Flavors::RailsPostgresStrongMigrations::SafetyAssertionValidator
                       .instance_method(:initialize)
                       .parameters
                       .filter_map { |kind, name| name if keyword_kinds.include?(kind) }

      forbidden_keywords = %i[skip force allow bypass override]
      expect(keyword_params & forbidden_keywords).to be_empty
    end

    it 'ignores Phase-Type and other plausible bypass trailers when scanning the commit' do
      drop = build_tagged_drop_commit
      results = [build_result(drop.hash, drop_column_type)]

      expect { validator.validate(results, [drop], build_flavor) }
        .to raise_error(Phaser::SafetyAssertionError) do |error|
          expect(error.failing_rule).to eq('safety-assertion-missing')
        end
    end
  end

  describe 'Phaser::SafetyAssertionError — payload contract (FR-041, FR-042)' do
    let(:missing_error) do
      Phaser::SafetyAssertionError.new(
        commit_hash: '9' * 40,
        failing_rule: 'safety-assertion-missing',
        cited_precedents: []
      )
    end

    let(:mismatch_error) do
      Phaser::SafetyAssertionError.new(
        commit_hash: '9' * 40,
        failing_rule: 'safety-assertion-precedent-mismatch',
        cited_precedents: ['a' * 40, 'b' * 40]
      )
    end

    it 'descends from Phaser::ValidationError so the engine can rescue uniformly' do
      expect(Phaser::SafetyAssertionError).to be < Phaser::ValidationError
    end

    it 'exposes commit_hash for the validation-failed ERROR record (FR-041)' do
      expect(missing_error.commit_hash).to eq('9' * 40)
    end

    it 'exposes failing_rule populated with safety-assertion-missing on the missing-block path' do
      expect(missing_error.failing_rule).to eq('safety-assertion-missing')
    end

    it 'exposes failing_rule populated with safety-assertion-precedent-mismatch on the mismatch path' do
      expect(mismatch_error.failing_rule).to eq('safety-assertion-precedent-mismatch')
    end

    it 'exposes cited_precedents listing the SHAs parsed from the safety-assertion block (FR-018)' do
      expect(mismatch_error.cited_precedents).to eq(['a' * 40, 'b' * 40])
    end

    it 'serializes the missing-block payload to the validation-failed ERROR shape per FR-041 / FR-042' do
      # The missing-block path has no precedents to cite, so the
      # payload omits `missing_precedent` entirely (consistent with
      # the column-drop validator's omit-on-irrelevant-fields stance).
      expect(missing_error.to_validation_failed_payload).to eq(
        commit_hash: '9' * 40,
        failing_rule: 'safety-assertion-missing'
      )
    end

    it 'serializes the mismatch payload to the validation-failed ERROR shape per FR-041 / FR-042' do
      # The mismatch path joins the cited SHAs with `", "` into the
      # singular `missing_precedent` schema field so the existing
      # `phase-creation-status.yaml` schema carries the audit trail
      # without introducing a schema-incompatible new key (the same
      # pattern the column-drop validator uses for two missing
      # precedent type names).
      expect(mismatch_error.to_validation_failed_payload).to eq(
        commit_hash: '9' * 40,
        failing_rule: 'safety-assertion-precedent-mismatch',
        missing_precedent: "#{'a' * 40}, #{'b' * 40}"
      )
    end

    it 'omits fields the safety-assertion mode does not populate' do
      # The schema permits these keys for OTHER failure modes
      # (forbidden-operation populates forbidden_operation /
      # decomposition_message; backfill-safety populates
      # missing_safeguard; feature-too-large populates commit_count /
      # phase_count). The safety-assertion rejection path MUST NOT
      # emit them so the operator-facing record is precise about
      # which rule fired.
      expect(missing_error.to_validation_failed_payload)
        .not_to include(:forbidden_operation, :decomposition_message,
                        :missing_safeguard, :commit_count, :phase_count)
      expect(mismatch_error.to_validation_failed_payload)
        .not_to include(:forbidden_operation, :decomposition_message,
                        :missing_safeguard, :commit_count, :phase_count)
    end
  end
end
