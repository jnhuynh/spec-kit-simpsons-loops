# frozen_string_literal: true

# Forbidden-operations module for the rails-postgres-strong-migrations
# reference flavor (feature 007-multi-phase-pipeline; T052, FR-015,
# FR-049, SC-005, SC-008, SC-015, D-016).
#
# Each predicate below corresponds 1:1 with a `forbidden_operations`
# entry in this flavor's `flavor.yaml` whose `detector.kind` is
# `module_method`. The pre-classification gate
# (`Phaser::ForbiddenOperationsGate`) dispatches to these predicates via
# `flavor.forbidden_module.public_send(method_name, commit)`; every
# predicate takes a single `Phaser::Commit` and returns a boolean.
#
# Anatomy contract (mirrors the documentation in
# `phaser/flavors/rails-postgres-strong-migrations/inference.rb`):
#
#   1. Namespaced under `Phaser::Flavors::RailsPostgresStrongMigrations`
#      so multiple shipped flavors cannot collide on a top-level
#      constant.
#   2. `module_function` so each predicate is callable directly off the
#      module without an instance.
#   3. Pure functions of the commit value object (no side effects, no
#      Git access). This keeps engine determinism intact (FR-002,
#      SC-002) — the same commit always trips (or doesn't trip) the
#      same gate.
#   4. NO bypass surface. None of these predicates consult the commit
#      message trailers, environment variables, or any flag that could
#      be flipped to "skip the gate" — D-016 / SC-015 mandate the gate
#      have zero bypass surface, and that begins at the predicate.
#
# Position in the engine pipeline (per quickstart.md "Pattern:
# Pre-Classification Gate Discipline"):
#
#   empty-diff filter (FR-009)
#     -> forbidden-operations gate (FR-049)        <-- THIS module
#     -> classifier (FR-004)
#     -> precedent validator (FR-006)
#     -> reference-flavor validators (FR-013, FR-014, FR-018)
#     -> size guard (FR-048)
#     -> isolation resolver (FR-005)
#     -> manifest writer (FR-002, FR-038)
#
# Discrimination strategy: every predicate scopes its scan to
# `db/migrate/*.rb` (the only file family in which the seven shipped
# unsafe operations can occur). For the borderline case where a safe
# variant of an unsafe verb exists (e.g., `add_index` vs.
# `add_index ... algorithm: :concurrently`, or `add_foreign_key` vs.
# `add_foreign_key ... validate: false`, or `remove_column` with vs.
# without an accompanying `self.ignored_columns =` removal in
# app/**/*.rb), the predicate explicitly checks for the safe-variant
# signal and returns false when it is present so the safe path can flow
# through the classifier.
#
# Determinism + first-match-wins: the gate iterates the registry in
# declared order and returns the first match. The shipped catalog
# orders the seven entries from most-specific to least-specific so
# overlapping detectors land on the right identifier; the predicates
# below DO NOT need to re-encode that ordering.
module Phaser
  module Flavors
    module RailsPostgresStrongMigrations
      # Forbidden-operation detectors for the reference flavor. Each
      # predicate name below corresponds 1:1 with a `module_method`
      # detector entry in `flavor.yaml`'s `forbidden_operations` list.
      # Adding a new detector here REQUIRES adding the matching registry
      # entry in `flavor.yaml` (and vice versa) — the gate falls closed
      # on `respond_to?` miss with a
      # `ForbiddenOperationsConfigurationError` so a missing predicate
      # is never silent.
      module ForbiddenOperations
        module_function

        MIGRATION_GLOB = 'db/migrate/*.rb'
        APP_RUBY_GLOB = 'app/**/*.rb'

        # Walk every hunk of every file matching `glob` and return true
        # if any hunk matches `regex`. Pure helper; no side effects.
        def hunk_match?(commit, glob, regex)
          commit.diff.files.any? do |file|
            next false unless File.fnmatch?(glob, file.path, File::FNM_PATHNAME)

            file.hunks.any? { |hunk| regex.match?(hunk) }
          end
        end

        # True iff any file in the commit lives under `glob` and has any
        # hunk. Used to detect whether the commit carries a migration at
        # all before scoping content scans to that file family.
        def touches?(commit, glob)
          commit.diff.files.any? do |file|
            File.fnmatch?(glob, file.path, File::FNM_PATHNAME)
          end
        end

        # ── direct column-type change ────────────────────────────────
        # `change_column :users, :email, :text` rewrites the table and
        # locks writes for the duration. Distinguished from the safe
        # `change_column_default` and `change_column_null` verbs (which
        # are word-boundary-followed by `_default` / `_null` and so
        # match a separate token); the regex insists on `change_column`
        # followed by whitespace or `(` so the safe verbs do not trip
        # this detector.
        def direct_column_type_change?(commit)
          return false unless touches?(commit, MIGRATION_GLOB)

          hunk_match?(commit, MIGRATION_GLOB, /\+.*\bchange_column[\s(]/)
        end

        # ── direct column rename ─────────────────────────────────────
        # `rename_column :users, :email, :email_address` causes
        # in-flight writes to the old column name to fail during deploy
        # — there is no safe variant of `rename_column` in Postgres, so
        # the detector matches the verb unconditionally on added lines.
        def direct_column_rename?(commit)
          return false unless touches?(commit, MIGRATION_GLOB)

          hunk_match?(commit, MIGRATION_GLOB, /\+.*\brename_column\b/)
        end

        # ── non-concurrent index ─────────────────────────────────────
        # `add_index :users, :email` (or `remove_index ...`) without
        # `algorithm: :concurrently` acquires a long-held write lock
        # that blocks production traffic. Distinguished from the safe
        # variant by the absence of `algorithm: :concurrently` ON THE
        # SAME ADDED LINE — Rails migration style is to put the verb
        # and its keyword arguments on a single line, so per-line
        # discrimination is correct here.
        def non_concurrent_index?(commit)
          added_line_in_migration?(commit) do |line|
            line.match?(/\b(add_index|remove_index)\b/) &&
              !line.match?(/algorithm:\s*:concurrently/)
          end
        end

        # ── direct add NOT NULL column ───────────────────────────────
        # `add_column :users, :email, :string, null: false` rewrites
        # the table for every existing row. Distinguished from the safe
        # `add_column ... null: true` (or no `null:` option, which
        # defaults to nullable) by the explicit `null: false` keyword
        # argument on the same added line.
        def direct_add_not_null_column?(commit)
          added_line_in_migration?(commit) do |line|
            line.match?(/\badd_column\b/) && line.match?(/null:\s*false/)
          end
        end

        # ── direct add foreign key ───────────────────────────────────
        # `add_foreign_key :users, :orgs` without `validate: false`
        # validates every existing row under a write lock. Distinguished
        # from the safe `add_foreign_key ... validate: false` by the
        # absence of the `validate: false` keyword on the same added
        # line.
        def direct_add_foreign_key?(commit)
          added_line_in_migration?(commit) do |line|
            line.match?(/\badd_foreign_key\b/) && !line.match?(/validate:\s*false/)
          end
        end

        # Iterate every added (`+`-prefixed) line in every migration-
        # file hunk and yield it to the caller's predicate. Returns true
        # iff the predicate returns true for at least one such line.
        # Encapsulates the "scope to db/migrate/*.rb, walk added lines"
        # boilerplate that all three of the per-line discriminators
        # above (and `add_column_with_volatile_default?` below) need.
        def added_line_in_migration?(commit)
          return false unless touches?(commit, MIGRATION_GLOB)

          commit.diff.files.any? do |file|
            next false unless File.fnmatch?(MIGRATION_GLOB, file.path, File::FNM_PATHNAME)

            file.hunks.any? do |hunk|
              hunk.each_line.any? { |line| line.start_with?('+') && yield(line) }
            end
          end
        end

        # ── add column with volatile default ─────────────────────────
        # `add_column :users, :seen_at, :datetime, default: -> { 'now()' }`
        # (or any of the other Postgres time/random functions wrapped
        # in a lambda) rewrites every row at migration time. Detected
        # by an added `add_column` line whose `default:` argument names
        # one of the well-known volatile expressions (now, current_*,
        # statement_*, transaction_*, clock_*, random, gen_random_uuid,
        # uuid_generate_*). Static defaults (booleans, integers, fixed
        # strings) are intentionally NOT in this list so the safe
        # `schema add-column-with-static-default` path flows through.
        VOLATILE_DEFAULT_TOKENS = %w[
          now
          current_timestamp
          current_time
          current_date
          statement_timestamp
          transaction_timestamp
          clock_timestamp
          random
          gen_random_uuid
          uuid_generate_v1
          uuid_generate_v3
          uuid_generate_v4
          uuid_generate_v5
        ].freeze

        # Compose the volatile-token regex once at load time so the
        # per-commit scan is a constant-time match. Tokens are joined
        # with `|` and bounded by word characters so e.g. `nowadays` does
        # not falsely trip the `now` token.
        VOLATILE_DEFAULT_REGEX = /
          \badd_column\b.*default:\s*           # add_column ... default:
          (?:->\s*\{\s*)?                       # optional lambda wrapper
          ['"`]?                                # optional opening quote
          (?:#{VOLATILE_DEFAULT_TOKENS.join('|')}) # one of the volatile fns
          \s*\(                                 # function call open-paren
        /x

        def add_column_with_volatile_default?(commit)
          added_line_in_migration?(commit) { |line| VOLATILE_DEFAULT_REGEX.match?(line) }
        end

        # ── drop column without code cleanup ─────────────────────────
        # `remove_column :users, :legacy_email` causes runtime failures
        # on the next deploy when application code still references the
        # column. Distinguished from the SAFE drop (which carries the
        # cleanup precedent — the worked example's step 7 commit ALSO
        # removes the `self.ignored_columns =` directive from the model
        # file in the same commit) by the ABSENCE of any app/**/*.rb
        # change that removes a `self.ignored_columns =` line.
        #
        # Detection rule:
        #
        #   * The commit must add a `remove_column` call in a migration.
        #   * AND the commit must NOT have any app/**/*.rb hunk whose
        #     diff REMOVES (`-` prefix) a `self.ignored_columns =` line.
        #
        # When both conditions hold the drop is unsafe and the gate
        # rejects it. The seven-step column-rename worked example (R-016,
        # FR-017) trips the second clause and so flows through to the
        # classifier as `schema drop-column-with-cleanup-precedent`.
        def drop_column_without_code_cleanup?(commit)
          return false unless touches?(commit, MIGRATION_GLOB)
          return false unless adds_remove_column?(commit)

          !removes_ignored_columns_directive?(commit)
        end

        # True iff the commit has a migration hunk whose ADDED lines
        # call `remove_column`. Helper for `drop_column_without_code_cleanup?`.
        def adds_remove_column?(commit)
          hunk_match?(commit, MIGRATION_GLOB, /\+.*\bremove_column\b/)
        end

        # True iff the commit has any app/**/*.rb hunk whose REMOVED
        # lines drop a `self.ignored_columns =` directive — the
        # canonical "I cleaned up the model before dropping the column"
        # precedent the safe-drop pattern requires. Helper for
        # `drop_column_without_code_cleanup?`.
        def removes_ignored_columns_directive?(commit)
          hunk_match?(commit, APP_RUBY_GLOB, /^-\s*self\.ignored_columns\s*=/)
        end
      end
    end
  end
end
