# frozen_string_literal: true

require 'phaser'

# Specs for the shipped `rails-postgres-strong-migrations` flavor's
# backfill-safety validator at `phaser/flavors/
# rails-postgres-strong-migrations/backfill_validator.rb` (feature
# 007-multi-phase-pipeline; T042/T053, FR-013, FR-041, FR-042,
# data-model.md "Error Conditions" table row "Backfill commit lacks
# batching/throttling/transaction-safety", spec.md User Story 2
# Acceptance Scenario 3).
#
# Position in the engine pipeline (per quickstart.md "Pattern:
# Pre-Classification Gate Discipline" and the validators-list dispatch
# wired through `flavor_loader.rb` in T055):
#
#   empty-diff filter (FR-009)
#     -> forbidden-operations gate (FR-049)
#     -> classifier (FR-004)
#     -> precedent validator (FR-006)
#     -> reference-flavor validators (FR-013 backfill, FR-014 column-drop, FR-018 safety-assertion)
#     -> size guard (FR-048)
#     -> isolation resolver (FR-005)
#     -> manifest writer (FR-002, FR-038)
#
# Contract (FR-013, spec.md User Story 2 Acceptance Scenario 3):
#
#   "The reference flavor MUST provide a backfill-safety validator that
#    rejects backfill commits lacking batching, throttling between
#    batches, or the directive to run outside a transaction; the
#    rejection error MUST name the missing safeguard."
#
# The three required safeguards on a `data backfill-batched` commit are
# the canonical strong_migrations / Rails-deploy-safety triad:
#
#   1. Batching — the rake task iterates the relation via
#      `find_each` or `in_batches` rather than loading the full
#      relation into memory and updating it in a single statement.
#   2. Throttling — between batches the task sleeps (e.g.,
#      `sleep 0.1`) so the backfill does not saturate the database
#      writer.
#   3. Transaction-safety — the migration that ships with the rake
#      task (or the rake task's body, depending on the flavor's
#      detection style) declares `disable_ddl_transaction!` so the
#      long-running update does not hold a transaction open across
#      hundreds of thousands of rows.
#
# Surface (T053):
#
#   * `Phaser::Flavors::RailsPostgresStrongMigrations::BackfillValidator
#     .new` — stateless; constructed once per engine run with no
#     arguments. Mirrors the bypass-empty stance of the
#     ForbiddenOperationsGate (D-016) and the PrecedentValidator: no
#     `skip:` / `force:` / `allow:` keyword exists.
#
#   * `#validate(classification_results, commits, flavor)` — given the
#     post-precedent-validator list of `Phaser::ClassificationResult`s
#     in commit-emission order, the same-length list of source
#     `Phaser::Commit`s (so the validator can read each backfill
#     commit's diff for the safeguard signals — `ClassificationResult`
#     intentionally does not carry the diff), and the active
#     `Phaser::Flavor`, returns the classification results unchanged on
#     success. On the first violation the validator raises
#     `Phaser::BackfillSafetyError`; classifications that already
#     passed before the violation are NOT returned because the engine
#     never proceeds past a backfill-safety failure.
#
#     The validator only inspects commits whose `task_type` is
#     `'data backfill-batched'`. Other task types are ignored — the
#     surface for catching unsafe non-backfill commits is
#     `forbidden_operations` (FR-015) and the per-flavor precedent
#     validators (FR-014, FR-018), not this one.
#
#   * `Phaser::BackfillSafetyError` — exception raised by the
#     validator. Carries the offending commit hash and the canonical
#     `failing_rule` value `'backfill-safety'` (per data-model.md
#     "Error Conditions" table) plus a `missing_safeguard` field
#     naming which of the three safeguards was absent
#     (`'batching'`, `'throttling'`, or `'transaction-safety'`).
#     Descends from `Phaser::ValidationError` so the engine's outer
#     rescue clause handles it uniformly with the other validation
#     failure modes (forbidden-operation, precedent, feature-too-large,
#     unknown-type-tag, safety-assertion-missing).
#
# Determinism contract (FR-002, SC-002):
#
#   * The validator iterates commits in input order; the FIRST
#     violation in input order is the one reported. Within a single
#     commit the safeguard checks fire in canonical order — batching,
#     throttling, transaction-safety — so when a commit lacks more than
#     one safeguard the FIRST missing one in canonical order is the one
#     named in the error. This makes the operator-facing message
#     reproducible across runs even when the commit lacks every
#     safeguard.
#
# Logging / status-file contract (FR-041, FR-042, data-model.md
# "PhaseCreationStatus", contracts/observability-events.md
# `validation-failed`):
#
#   * The engine relays `error.to_validation_failed_payload` to
#     `Observability#log_validation_failed` and `StatusWriter#write`.
#     The payload carries exactly `{commit_hash, failing_rule,
#     missing_safeguard}` — no `forbidden_operation`, no
#     `decomposition_message`, no `commit_count`/`phase_count` keys
#     (those belong to other failure classes). The validator does NOT
#     write to stderr or to the status file directly; emission is the
#     engine's responsibility (FR-041 mandates exactly one
#     `validation-failed` ERROR record per failure).
#
# This spec MUST observe failure (red) before T053 ships
# `backfill_validator.rb` (the test-first requirement in CLAUDE.md
# "Test-First Development"). Until then, the
# `Phaser::Flavors::RailsPostgresStrongMigrations::BackfillValidator`
# constant does not exist and the first `described_class` reference
# raises `NameError`.
RSpec.describe 'Phaser::Flavors::RailsPostgresStrongMigrations::BackfillValidator' do
  subject(:validator) do
    Phaser::Flavors::RailsPostgresStrongMigrations::BackfillValidator.new
  end

  # Build a minimal Phaser::Flavor with the `data backfill-batched`
  # task type plus a default catch-all so the classifier can produce
  # ClassificationResults for non-backfill commits in the same input.
  # The validator does not consult the flavor's precedent rules or
  # forbidden_operations — only the task type set — but we mirror the
  # FlavorLoader's value-object surface so the validator sees what
  # production hands it.
  def build_flavor # rubocop:disable Metrics/MethodLength
    Phaser::Flavor.new(
      name: 'rails-postgres-strong-migrations',
      version: '0.1.0',
      default_type: 'code default-catch-all-change',
      task_types: [
        Phaser::FlavorTaskType.new(
          name: 'data backfill-batched',
          isolation: :alone,
          description: 'Batched, throttled backfill rake task.'
        ),
        Phaser::FlavorTaskType.new(
          name: 'code default-catch-all-change',
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

  # Build a Phaser::Commit whose diff is a single `lib/tasks/*.rake`
  # rake-task file with the supplied hunk array. Defaults to a
  # syntactically complete safe backfill that exercises all three
  # safeguards so the per-safeguard examples can mutate one hunk at a
  # time without re-stating the entire fixture.
  def build_backfill_commit(hash:, hunks:)
    Phaser::Commit.new(
      hash: hash,
      subject: 'Backfill users.email_lower from users.email',
      message_trailers: {},
      diff: Phaser::Diff.new(
        files: [
          Phaser::FileChange.new(
            path: 'lib/tasks/backfill_user_emails.rake',
            change_kind: :added,
            hunks: hunks
          )
        ]
      ),
      author_timestamp: '2026-04-25T12:00:00Z'
    )
  end

  # Build a Phaser::Commit whose diff is a single migration file with
  # an `add_column` hunk — used by the per-task-type scope check to
  # demonstrate that a non-backfill commit is ignored regardless of
  # whether it would pass the safeguard checks.
  def build_migration_commit
    Phaser::Commit.new(
      hash: 'c' * 40,
      subject: 'Add email to users',
      message_trailers: {},
      diff: Phaser::Diff.new(
        files: [
          Phaser::FileChange.new(
            path: 'db/migrate/20260425000001_add_email_to_users.rb',
            change_kind: :added,
            hunks: ["+    add_column :users, :email, :string\n"]
          )
        ]
      ),
      author_timestamp: '2026-04-25T12:00:00Z'
    )
  end

  # Build a ClassificationResult that pretends the upstream classifier
  # already labelled the commit as `data backfill-batched`. The
  # validator's contract is that classification has already happened —
  # it inspects classified commits, not raw ones — so we can fixture
  # the result directly rather than running the full classifier.
  def build_backfill_result(commit_hash, task_type: 'data backfill-batched')
    Phaser::ClassificationResult.new(
      commit_hash: commit_hash,
      task_type: task_type,
      source: :inference,
      isolation: task_type == 'data backfill-batched' ? :alone : :groups,
      rule_name: task_type == 'data backfill-batched' ? 'backfill-batched-by-path' : nil,
      precedents_consulted: nil
    )
  end

  # The three canonical safeguard hunks the validator looks for.
  # Extracted so each per-safeguard example can drop ONE hunk to
  # simulate the missing-safeguard case while keeping the others
  # present.
  let(:batching_hunk) do
    "+    User.in_batches(of: 1_000) do |relation|\n" \
      "+      relation.update_all('email_lower = lower(email)')\n" \
      "+    end\n"
  end

  let(:throttling_hunk) do
    "+      sleep 0.1\n"
  end

  let(:transaction_safety_hunk) do
    "+  disable_ddl_transaction!\n"
  end

  let(:safe_backfill_hunks) do
    [transaction_safety_hunk, batching_hunk, throttling_hunk]
  end

  describe '#validate — accepts safe backfill commits' do
    it 'returns the classification results unchanged when every safeguard is present' do
      commit = build_backfill_commit(hash: 'a' * 40, hunks: safe_backfill_hunks)
      result = build_backfill_result(commit.hash)

      output = validator.validate([result], [commit], build_flavor)

      expect(output).to eq([result])
    end

    it 'recognises find_each as an acceptable batching primitive (FR-013)' do
      # `find_each` is the other canonical Rails batching primitive;
      # the validator must accept either it or `in_batches` per
      # spec.md User Story 2 Acceptance Scenario 3 ("lacks batching,
      # throttling, or the directive to run outside a transaction").
      find_each_hunks = [
        transaction_safety_hunk,
        "+    User.find_each(batch_size: 1_000) do |user|\n" \
        "+      user.update!(email_lower: user.email.downcase)\n" \
        "+    end\n",
        throttling_hunk
      ]
      commit = build_backfill_commit(hash: 'b' * 40, hunks: find_each_hunks)
      result = build_backfill_result(commit.hash)

      expect { validator.validate([result], [commit], build_flavor) }
        .not_to raise_error
    end

    it 'ignores commits whose task_type is not data backfill-batched' do
      # The validator only fires on `data backfill-batched` commits.
      # A migration commit whose diff happens to lack batching MUST
      # NOT be rejected by THIS validator — that is the
      # forbidden-operations gate's or the per-flavor precedent
      # validator's job.
      commit = build_migration_commit
      result = build_backfill_result(commit.hash, task_type: 'code default-catch-all-change')

      expect { validator.validate([result], [commit], build_flavor) }
        .not_to raise_error
    end

    it 'is a no-op when no commit is classified as data backfill-batched' do
      # Empty post-classification list, or a list with no backfills,
      # is the steady state for features that do not touch data — the
      # validator MUST exit fast without iterating diffs.
      expect { validator.validate([], [], build_flavor) }
        .not_to raise_error
    end
  end

  describe '#validate — rejects commits lacking the batching safeguard (FR-013)' do
    it 'raises Phaser::BackfillSafetyError naming `batching` when neither in_batches nor find_each is present' do
      # Strip the batching hunk; keep transaction-safety and throttling
      # so the failure is unambiguously about batching.
      hunks = [transaction_safety_hunk, "+    User.update_all('email_lower = lower(email)')\n", throttling_hunk]
      commit = build_backfill_commit(hash: 'd' * 40, hunks: hunks)
      result = build_backfill_result(commit.hash)

      expect { validator.validate([result], [commit], build_flavor) }
        .to raise_error(Phaser::BackfillSafetyError) do |error|
          expect(error.commit_hash).to eq('d' * 40)
          expect(error.failing_rule).to eq('backfill-safety')
          expect(error.missing_safeguard).to eq('batching')
        end
    end

    it 'mentions `batching` verbatim in the error message (SC-008)' do
      hunks = [transaction_safety_hunk, "+    User.update_all('email_lower = lower(email)')\n", throttling_hunk]
      commit = build_backfill_commit(hash: 'e' * 40, hunks: hunks)
      result = build_backfill_result(commit.hash)

      expect { validator.validate([result], [commit], build_flavor) }
        .to raise_error(Phaser::BackfillSafetyError, /batching/)
    end
  end

  describe '#validate — rejects commits lacking the throttling safeguard (FR-013)' do
    it 'raises Phaser::BackfillSafetyError naming `throttling` when no sleep call appears between batches' do
      # Strip the throttling hunk; keep transaction-safety and
      # batching so the failure is unambiguously about throttling.
      hunks = [transaction_safety_hunk, batching_hunk]
      commit = build_backfill_commit(hash: 'f' * 40, hunks: hunks)
      result = build_backfill_result(commit.hash)

      expect { validator.validate([result], [commit], build_flavor) }
        .to raise_error(Phaser::BackfillSafetyError) do |error|
          expect(error.commit_hash).to eq('f' * 40)
          expect(error.failing_rule).to eq('backfill-safety')
          expect(error.missing_safeguard).to eq('throttling')
        end
    end

    it 'mentions `throttling` verbatim in the error message (SC-008)' do
      hunks = [transaction_safety_hunk, batching_hunk]
      commit = build_backfill_commit(hash: '1' * 40, hunks: hunks)
      result = build_backfill_result(commit.hash)

      expect { validator.validate([result], [commit], build_flavor) }
        .to raise_error(Phaser::BackfillSafetyError, /throttling/)
    end
  end

  describe '#validate — rejects commits lacking the transaction-safety safeguard (FR-013)' do
    it 'raises Phaser::BackfillSafetyError naming `transaction-safety` when disable_ddl_transaction! is absent' do
      # Strip the transaction-safety hunk; keep batching and
      # throttling so the failure is unambiguously about
      # transaction-safety.
      hunks = [batching_hunk, throttling_hunk]
      commit = build_backfill_commit(hash: '2' * 40, hunks: hunks)
      result = build_backfill_result(commit.hash)

      expect { validator.validate([result], [commit], build_flavor) }
        .to raise_error(Phaser::BackfillSafetyError) do |error|
          expect(error.commit_hash).to eq('2' * 40)
          expect(error.failing_rule).to eq('backfill-safety')
          expect(error.missing_safeguard).to eq('transaction-safety')
        end
    end

    it 'mentions `transaction-safety` verbatim in the error message (SC-008)' do
      hunks = [batching_hunk, throttling_hunk]
      commit = build_backfill_commit(hash: '3' * 40, hunks: hunks)
      result = build_backfill_result(commit.hash)

      expect { validator.validate([result], [commit], build_flavor) }
        .to raise_error(Phaser::BackfillSafetyError, /transaction-safety/)
    end
  end

  describe 'determinism — first missing safeguard in canonical order is reported (FR-002, SC-002)' do
    # The canonical safeguard order is batching → throttling →
    # transaction-safety. When a commit lacks more than one safeguard,
    # the validator MUST report the FIRST missing one in this order so
    # the operator-facing message is reproducible across runs.
    it 'reports `batching` first when batching, throttling, AND transaction-safety are all missing' do
      hunks = ["+    User.update_all('email_lower = lower(email)')\n"]
      commit = build_backfill_commit(hash: '4' * 40, hunks: hunks)
      result = build_backfill_result(commit.hash)

      expect { validator.validate([result], [commit], build_flavor) }
        .to raise_error(Phaser::BackfillSafetyError) do |error|
          expect(error.missing_safeguard).to eq('batching')
        end
    end

    it 'reports `throttling` next when batching is present but throttling AND transaction-safety are missing' do
      hunks = [batching_hunk]
      commit = build_backfill_commit(hash: '5' * 40, hunks: hunks)
      result = build_backfill_result(commit.hash)

      expect { validator.validate([result], [commit], build_flavor) }
        .to raise_error(Phaser::BackfillSafetyError) do |error|
          expect(error.missing_safeguard).to eq('throttling')
        end
    end

    it 'reports the FIRST commit-in-input-order to fail when multiple backfill commits are unsafe' do
      # Two unsafe backfills; the FIRST in input order MUST be
      # reported regardless of which lacks the more egregious
      # safeguard. The contract is "first violation in input order"
      # not "most severe violation."
      first_unsafe = build_backfill_commit(
        hash: '6' * 40,
        hunks: [transaction_safety_hunk, "+    User.update_all('email_lower = lower(email)')\n", throttling_hunk]
      )
      second_unsafe = build_backfill_commit(hash: '7' * 40, hunks: [batching_hunk, throttling_hunk])
      results = [build_backfill_result(first_unsafe.hash), build_backfill_result(second_unsafe.hash)]
      run_validate = -> { validator.validate(results, [first_unsafe, second_unsafe], build_flavor) }

      expect(&run_validate).to raise_error(Phaser::BackfillSafetyError) do |error|
        expect(error.commit_hash).to eq('6' * 40)
        expect(error.missing_safeguard).to eq('batching')
      end
    end
  end

  describe 'bypass-surface contract (no operator override per D-016 spirit)' do
    # Mirrors the ForbiddenOperationsGate's D-016 stance: no trailer
    # — plausible or implausible — may suppress the validator's
    # decision. The validator's contract is "diff content only." The
    # constellation of trailer names below is intentionally "plausibly
    # bypass-shaped" so a future contributor cannot accidentally honour
    # one of them and silently expand the bypass surface.
    def build_tagged_unsafe_commit
      hunks = [transaction_safety_hunk, "+    User.update_all('email_lower = lower(email)')\n", throttling_hunk]
      Phaser::Commit.new(
        hash: '8' * 40,
        subject: 'Backfill with bypass attempt',
        message_trailers: {
          'Phase-Type' => 'data backfill-batched',
          'Phaser-Skip-Backfill-Safety' => 'true',
          'Phaser-Allow-Unsafe-Backfill' => 'true'
        },
        diff: Phaser::Diff.new(
          files: [
            Phaser::FileChange.new(
              path: 'lib/tasks/backfill_user_emails.rake',
              change_kind: :added,
              hunks: hunks
            )
          ]
        ),
        author_timestamp: '2026-04-25T12:00:00Z'
      )
    end

    it 'exposes no constructor option that would skip, force, or allow backfill-safety bypass' do
      keyword_kinds = %i[key keyreq].freeze
      keyword_params = Phaser::Flavors::RailsPostgresStrongMigrations::BackfillValidator
                       .instance_method(:initialize)
                       .parameters
                       .filter_map { |kind, name| name if keyword_kinds.include?(kind) }

      forbidden_keywords = %i[skip force allow bypass override]
      expect(keyword_params & forbidden_keywords).to be_empty
    end

    it 'ignores Phase-Type and other plausible bypass trailers when scanning the diff' do
      commit = build_tagged_unsafe_commit
      result = build_backfill_result(commit.hash)

      expect { validator.validate([result], [commit], build_flavor) }
        .to raise_error(Phaser::BackfillSafetyError) do |error|
          expect(error.missing_safeguard).to eq('batching')
        end
    end
  end

  describe 'Phaser::BackfillSafetyError — payload contract (FR-041, FR-042)' do
    let(:error) do
      Phaser::BackfillSafetyError.new(
        commit_hash: '9' * 40,
        missing_safeguard: 'throttling'
      )
    end

    it 'descends from Phaser::ValidationError so the engine can rescue uniformly' do
      expect(Phaser::BackfillSafetyError).to be < Phaser::ValidationError
    end

    it 'exposes commit_hash for the validation-failed ERROR record (FR-041)' do
      expect(error.commit_hash).to eq('9' * 40)
    end

    it 'exposes failing_rule populated with the canonical `backfill-safety` value (data-model.md "Error Conditions")' do
      expect(error.failing_rule).to eq('backfill-safety')
    end

    it 'exposes missing_safeguard naming the absent safeguard (FR-013)' do
      expect(error.missing_safeguard).to eq('throttling')
    end

    it 'serializes to the validation-failed ERROR payload shape per FR-041 / FR-042' do
      # The engine relays the three payload fields to
      # `Observability#log_validation_failed` (FR-041) and to
      # `StatusWriter#write` (FR-042). The error object exposes
      # `to_validation_failed_payload` so the engine does not have to
      # know the validator's internal layout.
      expect(error.to_validation_failed_payload).to eq(
        commit_hash: '9' * 40,
        failing_rule: 'backfill-safety',
        missing_safeguard: 'throttling'
      )
    end

    it 'omits fields the backfill-safety mode does not populate' do
      # The schema permits these keys for OTHER failure modes
      # (forbidden-operation populates forbidden_operation /
      # decomposition_message; precedent populates missing_precedent;
      # feature-too-large populates commit_count / phase_count). The
      # backfill-safety rejection path MUST NOT emit them so the
      # operator-facing record is precise about which rule fired.
      expect(error.to_validation_failed_payload)
        .not_to include(:forbidden_operation, :decomposition_message,
                        :missing_precedent, :commit_count, :phase_count)
    end
  end
end
