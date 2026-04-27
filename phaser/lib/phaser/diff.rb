# frozen_string_literal: true

module Phaser
  # A single commit's parsed diff.
  #
  # Diff is the container of FileChange entries the phaser engine
  # consumes (data-model.md "Diff"). It is intentionally minimal — the
  # only behaviour beyond field access is the `empty?` predicate that
  # the FR-009 empty-diff filter relies on before classification (per
  # quickstart.md "Pattern: Pre-Classification Gate Discipline").
  #
  # Attributes:
  #
  #   * files — list of Phaser::FileChange entries; an empty list means
  #             the commit had no file-level changes (merge commits with
  #             no conflict resolution, tag-only commits, or commits
  #             created with `git commit --allow-empty`).
  #
  # Implemented with `Data.define` (Ruby 3.2+) for immutability and
  # value-equality semantics. The `empty?` predicate is added via the
  # `Data.define` block so it lives on the value class itself rather
  # than requiring callers to reach into the `files` collection.
  Diff = Data.define(:files) do
    # FR-009: an empty diff (`files == []`) means the commit is skipped
    # before classification and does not count toward the FR-048 size
    # bound. The engine consults this predicate exactly once per
    # commit, immediately after diff parsing.
    def empty?
      files.empty?
    end
  end
end
