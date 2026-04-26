# frozen_string_literal: true

# Column-drop precedent validator for the
# rails-postgres-strong-migrations reference flavor (feature
# 007-multi-phase-pipeline; T054, FR-014, FR-041, FR-042, spec.md User
# Story 2 Acceptance Scenario 4, data-model.md "Error Conditions" row
# "Precedent rule violated").
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
# (T032):
#
#   The engine's `Phaser::PrecedentValidator` (T032) enforces ONE
#   precedent rule at a time and reports the FIRST rule that fails.
#   FR-014 demands a CONJOINED rejection: a column-drop commit MUST be
#   preceded by BOTH an "ignore column for pending drop" commit AND a
#   "remove all references to pending-drop column" commit, and the
#   rejection MUST name BOTH missing precedents in a single error so the
#   operator knows the full set of remediation commits to add. The
#   two-rules-with-AND semantics cannot be expressed by two independent
#   FlavorPrecedentRules — that would surface the precedents one at a
#   time across re-runs ("ignore is missing" -> operator adds it ->
#   "reference-removal is missing" -> operator adds it). One error
#   message that names both at once is the contract.
#
# Bypass-surface contract (mirrors ForbiddenOperationsGate's D-016
# stance and the engine PrecedentValidator): the constructor takes NO
# keyword arguments, and no commit-message trailer (Phase-Type,
# Phaser-Skip-*, Phaser-Allow-*, etc.) can suppress the validator's
# decision.
#
# Determinism (FR-002, SC-002): commits iterate in input order; the
# FIRST column-drop violation in input order is reported. Within the
# `missing_precedents` array, names are listed in canonical order —
# ignored-columns directive first, reference removal second — so the
# operator-facing message is reproducible across runs.
module Phaser
  # Raised when a `schema drop-column-with-cleanup-precedent` commit is
  # missing one or both of its required cleanup precedents (an earlier
  # `code ignore-column-for-pending-drop` commit AND an earlier
  # `code remove-references-to-pending-drop-column` commit, both
  # touching the same column being dropped).
  #
  # Carries the offending commit hash, the canonical `failing_rule`
  # value `'drop-column-cleanup-precedent'`, and a `missing_precedents`
  # field whose value is an Array of the precedent task-type names
  # absent in earlier commits in the input list. Descends from
  # `Phaser::ValidationError` so the engine's outer rescue clause
  # handles it uniformly with the other validation failure modes.
  class ColumnDropPrecedentError < ValidationError
    FAILING_RULE = 'drop-column-cleanup-precedent'

    attr_reader :commit_hash, :failing_rule, :missing_precedents

    def initialize(commit_hash:, missing_precedents:)
      @commit_hash = commit_hash
      @failing_rule = FAILING_RULE
      @missing_precedents = missing_precedents
      super(
        "Commit #{@commit_hash} cannot drop column without cleanup " \
        "precedents: missing #{@missing_precedents.join(', ')}"
      )
    end

    # The three-field Hash the engine hands to
    # `Observability#log_validation_failed` (FR-041) and to
    # `StatusWriter#write` (FR-042). Uses the singular `missing_precedent`
    # key (matching the existing
    # `contracts/phase-creation-status.schema.yaml` field used by the
    # engine PrecedentValidator) with both names joined so the existing
    # schema carries both without introducing a schema-incompatible new
    # key.
    def to_validation_failed_payload
      {
        commit_hash: @commit_hash,
        failing_rule: @failing_rule,
        missing_precedent: @missing_precedents.join(', ')
      }
    end
  end

  module Flavors
    module RailsPostgresStrongMigrations
      # Stateless validator: constructed once per engine run with no
      # arguments. The bypass-empty surface is enforced in tests
      # (`precedent_validator_spec.rb`'s "exposes no constructor option
      # that would skip, force, or allow precedent bypass" example) so a
      # future contributor cannot silently expand the surface.
      class PrecedentValidator
        # The task type this validator scopes to. Other types are
        # ignored — the engine PrecedentValidator (FR-006) and the
        # forbidden-operations gate (FR-015) handle them.
        DROP_TASK_TYPE = 'schema drop-column-with-cleanup-precedent'

        # The two precedent task-type names required for a safe
        # column drop. Listed in canonical order so the
        # `missing_precedents` array is reproducible across runs.
        IGNORE_TASK_TYPE = 'code ignore-column-for-pending-drop'
        REMOVE_REFS_TASK_TYPE = 'code remove-references-to-pending-drop-column'
        CANONICAL_PRECEDENT_ORDER = [IGNORE_TASK_TYPE, REMOVE_REFS_TASK_TYPE].freeze

        # Match `remove_column :<table>, :<column>` in an added line of
        # a migration diff. The column name (capture group 2) is what
        # we join against the precedent commits.
        REMOVE_COLUMN_REGEX = /\+.*\bremove_column\s+:(\w+)\s*,\s*:(\w+)/

        # Match `self.ignored_columns = %w[<col1> <col2> ...]` or
        # `self.ignored_columns = [:col1, :col2]`. The validator walks
        # both forms, extracting every column name on the added line(s).
        IGNORED_COLUMNS_WORDS_REGEX = /\+.*self\.ignored_columns\s*=\s*%w\[([^\]]+)\]/
        IGNORED_COLUMNS_ARRAY_REGEX = /\+.*self\.ignored_columns\s*=\s*\[([^\]]+)\]/

        # Validate the column-drop precedent contract for a list of
        # already-classified commits.
        #
        # `classification_results` — the same-length list of
        # `Phaser::ClassificationResult`s in commit-emission order.
        # `commits` — the source `Phaser::Commit` list (so the validator
        # can read the diff of each drop commit and each candidate
        # precedent commit to extract column names for the join).
        # `_flavor` — accepted for parity with the other reference-flavor
        # validators but not consulted (the validator's contract is
        # pinned by the canonical task-type names above).
        #
        # Returns `classification_results` unchanged on success. On the
        # first violation raises `Phaser::ColumnDropPrecedentError`.
        def validate(classification_results, commits, _flavor)
          commits_by_hash = index_commits_by_hash(commits)

          classification_results.each_with_index do |result, index|
            next unless result.task_type == DROP_TASK_TYPE

            drop_commit = commits_by_hash[result.commit_hash]
            column = extract_dropped_column(drop_commit)

            earlier_results = classification_results.first(index)
            missing = missing_precedents_for(
              column, earlier_results, commits_by_hash
            )
            next if missing.empty?

            raise ColumnDropPrecedentError.new(
              commit_hash: result.commit_hash,
              missing_precedents: missing
            )
          end

          classification_results
        end

        private

        # O(1) lookup from commit hash to source `Phaser::Commit`. The
        # classification result list and commit list are same-length and
        # in the same order, but we index by hash so the validator does
        # not depend on positional alignment.
        def index_commits_by_hash(commits)
          commits.to_h { |commit| [commit.hash, commit] }
        end

        # Walk the drop commit's diff looking for the canonical
        # `remove_column :<table>, :<column>` migration form. Returns
        # the column name as a String, or nil when the regex does not
        # match (in which case the validator falls back to listing both
        # precedents as missing — the safest possible default since no
        # column-name join can be performed).
        def extract_dropped_column(commit)
          commit.diff.files.each do |file|
            file.hunks.each do |hunk|
              match = hunk.match(REMOVE_COLUMN_REGEX)
              return match[2] if match
            end
          end
          nil
        end

        # Determine which canonical precedents are missing for the given
        # column. A precedent is considered "present" when an earlier
        # classified commit's task type matches the precedent type AND
        # that commit's diff touches the same column name as the drop
        # commit. Returned in canonical order
        # (ignored-columns first, reference-removal second).
        def missing_precedents_for(column, earlier_results, commits_by_hash)
          present = present_precedent_types(column, earlier_results, commits_by_hash)
          CANONICAL_PRECEDENT_ORDER.reject { |type| present.include?(type) }
        end

        def present_precedent_types(column, earlier_results, commits_by_hash)
          earlier_results.each_with_object(Set.new) do |result, acc|
            next unless CANONICAL_PRECEDENT_ORDER.include?(result.task_type)

            commit = commits_by_hash[result.commit_hash]
            acc << result.task_type if commit_touches_column?(
              commit, result.task_type, column
            )
          end
        end

        # True iff the candidate precedent commit's diff references the
        # column being dropped. When `column` is nil (the drop commit's
        # diff did not match the canonical `remove_column` form) the
        # column-name join cannot be performed, so neither precedent
        # type can be considered "present" for this drop.
        def commit_touches_column?(commit, task_type, column)
          return false if column.nil?

          case task_type
          when IGNORE_TASK_TYPE
            commit_ignores_column?(commit, column)
          when REMOVE_REFS_TASK_TYPE
            commit_mentions_column?(commit, column)
          else
            false
          end
        end

        # An ignored-columns directive commit is considered to cover the
        # column iff one of its added hunks declares
        # `self.ignored_columns = %w[... <column> ...]` (or the array
        # literal form) and the column appears in that list.
        def commit_ignores_column?(commit, column)
          commit.diff.files.any? do |file|
            file.hunks.any? { |hunk| hunk_lists_column?(hunk, column) }
          end
        end

        def hunk_lists_column?(hunk, column)
          words_match = hunk.match(IGNORED_COLUMNS_WORDS_REGEX)
          return true if words_match && words_match[1].split.include?(column)

          array_match = hunk.match(IGNORED_COLUMNS_ARRAY_REGEX)
          return false unless array_match

          tokens = array_match[1].split(',').map { |t| t.strip.delete_prefix(':') }
          tokens.include?(column)
        end

        # A reference-removal commit is considered to cover the column
        # iff any of its hunks (added OR removed lines) literally
        # mention the column name as a Ruby identifier
        # (`:<column>`, `<column>`, `\.<column>`). The validator uses a
        # word-boundary search so we don't false-positive on a column
        # whose name is a substring of another identifier.
        def commit_mentions_column?(commit, column)
          pattern = /\b#{Regexp.escape(column)}\b/
          commit.diff.files.any? do |file|
            file.hunks.any? { |hunk| pattern.match?(hunk) }
          end
        end
      end
    end
  end
end
