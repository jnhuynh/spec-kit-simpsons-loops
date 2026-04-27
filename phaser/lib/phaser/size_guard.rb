# frozen_string_literal: true

module Phaser
  # Raised by `Phaser::SizeGuard#enforce` (and constructible directly so
  # the engine, status writer, and observability surfaces can build a
  # payload without re-running the projection) when a feature exceeds
  # either of FR-048's two hard bounds: more than 200 non-empty commits,
  # or a worst-case projected phase count greater than 50.
  #
  # The error is feature-attributable, NOT commit-attributable, per the
  # `validation-failed` schema's "Not set for `feature-too-large`" note in
  # `contracts/observability-events.md`. Accordingly the payload returned
  # by `#to_validation_failed_payload` deliberately OMITS `commit_hash`
  # and any other commit-scoped key (`missing_precedent`,
  # `forbidden_operation`).
  #
  # Descends from `Phaser::ValidationError` so the engine's outer rescue
  # clause handles it uniformly with the other validation failure modes
  # (forbidden-operation, precedent, backfill-safety, unknown-type-tag,
  # safety-assertion-missing).
  class SizeBoundError < ValidationError
    # Canonical `failing_rule` literal for FR-041 / FR-048 /
    # `contracts/observability-events.md`. Pinned as a constant on the
    # error class so callers building payloads outside the engine (e.g.,
    # ad-hoc reproduction scripts) cannot drift from the wire shape.
    FAILING_RULE = 'feature-too-large'

    # Canonical operator-facing remediation. SC-008 (precise error
    # messages) requires the maintainer can diagnose the failure from
    # this string alone; the most actionable next step is to split the
    # feature into smaller specs (FR-048).
    DECOMPOSITION_MESSAGE =
      'Feature exceeds the supported size bounds (more than 200 ' \
      'non-empty commits or a projected phase count above 50). Split ' \
      'the feature into multiple smaller specs and re-run the phaser ' \
      'on each one.'

    attr_reader :commit_count, :phase_count

    def initialize(commit_count:, phase_count:)
      @commit_count = commit_count
      @phase_count = phase_count
      super(
        "Feature too large: #{commit_count} non-empty commits, " \
        "#{phase_count} projected phases (limits: " \
        "#{SizeGuard::MAX_COMMITS} commits, #{SizeGuard::MAX_PHASES} " \
        'phases). ' + DECOMPOSITION_MESSAGE
      )
    end

    # The canonical `failing_rule` literal for FR-041 /
    # `contracts/observability-events.md`. Exposed as a method so call
    # sites read symmetrically with `PrecedentError#failing_rule` and
    # `ForbiddenOperationError#failing_rule`.
    def failing_rule
      FAILING_RULE
    end

    # Operator-facing remediation string. Returned as a method (not
    # captured into an ivar at construction) so the value is always
    # exactly the canonical constant — a future contributor cannot pass
    # an alternative message through the constructor.
    def decomposition_message
      DECOMPOSITION_MESSAGE
    end

    # The four-field Hash the engine hands to
    # `Observability#log_validation_failed` (FR-041) and to
    # `StatusWriter#write` (FR-042). Returns ONLY the keys the
    # feature-too-large rejection mode populates so other failure modes
    # (precedent populates `missing_precedent`; forbidden-operation
    # populates `forbidden_operation`) remain visually distinct in the
    # operator-facing record.
    def to_validation_failed_payload
      {
        failing_rule: FAILING_RULE,
        commit_count: @commit_count,
        phase_count: @phase_count,
        decomposition_message: DECOMPOSITION_MESSAGE
      }
    end
  end

  # Pure-function feature-size guard that rejects any feature whose
  # post-classification commit count exceeds 200 or whose worst-case
  # projected phase count exceeds 50, BEFORE any manifest is written
  # (feature 007-multi-phase-pipeline; T034, FR-009, FR-041, FR-042,
  # FR-048, SC-014, data-model.md "Error Conditions" table row "Feature
  # branch exceeds 200 non-empty commits or projected 50 phases").
  #
  # Position in the engine pipeline per quickstart.md "Pattern:
  # Pre-Classification Gate Discipline" (T035 in tasks.md):
  #
  #   empty-diff filter (FR-009)
  #     -> forbidden-operations gate (FR-049)
  #     -> classifier (FR-004)
  #     -> precedent validator (FR-006)
  #     -> SIZE GUARD (FR-048)                       <-- this module
  #     -> isolation resolver (FR-005)
  #     -> manifest writer (FR-002, FR-038)
  #
  # The guard runs AFTER classification (so each input is a
  # `Phaser::ClassificationResult` carrying a normalized `isolation`
  # value the worst-case phase projection can read directly) and BEFORE
  # the isolation resolver and manifest writer (so a too-large feature
  # never produces a partial manifest on disk). FR-048 explicitly states
  # that empty-diff commits skipped under FR-009 do NOT count toward the
  # 200-commit bound; the guard sees only the post-FR-009 list, so this
  # is enforced by construction.
  #
  # Bypass-surface contract (mirrors ForbiddenOperationsGate's D-016
  # stance): the constructor takes no arguments, the bounds are class
  # constants (not flavor-configurable, not environment-variable-
  # controlled), and no flag, environment variable, or commit-message
  # trailer can suppress the guard. FR-048 is a deploy-safety guarantee,
  # not a tunable preference.
  #
  # Determinism contract (FR-002, SC-002): the projection is a pure
  # function of `(classification_result isolation values, ordering)`. The
  # same input list ALWAYS produces the same projection, so two operators
  # running the same flavor on the same commits see the same
  # `commit_count` / `phase_count` payload.
  class SizeGuard
    # Hard bound on the post-FR-009 (non-empty) commit count. 200 is the
    # MAXIMUM accepted count; 201 is the first rejected count. Pinned as
    # a constant so the threshold is visible at the call site and
    # assertable from the spec without introspecting the implementation.
    MAX_COMMITS = 200

    # Hard bound on the worst-case projected phase count under FR-005's
    # greedy-coalesce default. 50 is the MAXIMUM accepted count; 51 is
    # the first rejected count.
    MAX_PHASES = 50

    # Canonical `failing_rule` literal for FR-041 /
    # `contracts/observability-events.md`. Exposed on the class (as well
    # as on `SizeBoundError`) so a caller computing the payload from the
    # guard's perspective can pin the literal without instantiating an
    # error object.
    FAILING_RULE = SizeBoundError::FAILING_RULE

    # Returns the input list unchanged on success (so the engine can
    # chain the call site directly into the next pipeline stage). On
    # violation raises `Phaser::SizeBoundError` carrying `commit_count`,
    # the worst-case `phase_count`, and the canonical
    # `decomposition_message`.
    #
    # The `flavor` parameter is accepted for signature symmetry with
    # `PrecedentValidator#validate(results, flavor)` and
    # `IsolationResolver#resolve(results, flavor)` — the size guard does
    # NOT consume any flavor-side rules; the projection is a pure
    # function of the `ClassificationResult.isolation` values.
    def enforce(classification_results, _flavor)
      commit_count = classification_results.length
      phase_count = project_phase_count(classification_results)

      return classification_results if within_bounds?(commit_count, phase_count)

      raise SizeBoundError.new(commit_count: commit_count, phase_count: phase_count)
    end

    private

    def within_bounds?(commit_count, phase_count)
      commit_count <= MAX_COMMITS && phase_count <= MAX_PHASES
    end

    # Worst-case phase projection (FR-048 + FR-005): every `:alone`
    # result occupies its own phase (contributes 1); every contiguous
    # run of `:groups` results coalesces into a single phase
    # (contributes 1 per run, regardless of the run's length).
    #
    # The projection MUST NOT inspect the diff, the filesystem, or any
    # non-input source; it is a pure function of the isolation values
    # and their ordering. Walks the list once counting boundaries.
    def project_phase_count(classification_results)
      return 0 if classification_results.empty?

      phase_count = 0
      previous_isolation = nil

      classification_results.each do |result|
        phase_count += 1 if starts_new_phase?(result, previous_isolation)
        previous_isolation = result.isolation
      end

      phase_count
    end

    # A classification result opens a new phase when it is `:alone`
    # (every `:alone` result occupies its own phase) or when it is
    # `:groups` but the previous result was not `:groups` (the start of
    # a new contiguous coalesce-able run). A `:groups` result that
    # follows another `:groups` result extends the run without opening a
    # new phase, so it returns false.
    def starts_new_phase?(result, previous_isolation)
      result.isolation == :alone || previous_isolation != :groups
    end
  end
end
