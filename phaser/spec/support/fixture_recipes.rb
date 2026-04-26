# frozen_string_literal: true

# Auto-loader for the synthetic Git fixture recipes that live under
# `phaser/spec/fixtures/repos/<name>/recipe.rb` (feature
# 007-multi-phase-pipeline; T029 onwards).
#
# Why a dedicated loader instead of putting the recipes directly under
# `spec/support/`:
#
#   * The fixture data is logically part of the `phaser/spec/fixtures/`
#     tree (alongside classification fixtures and flavor fixtures), not
#     part of the test-helper surface in `spec/support/`. Moving the
#     recipes into `spec/support/` would lose that grouping and make it
#     harder for a maintainer scanning `spec/fixtures/repos/` to find
#     the canonical fixture definitions.
#
#   * Putting a single tiny loader under `spec/support/` (which is what
#     `spec_helper.rb` already auto-loads) lets us keep the recipes
#     where they belong while still making them requireable from any
#     spec without per-file `require_relative` chains.
#
# Discovery is deterministic: `Dir[]` returns sorted paths, which keeps
# load order stable across machines — important because determinism is
# a first-class property of this codebase (FR-002, SC-002).
recipe_glob = File.expand_path('../fixtures/repos/*/recipe.rb', __dir__)
# `Dir[]` already returns sorted results on Ruby 3.0+, so we rely on the
# default rather than calling `.sort` explicitly (rubocop
# `Lint/RedundantDirGlobSort`).
Dir[recipe_glob].each { |path| require path }
