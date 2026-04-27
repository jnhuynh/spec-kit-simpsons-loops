# frozen_string_literal: true

module Phaser
  # A single file's change inside a commit's diff.
  #
  # FileChange is one of the three commit-side value objects that the
  # phaser engine consumes (see also Phaser::Commit and Phaser::Diff).
  # It is the unit of granularity inference rules and forbidden-operation
  # detectors operate on (data-model.md "FileChange").
  #
  # Attributes:
  #
  #   * path        — repository-relative path of the changed file.
  #   * change_kind — one of :added, :modified, :deleted, :renamed
  #                   (data-model.md "FileChange" enum).
  #   * hunks       — list of raw hunk strings preserved verbatim so
  #                   content-regex and module-method matchers can
  #                   inspect them without re-parsing the diff.
  #
  # Implemented with `Data.define` (Ruby 3.2+) so instances are
  # immutable and support value-equality semantics out of the box; this
  # lets the engine pass FileChange entries between pipeline stages
  # without defensive copies (plan.md "Project Structure").
  FileChange = Data.define(:path, :change_kind, :hunks)
end
