# frozen_string_literal: true

module Phaser
  # Raised by the engine (NOT by the validator itself; the validator is a
  # pure decision function) when `Phaser::PrecedentValidator#validate`
  # encounters a classified commit whose `task_type` is the subject of a
  # flavor `PrecedentRule` but no earlier commit in the input list has
  # the rule's `predecessor_type`.
  #
  # Carries the offending commit hash, the violating rule's `name`
  # (canonical `failing_rule` for the validation-failed ERROR record per
  # FR-041), and the rule's `predecessor_type` (canonical
  # `missing_precedent` for the same record and for
  # `phase-creation-status.yaml` per FR-042). Descends from
  # `Phaser::ValidationError` so the engine's outer rescue clause handles
  # it uniformly with the other validation failure modes
  # (forbidden-operation, backfill-safety, feature-too-large,
  # unknown-type-tag, safety-assertion-missing).
  class PrecedentError < ValidationError
    attr_reader :commit_hash, :failing_rule, :missing_precedent

    def initialize(classification_result:, rule:)
      @commit_hash = classification_result.commit_hash
      @failing_rule = rule.name
      @missing_precedent = rule.predecessor_type
      super(
        "Commit #{@commit_hash} violates precedent rule " \
        "#{@failing_rule.inspect}: missing predecessor of type " \
        "#{@missing_precedent.inspect}"
      )
    end

    # The three-field Hash the engine hands to
    # `Observability#log_validation_failed` and `StatusWriter#write`. The
    # status writer adds the `stage:` discriminator and the observability
    # logger adds the envelope (`level`, `timestamp`, `event`); this
    # method intentionally returns ONLY the payload fields the precedent
    # rejection mode populates so other failure modes
    # (`feature-too-large` populates commit_count / phase_count;
    # forbidden-operation populates forbidden_operation /
    # decomposition_message) remain visually distinct in the
    # operator-facing record.
    def to_validation_failed_payload
      {
        commit_hash: @commit_hash,
        failing_rule: @failing_rule,
        missing_precedent: @missing_precedent
      }
    end
  end

  # Pure-function validator that enforces a flavor's precedent rules over
  # the post-classification commit list (feature 007-multi-phase-pipeline;
  # T032, FR-006, FR-041, FR-042, data-model.md "PrecedentRule" /
  # "ClassificationResult" / "Error Conditions" table row "Precedent
  # rule violated").
  #
  # Position in the engine pipeline per quickstart.md "Pattern:
  # Pre-Classification Gate Discipline" (T035 in tasks.md):
  #
  #   empty-diff filter (FR-009)
  #     -> forbidden-operations gate (FR-049)
  #     -> classifier (FR-004)
  #     -> PRECEDENT VALIDATOR (FR-006)            <-- this module
  #     -> size guard (FR-048)
  #     -> isolation resolver (FR-005)
  #     -> manifest writer (FR-002, FR-038)
  #
  # The validator runs over the FULL list of classified commits in
  # commit-emission order. For every flavor `PrecedentRule` it asserts
  # that each commit whose `task_type == rule.subject_type` is preceded
  # by at least one earlier commit (strictly earlier in the input list)
  # whose `task_type == rule.predecessor_type`. The "strictly later
  # phase" requirement of FR-006 is enforced jointly: the validator
  # guarantees the predecessor exists earlier in the commit sequence;
  # the IsolationResolver (T033) downstream guarantees the subject lands
  # in a strictly later phase. A precedent rule violation here halts the
  # engine BEFORE the size guard, isolation resolver, or manifest writer
  # is invoked, so no manifest is produced on failure (data-model.md
  # "Error Conditions" table — exit non-zero, no manifest).
  #
  # Bypass-surface contract (mirrors ForbiddenOperationsGate's D-016
  # stance): the validator is constructed with no arguments and exposes
  # only `#validate(classification_results, flavor)` so there is no
  # operator-supplied skip / force / allow / bypass / override surface.
  #
  # Determinism contract (FR-002, SC-002): rules are iterated in the
  # order declared by the flavor; commits in input order. The FIRST
  # violation reported is reproducible across runs. Two operators
  # running the same flavor against the same commits MUST see the same
  # offending commit reported, with the same `failing_rule` and
  # `missing_precedent` values.
  #
  # On success the validator returns a NEW list of `ClassificationResult`
  # value objects with `precedents_consulted` populated for every commit
  # whose type participates as a subject in at least one of the flavor's
  # precedent rules. The original results are unchanged
  # (`ClassificationResult` is `Data.define` and therefore immutable).
  class PrecedentValidator
    def validate(classification_results, flavor)
      rules = flavor.precedent_rules
      return classification_results.dup if rules.empty?

      enforce_rule_order!(classification_results, rules)
      enrich_with_precedents_consulted(classification_results, rules)
    end

    private

    # Raise on the FIRST violation in (rule order × commit order). The
    # outer loop iterates commits so the FIRST commit-in-input-order to
    # have an unmet rule is the one reported, even when multiple
    # subjects later in the list also lack predecessors. The inner loop
    # iterates rules in flavor-declared order so when a single subject
    # violates multiple rules the FIRST rule in declared order is the
    # one reported (per FR-002 / SC-002 determinism contract).
    def enforce_rule_order!(classification_results, rules)
      seen_types = Hash.new(0)

      classification_results.each do |result|
        rules.each do |rule|
          next unless rule.subject_type == result.task_type
          next if seen_types[rule.predecessor_type].positive?

          raise PrecedentError.new(classification_result: result, rule: rule)
        end
        seen_types[result.task_type] += 1
      end
    end

    # Build a NEW list of ClassificationResult instances, copying every
    # field verbatim and populating `precedents_consulted` on commits
    # whose type appears as a subject in one or more rules. Commits
    # whose type is not a subject of any rule are returned unchanged.
    # The original input list and its entries are untouched per the
    # immutability assertion in the spec.
    def enrich_with_precedents_consulted(classification_results, rules)
      subjects_to_rule_names = subjects_to_rule_names(rules)

      classification_results.map do |result|
        rule_names = subjects_to_rule_names[result.task_type]
        next result if rule_names.nil? || rule_names.empty?

        ClassificationResult.new(
          commit_hash: result.commit_hash,
          task_type: result.task_type,
          source: result.source,
          isolation: result.isolation,
          rule_name: result.rule_name,
          precedents_consulted: rule_names
        )
      end
    end

    # Returns { subject_type => [rule_name, ...] } preserving declared
    # rule order. Used to populate `precedents_consulted` so the
    # observability layer can attribute the consultation downstream
    # (SC-011, FR-041 commit-classified record's optional
    # `precedents_consulted` field).
    def subjects_to_rule_names(rules)
      result = Hash.new { |hash, key| hash[key] = [] }
      rules.each { |rule| result[rule.subject_type] << rule.name }
      result
    end
  end
end
