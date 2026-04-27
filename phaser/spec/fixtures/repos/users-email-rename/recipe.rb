# frozen_string_literal: true

# Synthetic Git fixture recipe for the rails-postgres-strong-migrations
# flavor's column-rename worked example (feature 007-multi-phase-pipeline;
# T048, FR-017, R-016, SC-001).
#
# The fixture is built at test time (not committed as a real Git repo
# under this directory) so commit hashes, author timestamps, and
# committer identity stay byte-stable across machines and CI hosts. The
# `GitFixtureHelper` (loaded by `spec_helper.rb`) pins the identity and
# clock; this recipe pins the commit content, file paths, and message
# trailers so every spec that consumes it sees the same seven-commit
# history.
#
# Why a recipe module instead of an on-disk Git repo:
#
#   * On-disk Git repositories carry per-commit author timestamps and
#     committer identities that vary per machine. Building the repo at
#     test time with the helper's fixed identity and frozen clock keeps
#     the resulting hashes reproducible (FR-002, SC-002 — the
#     column-rename example is the canonical end-to-end determinism
#     witness).
#
#   * The phaser engine reads commits via `git log` (T036), so the
#     fixture must be a real Git history at the moment the test runs.
#     The recipe builds a throwaway repo under `Dir.mktmpdir` (via the
#     helper) and returns its absolute location; the consuming spec
#     teardown (`cleanup_fixture_repos` from `GitFixtureHelper`) removes
#     it.
#
#   * Sharing the recipe across specs (the column-rename worked example
#     in `column_rename_worked_example_spec.rb`, the SC-001 end-to-end
#     pipeline test, and any future audit-trail check) means every
#     consumer sees an identical seven-commit history without per-spec
#     duplication.
#
# Recipe shape (matches R-016 in `research.md` and the per-type catalog
# pinned by `catalog_spec.rb`):
#
#   Step 1. Add `email_address` column as nullable, no default
#           — `db/migrate/202604250001_add_email_address.rb`. Inferred
#             as `schema add-nullable-column`.
#   Step 2. Add ignored-columns directive for `email`
#           — `app/models/user.rb` set `self.ignored_columns = [:email]`.
#             Inferred as `code ignore-column-for-pending-drop`.
#   Step 3. Dual-write to both `email` and `email_address`
#           — `app/models/user.rb` writes both columns on update.
#             Inferred as `code dual-write-old-and-new-column`.
#   Step 4. Backfill `email_address` from `email` (batched, throttled,
#           outside transaction)
#           — `lib/tasks/backfill_email_address.rake` uses `find_each`
#             with `sleep` throttling and `disable_ddl_transaction!`.
#             Inferred as `data backfill-batched`. Includes every
#             safeguard the backfill validator (T053, FR-013) requires.
#   Step 5. Switch reads to `email_address`
#           — `app/models/user.rb` reads from `email_address` instead of
#             `email`. Inferred as `code switch-reads-to-new-column`.
#   Step 6. Remove all references to `email`
#           — Drop every remaining read/write of the old column from
#             `app/models/user.rb` and supporting service files.
#             Inferred as `code remove-references-to-pending-drop-column`.
#   Step 7. Remove the ignored-columns directive AND drop the `email`
#           column
#           — A single migration that removes the directive and drops
#             the column in the same commit. Inferred as
#             `schema drop-column-with-cleanup-precedent`. Carries a
#             `Safety-Assertion:` trailer (FR-018, T054b) citing the
#             SHAs of step 2 (the ignored-columns precedent) and step 6
#             (the reference-removal precedent) so the safety-assertion
#             validator and the column-drop precedent validator (T054,
#             FR-014) both accept the commit.
#
# FR-017 demands "exactly seven ordered phases from this fixture
# without any operator intervention," so NO commit carries a
# `Phase-Type:` trailer — the seven phases must emerge from the
# inference layer alone (the `column_rename_worked_example_spec.rb`
# `'requires zero operator-supplied Phase-Type trailers'` example
# enforces this contract). The `Safety-Assertion:` trailer on step 7 is
# audit metadata, not a classification override; the safety-assertion
# validator reads it but the classifier does not.
#
# Ordering note: the seven steps must appear in this exact order. The
# precedent rules the reference flavor enforces (column-drop requires
# prior ignored-columns directive AND prior reference-removal per
# FR-014; safety-assertion precedents must be earlier on the branch per
# FR-018) make any other ordering an automatic rejection.
#
# Usage from a spec (the helper module is auto-loaded by spec_helper.rb;
# `make_fixture_repo` and `cleanup_fixture_repos` are mixed into every
# example group):
#
#   RSpec.describe "column-rename worked example" do
#     let(:repo_path) { UsersEmailRenameFixture.build(self) }
#     after { cleanup_fixture_repos }
#
#     it "produces a seven-phase manifest" do
#       # ... point the engine at repo_path ...
#     end
#   end
#
# `UsersEmailRenameFixture.build` takes the example-group instance (so
# it can call into `make_fixture_repo`) and returns the absolute path
# to the throwaway repo. The branch the engine consumes is
# `feature-users-email-rename`; the integration branch is `main`.
module UsersEmailRenameFixture
  # Branch name carrying the seven-commit feature history. Specs point
  # the engine / CLI at this branch via `git log`. Pinned as a constant
  # so consumers can reference it without hard-coding string literals
  # in multiple places (the worked-example spec reads
  # `UsersEmailRenameFixture::FEATURE_BRANCH` to build its
  # `Phaser::Engine` instance and to assert manifest branch names).
  FEATURE_BRANCH = 'feature-users-email-rename'

  # Integration branch the feature branch is based on. The phaser
  # engine treats this as the manifest's `base_branch` for phase 1 per
  # FR-026.
  DEFAULT_BRANCH = 'main'

  # Build the fixture repo and return its absolute path. The caller
  # must invoke `cleanup_fixture_repos` in an `after` block (or rely on
  # the suite-wide `after(:suite)` sweep) so the temporary directory is
  # removed.
  #
  # `host` is the RSpec example-group instance; the recipe needs it so
  # it can call into the `GitFixtureHelper` mixin (which is included
  # into every example group by `spec_helper.rb`).
  def self.build(host)
    host.make_fixture_repo('users-email-rename') do |repo|
      seed_main_branch(repo)
      repo.checkout(FEATURE_BRANCH, create: true)
      append_feature_commits(repo)
    end
  end

  # Ordered list of commit subjects the recipe writes onto the feature
  # branch. Exposed as a constant so specs that want to assert "the
  # engine saw exactly these seven subjects in this order" can do so
  # without re-typing the strings.
  FEATURE_COMMIT_SUBJECTS = [
    'Add nullable email_address column',
    'Ignore email column on User pending drop',
    'Dual-write email and email_address on User',
    'Backfill email_address from email in batches',
    'Switch User reads to email_address',
    'Remove all references to legacy email column',
    'Remove ignored-columns directive and drop email column'
  ].freeze

  # Ordered list of expected canonical task types per commit. The
  # column_rename_worked_example_spec asserts manifest task_type values
  # match this list exactly (in order); kept here so a future flavor or
  # inference change that breaks the contract is caught at the recipe
  # level too.
  FEATURE_COMMIT_TASK_TYPES = [
    'schema add-nullable-column',
    'code ignore-column-for-pending-drop',
    'code dual-write-old-and-new-column',
    'data backfill-batched',
    'code switch-reads-to-new-column',
    'code remove-references-to-pending-drop-column',
    'schema drop-column-with-cleanup-precedent'
  ].freeze

  # Seed `main` with a single bootstrap commit so the feature branch
  # has a meaningful base. Without this, a fresh repo's first feature
  # commit would itself be the root commit and `git diff main..feature`
  # would have no merge base to anchor the engine's commit walk.
  def self.seed_main_branch(repo)
    repo.commit(
      subject: 'Initial commit',
      files: {
        'README.md' => "# users-email-rename fixture\n",
        'app/models/user.rb' => initial_user_model_source,
        'db/schema.rb' => initial_schema_source
      }
    )
  end

  # Append the seven feature-branch commits in the canonical R-016
  # order. Each commit method below is a single, focused block so the
  # per-commit intent stays readable. The recipe is the canonical
  # reference for the column-rename fixture's shape.
  #
  # Step 7 cites the SHAs from steps 2 and 6 in its Safety-Assertion
  # trailer, so we capture those return values from `repo.commit` (the
  # Builder returns the new HEAD SHA) and thread them into the final
  # commit's trailer map.
  def self.append_feature_commits(repo)
    add_nullable_column_commit(repo)
    ignore_email_sha = ignore_email_column_commit(repo)
    dual_write_commit(repo)
    backfill_commit(repo)
    switch_reads_commit(repo)
    remove_refs_sha = remove_references_commit(repo)
    drop_column_commit(repo, ignore_email_sha: ignore_email_sha,
                            remove_refs_sha: remove_refs_sha)
  end

  # Step 1 — schema add-nullable-column. New migration adds the
  # `email_address` column as nullable with no default. The
  # `db/migrate/*.rb` path plus the `add_column ... null: true` call
  # let the inference layer classify this as the canonical nullable-
  # column-add type.
  def self.add_nullable_column_commit(repo)
    repo.commit(
      subject: FEATURE_COMMIT_SUBJECTS[0],
      files: {
        'db/migrate/202604250001_add_email_address_to_users.rb' => <<~RUBY
          # Adds the email_address column to users as nullable so the
          # rollout can proceed without locking the table or rejecting
          # writes from older code paths.
          class AddEmailAddressToUsers < ActiveRecord::Migration[7.1]
            def change
              add_column :users, :email_address, :string, null: true
            end
          end
        RUBY
      }
    )
  end

  # Step 2 — code ignore-column-for-pending-drop. Adds the
  # `ignored_columns` directive to the User model so ActiveRecord stops
  # caching `email` in its column registry. This is the "ignored
  # columns directive" precedent the column-drop validator (FR-014)
  # demands. Returns the new SHA so step 7 can cite it.
  #
  # Inference signal: the ADDED `self.ignored_columns = ...` line is
  # what the `code_ignore_column_for_pending_drop?` predicate matches
  # (T051, inference.rb).
  def self.ignore_email_column_commit(repo)
    repo.commit(
      subject: FEATURE_COMMIT_SUBJECTS[1],
      files: {
        'app/models/user.rb' => <<~RUBY
          # User model — ignore the legacy email column while the
          # rename rolls out so ActiveRecord does not cache it.
          class User < ApplicationRecord
            self.ignored_columns = %w[email]

            attr_accessor :email
            validates :email, presence: true

            def primary_email
              email
            end

            def primary_email=(value)
              self.email = value
            end
          end
        RUBY
      }
    )
  end

  # Step 3 — code dual-write-old-and-new-column. The User model now
  # mirrors writes from `email` into `email_address` on every save via
  # a `before_save` callback. The inference predicate
  # `code_dual_write_old_and_new_column?` (T051) matches the ADDED
  # `before_save :sync_email_address` line.
  def self.dual_write_commit(repo)
    repo.commit(
      subject: FEATURE_COMMIT_SUBJECTS[2],
      files: {
        'app/models/user.rb' => <<~RUBY
          # User model — dual-write email and email_address via a
          # before_save callback so reads from either column see
          # consistent data during the rename.
          class User < ApplicationRecord
            self.ignored_columns = %w[email]

            attr_accessor :email
            validates :email, presence: true

            before_save :sync_email_address

            def self.find_by_email(address)
              where(email: address).first
            end

            def primary_email
              email
            end

            def primary_email=(value)
              self.email = value
            end

            def sync_email_address
              self.email_address = email
            end
          end
        RUBY
      }
    )
  end

  # Step 4 — data backfill-batched. A rake task that copies `email`
  # into `email_address` in batches with sleep-throttling and
  # `disable_ddl_transaction!`. The backfill-safety validator
  # (FR-013, T053) inspects the diff for `find_each`/`in_batches`,
  # `sleep`, and `disable_ddl_transaction!` — all three are present so
  # the validator accepts the commit. The inference predicate
  # `data_backfill_batched?` (T051) matches the ADDED
  # `User.in_batches(...)` + `update_all(...)` lines.
  def self.backfill_commit(repo)
    repo.commit(
      subject: FEATURE_COMMIT_SUBJECTS[3],
      files: {
        'lib/tasks/backfill_email_address.rake' => <<~RUBY
          # Backfill email_address from email in batches. Runs outside
          # a DDL transaction (the strong_migrations gem requires it),
          # processes 1_000 rows at a time via in_batches + update_all,
          # and sleeps between batches to keep replica lag bounded.
          disable_ddl_transaction!

          namespace :users do
            desc 'Backfill email_address from email in batches.'
            task backfill_email_address: :environment do
              User.in_batches(of: 1_000) do |relation|
                relation.update_all('email_address = email')
                sleep 0.05
              end
            end
          end
        RUBY
      }
    )
  end

  # Step 5 — code switch-reads-to-new-column. The User model now reads
  # via a `where(email_address: ...)` scope instead of
  # `where(email: ...)`. The inference predicate
  # `code_switch_reads_to_new_column?` (T051) matches a single hunk
  # that REMOVES `where(email: ...)` AND ADDS
  # `where(email_address: ...)` — the canonical column-swap pattern.
  def self.switch_reads_commit(repo)
    repo.commit(
      subject: FEATURE_COMMIT_SUBJECTS[4],
      files: {
        'app/models/user.rb' => <<~RUBY
          # User model — switch reads to email_address. Writes still
          # mirror via the before_save callback until the legacy
          # reference is removed.
          class User < ApplicationRecord
            self.ignored_columns = %w[email]

            attr_accessor :email
            validates :email, presence: true

            before_save :sync_email_address

            def self.find_by_email(address)
              where(email_address: address).first
            end

            def primary_email
              email_address
            end

            def primary_email=(value)
              self.email = value
            end

            def sync_email_address
              self.email_address = email
            end
          end
        RUBY
      }
    )
  end

  # Step 6 — code remove-references-to-pending-drop-column. Removes
  # the `attr_accessor :email` and `validates :email, ...` references
  # to the legacy column. After this commit no application code reads
  # or writes `email`. The inference predicate
  # `code_remove_references_to_pending_drop_column?` (T051) matches
  # REMOVED `attr_accessor` / `validates` lines. Returns the new SHA
  # so step 7 can cite it as the reference-removal precedent.
  def self.remove_references_commit(repo)
    repo.commit(
      subject: FEATURE_COMMIT_SUBJECTS[5],
      files: {
        'app/models/user.rb' => <<~RUBY
          # User model — remove all references to the legacy email
          # column. The ignored_columns directive remains in place
          # until the drop migration removes it.
          class User < ApplicationRecord
            self.ignored_columns = %w[email]

            before_save :sync_email_address

            def self.find_by_email(address)
              where(email_address: address).first
            end

            def primary_email
              email_address
            end

            def sync_email_address
              # The legacy column has no live writers; this callback
              # will be removed in the follow-up cleanup phase.
            end
          end
        RUBY
      }
    )
  end

  # Step 7 — schema drop-column-with-cleanup-precedent. A single
  # migration removes the `ignored_columns` directive AND drops the
  # `email` column. Carries a `Safety-Assertion:` trailer (FR-018,
  # T054b) citing the SHAs of step 2 (the ignored-columns precedent
  # the column-drop validator demands per FR-014) and step 6 (the
  # reference-removal precedent). The cited SHAs are recorded on the
  # manifest task entry for audit per data-model.md "Task"
  # `safety_assertion_precedents`.
  def self.drop_column_commit(repo, ignore_email_sha:, remove_refs_sha:)
    repo.commit(
      subject: FEATURE_COMMIT_SUBJECTS[6],
      files: {
        'app/models/user.rb' => <<~RUBY,
          # User model — the legacy email column has been dropped, so
          # the ignored_columns directive is no longer needed.
          class User < ApplicationRecord
            def primary_email
              email_address
            end

            def primary_email=(value)
              self.email_address = value
            end
          end
        RUBY
        'db/migrate/202604250002_drop_email_from_users.rb' => <<~RUBY
          # Drop the email column from users now that all reads, writes,
          # and ActiveRecord caching of the column have been removed
          # (see the Safety-Assertion trailer on this commit for the
          # precedent SHAs).
          class DropEmailFromUsers < ActiveRecord::Migration[7.1]
            def change
              remove_column :users, :email, :string
            end
          end
        RUBY
      },
      trailers: {
        'Safety-Assertion' => "#{ignore_email_sha}, #{remove_refs_sha}"
      }
    )
  end

  # Initial User model source seeded onto `main` so steps 2, 3, 5, and
  # 6 are real diffs against a meaningful baseline (rather than file-
  # creation diffs each time). Without this, the inference layer would
  # see every User model edit as an `:added` FileChange and could not
  # distinguish "ignore directive added" from "switch reads added".
  def self.initial_user_model_source
    <<~RUBY
      # User model baseline before the email rename rollout. Reads and
      # writes go through the legacy `email` column.
      class User < ApplicationRecord
        def primary_email
          email
        end

        def primary_email=(value)
          self.email = value
        end
      end
    RUBY
  end

  # Initial schema seeded onto `main` so the migration commits in
  # steps 1 and 7 modify a real schema rather than introducing one.
  # The schema content is intentionally minimal — the inference layer
  # reads commit diffs, not `db/schema.rb`, so this file is here only
  # to anchor the migrations in a believable repository shape.
  def self.initial_schema_source
    <<~RUBY
      # Schema baseline. The email_address column does not exist yet;
      # step 1 adds it, step 7 drops the legacy email column.
      ActiveRecord::Schema.define(version: 2026_04_24_000000) do
        create_table 'users', force: :cascade do |t|
          t.string 'email', null: false
          t.timestamps
        end
      end
    RUBY
  end
end
