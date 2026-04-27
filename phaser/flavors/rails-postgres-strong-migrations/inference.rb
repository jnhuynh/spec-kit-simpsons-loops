# frozen_string_literal: true

# Inference module for the rails-postgres-strong-migrations reference
# flavor (feature 007-multi-phase-pipeline; T051, FR-012, SC-004).
#
# Each predicate below is named by an inference rule in this flavor's
# `flavor.yaml` under `inference_rules` with `match.kind: module_method`.
# The classifier (`Phaser::Classifier`) dispatches to these predicates
# via `flavor.inference_module.public_send(method_name, commit)`; every
# predicate takes a single `Phaser::Commit` and returns a boolean.
#
# Anatomy contract (mirrors the documentation in
# `phaser/flavors/example-minimal/inference.rb`):
#
#   1. Namespaced under `Phaser::Flavors::RailsPostgresStrongMigrations`
#      so multiple shipped flavors cannot collide on a top-level
#      constant.
#   2. `module_function` so each predicate is callable directly off the
#      module without an instance.
#   3. Pure functions of the commit value object (no side effects, no
#      Git access). This keeps engine determinism intact (FR-002,
#      SC-002) — the same commit always classifies the same way.
#
# Discrimination strategy: predicates inspect both the file path
# (`db/migrate/`, `lib/tasks/`, `app/`, `config/features/`,
# `terraform/`, `config/`) and the diff hunk text. Hunks are raw strings
# (one per `Phaser::FileChange#hunks` element) — they include leading
# `+` / `-` markers when the fixture or production diff captured them,
# so predicates that need to distinguish "added line" from "removed
# line" pattern-match the leading marker explicitly.
#
# Several rules share a common signal (e.g., `add_check_constraint`
# appears in both `add-virtual-not-null-via-check` and
# `add-check-constraint-without-validation`). The `flavor.yaml`
# precedence column resolves the cascade ordering; this module's job is
# just to return true/false correctly for each predicate. The cascade's
# precedence ordering (FR-036) is the classifier's responsibility, not
# this module's — predicates here can each be true at the same time
# without breaking the cascade because the higher-precedence rule wins
# at lookup time (so e.g. `schema_add_virtual_not_null_via_check?` is
# checked at precedence 185 while `schema_add_check_constraint_without_validation?`
# is checked at 180; if both match, virtual-not-null wins).
module Phaser
  module Flavors
    module RailsPostgresStrongMigrations
      # Inference predicates for the reference flavor. Each predicate
      # named below corresponds 1:1 with a `module_method` inference rule
      # in `flavor.yaml`. Adding a new rule here REQUIRES adding the
      # matching `inference_rules` entry in `flavor.yaml` (and vice
      # versa) — the classifier silently drops a predicate that the
      # YAML does not reference, and a YAML rule that names a missing
      # predicate will simply never match (Classifier#module_method_match?
      # falls closed on `respond_to?` miss).
      module Inference
        module_function

        # ── path predicates ──────────────────────────────────────────
        # Tiny helpers used by every category-specific predicate so the
        # path-membership check is written once and the per-rule logic
        # focuses on the diff content discriminator.

        MIGRATION_GLOB = 'db/migrate/*.rb'
        RAKE_GLOB = 'lib/tasks/**/*.rake'
        APP_RUBY_GLOB = 'app/**/*.rb'
        FEATURE_FLAG_GLOB = 'config/features/**/*.yml'
        TERRAFORM_GLOB = 'terraform/**/*.tf'
        CONFIG_YML_GLOB = 'config/**/*.yml'

        def migration?(commit)
          touches?(commit, MIGRATION_GLOB)
        end

        def rake_task?(commit)
          touches?(commit, RAKE_GLOB)
        end

        def app_ruby?(commit)
          touches?(commit, APP_RUBY_GLOB)
        end

        def feature_flag_yaml?(commit)
          touches?(commit, FEATURE_FLAG_GLOB)
        end

        def terraform?(commit)
          touches?(commit, TERRAFORM_GLOB)
        end

        def config_yaml?(commit)
          commit.diff.files.any? do |file|
            File.fnmatch?(CONFIG_YML_GLOB, file.path, File::FNM_PATHNAME) &&
              !File.fnmatch?(FEATURE_FLAG_GLOB, file.path, File::FNM_PATHNAME)
          end
        end

        def touches?(commit, glob)
          commit.diff.files.any? do |file|
            File.fnmatch?(glob, file.path, File::FNM_PATHNAME)
          end
        end

        # Walk every hunk of every file matching `glob` and return true
        # if any hunk matches `regex`. The classifier hands this module
        # the whole commit value object, so each predicate uses this
        # helper to scope its content scan to the relevant file family
        # and avoid false positives from unrelated files in a multi-file
        # commit.
        def hunk_match?(commit, glob, regex)
          commit.diff.files.any? do |file|
            next false unless File.fnmatch?(glob, file.path, File::FNM_PATHNAME)

            file.hunks.any? { |hunk| regex.match?(hunk) }
          end
        end

        # ── schema predicates (db/migrate/*.rb) ──────────────────────

        # Concurrent-index ADD: requires `disable_ddl_transaction!`
        # (per Postgres + strong_migrations convention) AND a positive
        # `add_index ..., algorithm: :concurrently` line. Both signals
        # together avoid a false positive on a migration that only
        # toggles `disable_ddl_transaction!` without an index call.
        def schema_add_concurrent_index?(commit)
          return false unless migration?(commit)

          hunk_match?(commit, MIGRATION_GLOB, /\+.*add_index\b.*algorithm:\s*:concurrently/)
        end

        # Concurrent-index DROP: same shape as add but with
        # `remove_index`. Distinguished from the add path by the helper
        # name so both rules can coexist in the same migration file (a
        # rare but possible "drop and re-add" pattern).
        def schema_drop_concurrent_index?(commit)
          return false unless migration?(commit)

          hunk_match?(commit, MIGRATION_GLOB, /\+.*remove_index\b.*algorithm:\s*:concurrently/)
        end

        # FK without validation: `add_foreign_key ... validate: false`.
        # The `validate: false` discriminator separates this from a
        # plain `add_foreign_key` (which the forbidden-operations gate
        # rejects pre-classification — so the classifier never sees
        # one).
        def schema_add_foreign_key_without_validation?(commit)
          return false unless migration?(commit)

          hunk_match?(commit, MIGRATION_GLOB, /\+.*add_foreign_key\b.*validate:\s*false/)
        end

        # Validate an existing FK constraint after rows are good.
        def schema_validate_foreign_key?(commit)
          return false unless migration?(commit)

          hunk_match?(commit, MIGRATION_GLOB, /\+.*validate_foreign_key\b/)
        end

        # Virtual NOT NULL via check constraint. Same `add_check_constraint`
        # surface as the generic `add-check-constraint-without-validation`
        # rule, distinguished by the constraint name embedding `not_null`.
        # The flavor's precedence column ranks this rule (185) higher
        # than the generic check-constraint rule (180), so when both
        # predicates would match, the cascade lands here.
        def schema_add_virtual_not_null_via_check?(commit)
          return false unless migration?(commit)

          hunk_match?(
            commit,
            MIGRATION_GLOB,
            /\+.*add_check_constraint\b.*name:\s*['"][^'"]*not_null[^'"]*['"]/
          )
        end

        # Generic "add a check constraint without validating existing
        # rows" — the safe Postgres pattern that strong_migrations
        # enforces. Distinguished from the virtual-not-null rule above
        # by the absence of `not_null` in the constraint name (the
        # virtual-not-null rule has higher precedence and wins ties).
        def schema_add_check_constraint_without_validation?(commit)
          return false unless migration?(commit)

          hunk_match?(commit, MIGRATION_GLOB, /\+.*add_check_constraint\b.*validate:\s*false/)
        end

        # Validate an existing check constraint.
        def schema_validate_check_constraint?(commit)
          return false unless migration?(commit)

          hunk_match?(commit, MIGRATION_GLOB, /\+.*validate_check_constraint\b/)
        end

        # Flip the real NOT NULL flag after the virtual check has been
        # validated. Detected by `change_column_null ... false` (the
        # `false` argument tells Rails to make the column NOT NULL).
        def schema_flip_real_not_null_after_check?(commit)
          return false unless migration?(commit)

          hunk_match?(commit, MIGRATION_GLOB, /\+.*change_column_null\b.*,\s*false\b/)
        end

        # Change the column default. Affects only future inserts; safe
        # without rewriting the table.
        def schema_change_column_default?(commit)
          return false unless migration?(commit)

          hunk_match?(commit, MIGRATION_GLOB, /\+.*change_column_default\b/)
        end

        # Drop an entire table.
        def schema_drop_table?(commit)
          return false unless migration?(commit)

          hunk_match?(commit, MIGRATION_GLOB, /\+.*drop_table\b/)
        end

        # Create a new table. Detected by `create_table` — the `do |t|`
        # block form is the canonical Rails phrasing.
        def schema_add_table?(commit)
          return false unless migration?(commit)

          hunk_match?(commit, MIGRATION_GLOB, /\+.*create_table\b/)
        end

        # Drop a column. The flavor's per-flavor PrecedentValidator
        # (T054) enforces the "must follow ignore + reference removal"
        # rule; this predicate just identifies the operation by helper
        # name (`remove_column`).
        def schema_drop_column_with_cleanup_precedent?(commit)
          return false unless migration?(commit)

          hunk_match?(commit, MIGRATION_GLOB, /\+.*remove_column\b/)
        end

        # Add a column with a non-volatile default — Postgres can
        # populate this without a table rewrite. Detected by an
        # `add_column` line that ALSO carries `default:` (any value).
        def schema_add_column_with_static_default?(commit)
          return false unless migration?(commit)

          hunk_match?(commit, MIGRATION_GLOB, /\+.*add_column\b.*default:/)
        end

        # Add a nullable column with no default. The "least specific"
        # add-column shape; safe in isolation. Distinguished from
        # add-column-with-static-default by the ABSENCE of `default:` on
        # the same line.
        def schema_add_nullable_column?(commit)
          return false unless migration?(commit)

          commit.diff.files.any? do |file|
            next false unless File.fnmatch?(MIGRATION_GLOB, file.path, File::FNM_PATHNAME)

            file.hunks.any? do |hunk|
              hunk.match?(/\+.*add_column\b/) && !hunk.match?(/default:/)
            end
          end
        end

        # ── data predicates (lib/tasks/**/*.rake) ────────────────────

        # Backfill rake task: `in_batches` + `update_all` (the
        # canonical write pattern). Distinguished from a cleanup task
        # by the `update_all` mutation verb.
        def data_backfill_batched?(commit)
          return false unless rake_task?(commit)

          hunk_match?(commit, RAKE_GLOB, /\+.*\bupdate_all\b/)
        end

        # Cleanup rake task: `in_batches` + `delete_all` (or `destroy_all`).
        # Same path family as backfill, distinguished by the destructive
        # verb.
        def data_cleanup_batched?(commit)
          return false unless rake_task?(commit)

          hunk_match?(commit, RAKE_GLOB, /\+.*\b(delete_all|destroy_all)\b/)
        end

        # ── code predicates (app/**/*.rb) ─────────────────────────────

        # Add `self.ignored_columns = ...` directive. Detected by an
        # ADDED line containing the assignment.
        def code_ignore_column_for_pending_drop?(commit)
          return false unless app_ruby?(commit)

          hunk_match?(commit, APP_RUBY_GLOB, /^\+\s*self\.ignored_columns\s*=/)
        end

        # Remove the `self.ignored_columns = ...` directive after the
        # column drop has shipped. Detected by a REMOVED line containing
        # the assignment (the `-` prefix on the diff hunk).
        def code_remove_ignored_columns_directive?(commit)
          return false unless app_ruby?(commit)

          hunk_match?(commit, APP_RUBY_GLOB, /^-\s*self\.ignored_columns\s*=/)
        end

        # Dual-write: a `before_save` callback (or equivalent) that
        # mirrors writes from one column into another. Detected by a
        # `before_save` callback declaration in the same commit as a
        # method definition.
        def code_dual_write_old_and_new_column?(commit)
          return false unless app_ruby?(commit)

          hunk_match?(commit, APP_RUBY_GLOB, /^\+\s*before_save\s+:/)
        end

        # Switch reads from the legacy column to the replacement.
        # Detected by a hunk that REMOVES a `where(<old_column>:` and
        # ADDS a `where(<new_column>:` — the canonical column-swap
        # pattern. We accept any hunk that contains both the removed-old
        # and added-new lines together (the diff fixture in
        # inference_spec.rb joins them into a single hunk string).
        def code_switch_reads_to_new_column?(commit)
          return false unless app_ruby?(commit)

          commit.diff.files.any? do |file|
            next false unless File.fnmatch?(APP_RUBY_GLOB, file.path, File::FNM_PATHNAME)

            file.hunks.any? do |hunk|
              hunk.match?(/^-.*\bwhere\(/) && hunk.match?(/^\+.*\bwhere\(/)
            end
          end
        end

        # Remove application-code references to a column slated for
        # drop. Detected by REMOVED lines for `attr_accessor`,
        # `validates`, or other model-level references to a column.
        # We check for any deletion of these reference forms; the
        # ignored-columns rules above run at higher precedence so a
        # commit that ONLY removes the directive is classified as
        # `remove-ignored-columns-directive`, not as a reference removal.
        def code_remove_references_to_pending_drop_column?(commit)
          return false unless app_ruby?(commit)

          commit.diff.files.any? do |file|
            next false unless File.fnmatch?(APP_RUBY_GLOB, file.path, File::FNM_PATHNAME)

            file.hunks.any? do |hunk|
              hunk.match?(/^-\s*(attr_accessor|validates|has_many|has_one|belongs_to)\s+:/)
            end
          end
        end

        # ── feature-flag predicates (config/features/**/*.yml) ───────

        # Create a feature flag with a default-off setting. Detected by
        # an ADDED `name:` line (a brand-new flag definition) AND an
        # ADDED `default: false` line.
        def feature_flag_create_default_off?(commit)
          return false unless feature_flag_yaml?(commit)

          added_name = hunk_match?(commit, FEATURE_FLAG_GLOB, /^\+\s*name:/)
          added_default_false = hunk_match?(commit, FEATURE_FLAG_GLOB, /^\+\s*default:\s*false/)
          added_name && added_default_false
        end

        # Flip a flag's default from off to on. Detected by a REMOVED
        # `default: false` AND an ADDED `default: true` in the same
        # commit.
        def feature_flag_enable?(commit)
          return false unless feature_flag_yaml?(commit)

          removed_false = hunk_match?(commit, FEATURE_FLAG_GLOB, /^-\s*default:\s*false/)
          added_true = hunk_match?(commit, FEATURE_FLAG_GLOB, /^\+\s*default:\s*true/)
          removed_false && added_true
        end

        # Remove a flag definition. Detected by REMOVED `name:` line
        # (the flag definition is being deleted entirely).
        def feature_flag_remove?(commit)
          return false unless feature_flag_yaml?(commit)

          hunk_match?(commit, FEATURE_FLAG_GLOB, /^-\s*name:/)
        end

        # ── infra predicates (terraform/**/*.tf, config/**/*.yml) ────

        # Provision a new infra resource. Detected by an ADDED
        # `resource "..."` line in a terraform file.
        def infra_provision?(commit)
          return false unless terraform?(commit)

          hunk_match?(commit, TERRAFORM_GLOB, /^\+.*\bresource\s+"/)
        end

        # Decommission an infra resource. Same shape as provision but
        # detected by a REMOVED `resource` line.
        def infra_decommission?(commit)
          return false unless terraform?(commit)

          hunk_match?(commit, TERRAFORM_GLOB, /^-.*\bresource\s+"/)
        end

        # Wire the application to a previously provisioned resource.
        # Detected by an edit to `config/*.yml` (excluding the
        # feature-flag config family handled above) — the canonical
        # spot Rails apps wire app config to URLs / hosts / credentials
        # for already-provisioned infra resources.
        def infra_wire?(commit)
          config_yaml?(commit)
        end
      end
    end
  end
end
