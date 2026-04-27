# frozen_string_literal: true

module Phaser
  # The artifact produced by the phaser engine and committed to the
  # feature branch as `<FEATURE_DIR>/phase-manifest.yaml` (FR-020,
  # FR-021, FR-035; data-model.md "PhaseManifest"). Full schema in
  # `contracts/phase-manifest.schema.yaml`.
  #
  # PhaseManifest is the top of the four manifest-side value objects
  # (alongside ClassificationResult, Phase, and Task) that the engine
  # produces and the manifest writer serializes deterministically.
  #
  # Attributes:
  #
  #   * flavor_name    — the active flavor's `name` (FR-021).
  #   * flavor_version — the active flavor's `version` (FR-021, FR-035);
  #                      pinned in the manifest so reviewers can see
  #                      which catalog version produced the phasing.
  #   * feature_branch — branch name the phaser ran against (FR-021).
  #   * generated_at   — ISO-8601 UTC string capturing the manifest
  #                      generation timestamp (FR-021).
  #   * phases         — ordered list of Phaser::Phase entries (FR-021).
  #
  # Implemented with `Data.define` (Ruby 3.2+) for immutability and
  # value-equality semantics. The `phases` collection is permitted to be
  # empty at the value-object boundary — the schema's `minItems: 1`
  # constraint and the phase-numbering invariants are enforced by the
  # manifest writer and JSON Schema validation, not here.
  PhaseManifest = Data.define(
    :flavor_name,
    :flavor_version,
    :feature_branch,
    :generated_at,
    :phases
  )
end
