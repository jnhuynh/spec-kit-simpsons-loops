# frozen_string_literal: true

require 'phaser'

# Forbidden-operation commit fixtures for the
# `rails-postgres-strong-migrations` reference flavor (feature
# 007-multi-phase-pipeline; T049, FR-015, FR-049, SC-005, SC-015).
#
# This module ships TWO fixture populations keyed off the registry's
# canonical forbidden-operation identifiers (the seven entries FR-015
# enumerates):
#
#   * `OFFENDING_FIXTURES`  — one commit per registry entry whose diff
#                             trips the matching detector, with NO
#                             operator tag. Powers SC-005's
#                             per-identifier regression.
#
#   * `BYPASS_ATTEMPT_FIXTURES` — the same diff as the offending fixture
#                             plus a `Phase-Type:` trailer naming a
#                             different valid task type from FR-010's
#                             catalog. Powers SC-015's
#                             operator-tag-cannot-bypass-gate regression.
#
# Why a single Ruby module instead of inline `let` blocks:
#
#   * The two consumer specs (`forbidden_operations_spec.rb` for T044 and
#     `operator_tag_cannot_bypass_gate_spec.rb` for T045) currently
#     duplicate the per-identifier diff fixtures. Pulling them into one
#     module keeps the two consumer specs in lock-step: a future change
#     to the canonical "smoking gun" diff for `direct-column-rename`
#     happens in one place, not two.
#
#   * Future variant-coverage specs (alternative phrasings of
#     `change_column`, `rename_column` with explicit type, etc.) extend
#     this module rather than the consumer specs, keeping the spec files
#     focused on assertion logic instead of data setup.
#
#   * Mirrors T047's pattern (per-type fixtures for the inference layer
#     consolidated in `phaser/spec/fixtures/classification/
#     rails_postgres_strong_migrations/fixtures.rb`).
#
# Why fixtures live under `phaser/spec/fixtures/classification/<flavor>_forbidden/`
# rather than the same directory as T047's per-type fixtures:
#
#   * The plan.md "Project Structure" pins
#     `phaser/spec/fixtures/classification/` as the per-type / per-rule
#     fixture root. The `_forbidden` suffix matches the tasks.md path
#     (`rails_postgres_strong_migrations_forbidden`) and keeps the
#     forbidden-operation fixtures discoverable next to the per-type
#     fixtures without commingling the two populations.
#
#   * Keeping forbidden-operation fixtures separate from happy-path
#     per-type fixtures prevents a future inference-spec sweep from
#     accidentally classifying the offending diffs as if they were valid
#     production diffs — they are deliberately UNSAFE and would
#     pollute the inference-rate measurement.
#
# Consumption pattern (mirrors T047's module):
#
#   require 'fixtures/classification/rails_postgres_strong_migrations_forbidden/fixtures'
#
#   RailsPostgresStrongMigrationsForbiddenFixtures::REQUIRED_FORBIDDEN_IDENTIFIERS.each do |id|
#     commit = RailsPostgresStrongMigrationsForbiddenFixtures.build_offending_commit(id)
#     # ...assert gate.evaluate(commit) returns the registry entry for `id`
#   end
#
# This module deliberately does NOT auto-load itself from
# `spec/support/` — it is opt-in via explicit `require` so specs that do
# not need the forbidden-operations fixtures are not burdened with
# parsing them.
#
# Determinism contract (FR-002, SC-002):
#
#   * Each per-identifier commit uses a stable, pinned 40-char hex hash
#     so a regression failure's payload (commit_hash) is reproducible
#     across runs and across machines.
#   * The bypass-attempt commit reuses the offending commit's hash so
#     the gate's decision is provably driven by the diff (not the hash).
module RailsPostgresStrongMigrationsForbiddenFixtures
  # Canonical forbidden-operation identifiers FR-015 enumerates.
  # Reproduced verbatim so a registry-level rename has to come through
  # this module, NOT through a silent edit to `flavor.yaml`. The chosen
  # identifier strings mirror the convention pinned by
  # `spec/forbidden_operations_gate_spec.rb` (T022) — kebab-case nouns
  # naming the unsafe operation.
  REQUIRED_FORBIDDEN_IDENTIFIERS = %w[
    direct-column-type-change
    direct-column-rename
    non-concurrent-index
    direct-add-not-null-column
    direct-add-foreign-key
    add-column-with-volatile-default
    drop-column-without-code-cleanup
  ].freeze

  # Per-identifier offending-commit fixtures (no operator tag). Each
  # entry names:
  #
  #   * `:path`  — the file path the offending commit's diff touches.
  #               Chosen so the path-shape (`db/migrate/*.rb`) trips a
  #               detector kind the registry is expected to use for
  #               that identifier (file_glob, path_regex, or
  #               content_regex's path_glob).
  #
  #   * `:hunks` — a one-or-two line excerpt of the unsafe Ruby a real
  #               offending migration would contain. Each excerpt is the
  #               canonical "smoking gun" the registry's detector is
  #               expected to look for. Keeping the hunks minimal makes
  #               failures easy to diff against the flavor's regex.
  #
  #   * `:safe_replacement_keywords` — at least one substring that any
  #               reasonable canonical decomposition message would
  #               contain. The keyword list is intentionally flexible
  #               (case-insensitive, OR semantics — at least one match
  #               required) so consuming specs do NOT pin the prose;
  #               authors can refine wording without breaking the
  #               regression. The keywords ARE pinned where the
  #               replacement-task SEQUENCE is part of the contract
  #               (e.g. "dual-write" + "backfill" + "switch reads"
  #               for column rename).
  #
  #   * `:description` — one-line human-readable summary used in failure
  #               messages and in the "what variant is this?" docs.
  OFFENDING_FIXTURES = {
    'direct-column-type-change' => {
      path: 'db/migrate/20260425000001_change_users_email_to_text.rb',
      hunks: ["@@ -0,0 +1 @@\n+    change_column :users, :email, :text\n"],
      safe_replacement_keywords: ['add column', 'backfill'],
      description: 'change_column on a live column (must decompose into add + dual-write + backfill + drop)'
    },
    'direct-column-rename' => {
      path: 'db/migrate/20260425000002_rename_users_email.rb',
      hunks: ["@@ -0,0 +1 @@\n+    rename_column :users, :email, :email_address\n"],
      safe_replacement_keywords: %w[add dual-write backfill switch drop],
      description: 'rename_column on a live column (must decompose into the seven-phase rename sequence)'
    },
    'non-concurrent-index' => {
      path: 'db/migrate/20260425000003_add_index_users_email.rb',
      hunks: ["@@ -0,0 +1 @@\n+    add_index :users, :email\n"],
      safe_replacement_keywords: %w[concurrently disable_ddl_transaction],
      description: 'add_index without algorithm: :concurrently and disable_ddl_transaction!'
    },
    'direct-add-not-null-column' => {
      path: 'db/migrate/20260425000004_add_required_email_to_users.rb',
      hunks: ["@@ -0,0 +1 @@\n+    add_column :users, :email, :string, null: false\n"],
      safe_replacement_keywords: ['nullable', 'backfill', 'check constraint'],
      description: 'add_column null: false without prior nullable + backfill + validated check'
    },
    'direct-add-foreign-key' => {
      path: 'db/migrate/20260425000005_add_fk_users_to_orgs.rb',
      hunks: ["@@ -0,0 +1 @@\n+    add_foreign_key :users, :orgs\n"],
      safe_replacement_keywords: ['validate:', 'not valid'],
      description: 'add_foreign_key without validate: false followed by validate_foreign_key'
    },
    'add-column-with-volatile-default' => {
      path: 'db/migrate/20260425000006_add_seen_at_to_users.rb',
      hunks: [
        "@@ -0,0 +1 @@\n+    add_column :users, :seen_at, :datetime, " \
        "default: -> { 'now()' }\n"
      ],
      safe_replacement_keywords: %w[without backfill default],
      description: 'add_column with a non-static (volatile) default like now() / lambda'
    },
    'drop-column-without-code-cleanup' => {
      path: 'db/migrate/20260425000007_drop_legacy_email_from_users.rb',
      hunks: ["@@ -0,0 +1 @@\n+    remove_column :users, :legacy_email\n"],
      safe_replacement_keywords: ['ignored_columns', 'remove references'],
      description: 'remove_column without prior ignored_columns directive and reference removal'
    }
  }.freeze

  # Per-identifier operator-tag-bypass fixtures (SC-015). Each entry
  # mirrors the corresponding `OFFENDING_FIXTURES` `:path` and `:hunks`
  # so the same detector trips the same commit; the only difference is
  # the `:phase_type_tag` field naming a VALID FR-010 task type other
  # than the forbidden operation itself — the canonical "I'll just call
  # my direct rename a safe schema add and the safety gate will go
  # away" bypass attempt SC-015 protects against.
  #
  # The chosen `:phase_type_tag` for each identifier is the most
  # plausible cover-story tag an operator would reach for: a "safe"
  # schema or code change in the same broad category as the forbidden
  # operation. Pinning the bypass-attempt tag per-identifier (rather
  # than rotating through the full catalog) keeps consumer-spec failure
  # messages specific without exploding the example count.
  BYPASS_ATTEMPT_FIXTURES = {
    'direct-column-type-change' => {
      path: 'db/migrate/20260425000001_change_users_email_to_text.rb',
      hunks: ["@@ -0,0 +1 @@\n+    change_column :users, :email, :text\n"],
      phase_type_tag: 'schema add-nullable-column'
    },
    'direct-column-rename' => {
      path: 'db/migrate/20260425000002_rename_users_email.rb',
      hunks: ["@@ -0,0 +1 @@\n+    rename_column :users, :email, :email_address\n"],
      phase_type_tag: 'schema add-nullable-column'
    },
    'non-concurrent-index' => {
      path: 'db/migrate/20260425000003_add_index_users_email.rb',
      hunks: ["@@ -0,0 +1 @@\n+    add_index :users, :email\n"],
      phase_type_tag: 'schema add-concurrent-index'
    },
    'direct-add-not-null-column' => {
      path: 'db/migrate/20260425000004_add_required_email_to_users.rb',
      hunks: ["@@ -0,0 +1 @@\n+    add_column :users, :email, :string, null: false\n"],
      phase_type_tag: 'schema add-nullable-column'
    },
    'direct-add-foreign-key' => {
      path: 'db/migrate/20260425000005_add_fk_users_to_orgs.rb',
      hunks: ["@@ -0,0 +1 @@\n+    add_foreign_key :users, :orgs\n"],
      phase_type_tag: 'schema add-foreign-key-without-validation'
    },
    'add-column-with-volatile-default' => {
      path: 'db/migrate/20260425000006_add_seen_at_to_users.rb',
      hunks: [
        "@@ -0,0 +1 @@\n+    add_column :users, :seen_at, :datetime, " \
        "default: -> { 'now()' }\n"
      ],
      phase_type_tag: 'schema add-column-with-static-default'
    },
    'drop-column-without-code-cleanup' => {
      path: 'db/migrate/20260425000007_drop_legacy_email_from_users.rb',
      hunks: ["@@ -0,0 +1 @@\n+    remove_column :users, :legacy_email\n"],
      phase_type_tag: 'schema drop-column-with-cleanup-precedent'
    }
  }.freeze

  # 40-char hex hash deterministically derived from the identifier so
  # every offending-commit fixture's `commit_hash` payload field is
  # reproducible across runs (FR-002, SC-002). The identifier's first
  # character pads the seed so distinct identifiers map to distinct
  # hashes even when their byte-sums collide.
  def self.stable_hash_for(identifier)
    seed = identifier.bytes.sum.to_s(16)
    seed.rjust(40, identifier[0]).slice(0, 40)
  end

  # Build a `Phaser::Commit` whose single `Phaser::FileChange` exercises
  # the registry's detector for `identifier`. No operator tag is
  # attached — this is the untagged offending case T044's spec consumes.
  def self.build_offending_commit(identifier)
    fixture = OFFENDING_FIXTURES.fetch(identifier)
    Phaser::Commit.new(
      hash: stable_hash_for(identifier),
      subject: "Trigger #{identifier}",
      message_trailers: {},
      diff: Phaser::Diff.new(
        files: [
          Phaser::FileChange.new(
            path: fixture.fetch(:path),
            change_kind: :added,
            hunks: fixture.fetch(:hunks)
          )
        ]
      ),
      author_timestamp: '2026-04-25T12:00:00Z'
    )
  end

  # Build a `Phaser::Commit` mirroring `build_offending_commit` but with
  # a `Phase-Type:` trailer naming a different VALID FR-010 task type —
  # the SC-015 operator-tag-bypass attempt. The hash matches the
  # offending commit's hash so consumer specs can prove the gate's
  # decision is driven by the diff, not by the hash.
  def self.build_bypass_attempt_commit(identifier)
    fixture = BYPASS_ATTEMPT_FIXTURES.fetch(identifier)
    Phaser::Commit.new(
      hash: stable_hash_for(identifier),
      subject: "Trigger #{identifier} with operator tag",
      message_trailers: { 'Phase-Type' => fixture.fetch(:phase_type_tag) },
      diff: Phaser::Diff.new(
        files: [
          Phaser::FileChange.new(
            path: fixture.fetch(:path),
            change_kind: :added,
            hunks: fixture.fetch(:hunks)
          )
        ]
      ),
      author_timestamp: '2026-04-25T12:00:00Z'
    )
  end
end
