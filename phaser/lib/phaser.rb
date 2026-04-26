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

# Forbidden-operations gate (T031 — pre-classification gate per FR-049
# / D-016; rejects any commit whose diff matches an entry in the
# active flavor's forbidden-operations registry; runs BEFORE the
# classifier with no operator-supplied bypass surface; SC-005, SC-008,
# SC-015).
require 'phaser/forbidden_operations_gate'

# Precedent validator (T032 — enforces a flavor's precedent rules over
# the post-classification commit list per FR-006 / FR-041 / FR-042;
# raises Phaser::PrecedentError when a subject commit has no earlier
# predecessor commit in the input list; runs after the classifier and
# before the size guard / isolation resolver / manifest writer).
require 'phaser/precedent_validator'

# Isolation resolver (T033 — partitions the post-precedent-validation
# classification result list into ordered phases per FR-005 / FR-006 /
# FR-037; honors `:alone`/`:groups` isolation, splits coalesced runs at
# precedent boundaries, and keeps backfill tasks sequential by default
# unless the flavor opts into parallel backfills).
require 'phaser/isolation_resolver'

# Size guard (T034 — enforces FR-048's two hard bounds on feature size:
# more than 200 non-empty commits or a worst-case projected phase count
# above 50 raises `Phaser::SizeBoundError` BEFORE any manifest is
# written; runs after the precedent validator and before the isolation
# resolver / manifest writer; SC-014).
require 'phaser/size_guard'

# Engine (T035 — orchestration shell that wires the empty-diff filter
# (FR-009), the forbidden-operations gate (FR-049), the classifier
# (FR-004), the precedent validator (FR-006), the size guard (FR-048),
# and the isolation resolver (FR-005) into a single deterministic
# pipeline that produces a `Phaser::PhaseManifest` and writes it to
# disk via `Phaser::ManifestWriter`; on validation failure persists
# the payload via `Phaser::StatusWriter` and re-raises so the CLI
# (T036) can map the exception to a non-zero exit code per
# `contracts/phaser-cli.md`).
require 'phaser/engine'
