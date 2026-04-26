# frozen_string_literal: true

# Pre-load the shipped reference flavor's standalone Ruby files so
# specs that instantiate flavor classes directly (e.g.,
# `Phaser::Flavors::RailsPostgresStrongMigrations::BackfillValidator.new`)
# resolve those constants without first invoking
# `Phaser::FlavorLoader#load` (feature 007-multi-phase-pipeline).
#
# Why this lives in spec/support rather than in `phaser/lib/phaser.rb`:
#
#   * The engine library MUST NOT name any concrete flavor — SC-003 /
#     FR-003 / R-006 / `engine_no_domain_leakage_spec.rb` enforce a
#     scan over `phaser/lib/phaser/` and `phaser/bin/` that fails on
#     any literal mention of the reference stack. Loading from
#     spec/support keeps the engine pristine.
#
#   * Production runtime loads these files via
#     `Phaser::FlavorLoader#load_companion_ruby_files` — the test seam
#     here mirrors that contract for specs that bypass the loader.
#
# The require list is intentionally narrow: the flavor's standalone
# Ruby files only. The flavor.yaml is not loaded here because tests
# that need the loaded `Phaser::Flavor` value object call
# `FlavorLoader.new.load('rails-postgres-strong-migrations')`
# explicitly.

# The shipped flavor's standalone Ruby files reference engine-side
# classes (`Phaser::ValidationError`, `Phaser::Flavor`, etc.). Ensure
# the engine is loaded before any of those files is required.
require 'phaser'

reference_flavor_root = File.expand_path(
  '../../flavors/rails-postgres-strong-migrations',
  __dir__
)

%w[
  inference.rb
  forbidden_operations.rb
  backfill_validator.rb
  precedent_validator.rb
  safety_assertion_validator.rb
].each do |file|
  path = File.join(reference_flavor_root, file)
  require path if File.file?(path)
end
