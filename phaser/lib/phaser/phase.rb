# frozen_string_literal: true

module Phaser
  # An ordered group of one or more classified Tasks plus the stacked-PR
  # branch metadata that the stacked-PR creator and the per-phase marge
  # consume (FR-026; data-model.md "Phase").
  #
  # Phase is one of the four manifest-side value objects (alongside
  # ClassificationResult, Task, and PhaseManifest) that the engine
  # produces and the manifest writer serializes.
  #
  # Attributes:
  #
  #   * number        — 1-indexed position of this phase inside the
  #                     manifest.
  #   * name          — human-readable phase name (sentence-case for
  #                     readability), e.g.,
  #                     `Schema: add nullable email_address column`.
  #   * branch_name   — stacked-PR branch name following the pattern
  #                     `<feature>-phase-<N>` (FR-026).
  #   * base_branch   — branch this phase is based on; either the
  #                     project's default integration branch (phase 1)
  #                     or the previous phase's `branch_name` (phases
  #                     2..N) (FR-026).
  #   * tasks         — ordered list of Phaser::Task entries belonging
  #                     to this phase.
  #   * ci_gates      — list of CI gate names applicable to this phase,
  #                     copied from the active flavor's catalog.
  #   * rollback_note — operator-facing rollback guidance derived from
  #                     the assigned task types in this phase.
  #
  # Implemented with `Data.define` (Ruby 3.2+) for immutability and
  # value-equality semantics. Every attribute is required; the
  # base_branch / branch_name relationship between adjacent phases is
  # enforced at the manifest writer / schema boundary, not at value
  # object construction time.
  Phase = Data.define(
    :number,
    :name,
    :branch_name,
    :base_branch,
    :tasks,
    :ci_gates,
    :rollback_note
  )
end
