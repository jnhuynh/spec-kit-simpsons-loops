# frozen_string_literal: true

require 'phaser'

# Specs for the shipped `rails-postgres-strong-migrations` flavor's
# file-pattern inference layer at `phaser/flavors/
# rails-postgres-strong-migrations/inference.rb` and the inference
# rules declared in its `flavor.yaml` (feature
# 007-multi-phase-pipeline; T041, T051, FR-012, SC-004).
#
# FR-012 requires the reference flavor to ship a file-pattern
# inference layer that "correctly classifies, without operator
# intervention, every commit in a shipped fixture set that exercises
# every type in the catalog." SC-004 sets the externally measurable
# success bar at "at least 90 percent of commits in the reference
# flavor's shipped fixture set are classified correctly by the
# file-pattern inference layer without any operator-supplied type
# tag."
#
# How this spec realises that contract:
#
#   1. It enumerates one representative fixture commit per task type
#      that FR-010 names (the same canonical-name list the catalog
#      spec at `catalog_spec.rb` pins). Each fixture is the smallest
#      synthetic commit that should trip the corresponding inference
#      rule — a file path, a tiny diff hunk, and (where a content
#      regex is the discriminator) a one-line snippet of Ruby.
#
#   2. It runs every fixture commit through the production
#      `Phaser::Classifier`, paired with the production `Phaser::
#      FlavorLoader#load("rails-postgres-strong-migrations")`. No
#      operator `Phase-Type:` trailer is set on any fixture, so the
#      cascade in FR-004 collapses to "inference rule wins, or default
#      type if no rule matches."
#
#   3. It asserts:
#        a. At least 90 % of the fixture set classifies via the
#           inference layer (`source == :inference`) and lands on the
#           expected task type (SC-004 — the headline numeric bar).
#        b. Every fixture that the inference layer DOES classify
#           classifies it correctly (zero-tolerance for inference
#           returning the wrong task type — a misclassification is a
#           silent deploy-safety bug; falling through to default is
#           merely "less helpful" but recoverable via operator tag).
#        c. A small set of representative fixtures named individually
#           so a regression failure surfaces "it's `add-table` that
#           broke", not "21/28 → 20/28."
#
#   4. The fixture set is built in-memory from `Phaser::Commit` value
#      objects rather than from real Git histories so the inference
#      layer is exercised in isolation from the engine's diff-reading
#      path. This mirrors the pattern the example-minimal flavor's
#      `inference_spec.rb` (T038) established — flavor inference
#      modules and YAML rules are pure functions of the commit value
#      object, not of Git, and tests should reflect that.
#
# This spec MUST observe failure (red) before T050 ships
# `flavor.yaml` and T051 ships `inference.rb` (the test-first
# requirement in CLAUDE.md "Test-First Development"). The first
# `Phaser::FlavorLoader#load("rails-postgres-strong-migrations")`
# call will raise `Phaser::FlavorNotFoundError` until then; once T050
# lands, the inference rule rate ramps from 0 % (every commit falls
# through to default) to ≥ 90 % as T051 wires up each match.
RSpec.describe 'rails-postgres-strong-migrations flavor inference' do # rubocop:disable RSpec/DescribeClass
  let(:flavor) do
    Phaser::FlavorLoader.new.load('rails-postgres-strong-migrations')
  end

  let(:classifier) { Phaser::Classifier.new }

  # One fixture per FR-010 task type. Each entry declares:
  #   * `expected_type`: the canonical task-type name from FR-010 the
  #     inference layer should land on (matches the names pinned in
  #     `catalog_spec.rb`'s `required_task_types`).
  #   * `paths`: the file paths in the synthetic commit's diff. Most
  #     fixtures are file-pattern-only and rely on path matches.
  #   * `hunks`: optional hunk strings for fixtures that the inference
  #     layer must discriminate by content (e.g., distinguishing
  #     `add-nullable-column` from `add-column-with-static-default`,
  #     both of which live under `db/migrate/`).
  #
  # The fixture set is intentionally NOT exhaustive of every possible
  # phrasing the inference layer must handle in production — it is the
  # minimum set required to exercise every FR-010 task type once and
  # measure the SC-004 bar. The richer per-type fixture suite that
  # T047 ships under `spec/fixtures/classification/
  # rails_postgres_strong_migrations/` will pin more variants (alias
  # rake task names, alternative migration helper spellings, etc.)
  # without duplicating this top-level rate check.
  def fixture_set # rubocop:disable Metrics/MethodLength
    [
      # ── schema (db/migrate/*.rb) ────────────────────────────────────
      {
        expected_type: 'schema add-nullable-column',
        paths: ['db/migrate/20260425000001_add_email_to_users.rb'],
        hunks: ["+    add_column :users, :email, :string\n"]
      },
      {
        expected_type: 'schema add-column-with-static-default',
        paths: ['db/migrate/20260425000002_add_active_to_users.rb'],
        hunks: ["+    add_column :users, :active, :boolean, default: false, null: false\n"]
      },
      {
        expected_type: 'schema add-table',
        paths: ['db/migrate/20260425000003_create_audits.rb'],
        hunks: ["+    create_table :audits do |t|\n+      t.string :event\n+    end\n"]
      },
      {
        expected_type: 'schema add-concurrent-index',
        paths: ['db/migrate/20260425000004_add_index_users_on_email.rb'],
        hunks: [
          "+  disable_ddl_transaction!\n",
          "+    add_index :users, :email, algorithm: :concurrently\n"
        ]
      },
      {
        expected_type: 'schema add-foreign-key-without-validation',
        paths: ['db/migrate/20260425000005_add_fk_orders_users.rb'],
        hunks: ["+    add_foreign_key :orders, :users, validate: false\n"]
      },
      {
        expected_type: 'schema validate-foreign-key',
        paths: ['db/migrate/20260425000006_validate_fk_orders_users.rb'],
        hunks: ["+    validate_foreign_key :orders, :users\n"]
      },
      {
        expected_type: 'schema add-check-constraint-without-validation',
        paths: ['db/migrate/20260425000007_add_check_users_email.rb'],
        hunks: [
          '+    add_check_constraint :users, "email IS NOT NULL", ' \
          "name: 'users_email_present', validate: false\n"
        ]
      },
      {
        expected_type: 'schema validate-check-constraint',
        paths: ['db/migrate/20260425000008_validate_check_users_email.rb'],
        hunks: ["+    validate_check_constraint :users, name: 'users_email_present'\n"]
      },
      {
        expected_type: 'schema add-virtual-not-null-via-check',
        paths: ['db/migrate/20260425000009_add_virtual_not_null_users_email.rb'],
        hunks: [
          '+    add_check_constraint :users, "email IS NOT NULL", ' \
          "name: 'users_email_not_null', validate: false\n"
        ]
      },
      {
        expected_type: 'schema flip-real-not-null-after-check',
        paths: ['db/migrate/20260425000010_flip_users_email_not_null.rb'],
        hunks: ["+    change_column_null :users, :email, false\n"]
      },
      {
        expected_type: 'schema change-column-default',
        paths: ['db/migrate/20260425000011_change_users_active_default.rb'],
        hunks: ["+    change_column_default :users, :active, from: false, to: true\n"]
      },
      {
        expected_type: 'schema drop-column-with-cleanup-precedent',
        paths: ['db/migrate/20260425000012_drop_users_legacy_email.rb'],
        hunks: ["+    remove_column :users, :legacy_email\n"]
      },
      {
        expected_type: 'schema drop-table',
        paths: ['db/migrate/20260425000013_drop_audits.rb'],
        hunks: ["+    drop_table :audits\n"]
      },
      {
        expected_type: 'schema drop-concurrent-index',
        paths: ['db/migrate/20260425000014_remove_index_users_on_email.rb'],
        hunks: [
          "+  disable_ddl_transaction!\n",
          "+    remove_index :users, :email, algorithm: :concurrently\n"
        ]
      },
      # ── data (lib/tasks/**/*.rake) ──────────────────────────────────
      {
        expected_type: 'data backfill-batched',
        paths: ['lib/tasks/backfill_user_emails.rake'],
        hunks: [
          "+    User.in_batches(of: 1_000) do |relation|\n",
          "+      relation.update_all(email_lower: 'lower(email)')\n",
          "+      sleep 0.1\n",
          "+    end\n"
        ]
      },
      {
        expected_type: 'data cleanup-batched',
        paths: ['lib/tasks/cleanup_orphaned_audits.rake'],
        hunks: [
          "+    Audit.where(event: 'legacy').in_batches(of: 1_000) do |relation|\n",
          "+      relation.delete_all\n",
          "+      sleep 0.1\n",
          "+    end\n"
        ]
      },
      # ── code (app/**/*.rb) ──────────────────────────────────────────
      {
        expected_type: 'code default-catch-all-change',
        paths: ['app/services/notifier.rb'],
        hunks: ["+    Notifier.call(user)\n"]
      },
      {
        expected_type: 'code dual-write-old-and-new-column',
        paths: ['app/models/user.rb'],
        hunks: [
          "+  before_save :sync_legacy_email\n",
          "+  def sync_legacy_email\n",
          "+    self.legacy_email = email\n",
          "+  end\n"
        ]
      },
      {
        expected_type: 'code switch-reads-to-new-column',
        paths: ['app/models/user.rb'],
        hunks: [
          "-    where(legacy_email: address)\n",
          "+    where(email: address)\n"
        ]
      },
      {
        expected_type: 'code ignore-column-for-pending-drop',
        paths: ['app/models/user.rb'],
        hunks: [
          "+  self.ignored_columns = %w[legacy_email]\n"
        ]
      },
      {
        expected_type: 'code remove-references-to-pending-drop-column',
        paths: ['app/models/user.rb'],
        hunks: [
          "-  attr_accessor :legacy_email\n",
          "-  validates :legacy_email, presence: true\n"
        ]
      },
      {
        expected_type: 'code remove-ignored-columns-directive',
        paths: ['app/models/user.rb'],
        hunks: [
          "-  self.ignored_columns = %w[legacy_email]\n"
        ]
      },
      # ── feature-flag (config/features/**/*.yml) ─────────────────────
      {
        expected_type: 'feature-flag create-default-off',
        paths: ['config/features/new_checkout.yml'],
        hunks: [
          "+name: new_checkout\n",
          "+default: false\n"
        ]
      },
      {
        expected_type: 'feature-flag enable',
        paths: ['config/features/new_checkout.yml'],
        hunks: [
          "-default: false\n",
          "+default: true\n"
        ]
      },
      {
        expected_type: 'feature-flag remove',
        paths: ['config/features/new_checkout.yml'],
        hunks: [
          "-name: new_checkout\n",
          "-default: true\n"
        ]
      },
      # ── infra (config/infra/**/*.tf | terraform/**/*.tf) ────────────
      {
        expected_type: 'infra provision',
        paths: ['terraform/redis.tf'],
        hunks: [
          "+resource \"aws_elasticache_cluster\" \"sessions\" {\n",
          "+  cluster_id = \"sessions\"\n",
          "+}\n"
        ]
      },
      {
        expected_type: 'infra wire',
        paths: ['config/cache.yml'],
        hunks: [
          "+production:\n",
          "+  url: <%= ENV['REDIS_URL'] %>\n"
        ]
      },
      {
        expected_type: 'infra decommission',
        paths: ['terraform/redis.tf'],
        hunks: [
          "-resource \"aws_elasticache_cluster\" \"sessions\" {\n",
          "-  cluster_id = \"sessions\"\n",
          "-}\n"
        ]
      }
    ].freeze
  end

  # Build a `Phaser::Commit` from a fixture-set entry. Diff hunks are
  # joined into a single string per file because the production
  # `Phaser::Classifier#content_regex_match?` invokes `regex.match?`
  # against each `FileChange#hunks` element directly (one regex,
  # whatever string shape the helper hands it). Most fixtures put one
  # hunk per file, but a few migrations need multiple lines (e.g.,
  # `disable_ddl_transaction!` plus the concurrent-index call) so the
  # joined-string shape keeps the fixture concise without changing
  # what the classifier sees.
  def build_commit(fixture, index)
    Phaser::Commit.new(
      hash: format('%040d', index + 1),
      subject: "fixture for #{fixture[:expected_type]}",
      message_trailers: {},
      diff: Phaser::Diff.new(
        files: fixture[:paths].map do |path|
          Phaser::FileChange.new(
            path: path,
            change_kind: :modified,
            hunks: fixture[:hunks] || []
          )
        end
      ),
      author_timestamp: '2026-04-25T12:00:00Z'
    )
  end

  # Run every fixture commit through the classifier and return one
  # plain-Hash result per fixture so the assertions below can reason
  # about the population without re-running classification.
  def classify_fixtures
    fixture_set.each_with_index.map do |fixture, index|
      commit = build_commit(fixture, index)
      result = classifier.classify(commit, flavor)
      {
        expected_type: fixture[:expected_type],
        actual_type: result.task_type,
        source: result.source,
        rule_name: result.rule_name,
        commit_hash: commit.hash
      }
    end
  end

  # Helper kept at describe scope (not inside the `it` block) so the
  # SC-004 example's body stays under the RSpec/ExampleLength cap and
  # the per-miss diagnostic stays readable. A miss is any fixture
  # whose source is not `:inference` OR whose `actual_type` does not
  # equal the `expected_type`. The returned shape is the same plain
  # Hash `classify_fixtures` produces.
  def inference_misses(results)
    results.reject do |r|
      r[:source] == :inference && r[:actual_type] == r[:expected_type]
    end
  end

  # Render a miss list into a single-line summary for failure output
  # (e.g., `schema add-table → :default/code default-catch-all-change`).
  def format_miss_summary(misses)
    misses.map do |r|
      "#{r[:expected_type]} → #{r[:source]}/#{r[:actual_type]}"
    end.join('; ')
  end

  describe 'SC-004 inference rate (≥90 % of fixtures classified by the inference layer)' do
    it 'classifies at least 90 % of fixture commits via the inference layer to the expected task type' do
      results = classify_fixtures
      total = results.size
      misses = inference_misses(results)
      correctly_inferred = total - misses.size
      ratio = correctly_inferred.fdiv(total)

      expect(ratio).to be >= 0.90,
                       'SC-004 requires at least 90% of fixtures to classify via the ' \
                       'inference layer to the expected type; observed ' \
                       "#{correctly_inferred}/#{total} = " \
                       "#{(ratio * 100).round(1)}%. Misses: #{format_miss_summary(misses)}"
    end

    it 'never misclassifies a fixture that the inference layer DOES match (correctness is zero-tolerance)' do
      results = classify_fixtures
      inferred = results.select { |r| r[:source] == :inference }
      misclassified = inferred.reject { |r| r[:actual_type] == r[:expected_type] }

      expect(misclassified).to eq([]),
                               'Inference rules must never assign the wrong task type (a silent ' \
                               'deploy-safety bug). Falling through to :default is acceptable for ' \
                               'rare fixtures; assigning the wrong type is not. Offenders: ' \
                               "#{misclassified.map do |r|
                                 "#{r[:expected_type]} got #{r[:actual_type]} via rule #{r[:rule_name].inspect}"
                               end.join('; ')}"
    end
  end

  describe 'per-task-type spot checks (named so a regression points at the broken rule)' do
    # Each example below picks one fixture from `fixture_set` and
    # asserts the inference layer lands on the expected type. Listing
    # every type as its own `it` makes a regression report read
    # "schema add-concurrent-index broken" instead of "rate dropped to
    # 88 %", so the failure is actionable on first read. We do not
    # list ALL 28 types here — that would duplicate the rate check
    # above — but we do cover one representative per FR-010 category
    # (schema, data, code, feature-flag, infra) plus the two
    # historically-tricky ones (concurrent-index discrimination, and
    # the dual ignored-columns-directive add/remove pair) that are
    # most prone to regressions during catalog edits.
    let(:results_by_expected_type) do
      classify_fixtures.to_h { |r| [r[:expected_type], r] }
    end

    {
      'schema add-nullable-column' => 'a migration whose only change is `add_column ... :string`',
      'schema add-concurrent-index' => 'a concurrent-index migration with `disable_ddl_transaction!`',
      'data backfill-batched' => 'a rake task using `in_batches` with a sleep throttle',
      'code ignore-column-for-pending-drop' => 'a model edit adding `self.ignored_columns = ...`',
      'code remove-ignored-columns-directive' => 'a model edit removing `self.ignored_columns = ...`',
      'feature-flag create-default-off' => 'a new flag definition file under config/features/',
      'infra provision' => 'a terraform resource added under terraform/'
    }.each do |expected_type, fixture_description|
      it "infers #{expected_type.inspect} from #{fixture_description}" do
        result = results_by_expected_type.fetch(expected_type) do
          raise "fixture for #{expected_type.inspect} missing from fixture_set"
        end

        expect(result[:source]).to eq(:inference),
                                   "expected #{expected_type.inspect} to classify via the inference layer; " \
                                   "got source=#{result[:source].inspect} type=#{result[:actual_type].inspect}"
        expect(result[:actual_type]).to eq(expected_type)
      end
    end
  end
end
