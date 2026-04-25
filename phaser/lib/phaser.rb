# frozen_string_literal: true

# Top-level loader for the Phaser library (feature 007-multi-phase-pipeline).
#
# This file is the public entry point: `require "phaser"` from spec
# files, the `bin/phaser` CLI, and downstream tooling brings in the
# full set of foundational value objects, services, and writers the
# engine depends on.
#
# T020 in tasks.md is the dedicated task to enumerate every
# foundational require here. As individual foundational tasks land
# (T010, T011, T013, T015, T017, T019), this file is extended with the
# corresponding `require` statements so each spec — which always uses
# the canonical `require "phaser"` — sees the value objects and
# services it needs without per-spec load-path manipulation.

require 'phaser/version'

# Commit-side value objects (T010 — feeds the engine's input layer).
require 'phaser/file_change'
require 'phaser/diff'
require 'phaser/commit'

# Manifest-side value objects (T011 — feeds the engine's output layer).
require 'phaser/classification_result'
require 'phaser/task'
require 'phaser/phase'
require 'phaser/phase_manifest'
