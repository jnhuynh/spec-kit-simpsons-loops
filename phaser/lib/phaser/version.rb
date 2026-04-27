# frozen_string_literal: true

# Single source of truth for the Phaser library version.
#
# Defined in its own file (rather than inline in `phaser/lib/phaser.rb`)
# so that build tooling, gem-style introspection, and the eventual
# `phaser/bin/phaser --version` output can `require "phaser/version"`
# without pulling in the full engine and its transitive dependencies.
#
# The constant is updated by hand on each release. Bumping it here is the
# only edit required — the top-level `Phaser` module loader added in
# T020 simply requires this file.

module Phaser
  VERSION = '0.1.0'
end
