# frozen_string_literal: true

# Safety-assertion validator for the rails-postgres-strong-migrations
# reference flavor (feature 007-multi-phase-pipeline; T054b, FR-018,
# FR-041, FR-042, plan.md D-017, data-model.md "Task"
# `safety_assertion_precedents` field, data-model.md "Error Conditions"
# rows for safety-assertion failures).
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
# directive. Two failure modes:
#
#   1. The commit message carries no `Safety-Assertion:` trailer (and
#      no fenced ` ```safety-assertion ` block) — `failing_rule:
#      safety-assertion-missing`.
#   2. The commit message cites a SHA that is not a valid precedent
#      under the flavor's precedent rules for the subject task type —
#      `failing_rule: safety-assertion-precedent-mismatch`.
#
# On success the cited SHAs are attached to the corresponding
# `Phaser::ClassificationResult#safety_assertion_precedents` so the
# engine forwards them into `Phaser::Task#safety_assertion_precedents`
# at manifest-build time and the audit trail reaches the manifest
# (data-model.md "Task").
#
# Bypass-surface contract (mirrors ForbiddenOperationsGate's D-016
# stance, the engine PrecedentValidator, the backfill validator, and
# the column-drop precedent validator): the constructor takes NO
# keyword arguments, and no commit-message trailer (Phase-Type,
# Phaser-Skip-*, Phaser-Allow-*, etc.) other than the canonical
# `Safety-Assertion:` trailer the validator itself reads can suppress
# the validator's decision.
#
# Determinism (FR-002, SC-002): commits iterate in input order; the
# FIRST irreversible-commit violation in input order is reported.
# Within `cited_precedents`, SHAs appear in the order they were listed
# in the safety-assertion block.
module Phaser
  # Raised when a commit classified as one of the flavor's irreversible
  # task types lacks a well-formed safety-assertion block. Carries the
  # offending commit hash, one of two canonical `failing_rule` values
  # (`'safety-assertion-missing'` or
  # `'safety-assertion-precedent-mismatch'`), and a `cited_precedents`
  # array of the SHAs parsed out of the commit's safety-assertion block
  # (empty when the block is absent entirely; non-empty array of the
  # non-matching SHAs when the failure is a precedent mismatch).
  # Descends from `Phaser::ValidationError` so the engine's outer rescue
  # clause handles it uniformly with the other validation failure
  # modes.
  class SafetyAssertionError < ValidationError
    MISSING = 'safety-assertion-missing'
    PRECEDENT_MISMATCH = 'safety-assertion-precedent-mismatch'

    attr_reader :commit_hash, :failing_rule, :cited_precedents

    def initialize(commit_hash:, failing_rule:, cited_precedents:)
      @commit_hash = commit_hash
      @failing_rule = failing_rule
      @cited_precedents = cited_precedents
      super(build_message)
    end

    # The Hash the engine hands to
    # `Observability#log_validation_failed` (FR-041) and to
    # `StatusWriter#write` (FR-042). The mismatch path joins cited
    # SHAs with `", "` into the singular `missing_precedent` schema
    # field (the same pattern the column-drop precedent validator uses)
    # so the existing `phase-creation-status.yaml` schema carries the
    # audit trail without introducing a schema-incompatible new key.
    # The missing-block path has no precedents to cite, so the payload
    # omits `missing_precedent` entirely.
    def to_validation_failed_payload
      payload = {
        commit_hash: @commit_hash,
        failing_rule: @failing_rule
      }
      return payload if @failing_rule == MISSING

      payload[:missing_precedent] = @cited_precedents.join(', ')
      payload
    end

    private

    def build_message
      case @failing_rule
      when MISSING
        "Commit #{@commit_hash} is irreversible and is missing a " \
        'safety-assertion block citing its precedent commits.'
      else
        "Commit #{@commit_hash} cites SHAs that are not valid " \
        "precedents for this task type: #{@cited_precedents.join(', ')}"
      end
    end
  end

  module Flavors
    module RailsPostgresStrongMigrations
      # Stateless validator: constructed once per engine run with no
      # arguments. The bypass-empty surface is enforced in tests
      # (`safety_assertion_validator_spec.rb`'s "exposes no constructor
      # option that would skip, force, or allow safety-assertion bypass"
      # example) so a future contributor cannot silently expand the
      # surface.
      class SafetyAssertionValidator
        # Hard-coded fallback list mirroring `flavor.yaml`'s irreversible
        # task types (plan.md D-017). The validator prefers the active
        # flavor's `irreversible_task_types` accessor when present (T055
        # will surface it through the loader) and falls back to this
        # constant only if the flavor does not expose the accessor — a
        # transitional safety net for the incremental landings in
        # T054b/T055 per quickstart.md "Pattern: Validators-List
        # Dispatch".
        DEFAULT_IRREVERSIBLE_TASK_TYPES = [
          'schema drop-column-with-cleanup-precedent',
          'schema drop-table',
          'schema drop-concurrent-index',
          'code remove-ignored-columns-directive'
        ].freeze

        # Canonical 40-char Git SHA pattern. The validator scans the
        # safety-assertion block for these exact tokens so surrounding
        # prose ("see commit abc...") does not interfere with the parse.
        SHA_REGEX = /[0-9a-f]{40}/

        # The Git trailer key the validator reads when the operator
        # places the safety-assertion in the commit's trailer block.
        SAFETY_ASSERTION_TRAILER = 'Safety-Assertion'

        # Match the fenced ` ```safety-assertion ` block in a commit
        # subject (the spec embeds the block as a multi-line subject;
        # production reads commits with a separate body, so the regex
        # is anchored to the fence opener / closer rather than to a
        # specific position in the message).
        FENCED_BLOCK_REGEX = /```safety-assertion\s*\n(.*?)\n```/m

        # Validate the safety-assertion contract for a list of
        # already-classified commits.
        #
        # `classification_results` — the same-length list of
        # `Phaser::ClassificationResult`s in commit-emission order.
        # `commits` — the source `Phaser::Commit` list (so the validator
        # can read each subject commit's `message_trailers` and subject
        # for the safety-assertion block).
        # `flavor` — the active `Phaser::Flavor`. The validator reads
        # `flavor.irreversible_task_types` when the accessor is present
        # and `flavor.precedent_rules` to verify each cited SHA's
        # classified type is a valid precedent for the subject type.
        #
        # Returns a NEW list of classification results with the cited
        # SHAs attached to each accepted irreversible commit's result
        # via `safety_assertion_precedents`. On the first violation
        # raises `Phaser::SafetyAssertionError`.
        def validate(classification_results, commits, flavor)
          irreversible_types = irreversible_task_types_for(flavor)
          commits_by_hash = index_commits_by_hash(commits)
          earlier_results_by_hash = build_earlier_results_index(classification_results)

          classification_results.map do |result|
            next result unless irreversible_types.include?(result.task_type)

            commit = commits_by_hash[result.commit_hash]
            cited = parse_cited_shas(commit)
            raise_missing(result.commit_hash) if cited.empty?

            verify_cited_precedents!(
              result, cited, earlier_results_by_hash, flavor
            )
            with_safety_assertion_precedents(result, cited)
          end
        end

        private

        # Read the irreversible task-type list from the active flavor
        # when the accessor is present (T055 will surface it through
        # the loader); fall back to the canonical four-type list
        # otherwise so individual test runs against a Flavor value
        # object that has not yet been extended still classify
        # correctly.
        def irreversible_task_types_for(flavor)
          if flavor.respond_to?(:irreversible_task_types)
            flavor.irreversible_task_types
          else
            DEFAULT_IRREVERSIBLE_TASK_TYPES
          end
        end

        # O(1) lookup from commit hash to source `Phaser::Commit`. The
        # classification result list and commit list are same-length
        # and in the same order, but we index by hash so the validator
        # does not depend on positional alignment.
        def index_commits_by_hash(commits)
          commits.to_h { |commit| [commit.hash, commit] }
        end

        # Build a hash from commit hash to the Array of classification
        # results that appear STRICTLY EARLIER in input order. Used to
        # verify each cited SHA refers to a precedent commit on the
        # feature branch, not to the subject commit itself or to a
        # commit that comes after.
        def build_earlier_results_index(classification_results)
          index = {}
          earlier = []
          classification_results.each do |result|
            index[result.commit_hash] = earlier.dup
            earlier << result
          end
          index
        end

        # Parse cited 40-char SHAs out of either the canonical
        # `Safety-Assertion:` trailer or a fenced ` ```safety-assertion
        # ``` ` block in the commit subject/body. Trailer takes
        # precedence when both are present; within the trailer the SHAs
        # are scanned in the order they appear so the operator-facing
        # output (and the audit-trail attached to the manifest) is
        # reproducible.
        def parse_cited_shas(commit)
          trailer_value = commit.message_trailers[SAFETY_ASSERTION_TRAILER]
          return trailer_value.scan(SHA_REGEX) if trailer_value

          match = commit.subject.match(FENCED_BLOCK_REGEX)
          return [] unless match

          match[1].scan(SHA_REGEX)
        end

        # Verify every cited SHA refers to an EARLIER commit in the
        # input list AND that its classified task type is a valid
        # predecessor for the subject's task type per the flavor's
        # precedent rules. The first cited SHA that fails either check
        # produces a precedent-mismatch rejection naming the entire
        # cited list (so the operator sees the full audit decision in
        # one error rather than discovering one bad citation per re-run).
        def verify_cited_precedents!(result, cited, earlier_results_by_hash, flavor)
          earlier_results = earlier_results_by_hash.fetch(result.commit_hash, [])
          earlier_by_hash = earlier_results.to_h { |r| [r.commit_hash, r] }
          valid_predecessor_types = predecessor_types_for(result.task_type, flavor)

          cited.each do |sha|
            earlier = earlier_by_hash[sha]
            unless earlier && valid_predecessor_types.include?(earlier.task_type)
              raise_precedent_mismatch(result.commit_hash, cited)
            end
          end
        end

        # The set of task-type names declared as precedents for
        # `subject_type` by the flavor's precedent rules. Returned as a
        # Set for O(1) membership checks; empty when the flavor
        # declares no precedent rules for the subject type (in which
        # case any cited SHA fails the precedent check, the safest
        # possible default).
        def predecessor_types_for(subject_type, flavor)
          flavor.precedent_rules
                .select { |rule| rule.subject_type == subject_type }
                .to_set(&:predecessor_type)
        end

        # Return a NEW ClassificationResult with the cited SHAs
        # recorded in `safety_assertion_precedents`. ClassificationResult
        # is a `Data.define` value object whose `with` method copies
        # the existing attributes and overrides only the named ones,
        # preserving immutability.
        def with_safety_assertion_precedents(result, cited)
          result.with(safety_assertion_precedents: cited)
        end

        def raise_missing(commit_hash)
          raise SafetyAssertionError.new(
            commit_hash: commit_hash,
            failing_rule: SafetyAssertionError::MISSING,
            cited_precedents: []
          )
        end

        def raise_precedent_mismatch(commit_hash, cited)
          raise SafetyAssertionError.new(
            commit_hash: commit_hash,
            failing_rule: SafetyAssertionError::PRECEDENT_MISMATCH,
            cited_precedents: cited
          )
        end
      end
    end
  end
end
