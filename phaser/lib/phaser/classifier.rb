# frozen_string_literal: true

module Phaser
  # Common ancestor for every classification-time error so engine
  # callers can rescue the entire family with a single `rescue
  # Phaser::ClassificationError` clause and forward the payload to the
  # `validation-failed` ERROR record (FR-041) and the
  # `phase-creation-status.yaml` writer (FR-042).
  class ClassificationError < StandardError; end

  # Raised when a commit's `Phase-Type:` trailer (FR-016) names a task
  # type that is not declared by the active flavor (FR-007;
  # data-model.md "Error Conditions" row 1).
  #
  # Carries the unknown tag, the offending commit's full hash, and the
  # canonical `failing_rule = "unknown-type-tag"` value so the engine
  # can emit a structured ERROR record without re-deriving any of the
  # payload fields.
  class UnknownTypeTagError < ClassificationError
    attr_reader :unknown_tag, :commit_hash, :failing_rule

    def initialize(unknown_tag:, commit_hash:, valid_tags:)
      @unknown_tag = unknown_tag
      @commit_hash = commit_hash
      @failing_rule = 'unknown-type-tag'
      super(
        "Phase-Type trailer on commit #{commit_hash} names unknown task type " \
        "#{unknown_tag.inspect}. Valid task types declared by this flavor: " \
        "#{valid_tags.join(', ')}."
      )
    end
  end

  # Pure-function classifier that assigns one task type to a single
  # non-empty commit per the operator-tag → inference → default cascade
  # (FR-004; feature 007-multi-phase-pipeline; T030).
  #
  # The classifier is the second stage of the engine's per-commit
  # pipeline (after the empty-diff filter (FR-009) and the
  # forbidden-operations gate (FR-049) — see quickstart.md "Pattern:
  # Pre-Classification Gate Discipline"). It is deliberately stateless
  # so two operators running the same flavor over the same commits
  # produce byte-identical manifests (FR-002, SC-002).
  #
  # Cascade contract per FR-004:
  #
  #   1. If the commit's `Phase-Type:` trailer (FR-016) names a task
  #      type that exists in the active flavor's catalog, that type
  #      wins and `source = :operator_tag`. If the trailer names a tag
  #      that is NOT in the catalog, `Phaser::UnknownTypeTagError` is
  #      raised (FR-007) before any inference work is done.
  #
  #   2. Otherwise, every inference rule is evaluated against the
  #      commit's diff. Among matching rules, the highest-`precedence`
  #      rule wins (FR-036); ties on `precedence` are broken
  #      alphabetically by rule `name` so ordering is deterministic.
  #      `source = :inference` and `rule_name` is set to the winning
  #      rule's name.
  #
  #   3. Otherwise, the flavor's `default_type` is assigned and
  #      `source = :default`.
  #
  # The classifier never inspects the diff for forbidden operations —
  # that is the FR-049 pre-classification gate's job
  # (`Phaser::ForbiddenOperationsGate`, T031). The classifier is ONLY
  # responsible for the cascade defined above.
  class Classifier
    OPERATOR_TAG_TRAILER = 'Phase-Type'

    def classify(commit, flavor)
      tag = commit.message_trailers[OPERATOR_TAG_TRAILER]
      return classify_by_operator_tag(commit, flavor, tag) if tag && !tag.empty?

      winning_rule = highest_precedence_match(commit, flavor.inference_rules)
      return classify_by_inference(commit, flavor, winning_rule) if winning_rule

      classify_by_default(commit, flavor)
    end

    private

    def classify_by_operator_tag(commit, flavor, tag)
      task_type = find_task_type(flavor, tag)
      raise unknown_type_tag(commit, flavor, tag) unless task_type

      build_result(
        commit: commit,
        task_type: task_type,
        source: :operator_tag,
        rule_name: nil
      )
    end

    def classify_by_inference(commit, flavor, rule)
      task_type = find_task_type(flavor, rule.task_type)
      build_result(
        commit: commit,
        task_type: task_type,
        source: :inference,
        rule_name: rule.name
      )
    end

    def classify_by_default(commit, flavor)
      task_type = find_task_type(flavor, flavor.default_type)
      build_result(
        commit: commit,
        task_type: task_type,
        source: :default,
        rule_name: nil
      )
    end

    def build_result(commit:, task_type:, source:, rule_name:)
      ClassificationResult.new(
        commit_hash: commit.hash,
        task_type: task_type.name,
        source: source,
        isolation: task_type.isolation,
        rule_name: rule_name
      )
    end

    def find_task_type(flavor, name)
      flavor.task_types.find { |task_type| task_type.name == name }
    end

    def unknown_type_tag(commit, flavor, tag)
      UnknownTypeTagError.new(
        unknown_tag: tag,
        commit_hash: commit.hash,
        valid_tags: flavor.task_types.map(&:name)
      )
    end

    # Among every inference rule that matches the commit's diff, return
    # the rule with the highest `precedence`. Ties on `precedence` are
    # broken alphabetically by `name` so the cascade is deterministic
    # across runs (FR-036, SC-002). Returns nil when no rule matches.
    def highest_precedence_match(commit, inference_rules)
      matching = inference_rules.select { |rule| rule_matches?(rule, commit) }
      return nil if matching.empty?

      matching.min_by { |rule| [-rule.precedence, rule.name] }
    end

    def rule_matches?(rule, commit)
      case rule.match['kind']
      when 'file_glob'    then file_glob_match?(rule.match, commit)
      when 'path_regex'   then path_regex_match?(rule.match, commit)
      when 'content_regex' then content_regex_match?(rule.match, commit)
      else
        # Unknown match kinds (e.g., module_method) are not handled by
        # the classifier directly; the flavor loader is responsible for
        # rejecting unsupported shapes. Fail closed if one slips
        # through so the determinism contract is not silently violated.
        false
      end
    end

    def file_glob_match?(match, commit)
      pattern = match['pattern']
      commit.diff.files.any? { |file| File.fnmatch?(pattern, file.path, File::FNM_PATHNAME) }
    end

    def path_regex_match?(match, commit)
      regex = Regexp.new(match['pattern'])
      commit.diff.files.any? { |file| regex.match?(file.path) }
    end

    def content_regex_match?(match, commit)
      path_glob = match['path_glob']
      regex = Regexp.new(match['pattern'])
      commit.diff.files.any? do |file|
        next false unless File.fnmatch?(path_glob, file.path, File::FNM_PATHNAME)

        file.hunks.any? { |hunk| regex.match?(hunk) }
      end
    end
  end
end
