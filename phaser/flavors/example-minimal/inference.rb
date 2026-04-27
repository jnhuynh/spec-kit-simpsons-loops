# frozen_string_literal: true

# Inference module for the example-minimal flavor (feature
# 007-multi-phase-pipeline; T038).
#
# This module is the Ruby twin of the `schema-by-path` inference rule
# declared in `phaser/flavors/example-minimal/flavor.yaml`. The shipped
# YAML rule uses `kind: file_glob` and is what the engine's
# `Phaser::Classifier` evaluates today (the classifier handles
# `file_glob`, `path_regex`, and `content_regex` natively); this module
# exists as the reference implementation of a flavor's inference-module
# anatomy so future flavors that need richer matching — e.g.,
# AST-aware migration detection too expressive for a glob — have a
# documented shape to copy.
#
# Anatomy contract (matches the conventions used by the
# rails-postgres-strong-migrations reference flavor in T051 and the
# `module_method` match-kind contract enforced by
# `Phaser::ForbiddenOperationsGate#module_method_match?`):
#
#   1. The module is namespaced under `Phaser::Flavors::ExampleMinimal`
#      so multiple shipped flavors cannot collide on a top-level Ruby
#      constant.
#   2. The module declares `module_function` so each predicate is
#      callable directly off the module (e.g.,
#      `Phaser::Flavors::ExampleMinimal::Inference.schema_by_path?(commit)`).
#      The flavor loader and forbidden-operations gate dispatch via
#      `module.public_send(method, commit)`, which requires this shape.
#   3. Each predicate takes a single `commit` argument (a
#      `Phaser::Commit`) and returns a boolean. The predicate inspects
#      the commit only via its public value-object surface
#      (`Phaser::Commit`, `Phaser::Diff`, `Phaser::FileChange`) so it
#      stays a pure function and remains testable in isolation without
#      mocking Git.
#   4. The predicate has no side effects: it reads from the commit and
#      returns a boolean. This keeps engine determinism intact (FR-002,
#      SC-002) — the same commit always classifies the same way.
#
# Why a Ruby module for a flavor that doesn't strictly need one: the
# example-minimal flavor's job is to be the no-domain-leakage
# regression contract (FR-003, SC-003). A flavor that ships ONLY a
# YAML catalog leaves the Ruby-module surface untested by the toy
# flavor. By shipping a module here — even one whose single predicate
# is the Ruby twin of an existing `file_glob` rule — the project
# structure documented in plan.md
# (`phaser/flavors/example-minimal/{flavor.yaml,inference.rb}`) and
# research.md R-003 is satisfied, and the rails-postgres-strong-
# migrations reference flavor (T051) has a concrete model to follow.
module Phaser
  module Flavors
    module ExampleMinimal
      # Inference predicates for the example-minimal flavor.
      #
      # Currently ships a single predicate, `schema_by_path?`, which
      # mirrors the shipped `schema-by-path` `file_glob` rule in
      # `flavor.yaml`. Both classify a commit as `schema` when the
      # diff touches any file under `db/migrate/` — the YAML rule is
      # the authoritative path the engine takes today; the Ruby
      # predicate is a documentation-equivalent reference operators
      # can read alongside the YAML to understand the rule's intent.
      module Inference
        module_function

        # Return true when any file in `commit.diff.files` lives under
        # the repository's `db/migrate/` directory. This is the
        # canonical signal of a schema migration in a Rails-style
        # codebase, which is the same signal the YAML rule's
        # `db/migrate/*.rb` glob captures.
        #
        # The predicate uses `File.fnmatch?` with `FNM_PATHNAME` so a
        # top-level file whose name happens to include the substring
        # `db/migrate` (e.g., `db_migrate_notes.md`) is correctly
        # excluded — only files whose path component literally starts
        # with `db/migrate/` match. This mirrors the semantics of the
        # classifier's own `file_glob_match?` so the Ruby twin and the
        # YAML rule agree on every commit.
        def schema_by_path?(commit)
          commit.diff.files.any? do |file|
            File.fnmatch?('db/migrate/*', file.path, File::FNM_PATHNAME)
          end
        end
      end
    end
  end
end
