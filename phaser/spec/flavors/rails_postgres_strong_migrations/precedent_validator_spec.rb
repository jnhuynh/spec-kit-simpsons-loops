# frozen_string_literal: true

require 'phaser'

# Specs for the shipped `rails-postgres-strong-migrations` flavor's
# column-drop precedent validator at `phaser/flavors/
# rails-postgres-strong-migrations/precedent_validator.rb` (feature
# 007-multi-phase-pipeline; T043/T054, FR-014, FR-041, FR-042,
# data-model.md "Error Conditions" table row "Precedent rule violated",
# spec.md User Story 2 Acceptance Scenario 4).
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
# Why a flavor-specific validator on top of the engine PrecedentValidator
# (T032/T023):
#
#   The engine's `Phaser::PrecedentValidator` (T032) enforces ONE
#   precedent rule at a time and reports the FIRST rule that fails. FR-014
#   demands a CONJOINED rejection: a column-drop commit MUST be preceded
#   by BOTH an "ignore column for pending drop" commit AND a "remove all
#   references to pending-drop column" commit, and the rejection MUST
#   name BOTH missing precedents in a single error so the operator knows
#   the full set of remediation commits to add. The two-rules-with-AND
#   semantics cannot be expressed by two independent
#   FlavorPrecedentRules — that would surface the precedents one at a
#   time across re-runs ("ignore is missing" → operator adds it →
#   "reference-removal is missing" → operator adds it). One error message
#   that names both at once is the contract.
#
# Contract (FR-014, spec.md User Story 2 Acceptance Scenario 4):
#
#   "The reference flavor MUST provide a precedent validator that
#    rejects a column-drop commit that is not preceded by both an
#    'ignore column for pending drop' commit AND a 'remove all
#    references to column' commit; the rejection error MUST name the
#    missing precedent commits."
#
# The validator inspects only commits whose `task_type` is the
# canonical column-drop type from FR-010's catalog —
# `'schema drop-column-with-cleanup-precedent'`. Other task types are
# ignored by THIS validator; engine-level precedent rules (FR-006) and
# the forbidden-operations gate (FR-015) handle the remaining cases.
#
# The validator joins each column-drop commit's diff against earlier
# `code ignore-column-for-pending-drop` and
# `code remove-references-to-pending-drop-column` commits' diffs by the
# column name they touch — both precedents must exist for the SAME
# column in earlier commits in the input list. A column-drop commit
# that has only one of the two precedents (or has both precedents but
# for a DIFFERENT column) is rejected with both names listed.
#
# Surface (T054):
#
#   * `Phaser::Flavors::RailsPostgresStrongMigrations::PrecedentValidator
#     .new` — stateless; constructed once per engine run with no
#     arguments. Mirrors the bypass-empty stance of the engine
#     PrecedentValidator and the ForbiddenOperationsGate (D-016): no
#     `skip:` / `force:` / `allow:` keyword exists.
#
#   * `#validate(classification_results, commits, flavor)` — given the
#     post-precedent-validator list of `Phaser::ClassificationResult`s
#     in commit-emission order, the same-length list of source
#     `Phaser::Commit`s (so the validator can read each column-drop
#     commit's diff to identify the column being dropped, and each
#     candidate-precedent commit's diff to identify which column the
#     ignored-columns directive or reference removal touches), and the
#     active `Phaser::Flavor`, returns the classification results
#     unchanged on success. On the first violation the validator raises
#     `Phaser::ColumnDropPrecedentError`; classifications that already
#     passed before the violation are NOT returned because the engine
#     never proceeds past a precedent failure.
#
#     The validator only inspects commits whose `task_type` is
#     `'schema drop-column-with-cleanup-precedent'`. Other task types
#     are ignored — the surface for catching unsafe non-drop commits
#     belongs to the engine PrecedentValidator (FR-006) and the
#     forbidden-operations gate (FR-015), not this one.
#
#   * `Phaser::ColumnDropPrecedentError` — exception raised by the
#     validator. Carries the offending commit hash, the canonical
#     `failing_rule` value `'drop-column-cleanup-precedent'` (the
#     conjoined-rule name pinned by the reference flavor), and a
#     `missing_precedents` field whose value is an Array of the
#     precedent task-type names absent in earlier commits in the input
#     list (`['code ignore-column-for-pending-drop',
#     'code remove-references-to-pending-drop-column']` when both are
#     missing; one entry when only one is missing). Descends from
#     `Phaser::ValidationError` so the engine's outer rescue clause
#     handles it uniformly with the other validation failure modes
#     (forbidden-operation, precedent, backfill-safety,
#     feature-too-large, unknown-type-tag, safety-assertion-missing).
#
# Determinism contract (FR-002, SC-002):
#
#   * The validator iterates commits in input order; the FIRST
#     column-drop violation in input order is the one reported.
#   * Within the `missing_precedents` array, the precedent task-type
#     names are listed in canonical order — ignored-columns directive
#     first, reference removal second — so when both are missing the
#     operator-facing message is reproducible across runs.
#   * Two operators running the reference flavor against the same
#     commits MUST see the same offending commit reported, with the
#     same `failing_rule` and `missing_precedents` values.
#
# Logging / status-file contract (FR-041, FR-042, data-model.md
# "PhaseCreationStatus", contracts/observability-events.md
# `validation-failed`):
#
#   * The engine relays `error.to_validation_failed_payload` to
#     `Observability#log_validation_failed` and `StatusWriter#write`.
#     The payload carries exactly `{commit_hash, failing_rule,
#     missing_precedent}` — `missing_precedent` is the comma-joined
#     string of precedent names so the existing
#     `phase-creation-status.yaml` schema field (singular per
#     contracts/phase-creation-status.schema.yaml and the engine
#     PrecedentValidator's contract) carries both names without
#     introducing a schema-incompatible new key. The validator does NOT
#     write to stderr or to the status file directly; emission is the
#     engine's responsibility (FR-041 mandates exactly one
#     `validation-failed` ERROR record per failure).
#
# This spec MUST observe failure (red) before T054 ships
# `precedent_validator.rb` (the test-first requirement in CLAUDE.md
# "Test-First Development"). Until then, the
# `Phaser::Flavors::RailsPostgresStrongMigrations::PrecedentValidator`
# constant does not exist and the first `described_class` reference
# raises `NameError`.
RSpec.describe 'Phaser::Flavors::RailsPostgresStrongMigrations::PrecedentValidator' do
  subject(:validator) do
    Phaser::Flavors::RailsPostgresStrongMigrations::PrecedentValidator.new
  end

  # Canonical task-type names from FR-010 / catalog_spec.rb's
  # required_task_types. Centralised so a future rename in flavor.yaml
  # only flips one constant per role here.
  let(:drop_type) { 'schema drop-column-with-cleanup-precedent' }
  let(:ignore_type) { 'code ignore-column-for-pending-drop' }
  let(:remove_refs_type) { 'code remove-references-to-pending-drop-column' }
  let(:catch_all_type) { 'code default-catch-all-change' }

  # Build a minimal Phaser::Flavor with the four task types this
  # validator reasons about. The validator does not consult the
  # flavor's precedent rules, inference rules, or forbidden_operations
  # — only the task-type names — but we mirror the FlavorLoader's
  # value-object surface so the validator sees what production hands
  # it.
  def build_flavor # rubocop:disable Metrics/MethodLength
    Phaser::Flavor.new(
      name: 'rails-postgres-strong-migrations',
      version: '0.1.0',
      default_type: catch_all_type,
      task_types: [
        Phaser::FlavorTaskType.new(
          name: drop_type,
          isolation: :alone,
          description: 'Drop a column whose code references have already been removed.'
        ),
        Phaser::FlavorTaskType.new(
          name: ignore_type,
          isolation: :groups,
          description: 'Mark a column as ignored on the model so it can be dropped safely.'
        ),
        Phaser::FlavorTaskType.new(
          name: remove_refs_type,
          isolation: :groups,
          description: 'Remove all code references to a column slated for drop.'
        ),
        Phaser::FlavorTaskType.new(
          name: catch_all_type,
          isolation: :groups,
          description: 'Default catch-all code change.'
        )
      ],
      precedent_rules: [],
      inference_rules: [],
      forbidden_operations: [],
      stack_detection: Phaser::FlavorStackDetection.new(signals: [])
    )
  end

  # Build a Phaser::Commit whose diff is a single migration file with
  # a `remove_column :<table>, :<column>` hunk. The validator must
  # parse the column name out of the hunk to join against earlier
  # ignored-columns directive commits and reference-removal commits.
  def build_drop_commit(hash:, table: 'users', column: 'legacy_email')
    Phaser::Commit.new(
      hash: hash,
      subject: "Drop #{table}.#{column}",
      message_trailers: {},
      diff: Phaser::Diff.new(
        files: [
          Phaser::FileChange.new(
            path: "db/migrate/20260425000099_drop_#{table}_#{column}.rb",
            change_kind: :added,
            hunks: ["+    remove_column :#{table}, :#{column}\n"]
          )
        ]
      ),
      author_timestamp: '2026-04-25T12:00:00Z'
    )
  end

  # Build a Phaser::Commit whose diff is a model edit adding
  # `self.ignored_columns = %w[<column>]`. The validator joins by
  # column name so the column appears verbatim in the hunk.
  def build_ignore_commit(hash:, column: 'legacy_email', model_path: 'app/models/user.rb')
    Phaser::Commit.new(
      hash: hash,
      subject: "Ignore #{column} on #{File.basename(model_path, '.rb')}",
      message_trailers: {},
      diff: Phaser::Diff.new(
        files: [
          Phaser::FileChange.new(
            path: model_path,
            change_kind: :modified,
            hunks: ["+  self.ignored_columns = %w[#{column}]\n"]
          )
        ]
      ),
      author_timestamp: '2026-04-25T12:00:00Z'
    )
  end

  # Build a Phaser::Commit whose diff removes references to a column
  # (validators, attr_accessors, scope queries, etc.). The validator
  # joins by column name so the column appears verbatim in the hunk.
  def build_remove_refs_commit(hash:, column: 'legacy_email',
                               model_path: 'app/models/user.rb')
    Phaser::Commit.new(
      hash: hash,
      subject: "Remove references to #{column}",
      message_trailers: {},
      diff: Phaser::Diff.new(
        files: [
          Phaser::FileChange.new(
            path: model_path,
            change_kind: :modified,
            hunks: [
              "-  attr_accessor :#{column}\n",
              "-  validates :#{column}, presence: true\n"
            ]
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
    isolation = task_type == drop_type ? :alone : :groups
    rule_name = case task_type
                when drop_type then 'drop-column-by-path'
                when ignore_type then 'ignore-column-by-content'
                when remove_refs_type then 'remove-references-by-content'
                end
    Phaser::ClassificationResult.new(
      commit_hash: commit_hash,
      task_type: task_type,
      source: :inference,
      isolation: isolation,
      rule_name: rule_name,
      precedents_consulted: nil
    )
  end

  describe '#validate — accepts column-drop commits with both precedents' do
    it 'returns the classification results unchanged when both precedents exist for the same column' do
      ignore = build_ignore_commit(hash: 'a' * 40)
      remove_refs = build_remove_refs_commit(hash: 'b' * 40)
      drop = build_drop_commit(hash: 'c' * 40)
      commits = [ignore, remove_refs, drop]
      results = [
        build_result(ignore.hash, ignore_type),
        build_result(remove_refs.hash, remove_refs_type),
        build_result(drop.hash, drop_type)
      ]

      output = validator.validate(results, commits, build_flavor)

      expect(output).to eq(results)
    end

    it 'accepts the precedents in either order (reference-removal before ignored-columns)' do
      remove_refs = build_remove_refs_commit(hash: 'a' * 40)
      ignore = build_ignore_commit(hash: 'b' * 40)
      drop = build_drop_commit(hash: 'c' * 40)
      commits = [remove_refs, ignore, drop]
      results = [
        build_result(remove_refs.hash, remove_refs_type),
        build_result(ignore.hash, ignore_type),
        build_result(drop.hash, drop_type)
      ]

      expect { validator.validate(results, commits, build_flavor) }
        .not_to raise_error
    end

    it 'accepts unrelated commits between the precedents and the drop' do # rubocop:disable RSpec/ExampleLength
      ignore = build_ignore_commit(hash: 'a' * 40)
      remove_refs = build_remove_refs_commit(hash: 'b' * 40)
      filler = Phaser::Commit.new(
        hash: 'd' * 40,
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
      drop = build_drop_commit(hash: 'c' * 40)
      commits = [ignore, remove_refs, filler, drop]
      results = [
        build_result(ignore.hash, ignore_type),
        build_result(remove_refs.hash, remove_refs_type),
        build_result(filler.hash, catch_all_type),
        build_result(drop.hash, drop_type)
      ]

      expect { validator.validate(results, commits, build_flavor) }
        .not_to raise_error
    end

    it 'is a no-op when no commit is classified as column-drop' do
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

  describe '#validate — rejects column-drop commits missing both precedents (FR-014)' do
    it 'raises Phaser::ColumnDropPrecedentError when no precedents exist anywhere in the input' do
      drop = build_drop_commit(hash: 'a' * 40)
      commits = [drop]
      results = [build_result(drop.hash, drop_type)]

      expect { validator.validate(results, commits, build_flavor) }
        .to raise_error(Phaser::ColumnDropPrecedentError) do |error|
          expect(error.commit_hash).to eq('a' * 40)
          expect(error.failing_rule).to eq('drop-column-cleanup-precedent')
          expect(error.missing_precedents).to eq([ignore_type, remove_refs_type])
        end
    end

    it 'names both missing precedents in the human-readable message (FR-014, SC-008)' do
      drop = build_drop_commit(hash: 'b' * 40)
      commits = [drop]
      results = [build_result(drop.hash, drop_type)]

      expect { validator.validate(results, commits, build_flavor) }
        .to raise_error(Phaser::ColumnDropPrecedentError) do |error|
          expect(error.message).to include(ignore_type)
          expect(error.message).to include(remove_refs_type)
          expect(error.message).to include('b' * 40)
        end
    end
  end

  describe '#validate — rejects column-drop commits missing the ignored-columns directive (FR-014)' do
    it 'raises ColumnDropPrecedentError naming the ignored-columns directive when only reference-removal exists' do
      remove_refs = build_remove_refs_commit(hash: 'a' * 40)
      drop = build_drop_commit(hash: 'b' * 40)
      commits = [remove_refs, drop]
      results = [
        build_result(remove_refs.hash, remove_refs_type),
        build_result(drop.hash, drop_type)
      ]

      expect { validator.validate(results, commits, build_flavor) }
        .to raise_error(Phaser::ColumnDropPrecedentError) do |error|
          expect(error.commit_hash).to eq('b' * 40)
          expect(error.failing_rule).to eq('drop-column-cleanup-precedent')
          expect(error.missing_precedents).to eq([ignore_type])
        end
    end
  end

  describe '#validate — rejects column-drop commits missing the reference-removal (FR-014)' do
    it 'raises ColumnDropPrecedentError naming the reference-removal when only ignored-columns directive exists' do
      ignore = build_ignore_commit(hash: 'a' * 40)
      drop = build_drop_commit(hash: 'b' * 40)
      commits = [ignore, drop]
      results = [
        build_result(ignore.hash, ignore_type),
        build_result(drop.hash, drop_type)
      ]

      expect { validator.validate(results, commits, build_flavor) }
        .to raise_error(Phaser::ColumnDropPrecedentError) do |error|
          expect(error.commit_hash).to eq('b' * 40)
          expect(error.failing_rule).to eq('drop-column-cleanup-precedent')
          expect(error.missing_precedents).to eq([remove_refs_type])
        end
    end
  end

  describe '#validate — column-name join (precedents must touch the same column)' do
    it 'rejects when both precedents exist but for a DIFFERENT column than the drop' do
      # ignored-columns directive marks `users.email_old` as ignored;
      # reference removal scrubs `users.email_old` references; but the
      # drop commit removes `users.legacy_email`. The precedents do not
      # cover the column being dropped, so both are reported missing.
      ignore = build_ignore_commit(hash: 'a' * 40, column: 'email_old')
      remove_refs = build_remove_refs_commit(hash: 'b' * 40, column: 'email_old')
      drop = build_drop_commit(hash: 'c' * 40, column: 'legacy_email')
      commits = [ignore, remove_refs, drop]
      results = [
        build_result(ignore.hash, ignore_type),
        build_result(remove_refs.hash, remove_refs_type),
        build_result(drop.hash, drop_type)
      ]

      expect { validator.validate(results, commits, build_flavor) }
        .to raise_error(Phaser::ColumnDropPrecedentError) do |error|
          expect(error.commit_hash).to eq('c' * 40)
          expect(error.missing_precedents).to eq([ignore_type, remove_refs_type])
        end
    end

    it 'accepts when each precedent column matches its own drop in a multi-drop input' do # rubocop:disable RSpec/ExampleLength
      ignore_a = build_ignore_commit(hash: 'a' * 40, column: 'col_a')
      remove_a = build_remove_refs_commit(hash: 'b' * 40, column: 'col_a')
      drop_a = build_drop_commit(hash: 'c' * 40, column: 'col_a')
      ignore_b = build_ignore_commit(hash: 'd' * 40, column: 'col_b')
      remove_b = build_remove_refs_commit(hash: 'e' * 40, column: 'col_b')
      drop_b = build_drop_commit(hash: 'f' * 40, column: 'col_b')
      commits = [ignore_a, remove_a, drop_a, ignore_b, remove_b, drop_b]
      results = [
        build_result(ignore_a.hash, ignore_type),
        build_result(remove_a.hash, remove_refs_type),
        build_result(drop_a.hash, drop_type),
        build_result(ignore_b.hash, ignore_type),
        build_result(remove_b.hash, remove_refs_type),
        build_result(drop_b.hash, drop_type)
      ]

      expect { validator.validate(results, commits, build_flavor) }
        .not_to raise_error
    end
  end

  describe '#validate — predecessor must appear EARLIER in input order (FR-006 spirit)' do
    it 'rejects when the only precedents appear AFTER the drop in input order' do
      drop = build_drop_commit(hash: 'a' * 40)
      ignore = build_ignore_commit(hash: 'b' * 40)
      remove_refs = build_remove_refs_commit(hash: 'c' * 40)
      commits = [drop, ignore, remove_refs]
      results = [
        build_result(drop.hash, drop_type),
        build_result(ignore.hash, ignore_type),
        build_result(remove_refs.hash, remove_refs_type)
      ]

      expect { validator.validate(results, commits, build_flavor) }
        .to raise_error(Phaser::ColumnDropPrecedentError) do |error|
          expect(error.commit_hash).to eq('a' * 40)
          expect(error.missing_precedents).to eq([ignore_type, remove_refs_type])
        end
    end
  end

  describe 'determinism — first column-drop in input order is the one reported (FR-002, SC-002)' do
    it 'reports the FIRST drop-column commit when multiple drops fail' do
      first_drop = build_drop_commit(hash: '1' * 40, column: 'col_a')
      second_drop = build_drop_commit(hash: '2' * 40, column: 'col_b')
      commits = [first_drop, second_drop]
      results = [
        build_result(first_drop.hash, drop_type),
        build_result(second_drop.hash, drop_type)
      ]

      expect { validator.validate(results, commits, build_flavor) }
        .to raise_error(Phaser::ColumnDropPrecedentError) do |error|
          expect(error.commit_hash).to eq('1' * 40)
        end
    end

    it 'lists missing precedents in canonical order (ignored-columns first, reference-removal second)' do
      drop = build_drop_commit(hash: 'a' * 40)
      commits = [drop]
      results = [build_result(drop.hash, drop_type)]

      expect { validator.validate(results, commits, build_flavor) }
        .to raise_error(Phaser::ColumnDropPrecedentError) do |error|
          expect(error.missing_precedents).to eq([ignore_type, remove_refs_type])
        end
    end
  end

  describe 'bypass-surface contract (no operator override per D-016 spirit)' do
    # Mirrors the ForbiddenOperationsGate's D-016 stance and the
    # backfill validator's bypass-empty contract: no trailer — plausible
    # or implausible — may suppress the validator's decision. The
    # constellation of trailer names below is intentionally "plausibly
    # bypass-shaped" so a future contributor cannot accidentally honour
    # one of them and silently expand the bypass surface.
    def build_tagged_drop_commit
      Phaser::Commit.new(
        hash: '8' * 40,
        subject: 'Drop legacy_email with bypass attempt',
        message_trailers: {
          'Phase-Type' => drop_type,
          'Phaser-Skip-Cleanup-Precedent' => 'true',
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

    it 'exposes no constructor option that would skip, force, or allow precedent bypass' do
      keyword_kinds = %i[key keyreq].freeze
      keyword_params = Phaser::Flavors::RailsPostgresStrongMigrations::PrecedentValidator
                       .instance_method(:initialize)
                       .parameters
                       .filter_map { |kind, name| name if keyword_kinds.include?(kind) }

      forbidden_keywords = %i[skip force allow bypass override]
      expect(keyword_params & forbidden_keywords).to be_empty
    end

    it 'ignores Phase-Type and other plausible bypass trailers when scanning the input' do
      drop = build_tagged_drop_commit
      commits = [drop]
      results = [build_result(drop.hash, drop_type)]

      expect { validator.validate(results, commits, build_flavor) }
        .to raise_error(Phaser::ColumnDropPrecedentError) do |error|
          expect(error.missing_precedents).to eq([ignore_type, remove_refs_type])
        end
    end
  end

  describe 'Phaser::ColumnDropPrecedentError — payload contract (FR-041, FR-042)' do
    let(:error) do
      Phaser::ColumnDropPrecedentError.new(
        commit_hash: '9' * 40,
        missing_precedents: [
          'code ignore-column-for-pending-drop',
          'code remove-references-to-pending-drop-column'
        ]
      )
    end

    it 'descends from Phaser::ValidationError so the engine can rescue uniformly' do
      expect(Phaser::ColumnDropPrecedentError).to be < Phaser::ValidationError
    end

    it 'exposes commit_hash for the validation-failed ERROR record (FR-041)' do
      expect(error.commit_hash).to eq('9' * 40)
    end

    it 'exposes failing_rule populated with the canonical `drop-column-cleanup-precedent` value' do
      expect(error.failing_rule).to eq('drop-column-cleanup-precedent')
    end

    it 'exposes missing_precedents listing the absent precedent task-type names (FR-014)' do
      expect(error.missing_precedents).to eq([
                                               'code ignore-column-for-pending-drop',
                                               'code remove-references-to-pending-drop-column'
                                             ])
    end

    it 'serializes to the validation-failed ERROR payload shape per FR-041 / FR-042' do
      # The engine relays the three payload fields to
      # `Observability#log_validation_failed` (FR-041) and to
      # `StatusWriter#write` (FR-042). The error object exposes
      # `to_validation_failed_payload` so the engine does not have to
      # know the validator's internal layout. The payload uses the
      # singular `missing_precedent` key (matching the existing
      # contracts/phase-creation-status.schema.yaml field) with both
      # names joined so the existing schema carries both without a
      # schema-incompatible new key.
      expect(error.to_validation_failed_payload).to eq(
        commit_hash: '9' * 40,
        failing_rule: 'drop-column-cleanup-precedent',
        missing_precedent: 'code ignore-column-for-pending-drop, ' \
                           'code remove-references-to-pending-drop-column'
      )
    end

    it 'omits fields the column-drop precedent mode does not populate' do
      # The schema permits these keys for OTHER failure modes
      # (forbidden-operation populates forbidden_operation /
      # decomposition_message; backfill-safety populates
      # missing_safeguard; feature-too-large populates commit_count /
      # phase_count). The column-drop precedent rejection path MUST NOT
      # emit them so the operator-facing record is precise about which
      # rule fired.
      expect(error.to_validation_failed_payload)
        .not_to include(:forbidden_operation, :decomposition_message,
                        :missing_safeguard, :commit_count, :phase_count)
    end
  end
end
