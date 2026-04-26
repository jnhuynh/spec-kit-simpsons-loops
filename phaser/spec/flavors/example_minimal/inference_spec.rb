# frozen_string_literal: true

require 'phaser'
require File.expand_path('../../../flavors/example-minimal/inference', __dir__)

# Specs for the example-minimal flavor's inference module at
# `phaser/flavors/example-minimal/inference.rb` (feature
# 007-multi-phase-pipeline; T038).
#
# `example-minimal` is the toy flavor that proves the engine is truly
# flavor-agnostic. Alongside `flavor.yaml` (T037), the flavor ships a
# small Ruby inference module to demonstrate the canonical anatomy of a
# flavor's pattern-matcher methods (per plan.md project structure and
# research.md R-003: "pattern-matcher methods sit in small Ruby modules
# that the YAML references by name").
#
# The example-minimal inference module exposes a single predicate —
# `schema_by_path?(commit)` — that returns true when any file in the
# commit's diff lives under `db/migrate/`. This is the Ruby twin of the
# `schema-by-path` `file_glob` rule declared in `flavor.yaml`; the YAML
# rule is what the engine's classifier evaluates today, but the Ruby
# module exists so future flavors that need richer matching (e.g.,
# AST-aware checks too expressive for a glob) have a documented
# reference for the module-method shape.
#
# This spec pins the module's externally observable contract:
#
#   1. The module is loadable (its file lives at the canonical path the
#      flavor's project structure demands).
#   2. The module is namespaced under `Phaser::Flavors::ExampleMinimal`
#      so it cannot collide with any other shipped flavor's modules.
#   3. `schema_by_path?` is a `module_function` that takes a single
#      `commit` argument so it can be invoked directly off the module
#      (the `module_method` match-kind contract — see
#      `Phaser::ForbiddenOperationsGate#module_method_match?`).
#   4. The predicate returns true when ANY file in the diff sits under
#      `db/migrate/`, false otherwise (matches the Ruby twin of the
#      `db/migrate/*.rb` glob).
#   5. The predicate has no side effects and inspects the commit only
#      via its public `Phaser::Commit` / `Phaser::Diff` /
#      `Phaser::FileChange` value-object surface.
RSpec.describe 'Phaser::Flavors::ExampleMinimal::Inference' do
  let(:module_under_test) { Phaser::Flavors::ExampleMinimal::Inference }

  # Build a `Phaser::Commit` with a single file at `path`. Inference
  # rules consult only the diff's file paths for this flavor, so the
  # other commit fields can carry inert defaults.
  def build_commit_with_path(path)
    Phaser::Commit.new(
      hash: 'a' * 40,
      subject: 'fixture commit',
      message_trailers: {},
      diff: Phaser::Diff.new(
        files: [
          Phaser::FileChange.new(path: path, change_kind: :added, hunks: [])
        ]
      ),
      author_timestamp: '2026-04-25T12:00:00Z'
    )
  end

  # Build a commit whose diff touches multiple files. Used to assert
  # the predicate returns true as long as ANY file matches the
  # migration path (mirrors File.fnmatch?'s "any?" semantics in the
  # classifier's `file_glob_match?`).
  def build_commit_with_paths(*paths)
    Phaser::Commit.new(
      hash: 'b' * 40,
      subject: 'fixture commit',
      message_trailers: {},
      diff: Phaser::Diff.new(
        files: paths.map do |path|
          Phaser::FileChange.new(path: path, change_kind: :added, hunks: [])
        end
      ),
      author_timestamp: '2026-04-25T12:00:00Z'
    )
  end

  it 'is namespaced under Phaser::Flavors::ExampleMinimal' do
    expect(module_under_test).to be_a(Module)
    expect(module_under_test.name).to eq('Phaser::Flavors::ExampleMinimal::Inference')
  end

  it 'exposes schema_by_path? as a module function callable off the module' do
    expect(module_under_test).to respond_to(:schema_by_path?)
  end

  it 'returns true when the commit touches a file under db/migrate/' do
    commit = build_commit_with_path('db/migrate/202604250001_add_email.rb')

    expect(module_under_test.schema_by_path?(commit)).to be(true)
  end

  it 'returns true when only one of several files is under db/migrate/' do
    commit = build_commit_with_paths(
      'app/models/user.rb',
      'db/migrate/202604250002_add_index.rb',
      'README.md'
    )

    expect(module_under_test.schema_by_path?(commit)).to be(true)
  end

  it 'returns false when no file in the diff is under db/migrate/' do
    commit = build_commit_with_path('app/models/user.rb')

    expect(module_under_test.schema_by_path?(commit)).to be(false)
  end

  it 'returns false for an empty diff (the empty-diff filter would skip this commit anyway)' do
    commit = Phaser::Commit.new(
      hash: 'c' * 40,
      subject: 'empty fixture commit',
      message_trailers: {},
      diff: Phaser::Diff.new(files: []),
      author_timestamp: '2026-04-25T12:00:00Z'
    )

    expect(module_under_test.schema_by_path?(commit)).to be(false)
  end

  it 'returns false when a file path merely contains the substring db/migrate but is not under it' do
    # The predicate matches ONLY paths under the `db/migrate/` directory
    # so a top-level file whose name happens to include the substring
    # (e.g., `db_migrate_notes.md`) is correctly excluded.
    commit = build_commit_with_path('db_migrate_notes.md')

    expect(module_under_test.schema_by_path?(commit)).to be(false)
  end
end
