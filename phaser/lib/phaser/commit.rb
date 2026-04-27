# frozen_string_literal: true

module Phaser
  # A single Git commit's representation as consumed by the phaser
  # engine.
  #
  # Commit is the third commit-side value object (alongside Diff and
  # FileChange) and is the unit the engine classifies, validates, and
  # groups into Phases (data-model.md "Commit").
  #
  # Attributes:
  #
  #   * hash             — full 40-char Git SHA.
  #   * subject          — commit subject line, surfaced in logs and
  #                        the manifest's Task entries.
  #   * message_trailers — map<string, string> of parsed trailer
  #                        lines (e.g., `"Phase-Type" => "schema
  #                        add-nullable-column"`); the operator-tag
  #                        classification path (FR-004) reads from this
  #                        map.
  #   * diff             — Phaser::Diff parsed from `git show`; the
  #                        engine consults `diff.empty?` for the
  #                        FR-009 empty-diff skip and feeds the diff
  #                        to inference rules and forbidden-operation
  #                        detectors.
  #   * author_timestamp — ISO-8601 UTC string used for tie-breaking
  #                        and observability (data-model.md "Commit").
  #
  # Implemented with `Data.define` (Ruby 3.2+) for immutability,
  # value-equality, and a friendly keyword constructor that raises
  # ArgumentError naming any missing attribute — relied on by the
  # spec to assert constructor strictness.
  #
  # NOTE on the `:hash` member: it shadows Object#hash on Commit
  # instances, but this is the documented field name in
  # data-model.md "Commit" (the 40-char Git SHA). The override is
  # intentional and benign — value equality still works because
  # Data.define synthesizes `eql?` / `hash` from the member values,
  # and equal commits have equal hash members. The rubocop warning
  # is suppressed inline to make the intent explicit.
  Commit = Data.define(
    :hash, # rubocop:disable Lint/DataDefineOverride
    :subject,
    :message_trailers,
    :diff,
    :author_timestamp
  )
end
