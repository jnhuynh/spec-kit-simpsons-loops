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

# Observability surface (T013 — JSON-line stderr logger used by the
# engine and the stacked-PR creator).
require 'phaser/observability'

# Manifest writer (T015 — stable-key-order YAML emitter that
# serializes a Phaser::PhaseManifest deterministically; FR-002, FR-038,
# SC-002).
require 'phaser/manifest_writer'

# Status writer (T017 — stable-key-order YAML emitter that persists
# `<FEATURE_DIR>/phase-creation-status.yaml` on engine or stacked-PR
# creator failure; FR-039, FR-040, FR-042, FR-046, FR-047, SC-013).
require 'phaser/status_writer'

# Flavor value object and schema-validated loader (T019 — single
# ingress for shipped flavor catalogs at phaser/flavors/<name>/flavor.yaml;
# data-model.md "Flavor", contracts/flavor.schema.yaml, plan.md
# "Pattern: Flavor Loader" / D-002). The validator lives in its own
# file so each surface (filesystem IO + value-object build vs. schema
# enforcement) stays small and testable in isolation.
require 'phaser/flavor'
require 'phaser/precedent_rule_graph'
require 'phaser/flavor_catalog_validator'
require 'phaser/flavor_loader'

# Classifier (T030 — operator-tag → inference → default cascade per
# FR-004 / FR-007 / FR-036; the second stage of the engine's per-commit
# pipeline after the empty-diff filter and forbidden-operations gate).
require 'phaser/classifier'
