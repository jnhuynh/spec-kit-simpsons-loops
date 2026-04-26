# frozen_string_literal: true

module Phaser
  # The verdict of running a single Commit through the operator-tag →
  # inference → default classification cascade (FR-004; data-model.md
  # "ClassificationResult").
  #
  # ClassificationResult is one of the four manifest-side value objects
  # (alongside Phase, Task, and PhaseManifest) that the phaser engine
  # produces and the manifest writer consumes.
  #
  # Attributes:
  #
  #   * commit_hash           — full 40-char Git SHA of the source commit.
  #   * task_type             — name of the task type assigned to the
  #                             commit (must match an entry in the
  #                             active flavor's task-type catalog).
  #   * source                — which classification path won; one of
  #                             :operator_tag, :inference, :default
  #                             (FR-004).
  #   * isolation             — copied from the assigned task type; one
  #                             of :alone, :groups (data-model.md
  #                             "TaskType").
  #   * rule_name             — optional; set when `source = :inference`
  #                             to the name of the winning inference
  #                             rule. Nil otherwise.
  #   * precedents_consulted  — optional; list of precedent rule names
  #                             that were checked for this commit. Nil
  #                             when no precedents were consulted.
  #   * safety_assertion_precedents — optional; list of precedent commit
  #                             SHAs cited in the source commit's
  #                             safety-assertion block (FR-018, plan.md
  #                             D-017). Set by the reference flavor's
  #                             SafetyAssertionValidator (T054b) when
  #                             the commit's task type is declared
  #                             irreversible by the active flavor; nil
  #                             otherwise. Forwarded by the engine into
  #                             the corresponding `Phaser::Task#new`
  #                             call so the audit trail reaches the
  #                             manifest.
  #
  # Implemented with `Data.define` (Ruby 3.2+) for immutability,
  # value-equality, and a strict keyword constructor that raises
  # ArgumentError when a required attribute is missing. Optional
  # attributes default to nil so callers do not have to remember which
  # attributes are required and which are optional.
  ClassificationResult = Data.define(
    :commit_hash,
    :task_type,
    :source,
    :isolation,
    :rule_name,
    :precedents_consulted,
    :safety_assertion_precedents
  ) do
    # Override the synthesized initializer to give the optional
    # attributes nil defaults. Data.define alone treats every member as
    # required; the spec asserts the optional fields default to nil
    # when omitted.
    def initialize(commit_hash:, task_type:, source:, isolation:,
                   rule_name: nil, precedents_consulted: nil,
                   safety_assertion_precedents: nil)
      super
    end
  end
end
