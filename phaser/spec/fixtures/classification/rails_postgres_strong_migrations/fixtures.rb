# frozen_string_literal: true

require 'phaser'

# Per-type classification fixture set for the
# `rails-postgres-strong-migrations` reference flavor (feature
# 007-multi-phase-pipeline; T047, FR-010, FR-012, SC-004).
#
# This module ships a richer per-type fixture suite than the inline
# fixture set in `phaser/spec/flavors/rails_postgres_strong_migrations/
# inference_spec.rb`. The inline fixture set in `inference_spec.rb`
# carries one canonical fixture per FR-010 task type so it can pin the
# top-level SC-004 inference rate (≥90 %) and per-task-type spot checks
# in a single, scannable spec file. This module ships ADDITIONAL
# variants — alternative migration helper spellings, alias rake task
# names, real-world phrasings — so that a future variant-coverage spec
# (or a maintainer reproducing a misclassification reported from the
# field) can exercise the inference layer against a population that
# better reflects production diffs.
#
# Why a single Ruby module instead of 28 separate per-type files:
#
#   * Reviewability: one file means one diff when a maintainer adds a
#     new variant or renames a task type. Splitting into 28 files would
#     fan a single rename across 28 small diffs.
#
#   * Loadability: a single `require` from any consuming spec returns
#     the full fixture set. The inline-fixture pattern in
#     `inference_spec.rb` already proves this shape works.
#
#   * Determinism: the fixture order is the FR-010 catalog order, so
#     iteration through `ALL_FIXTURES` is deterministic without
#     additional sort calls (FR-002, SC-002).
#
# Why a Ruby module instead of YAML or JSON data files:
#
#   * The fixtures need to construct `Phaser::Commit`,
#     `Phaser::Diff`, and `Phaser::FileChange` value objects (per
#     `data-model.md`), which is more naturally done in Ruby than
#     through a separate YAML-to-value-object loader.
#
#   * The example-minimal flavor's fixture recipe (`phaser/spec/
#     fixtures/repos/example-minimal/recipe.rb`, T029) established the
#     "fixtures are Ruby modules" pattern; T047 mirrors it for
#     consistency.
#
# Why fixtures live under `phaser/spec/fixtures/classification/<flavor>/`
# rather than `phaser/spec/flavors/<flavor>/fixtures/`:
#
#   * The plan.md "Project Structure" pins
#     `phaser/spec/fixtures/classification/` as "Per-type fixture
#     commits (FR-012)" — a flavor-agnostic location for fixture data.
#     Each shipped flavor that wants per-type fixtures gets its own
#     subdirectory here. Keeping fixtures separated from spec files
#     prevents `_spec.rb` auto-discovery from trying to run them as
#     specs.
#
# Consumption pattern (mirrors the inline fixture set in
# `inference_spec.rb`):
#
#   require 'fixtures/classification/rails_postgres_strong_migrations/fixtures'
#
#   RailsPostgresStrongMigrationsFixtures::ALL_FIXTURES.each do |fixture|
#     commit = RailsPostgresStrongMigrationsFixtures.build_commit(fixture, index)
#     result = classifier.classify(commit, flavor)
#     expect(result.task_type).to eq(fixture[:expected_type])
#   end
#
# This module deliberately does NOT auto-load itself from
# `spec/support/` — it is opt-in via explicit `require` so specs that
# do not need the variant suite are not burdened with parsing it. The
# inline fixture set in `inference_spec.rb` is the one that pins the
# headline SC-004 rate; this module is supplementary coverage.
module RailsPostgresStrongMigrationsFixtures
  # Each fixture entry follows the same shape the inline fixture set in
  # `inference_spec.rb` uses, so a consuming spec can iterate either
  # population through the same construction helper:
  #
  #   {
  #     expected_type: <FR-010 canonical task-type name>,
  #     paths: <Array<String> of repository-relative file paths>,
  #     hunks: <Array<String> of raw hunk text snippets>,
  #     description: <one-line human-readable summary used in failure
  #                   messages and in the "what variant is this?" docs>
  #   }
  #
  # Variants for a single task type are listed adjacent so a maintainer
  # editing one rule can scan all the shapes that rule must accept.

  # ── schema (db/migrate/*.rb) ─────────────────────────────────────────
  #
  # The reference flavor's inference layer (T051) classifies migrations
  # by reading the `db/migrate/*.rb` path AND the migration helper call
  # in the diff hunks. Each variant below picks an alternative phrasing
  # the inference layer must accept (timestamp prefix, helper alias,
  # block-vs-args spelling, …) so that fixtures composed from real
  # production diffs are not surprised by "the inference rule only
  # matched the canonical example."
  SCHEMA_ADD_NULLABLE_COLUMN = [
    {
      expected_type: 'schema add-nullable-column',
      paths: ['db/migrate/20260425000001_add_email_to_users.rb'],
      hunks: ["+    add_column :users, :email, :string\n"],
      description: 'canonical add_column with no options (nullable by default)'
    },
    {
      expected_type: 'schema add-nullable-column',
      paths: ['db/migrate/20260601121501_add_phone_to_users.rb'],
      hunks: ["+    add_column :users, :phone, :string, null: true\n"],
      description: 'add_column with explicit null: true'
    },
    {
      expected_type: 'schema add-nullable-column',
      paths: ['db/migrate/20260710080000_add_metadata_to_orders.rb'],
      hunks: [
        "+    change_table :orders do |t|\n",
        "+      t.string :metadata\n",
        "+    end\n"
      ],
      description: 'change_table block with t.string for a nullable column'
    }
  ].freeze

  SCHEMA_ADD_COLUMN_WITH_STATIC_DEFAULT = [
    {
      expected_type: 'schema add-column-with-static-default',
      paths: ['db/migrate/20260425000002_add_active_to_users.rb'],
      hunks: ["+    add_column :users, :active, :boolean, default: false, null: false\n"],
      description: 'add_column boolean with literal default'
    },
    {
      expected_type: 'schema add-column-with-static-default',
      paths: ['db/migrate/20260620140000_add_status_to_orders.rb'],
      hunks: ["+    add_column :orders, :status, :string, default: 'pending', null: false\n"],
      description: 'add_column string with literal default and null: false'
    }
  ].freeze

  SCHEMA_ADD_TABLE = [
    {
      expected_type: 'schema add-table',
      paths: ['db/migrate/20260425000003_create_audits.rb'],
      hunks: ["+    create_table :audits do |t|\n+      t.string :event\n+    end\n"],
      description: 'create_table block with one column'
    },
    {
      expected_type: 'schema add-table',
      paths: ['db/migrate/20260801120000_create_sessions.rb'],
      hunks: [
        "+    create_table :sessions, id: :uuid do |t|\n",
        "+      t.references :user, null: false, foreign_key: true\n",
        "+      t.datetime :expires_at, null: false\n",
        "+      t.timestamps\n",
        "+    end\n"
      ],
      description: 'create_table with uuid primary key and references'
    }
  ].freeze

  SCHEMA_ADD_CONCURRENT_INDEX = [
    {
      expected_type: 'schema add-concurrent-index',
      paths: ['db/migrate/20260425000004_add_index_users_on_email.rb'],
      hunks: [
        "+  disable_ddl_transaction!\n",
        "+    add_index :users, :email, algorithm: :concurrently\n"
      ],
      description: 'add_index with algorithm: :concurrently and disable_ddl_transaction!'
    },
    {
      expected_type: 'schema add-concurrent-index',
      paths: ['db/migrate/20260711090000_add_index_orders_on_user_id.rb'],
      hunks: [
        "+  disable_ddl_transaction!\n",
        "+    add_index :orders, :user_id, name: 'idx_orders_on_user_id', algorithm: :concurrently\n"
      ],
      description: 'add_index with explicit name and algorithm: :concurrently'
    }
  ].freeze

  SCHEMA_ADD_FOREIGN_KEY_WITHOUT_VALIDATION = [
    {
      expected_type: 'schema add-foreign-key-without-validation',
      paths: ['db/migrate/20260425000005_add_fk_orders_users.rb'],
      hunks: ["+    add_foreign_key :orders, :users, validate: false\n"],
      description: 'add_foreign_key with validate: false'
    },
    {
      expected_type: 'schema add-foreign-key-without-validation',
      paths: ['db/migrate/20260820103000_add_fk_invoices_customers.rb'],
      hunks: ["+    add_foreign_key :invoices, :customers, column: :customer_id, validate: false\n"],
      description: 'add_foreign_key with explicit column and validate: false'
    }
  ].freeze

  SCHEMA_VALIDATE_FOREIGN_KEY = [
    {
      expected_type: 'schema validate-foreign-key',
      paths: ['db/migrate/20260425000006_validate_fk_orders_users.rb'],
      hunks: ["+    validate_foreign_key :orders, :users\n"],
      description: 'validate_foreign_key with table pair'
    },
    {
      expected_type: 'schema validate-foreign-key',
      paths: ['db/migrate/20260821110000_validate_fk_invoices_customers.rb'],
      hunks: ["+    validate_foreign_key :invoices, column: :customer_id\n"],
      description: 'validate_foreign_key with explicit column option'
    }
  ].freeze

  SCHEMA_ADD_CHECK_CONSTRAINT_WITHOUT_VALIDATION = [
    {
      expected_type: 'schema add-check-constraint-without-validation',
      paths: ['db/migrate/20260425000007_add_check_users_email.rb'],
      hunks: [
        '+    add_check_constraint :users, "email IS NOT NULL", ' \
        "name: 'users_email_present', validate: false\n"
      ],
      description: 'add_check_constraint with named constraint and validate: false'
    }
  ].freeze

  SCHEMA_VALIDATE_CHECK_CONSTRAINT = [
    {
      expected_type: 'schema validate-check-constraint',
      paths: ['db/migrate/20260425000008_validate_check_users_email.rb'],
      hunks: ["+    validate_check_constraint :users, name: 'users_email_present'\n"],
      description: 'validate_check_constraint by name'
    }
  ].freeze

  SCHEMA_ADD_VIRTUAL_NOT_NULL_VIA_CHECK = [
    {
      expected_type: 'schema add-virtual-not-null-via-check',
      paths: ['db/migrate/20260425000009_add_virtual_not_null_users_email.rb'],
      hunks: [
        '+    add_check_constraint :users, "email IS NOT NULL", ' \
        "name: 'users_email_not_null', validate: false\n"
      ],
      description: 'add_check_constraint shaped as a virtual NOT NULL (name encodes intent)'
    }
  ].freeze

  SCHEMA_FLIP_REAL_NOT_NULL_AFTER_CHECK = [
    {
      expected_type: 'schema flip-real-not-null-after-check',
      paths: ['db/migrate/20260425000010_flip_users_email_not_null.rb'],
      hunks: ["+    change_column_null :users, :email, false\n"],
      description: 'change_column_null flipping to NOT NULL after a validated check'
    }
  ].freeze

  SCHEMA_CHANGE_COLUMN_DEFAULT = [
    {
      expected_type: 'schema change-column-default',
      paths: ['db/migrate/20260425000011_change_users_active_default.rb'],
      hunks: ["+    change_column_default :users, :active, from: false, to: true\n"],
      description: 'change_column_default with from/to keyword form'
    },
    {
      expected_type: 'schema change-column-default',
      paths: ['db/migrate/20260822100000_change_orders_status_default.rb'],
      hunks: ["+    change_column_default :orders, :status, 'open'\n"],
      description: 'change_column_default with positional new-default form'
    }
  ].freeze

  SCHEMA_DROP_COLUMN_WITH_CLEANUP_PRECEDENT = [
    {
      expected_type: 'schema drop-column-with-cleanup-precedent',
      paths: ['db/migrate/20260425000012_drop_users_legacy_email.rb'],
      hunks: ["+    remove_column :users, :legacy_email\n"],
      description: 'remove_column for a column already ignored and dereferenced'
    },
    {
      expected_type: 'schema drop-column-with-cleanup-precedent',
      paths: ['db/migrate/20260901090000_drop_orders_legacy_status.rb'],
      hunks: ["+    remove_column :orders, :legacy_status, :string\n"],
      description: 'remove_column with explicit type (reversible form)'
    }
  ].freeze

  SCHEMA_DROP_TABLE = [
    {
      expected_type: 'schema drop-table',
      paths: ['db/migrate/20260425000013_drop_audits.rb'],
      hunks: ["+    drop_table :audits\n"],
      description: 'drop_table on a fully decommissioned table'
    }
  ].freeze

  SCHEMA_DROP_CONCURRENT_INDEX = [
    {
      expected_type: 'schema drop-concurrent-index',
      paths: ['db/migrate/20260425000014_remove_index_users_on_email.rb'],
      hunks: [
        "+  disable_ddl_transaction!\n",
        "+    remove_index :users, :email, algorithm: :concurrently\n"
      ],
      description: 'remove_index with algorithm: :concurrently and disable_ddl_transaction!'
    },
    {
      expected_type: 'schema drop-concurrent-index',
      paths: ['db/migrate/20260902120000_remove_index_orders_on_user_id.rb'],
      hunks: [
        "+  disable_ddl_transaction!\n",
        "+    remove_index :orders, name: 'idx_orders_on_user_id', algorithm: :concurrently\n"
      ],
      description: 'remove_index by name with algorithm: :concurrently'
    }
  ].freeze

  # ── data (lib/tasks/**/*.rake) ───────────────────────────────────────
  #
  # Backfill and cleanup rake tasks must each be batched (in_batches /
  # find_each), throttled (sleep between batches), and the migration
  # variant must run outside a transaction. The variants below cover
  # both Ruby helper spellings (`in_batches`, `find_each`) so the
  # backfill-safety validator (T053) and the inference layer (T051) see
  # both shapes during development.
  DATA_BACKFILL_BATCHED = [
    {
      expected_type: 'data backfill-batched',
      paths: ['lib/tasks/backfill_user_emails.rake'],
      hunks: [
        "+    User.in_batches(of: 1_000) do |relation|\n",
        "+      relation.update_all(email_lower: 'lower(email)')\n",
        "+      sleep 0.1\n",
        "+    end\n"
      ],
      description: 'in_batches with update_all and sleep throttle'
    },
    {
      expected_type: 'data backfill-batched',
      paths: ['lib/tasks/backfill_order_status.rake'],
      hunks: [
        "+    Order.find_each(batch_size: 1_000) do |order|\n",
        "+      order.update!(status: order.legacy_status)\n",
        "+      sleep 0.05\n",
        "+    end\n"
      ],
      description: 'find_each with explicit batch_size and sleep throttle'
    }
  ].freeze

  DATA_CLEANUP_BATCHED = [
    {
      expected_type: 'data cleanup-batched',
      paths: ['lib/tasks/cleanup_orphaned_audits.rake'],
      hunks: [
        "+    Audit.where(event: 'legacy').in_batches(of: 1_000) do |relation|\n",
        "+      relation.delete_all\n",
        "+      sleep 0.1\n",
        "+    end\n"
      ],
      description: 'in_batches scoped delete_all with sleep throttle'
    },
    {
      expected_type: 'data cleanup-batched',
      paths: ['lib/tasks/cleanup_stale_sessions.rake'],
      hunks: [
        "+    Session.where('expires_at < ?', 7.days.ago).in_batches(of: 500) do |relation|\n",
        "+      relation.destroy_all\n",
        "+      sleep 0.2\n",
        "+    end\n"
      ],
      description: 'in_batches scoped destroy_all with sleep throttle'
    }
  ].freeze

  # ── code (app/**/*.rb) ───────────────────────────────────────────────
  #
  # Code commits are the trickiest population for inference because
  # `app/**/*.rb` is the catch-all path for the default type ("code
  # default-catch-all-change"). Each variant below is built so the
  # discriminating signal lives in the diff hunks (a `before_save`
  # callback for dual-write, an `ignored_columns =` assignment for the
  # ignore-column directive, etc.) — the inference rule must read both
  # the path AND the hunk content to land on the right type.
  CODE_DEFAULT_CATCH_ALL_CHANGE = [
    {
      expected_type: 'code default-catch-all-change',
      paths: ['app/services/notifier.rb'],
      hunks: ["+    Notifier.call(user)\n"],
      description: 'plain method call inside an app service (no migration signal)'
    },
    {
      expected_type: 'code default-catch-all-change',
      paths: ['app/controllers/orders_controller.rb'],
      hunks: ["+    redirect_to order_path(@order)\n"],
      description: 'redirect_to in a controller (no migration signal)'
    }
  ].freeze

  CODE_DUAL_WRITE_OLD_AND_NEW_COLUMN = [
    {
      expected_type: 'code dual-write-old-and-new-column',
      paths: ['app/models/user.rb'],
      hunks: [
        "+  before_save :sync_legacy_email\n",
        "+  def sync_legacy_email\n",
        "+    self.legacy_email = email\n",
        "+  end\n"
      ],
      description: 'before_save callback writing the legacy column from the new one'
    },
    {
      expected_type: 'code dual-write-old-and-new-column',
      paths: ['app/models/order.rb'],
      hunks: [
        "+  before_save :sync_legacy_status\n",
        "+  def sync_legacy_status\n",
        "+    self.legacy_status = status\n",
        "+  end\n"
      ],
      description: 'before_save callback for a different model'
    }
  ].freeze

  CODE_SWITCH_READS_TO_NEW_COLUMN = [
    {
      expected_type: 'code switch-reads-to-new-column',
      paths: ['app/models/user.rb'],
      hunks: [
        "-    where(legacy_email: address)\n",
        "+    where(email: address)\n"
      ],
      description: 'where-clause swap from legacy column to new column'
    },
    {
      expected_type: 'code switch-reads-to-new-column',
      paths: ['app/models/order.rb'],
      hunks: [
        "-  scope :open, -> { where(legacy_status: 'open') }\n",
        "+  scope :open, -> { where(status: 'open') }\n"
      ],
      description: 'scope rewritten from legacy column to new column'
    }
  ].freeze

  CODE_IGNORE_COLUMN_FOR_PENDING_DROP = [
    {
      expected_type: 'code ignore-column-for-pending-drop',
      paths: ['app/models/user.rb'],
      hunks: ["+  self.ignored_columns = %w[legacy_email]\n"],
      description: 'self.ignored_columns assignment with %w[] literal'
    },
    {
      expected_type: 'code ignore-column-for-pending-drop',
      paths: ['app/models/order.rb'],
      hunks: ["+  self.ignored_columns += %w[legacy_status]\n"],
      description: 'self.ignored_columns += append form'
    }
  ].freeze

  CODE_REMOVE_REFERENCES_TO_PENDING_DROP_COLUMN = [
    {
      expected_type: 'code remove-references-to-pending-drop-column',
      paths: ['app/models/user.rb'],
      hunks: [
        "-  attr_accessor :legacy_email\n",
        "-  validates :legacy_email, presence: true\n"
      ],
      description: 'attr_accessor and validates removal for a soon-to-drop column'
    }
  ].freeze

  CODE_REMOVE_IGNORED_COLUMNS_DIRECTIVE = [
    {
      expected_type: 'code remove-ignored-columns-directive',
      paths: ['app/models/user.rb'],
      hunks: ["-  self.ignored_columns = %w[legacy_email]\n"],
      description: 'removal of the ignored_columns directive after drop'
    },
    {
      expected_type: 'code remove-ignored-columns-directive',
      paths: ['app/models/order.rb'],
      hunks: ["-  self.ignored_columns += %w[legacy_status]\n"],
      description: 'removal of the appended ignored_columns directive'
    }
  ].freeze

  # ── feature-flag (config/features/**/*.yml) ──────────────────────────
  #
  # Feature-flag fixtures discriminate by both the YAML file location
  # AND the diff content (introducing a flag vs. flipping `default:` vs.
  # removing the file). The variants below pick alternative flag names
  # so the inference rule's scope (the `config/features/` path glob)
  # is exercised independently of the rule's content discriminator.
  FEATURE_FLAG_CREATE_DEFAULT_OFF = [
    {
      expected_type: 'feature-flag create-default-off',
      paths: ['config/features/new_checkout.yml'],
      hunks: [
        "+name: new_checkout\n",
        "+default: false\n"
      ],
      description: 'new flag file declared with default: false'
    },
    {
      expected_type: 'feature-flag create-default-off',
      paths: ['config/features/payments_v2.yml'],
      hunks: [
        "+name: payments_v2\n",
        "+description: New payments engine, off by default for staged rollout\n",
        "+default: false\n"
      ],
      description: 'new flag file with description and default: false'
    }
  ].freeze

  FEATURE_FLAG_ENABLE = [
    {
      expected_type: 'feature-flag enable',
      paths: ['config/features/new_checkout.yml'],
      hunks: [
        "-default: false\n",
        "+default: true\n"
      ],
      description: 'flip default from false to true'
    }
  ].freeze

  FEATURE_FLAG_REMOVE = [
    {
      expected_type: 'feature-flag remove',
      paths: ['config/features/new_checkout.yml'],
      hunks: [
        "-name: new_checkout\n",
        "-default: true\n"
      ],
      description: 'flag file fully removed after rollout completes'
    }
  ].freeze

  # ── infra (terraform/**/*.tf | config/**/*.yml) ──────────────────────
  #
  # Infra fixtures cover the three-phase pattern Rails+Postgres deploys
  # use for new shared resources (Redis, S3 buckets, queues, …):
  # provision (declare the resource), wire (point the app at it), and
  # decommission (remove the resource after the app no longer uses it).
  INFRA_PROVISION = [
    {
      expected_type: 'infra provision',
      paths: ['terraform/redis.tf'],
      hunks: [
        "+resource \"aws_elasticache_cluster\" \"sessions\" {\n",
        "+  cluster_id = \"sessions\"\n",
        "+}\n"
      ],
      description: 'new terraform resource for a Redis cluster'
    },
    {
      expected_type: 'infra provision',
      paths: ['terraform/s3.tf'],
      hunks: [
        "+resource \"aws_s3_bucket\" \"uploads\" {\n",
        "+  bucket = \"app-uploads\"\n",
        "+}\n"
      ],
      description: 'new terraform resource for an S3 bucket'
    }
  ].freeze

  INFRA_WIRE = [
    {
      expected_type: 'infra wire',
      paths: ['config/cache.yml'],
      hunks: [
        "+production:\n",
        "+  url: <%= ENV['REDIS_URL'] %>\n"
      ],
      description: 'production cache config wired to a new Redis URL'
    },
    {
      expected_type: 'infra wire',
      paths: ['config/storage.yml'],
      hunks: [
        "+amazon:\n",
        "+  service: S3\n",
        "+  bucket: <%= ENV['UPLOADS_BUCKET'] %>\n"
      ],
      description: 'storage config wired to a new S3 bucket'
    }
  ].freeze

  INFRA_DECOMMISSION = [
    {
      expected_type: 'infra decommission',
      paths: ['terraform/redis.tf'],
      hunks: [
        "-resource \"aws_elasticache_cluster\" \"sessions\" {\n",
        "-  cluster_id = \"sessions\"\n",
        "-}\n"
      ],
      description: 'terraform resource removed after migration off Redis'
    }
  ].freeze

  # Aggregate every variant in FR-010 catalog order. Iterating
  # `ALL_FIXTURES` walks the population in the same order the catalog
  # spec at `phaser/spec/flavors/rails_postgres_strong_migrations/
  # catalog_spec.rb` pins, which keeps cross-spec failure messages
  # comparable when a regression touches both surfaces.
  ALL_FIXTURES = [
    *SCHEMA_ADD_NULLABLE_COLUMN,
    *SCHEMA_ADD_COLUMN_WITH_STATIC_DEFAULT,
    *SCHEMA_ADD_TABLE,
    *SCHEMA_ADD_CONCURRENT_INDEX,
    *SCHEMA_ADD_FOREIGN_KEY_WITHOUT_VALIDATION,
    *SCHEMA_VALIDATE_FOREIGN_KEY,
    *SCHEMA_ADD_CHECK_CONSTRAINT_WITHOUT_VALIDATION,
    *SCHEMA_VALIDATE_CHECK_CONSTRAINT,
    *SCHEMA_ADD_VIRTUAL_NOT_NULL_VIA_CHECK,
    *SCHEMA_FLIP_REAL_NOT_NULL_AFTER_CHECK,
    *SCHEMA_CHANGE_COLUMN_DEFAULT,
    *SCHEMA_DROP_COLUMN_WITH_CLEANUP_PRECEDENT,
    *SCHEMA_DROP_TABLE,
    *SCHEMA_DROP_CONCURRENT_INDEX,
    *DATA_BACKFILL_BATCHED,
    *DATA_CLEANUP_BATCHED,
    *CODE_DEFAULT_CATCH_ALL_CHANGE,
    *CODE_DUAL_WRITE_OLD_AND_NEW_COLUMN,
    *CODE_SWITCH_READS_TO_NEW_COLUMN,
    *CODE_IGNORE_COLUMN_FOR_PENDING_DROP,
    *CODE_REMOVE_REFERENCES_TO_PENDING_DROP_COLUMN,
    *CODE_REMOVE_IGNORED_COLUMNS_DIRECTIVE,
    *FEATURE_FLAG_CREATE_DEFAULT_OFF,
    *FEATURE_FLAG_ENABLE,
    *FEATURE_FLAG_REMOVE,
    *INFRA_PROVISION,
    *INFRA_WIRE,
    *INFRA_DECOMMISSION
  ].freeze

  # Every FR-010 task type, in catalog order. Used by the fixture
  # smoke spec to assert the suite covers every required type without
  # gaps, and by future variant-coverage specs to group fixtures by
  # type.
  REQUIRED_TASK_TYPES = [
    'schema add-nullable-column',
    'schema add-column-with-static-default',
    'schema add-table',
    'schema add-concurrent-index',
    'schema add-foreign-key-without-validation',
    'schema validate-foreign-key',
    'schema add-check-constraint-without-validation',
    'schema validate-check-constraint',
    'schema add-virtual-not-null-via-check',
    'schema flip-real-not-null-after-check',
    'schema change-column-default',
    'schema drop-column-with-cleanup-precedent',
    'schema drop-table',
    'schema drop-concurrent-index',
    'data backfill-batched',
    'data cleanup-batched',
    'code default-catch-all-change',
    'code dual-write-old-and-new-column',
    'code switch-reads-to-new-column',
    'code ignore-column-for-pending-drop',
    'code remove-references-to-pending-drop-column',
    'code remove-ignored-columns-directive',
    'feature-flag create-default-off',
    'feature-flag enable',
    'feature-flag remove',
    'infra provision',
    'infra wire',
    'infra decommission'
  ].freeze

  # Build a `Phaser::Commit` from a fixture entry. Mirrors the
  # `build_commit` helper in `inference_spec.rb` so consuming specs can
  # use either fixture population (inline or this richer suite) through
  # the same shape. The synthetic SHA encodes the fixture index so a
  # failure message can point back to the exact entry in `ALL_FIXTURES`.
  def self.build_commit(fixture, index)
    Phaser::Commit.new(
      hash: format('%040d', index + 1),
      subject: "fixture for #{fixture[:expected_type]} (#{fixture[:description]})",
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

  # Group `ALL_FIXTURES` by `expected_type`. Returned as an Array of
  # `[type_name, [fixture, ...]]` pairs in catalog order so a consumer
  # iterating the result sees groups in FR-010 order without an extra
  # sort. Frozen so callers cannot mutate the grouping by accident.
  def self.fixtures_by_type
    grouped = ALL_FIXTURES.group_by { |fixture| fixture[:expected_type] }
    REQUIRED_TASK_TYPES.map { |type_name| [type_name, grouped.fetch(type_name, []).freeze] }.freeze
  end
end
