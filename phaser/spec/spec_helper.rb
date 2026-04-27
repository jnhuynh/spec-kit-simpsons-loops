# frozen_string_literal: true

# RSpec configuration for the Phaser engine and reference flavor
# (feature 007-multi-phase-pipeline).
#
# Responsibilities:
#
#   1. Make the production code under `phaser/lib/` requireable from any
#      spec file via `require "phaser"` (mirrors the convention used by
#      the rest of the Ruby ecosystem and removes per-file `$LOAD_PATH`
#      manipulation from individual specs).
#
#   2. Auto-load every helper under `phaser/spec/support/` so test
#      helpers (e.g., `git_fixture_helper.rb`) become available to all
#      specs without per-file `require_relative` chains.
#
#   3. Apply the standard RSpec defaults that the project's quality
#      gates rely on: random ordering with a deterministic seed, the
#      documentation formatter when run with `--format documentation`,
#      and the recommended expectations / mocks configuration that
#      matches RSpec 3.13 best practice and the rubocop-rspec defaults
#      pinned in `.rubocop.yml`.

# Place the production library on the load path so `require "phaser"`
# resolves the top-level loader at `phaser/lib/phaser.rb` (added in
# T020) and any submodule under `phaser/lib/phaser/`.
$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

# Autoload every support helper. `Dir[]` is sorted by default, which
# keeps load order deterministic across machines — important because
# determinism is a first-class property of this codebase (FR-002,
# SC-002).
Dir[File.expand_path('support/**/*.rb', __dir__)].each { |path| require path }

RSpec.configure do |config|
  # Use the recommended `expect` syntax exclusively. `should` is
  # deprecated and forbidden by rubocop-rspec defaults.
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
    expectations.syntax = :expect
  end

  # Verify partial doubles so a typo in a stubbed method name fails
  # loudly instead of silently passing — matches the spirit of the
  # project's "fail fast on configuration errors" stance.
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  # Share metadata across `shared_examples` definitions so each spec
  # file can use the standard RSpec idioms without bespoke wiring.
  config.shared_context_metadata_behavior = :apply_to_host_groups

  # Allow focusing on a single example with `fit`/`fdescribe` during
  # local development, but fall back to the full suite when no focus is
  # set. This is the default RSpec recommendation.
  config.filter_run_when_matching :focus

  # Persist example status so `--only-failures` works between runs.
  config.example_status_persistence_file_path = File.expand_path(
    '../tmp/rspec-status.txt',
    __dir__
  )

  # Randomize spec order each run, but record the seed so a flaky
  # ordering bug is reproducible. Determinism of the engine itself is
  # tested by SC-002's 100-run check (T014); this seed only governs the
  # order in which test files run.
  config.order = :random
  Kernel.srand config.seed

  # Make the test-fixture helpers available inside every example
  # without explicit `include` directives. The helpers live under
  # `phaser/spec/support/` and are loaded above.
  config.include GitFixtureHelper
end
