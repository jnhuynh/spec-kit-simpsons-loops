# frozen_string_literal: true

module Phaser
  # Pure-function partitioner that turns the post-precedent-validation
  # list of `Phaser::ClassificationResult`s into an ordered sequence of
  # phases (feature 007-multi-phase-pipeline; T033, FR-005, FR-006,
  # FR-037, R-005, data-model.md "TaskType" / "Phase").
  #
  # Position in the engine pipeline (per quickstart.md "Pattern:
  # Pre-Classification Gate Discipline" and T035 in tasks.md):
  #
  #   empty-diff filter (FR-009)
  #     -> forbidden-operations gate (FR-049)
  #     -> classifier (FR-004)
  #     -> precedent validator (FR-006)
  #     -> size guard (FR-048)
  #     -> ISOLATION RESOLVER (FR-005)             <-- this module
  #     -> manifest writer (FR-002, FR-038)
  #
  # The resolver is stateless and consumes the validated, in-input-order
  # list of `Phaser::ClassificationResult`s along with the active
  # `Phaser::Flavor`. It returns an `Array<Array<ClassificationResult>>`:
  # the outer list is the sequence of phases (1..N) and each inner list
  # is the ordered group of classification results that belong to that
  # phase. The engine wraps each inner list as a `Phaser::Phase` value
  # object, attaching branch-naming and CI metadata.
  #
  # Contract surfaces enforced here:
  #
  #   * FR-005 isolation:
  #       - `:alone` results occupy their own phase regardless of
  #         neighboring isolation kinds.
  #       - Contiguous `:groups` results coalesce into a single phase.
  #       - An `:alone` result acts as a phase boundary that splits
  #         adjacent `:groups` runs into separate phases.
  #
  #   * FR-006 precedent: when the active flavor declares a
  #     PrecedentRule whose `subject_type` matches the current commit
  #     and any commit already in the current phase has the rule's
  #     `predecessor_type`, the resolver opens a new phase so the
  #     subject lands strictly later than its predecessor (the
  #     PrecedentValidator at T032 already guaranteed the predecessor
  #     exists earlier in the input list; the resolver's job is to
  #     translate that into "strictly later phase").
  #
  #   * FR-037 backfill sequencing: a "backfill task type" (identified
  #     by a `/backfill/` substring in the type name OR a description
  #     containing "backfill") is sequential by default. The flavor
  #     toggle `allow_parallel_backfills: true` relaxes this so
  #     backfills may coalesce with adjacent `:groups` peers; otherwise,
  #     a backfill task always creates a phase boundary like an
  #     `:alone` task would, even when its declared isolation is
  #     `:groups`.
  #
  #   * FR-002 / SC-002 / R-005 determinism: the resolver is a pure
  #     function of `(classification_results, flavor)`. It never
  #     consults wall-clock time, the filesystem, or environment
  #     variables. It preserves input order within each phase and never
  #     re-sorts inputs that arrive in a deterministic order.
  #
  # Bypass-surface contract: the resolver is constructed with no
  # arguments and exposes only `#resolve(classification_results,
  # flavor)`. There is no operator-supplied flag/env-var/trailer that
  # can change the resolver's grouping behavior.
  class IsolationResolver
    # Partition the post-validation classification result list into
    # ordered phases. Returns `Array<Array<ClassificationResult>>`.
    # The input list is never mutated.
    def resolve(classification_results, flavor)
      return [] if classification_results.empty?

      backfill_types = backfill_task_type_names(flavor)
      allow_parallel_backfills = flavor.allow_parallel_backfills
      precedent_pairs = precedent_subject_to_predecessors(flavor)

      partition(
        classification_results,
        backfill_types: backfill_types,
        allow_parallel_backfills: allow_parallel_backfills,
        precedent_pairs: precedent_pairs
      )
    end

    private

    # Walk the input list in order, opening a new phase whenever the
    # next result cannot legally share the current phase with the
    # results already accumulated. The boundary conditions are:
    #
    #   1. The current result is `:alone`.
    #   2. The previous result that opened (or was added to) the current
    #      phase is `:alone`.
    #   3. The current result is a backfill task type and the flavor
    #      does NOT permit parallel backfills.
    #   4. Any result already in the current phase is a backfill task
    #      type and the flavor does NOT permit parallel backfills.
    #   5. The current result's `task_type` is the subject of a
    #      precedent rule and any result already in the current phase
    #      has the corresponding `predecessor_type`.
    def partition(results, backfill_types:, allow_parallel_backfills:, precedent_pairs:)
      phases = []
      current_phase = []
      boundary_options = {
        backfill_types: backfill_types,
        allow_parallel_backfills: allow_parallel_backfills,
        precedent_pairs: precedent_pairs
      }

      results.each do |result|
        if start_new_phase?(current_phase, result, boundary_options)
          phases << current_phase unless current_phase.empty?
          current_phase = [result]
        else
          current_phase << result
        end
      end

      phases << current_phase unless current_phase.empty?
      phases
    end

    # The first commit always starts a phase; thereafter, defer to
    # `needs_new_phase?` for the FR-005 / FR-006 / FR-037 boundary
    # checks. Splitting this predicate out keeps `partition` short
    # enough to satisfy rubocop's method-length budget while preserving
    # the two-step "open phase if empty, otherwise check boundaries"
    # control flow.
    def start_new_phase?(current_phase, incoming, boundary_options)
      return true if current_phase.empty?

      needs_new_phase?(
        current_phase: current_phase,
        incoming: incoming,
        **boundary_options
      )
    end

    # Decide whether `incoming` requires a fresh phase rather than
    # joining `current_phase`. Returns true on any of the boundary
    # conditions enumerated in `partition`.
    def needs_new_phase?(current_phase:, incoming:, backfill_types:,
                         allow_parallel_backfills:, precedent_pairs:)
      return true if incoming.isolation == :alone
      return true if current_phase.any? { |r| r.isolation == :alone }

      if backfill_boundary?(current_phase, incoming, backfill_types,
                            allow_parallel_backfills)
        return true
      end

      precedent_boundary?(current_phase, incoming, precedent_pairs)
    end

    # FR-037 backfill boundary: when the flavor disallows parallel
    # backfills, a backfill task type creates a phase boundary on both
    # the incoming side (the new backfill cannot join the current
    # phase) and the trailing side (the current phase already contains
    # a backfill, so any new task starts a fresh phase).
    def backfill_boundary?(current_phase, incoming, backfill_types,
                           allow_parallel_backfills)
      return false if allow_parallel_backfills
      return false if backfill_types.empty?

      return true if backfill_types.include?(incoming.task_type)

      current_phase.any? { |r| backfill_types.include?(r.task_type) }
    end

    # FR-006 precedent boundary: open a new phase when the incoming
    # result's task type is the subject of a precedent rule and the
    # current phase already contains at least one result with the
    # matching predecessor type.
    def precedent_boundary?(current_phase, incoming, precedent_pairs)
      predecessor_types = precedent_pairs[incoming.task_type]
      return false if predecessor_types.nil? || predecessor_types.empty?

      current_phase.any? { |r| predecessor_types.include?(r.task_type) }
    end

    # Identify backfill task types by inspecting the flavor's catalog.
    # A task type is treated as a backfill when its name matches
    # `/backfill/` (case-insensitive) OR its description contains the
    # substring "backfill" (case-insensitive). The detection rule is
    # intentionally simple so future flavors can declare a backfill
    # type by naming convention without changing the engine.
    def backfill_task_type_names(flavor)
      flavor.task_types.each_with_object([]) do |task_type, names|
        if task_type.name.match?(/backfill/i) ||
           task_type.description.to_s.match?(/backfill/i)
          names << task_type.name
        end
      end
    end

    # Build a `{ subject_type => [predecessor_type, ...] }` map from
    # the flavor's precedent rules. Used by `precedent_boundary?` to
    # decide when to split coalesced `:groups` runs at a precedent
    # boundary. Iterating `flavor.precedent_rules` preserves the
    # flavor-declared ordering for determinism.
    def precedent_subject_to_predecessors(flavor)
      result = Hash.new { |h, k| h[k] = [] }
      flavor.precedent_rules.each do |rule|
        result[rule.subject_type] << rule.predecessor_type
      end
      result
    end
  end
end
