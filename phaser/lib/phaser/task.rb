# frozen_string_literal: true

module Phaser
  # A single classified commit's representation inside a Phase entry of
  # the phase manifest (data-model.md "Task").
  #
  # Task is one of the four manifest-side value objects (alongside
  # ClassificationResult, Phase, and PhaseManifest) that the engine
  # produces and the manifest writer serializes.
  #
  # Attributes:
  #
  #   * id                          — stable identifier of the form
  #                                   `phase-<N>-task-<M>` for
  #                                   cross-referencing inside the
  #                                   manifest and in operator tooling.
  #   * task_type                   — the assigned task type name (must
  #                                   match an entry in the active
  #                                   flavor's catalog).
  #   * commit_hash                 — source commit SHA (40-char hex).
  #   * commit_subject              — mirror of the commit subject line
  #                                   for reviewer convenience inside
  #                                   the manifest.
  #   * safety_assertion_precedents — optional; list of precedent commit
  #                                   SHAs cited in the source commit's
  #                                   safety-assertion block (FR-018,
  #                                   plan.md D-017). Set by the
  #                                   reference flavor's
  #                                   SafetyAssertionValidator when the
  #                                   commit's task type is declared
  #                                   irreversible by the active
  #                                   flavor; nil otherwise.
  #
  # Implemented with `Data.define` (Ruby 3.2+) for immutability and
  # value-equality semantics. The single optional field defaults to nil
  # via an overridden keyword initializer.
  Task = Data.define(
    :id,
    :task_type,
    :commit_hash,
    :commit_subject,
    :safety_assertion_precedents
  ) do
    def initialize(id:, task_type:, commit_hash:, commit_subject:,
                   safety_assertion_precedents: nil)
      super
    end
  end
end
