# frozen_string_literal: true

# Backfill-safety validator for the rails-postgres-strong-migrations
# reference flavor (feature 007-multi-phase-pipeline; T053, FR-013,
# FR-041, FR-042, spec.md User Story 2 Acceptance Scenario 3,
# data-model.md "Error Conditions" row "Backfill commit lacks
# batching/throttling/transaction-safety").
#
# Position in the engine pipeline (per quickstart.md "Pattern:
# Pre-Classification Gate Discipline" and the validators-list dispatch
# wired through `flavor_loader.rb` in T055):
#
#   empty-diff filter (FR-009)
#     -> forbidden-operations gate (FR-049)
#     -> classifier (FR-004)
#     -> precedent validator (FR-006)
#     -> reference-flavor validators (THIS module is one of them; FR-013)
#     -> size guard (FR-048)
#     -> isolation resolver (FR-005)
#     -> manifest writer (FR-002, FR-038)
#
# Contract (from FR-013 / spec.md User Story 2 Acceptance Scenario 3):
#
#   "The reference flavor MUST provide a backfill-safety validator that
#    rejects backfill commits lacking batching, throttling between
#    batches, or the directive to run outside a transaction; the
#    rejection error MUST name the missing safeguard."
#
# Three canonical safeguards are checked, in this fixed order so the
# operator-facing error message is reproducible across runs (FR-002,
# SC-002):
#
#   1. Batching       — `find_each` or `in_batches` somewhere in any
#                       added rake-task line.
#   2. Throttling     — `sleep <number>` somewhere in any added
#                       rake-task line (canonical Rails throttle).
#   3. Transaction-safety — `disable_ddl_transaction!` somewhere in any
#                       added rake-task line.
#
# Bypass-surface contract (mirrors ForbiddenOperationsGate's D-016
# stance and the engine PrecedentValidator): the constructor takes NO
# keyword arguments, the diff is the SOLE input to the safeguard scan,
# and no commit-message trailer (Phase-Type, Phaser-Skip-*, etc.) can
# suppress the validator's decision.
#
# Determinism: commits iterate in input order; the FIRST violation in
# input order is reported. Within a single commit, safeguards are
# checked in the canonical order above and the FIRST missing one is
# named in the error.
module Phaser
  # Raised when a commit classified as `data backfill-batched` lacks
  # one of the three required safeguards. Carries the offending commit
  # hash, the canonical `failing_rule` value `'backfill-safety'`, and a
  # `missing_safeguard` field naming which safeguard was absent.
  # Descends from `Phaser::ValidationError` so the engine's outer rescue
  # handles it uniformly with the other validation failure modes.
  class BackfillSafetyError < ValidationError
    attr_reader :commit_hash, :failing_rule, :missing_safeguard

    def initialize(commit_hash:, missing_safeguard:)
      @commit_hash = commit_hash
      @failing_rule = 'backfill-safety'
      @missing_safeguard = missing_safeguard
      super(
        "Commit #{@commit_hash} backfill is unsafe: missing " \
        "#{@missing_safeguard} safeguard"
      )
    end

    # The three-field Hash the engine hands to
    # `Observability#log_validation_failed` (FR-041) and to
    # `StatusWriter#write` (FR-042). Returned shape intentionally
    # excludes the keys belonging to other failure modes
    # (`forbidden_operation`, `decomposition_message`,
    # `missing_precedent`, `commit_count`, `phase_count`) so the
    # operator-facing record stays unambiguous about which rule fired.
    def to_validation_failed_payload
      {
        commit_hash: @commit_hash,
        failing_rule: @failing_rule,
        missing_safeguard: @missing_safeguard
      }
    end
  end

  module Flavors
    module RailsPostgresStrongMigrations
      # Stateless validator: constructed once per engine run with no
      # arguments. The bypass-empty surface is enforced in tests
      # (`backfill_validator_spec.rb`'s "exposes no constructor option
      # that would skip, force, or allow backfill-safety bypass"
      # example) so a future contributor cannot silently expand the
      # surface.
      class BackfillValidator
        # The task type this validator scopes to. Other types are
        # ignored (forbidden-operations / precedent validators handle
        # them).
        BACKFILL_TASK_TYPE = 'data backfill-batched'

        # The canonical safeguard order. The FIRST missing safeguard in
        # this order is the one named in the rejection error.
        SAFEGUARDS = %w[batching throttling transaction-safety].freeze

        # Batching primitives we accept: either `find_each` or
        # `in_batches`. Match them on added lines (leading `+`) inside
        # the rake-task diff hunks.
        BATCHING_REGEX = /\+.*\b(find_each|in_batches)\b/

        # Canonical throttle: a `sleep <number>` call on an added
        # line. The flavor accepts any numeric argument (integer or
        # float) so operators can tune throttle pace without re-tripping
        # the validator.
        THROTTLING_REGEX = /\+.*\bsleep\s+\d+(\.\d+)?\b/

        # Canonical transaction-safety directive: `disable_ddl_transaction!`
        # on an added line. Anchored to the bang to avoid colliding with
        # the (non-existent in Rails) un-banged variant.
        TRANSACTION_SAFETY_REGEX = /\+.*\bdisable_ddl_transaction!/

        # `validate(classification_results, commits, flavor)` — given
        # the post-precedent-validator list of `Phaser::ClassificationResult`s
        # in commit-emission order and the same-length list of source
        # `Phaser::Commit`s, returns the classification results
        # unchanged on success. On the first violation raises
        # `Phaser::BackfillSafetyError`.
        #
        # The validator only inspects commits whose `task_type` is
        # `'data backfill-batched'`. The `flavor` argument is accepted
        # for parity with the other reference-flavor validators but is
        # not consulted by this validator — the safeguard checks are
        # diff-only.
        def validate(classification_results, commits, _flavor)
          commits_by_hash = index_commits_by_hash(commits)

          classification_results.each do |result|
            next unless result.task_type == BACKFILL_TASK_TYPE

            commit = commits_by_hash[result.commit_hash]
            missing = first_missing_safeguard(commit)
            next if missing.nil?

            raise BackfillSafetyError.new(
              commit_hash: result.commit_hash,
              missing_safeguard: missing
            )
          end

          classification_results
        end

        private

        # Build a hash from commit hash to `Phaser::Commit` so the
        # validator can pull the diff for each classified backfill in
        # O(1). The classification result list and commit list are
        # same-length and in the same order, but we index by hash so
        # the validator does not depend on positional alignment.
        def index_commits_by_hash(commits)
          commits.to_h { |commit| [commit.hash, commit] }
        end

        # Iterate SAFEGUARDS in canonical order; return the FIRST
        # absent safeguard's name, or nil if every safeguard is
        # present. The deterministic ordering is the contract pinned by
        # the spec's "first missing safeguard in canonical order"
        # describe block.
        def first_missing_safeguard(commit)
          SAFEGUARDS.find { |safeguard| !safeguard_present?(commit, safeguard) }
        end

        def safeguard_present?(commit, safeguard)
          regex = regex_for(safeguard)
          any_added_line_matches?(commit, regex)
        end

        def regex_for(safeguard)
          case safeguard
          when 'batching'            then BATCHING_REGEX
          when 'throttling'          then THROTTLING_REGEX
          when 'transaction-safety'  then TRANSACTION_SAFETY_REGEX
          end
        end

        # True iff any hunk of any file in the commit's diff matches
        # the regex. The validator scans every file rather than scoping
        # to `lib/tasks/*.rake` because some flavors place the
        # `disable_ddl_transaction!` directive in the migration file
        # adjacent to the rake task; pinning to the rake-task path
        # would cause a false rejection in that arrangement.
        def any_added_line_matches?(commit, regex)
          commit.diff.files.any? do |file|
            file.hunks.any? { |hunk| regex.match?(hunk) }
          end
        end
      end
    end
  end
end
