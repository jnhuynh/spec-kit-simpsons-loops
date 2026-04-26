# frozen_string_literal: true

# Synthetic Git fixture recipe for the example-minimal flavor's engine
# tests (feature 007-multi-phase-pipeline; T029).
#
# The fixture is built at test time (not committed as a real Git repo
# under this directory) so commit hashes, author timestamps, and
# committer identity stay byte-stable across machines and CI hosts. The
# `GitFixtureHelper` (loaded by `spec_helper.rb`) pins the identity and
# clock; this recipe pins the commit content, ordering, and trailer
# values so every spec that consumes it sees the same five-commit
# history.
#
# Why a recipe module instead of an on-disk Git repo:
#
#   * On-disk Git repositories carry per-commit author timestamps and
#     committer identities that vary per machine. Building the repo at
#     test time with the helper's fixed identity and frozen clock keeps
#     the resulting hashes reproducible (FR-002, SC-002 — the engine's
#     determinism contract reads the fixture, so the fixture itself
#     must be deterministic).
#
#   * The phaser engine reads commits via `git log` (T036), so the
#     fixture must be a real Git history at the moment the test runs.
#     The recipe builds a throwaway repo under a `Dir.mktmpdir` path
#     and returns its absolute location; the consuming spec teardown
#     (`cleanup_fixture_repos` from `GitFixtureHelper`) removes it.
#
#   * Sharing the recipe across specs (the engine integration test, the
#     CLI contract test, the no-domain-leakage scan, and the SC-002
#     determinism check) means every consumer sees an identical
#     five-commit history without per-spec duplication.
#
# Recipe shape (matches the example-minimal flavor catalog in T037):
#
#   * Two task types: `schema` (`:alone` isolation) and `misc`
#     (`:groups` isolation, default).
#   * One inference rule: `schema-by-path` matches `db/migrate/*.rb`.
#   * One precedent rule: `misc-after-schema` requires every `misc`
#     commit to follow at least one `schema` commit.
#   * Default type: `misc`.
#
# Five-commit history on the `feature-example-minimal` branch (after a
# single bootstrap commit on `main`):
#
#   1. Schema, inferred           — `db/migrate/202604250001_add_email.rb`.
#                                   The path matches the `schema-by-path`
#                                   inference rule; no operator tag is
#                                   present, so the classifier records
#                                   `source: :inference`,
#                                   `rule_name: 'schema-by-path'`.
#
#   2. Schema, operator-tagged    — `db/migrate/202604250002_add_index.rb`
#                                   with a `Phase-Type: schema` trailer
#                                   (FR-016). The operator tag wins over
#                                   inference per FR-004; the classifier
#                                   records `source: :operator_tag`.
#
#   3. Misc, operator-tagged      — `app/models/user.rb` with a
#                                   `Phase-Type: misc` trailer. Demonstrates
#                                   that the operator tag can name a
#                                   type other than what inference would
#                                   pick.
#
#   4. Misc, default cascade      — `app/services/notifier.rb`. No rule
#                                   matches, no trailer is present, so
#                                   the classifier falls through to the
#                                   flavor's `default_type: misc`
#                                   (`source: :default`). This is the
#                                   "non-matching commit that gets the
#                                   default type" T029 explicitly calls
#                                   for.
#
#   5. Misc, default cascade      — `lib/tasks/cleanup.rake`. Second
#                                   default-cascade commit so the
#                                   isolation resolver can demonstrate
#                                   `:groups` consolidation: both misc
#                                   defaults can share a phase, while
#                                   each schema commit gets its own
#                                   phase per `:alone` isolation.
#
# Every misc commit (3, 4, 5) follows at least one schema commit (1, 2),
# so the `misc-after-schema` precedent rule is satisfied; a future spec
# can flip the order by reordering the recipe's `commit` calls to
# exercise the precedent-failure path.
#
# Usage from a spec (the helper module is auto-loaded by spec_helper.rb;
# `make_fixture_repo` and `cleanup_fixture_repos` are mixed into every
# example group):
#
#   RSpec.describe "Phaser::Engine end-to-end" do
#     let(:repo_path) { ExampleMinimalFixture.build(self) }
#     after { cleanup_fixture_repos }
#
#     it "produces a deterministic manifest" do
#       # ... point the engine / CLI at repo_path ...
#     end
#   end
#
# `ExampleMinimalFixture.build` takes the example-group instance (so it
# can call into `make_fixture_repo`) and returns the absolute path to
# the throwaway repo. The branch the engine should consume is
# `feature-example-minimal`; the integration branch is `main`.
module ExampleMinimalFixture
  # Branch name carrying the five-commit feature history. Specs point
  # the engine / CLI at this branch via `git log`. Pinned as a constant
  # so consumers can reference it without hard-coding string literals
  # in multiple places.
  FEATURE_BRANCH = 'feature-example-minimal'

  # Integration branch the feature branches off of. The phaser engine
  # treats this as the manifest's `base_branch` per FR-026.
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
    host.make_fixture_repo('example-minimal') do |repo|
      seed_main_branch(repo)
      repo.checkout(FEATURE_BRANCH, create: true)
      append_feature_commits(repo)
    end
  end

  # Returns the ordered list of commit subjects the recipe writes onto
  # the feature branch. Exposed as a constant so specs that want to
  # assert "the engine saw exactly these five subjects in this order"
  # can do so without re-typing the strings.
  FEATURE_COMMIT_SUBJECTS = [
    'Add nullable email_address column',
    'Add index on users email_address',
    'Update user model to read new column',
    'Send notification when email changes',
    'Cleanup stale email-change audit rows'
  ].freeze

  # Returns the ordered list of file paths the recipe touches on the
  # feature branch (one per commit). Exposed for specs that want to
  # assert the diff contents without re-deriving the paths.
  FEATURE_COMMIT_PATHS = [
    'db/migrate/202604250001_add_email.rb',
    'db/migrate/202604250002_add_index.rb',
    'app/models/user.rb',
    'app/services/notifier.rb',
    'lib/tasks/cleanup.rake'
  ].freeze

  # Returns the expected classification source for each feature commit
  # in order. Specs that exercise the classifier-cascade contract
  # (`:operator_tag` > `:inference` > `:default`) read this constant to
  # assert the engine's per-commit decisions match the recipe's intent.
  FEATURE_COMMIT_SOURCES = %i[inference operator_tag operator_tag default default].freeze

  # Returns the expected task type assigned to each feature commit in
  # order. With the example-minimal catalog (two task types: `schema`
  # `:alone` and `misc` `:groups`, default `misc`), commits 1-2 land
  # as `schema` and commits 3-5 land as `misc`.
  FEATURE_COMMIT_TASK_TYPES = %w[schema schema misc misc misc].freeze

  # Seed `main` with a single bootstrap commit so the feature branch
  # has a meaningful base. Without this, a fresh repo's first feature
  # commit would itself be the root commit and `git diff main..feature`
  # would have no merge base to anchor the engine's commit walk.
  def self.seed_main_branch(repo)
    repo.commit(
      subject: 'Initial commit',
      files: { 'README.md' => "# example-minimal fixture\n" }
    )
  end

  # Append the five feature-branch commits in the order documented in
  # the file header. Each commit method below is a single, focused
  # block so the per-commit intent stays readable; the recipe is the
  # canonical reference for the example-minimal fixture's shape.
  def self.append_feature_commits(repo)
    add_inferred_schema_commit(repo)
    add_tagged_schema_commit(repo)
    add_tagged_misc_commit(repo)
    add_default_misc_commit_one(repo)
    add_default_misc_commit_two(repo)
  end

  # Commit 1 — schema via inference. The path matches the `schema-by-path`
  # inference rule (`db/migrate/*.rb`). No operator tag, so the classifier
  # records `source: :inference`.
  def self.add_inferred_schema_commit(repo)
    repo.commit(
      subject: FEATURE_COMMIT_SUBJECTS[0],
      files: {
        FEATURE_COMMIT_PATHS[0] => <<~RUBY
          # Migration: add nullable email_address column.
          class AddEmailAddressColumn
            def change
              add_column :users, :email_address, :string
            end
          end
        RUBY
      }
    )
  end

  # Commit 2 — schema via operator tag (FR-016). The path also matches
  # the inference rule, but the explicit `Phase-Type: schema` trailer
  # is what the classifier records as the source.
  def self.add_tagged_schema_commit(repo)
    repo.commit(
      subject: FEATURE_COMMIT_SUBJECTS[1],
      files: {
        FEATURE_COMMIT_PATHS[1] => <<~RUBY
          # Migration: add index on users.email_address.
          class AddIndexOnUsersEmailAddress
            def change
              add_index :users, :email_address
            end
          end
        RUBY
      },
      trailers: { 'Phase-Type' => 'schema' }
    )
  end

  # Commit 3 — misc via operator tag. The path does NOT match the
  # inference rule, but the explicit `Phase-Type: misc` trailer makes
  # the operator's intent explicit.
  def self.add_tagged_misc_commit(repo)
    repo.commit(
      subject: FEATURE_COMMIT_SUBJECTS[2],
      files: {
        FEATURE_COMMIT_PATHS[2] => <<~RUBY
          # Read the new email_address column when present.
          class User
            def address_for_notifications
              email_address || legacy_email
            end
          end
        RUBY
      },
      trailers: { 'Phase-Type' => 'misc' }
    )
  end

  # Commit 4 — misc via the default-type cascade. No inference rule
  # matches and no operator tag is present, so the classifier falls
  # through to the flavor's `default_type: misc`. This is the
  # "non-matching commit that gets the default type" T029 explicitly
  # requires.
  def self.add_default_misc_commit_one(repo)
    repo.commit(
      subject: FEATURE_COMMIT_SUBJECTS[3],
      files: {
        FEATURE_COMMIT_PATHS[3] => <<~RUBY
          # Send notification when a user changes their email_address.
          class Notifier
            def call(user)
              return unless user.email_address_previously_changed?

              deliver(user.email_address)
            end
          end
        RUBY
      }
    )
  end

  # Commit 5 — second misc via the default-type cascade. With the misc
  # type's `:groups` isolation, commits 4 and 5 can share a phase while
  # the schema commits remain in their own `:alone` phases.
  def self.add_default_misc_commit_two(repo)
    repo.commit(
      subject: FEATURE_COMMIT_SUBJECTS[4],
      files: {
        FEATURE_COMMIT_PATHS[4] => <<~RUBY
          # Rake task: remove email-change audit rows older than 30 days.
          namespace :cleanup do
            task :stale_email_audits do
              EmailChangeAudit.where('created_at < ?', 30.days.ago).delete_all
            end
          end
        RUBY
      }
    )
  end
end
