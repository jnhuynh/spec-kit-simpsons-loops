# frozen_string_literal: true

require 'phaser'

# Specs for the shipped `rails-postgres-strong-migrations` flavor's
# task-type catalog at `phaser/flavors/rails-postgres-strong-migrations/
# flavor.yaml` (feature 007-multi-phase-pipeline; T040, T050).
#
# `rails-postgres-strong-migrations` is the reference flavor that
# proves the engine can drive a real-world deploy-safety domain (Rails
# applications backed by Postgres with the strong_migrations gem). The
# catalog completeness contract pinned here is the externally visible
# checklist FR-010 enumerates, plus FR-011's isolation discipline.
# Authors editing the flavor must keep this spec green so that:
#
#   1. No catalog entry FR-010 names is silently dropped or renamed
#      (the per-type fixture suite in T047 and the column-rename worked
#      example in T046 both cite these names).
#   2. Every shipped catalog entry declares an isolation value the
#      engine can reason about — concretely one of the two enum members
#      (`:alone` or `:groups`) `Phaser::IsolationResolver` recognises;
#      any other value would be rejected by `FlavorCatalogValidator`
#      anyway, but pinning it here makes the contract explicit so a
#      future schema change cannot quietly broaden the surface.
#
# This spec deliberately does NOT pin the per-type isolation choice
# (`schema add-nullable-column` → `:alone` vs `:groups`, etc.). That
# decision belongs to the flavor author (T050) and is verified
# behaviourally by the column-rename worked example (T046, FR-017,
# SC-001), which would fail if any of the seven phase-emitting types
# were misclassified as `:groups`. Keeping the per-type isolation out
# of this spec preserves a single source of truth and avoids two
# parallel checklists drifting apart.
#
# The spec MUST observe failure (red) before T050 authors `flavor.yaml`
# (the test-first requirement in CLAUDE.md "Test-First Development"),
# and it MUST go green once T050 ships the catalog with all 28 entries
# from FR-010.
RSpec.describe 'rails-postgres-strong-migrations flavor catalog' do # rubocop:disable RSpec/DescribeClass
  # Canonical task-type names enumerated by FR-010 (spec.md). The list
  # is reproduced here verbatim — in the canonical "category verb-noun"
  # form already used by the example-minimal flavor's `schema` /
  # `misc` types and by the `Phase-Type:` trailer example in
  # data-model.md ("Phase-Type: schema add-nullable-column"). Any
  # rename here MUST be accompanied by a corresponding rename in
  # `flavor.yaml`, in `inference.rb`'s rule-to-type mapping, and in
  # every fixture under `spec/fixtures/classification/
  # rails_postgres_strong_migrations*/`. Keeping the names in one place
  # makes that fan-out reviewable in a single diff.
  let(:required_task_types) do
    [
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
  end

  # The two enum members `Phaser::IsolationResolver` and
  # `Phaser::FlavorCatalogValidator` recognise (FR-005, FR-011, and the
  # `enum: [alone, groups]` clause in `contracts/flavor.schema.yaml`).
  # Any other value is a contract violation regardless of which path
  # the catalog took to ship it.
  let(:valid_isolation_values) { %i[alone groups].freeze }

  let(:flavor_path) do
    File.expand_path(
      '../../../flavors/rails-postgres-strong-migrations/flavor.yaml',
      __dir__
    )
  end

  let(:flavor) do
    Phaser::FlavorLoader.new.load('rails-postgres-strong-migrations')
  end

  it 'ships at phaser/flavors/rails-postgres-strong-migrations/flavor.yaml' do
    expect(File.file?(flavor_path)).to be(true)
  end

  it 'loads as a Phaser::Flavor via the production FlavorLoader' do
    expect(flavor).to be_a(Phaser::Flavor)
  end

  it 'declares the canonical name and a semver version' do
    expect(flavor.name).to eq('rails-postgres-strong-migrations')
    expect(flavor.version).to match(/\A\d+\.\d+\.\d+\z/)
  end

  it 'declares default_type as a name present in task_types (FR-004 cascade target)' do
    type_names = flavor.task_types.map(&:name)

    expect(type_names).to include(flavor.default_type)
  end

  describe 'FR-010 catalog completeness' do
    it 'declares every task type FR-010 enumerates' do
      shipped_names = flavor.task_types.map(&:name)

      expect(shipped_names).to include(*required_task_types)
    end

    # Each entry in FR-010 names a single deploy-safety category, so the
    # catalog MUST NOT split one entry into two collisions. Asserting
    # uniqueness here catches a class of catalog-edit bugs (typo'd copy,
    # accidental duplication during a rename) that the engine itself
    # would silently tolerate by picking the first match.
    it 'declares each task type exactly once (no duplicate entries)' do
      shipped_names = flavor.task_types.map(&:name)

      expect(shipped_names).to eq(shipped_names.uniq)
    end
  end

  describe 'FR-011 isolation discipline' do
    it 'declares an isolation value for every required task type' do
      by_name = flavor.task_types.to_h { |t| [t.name, t] }

      required_task_types.each do |required_name|
        task_type = by_name.fetch(required_name) do
          raise "FR-010 task type #{required_name.inspect} missing from catalog"
        end

        expect(valid_isolation_values).to include(task_type.isolation),
                                          "expected #{required_name.inspect} isolation to be one of " \
                                          "#{valid_isolation_values.inspect}, got #{task_type.isolation.inspect}"
      end
    end

    it 'declares isolation as one of [:alone, :groups] for every shipped task type' do
      shipped_isolations = flavor.task_types.map(&:isolation).uniq

      expect(shipped_isolations - valid_isolation_values).to eq([])
    end

    it 'attaches a human-readable description to every required task type ' \
       '(surfaced in error messages and the manifest per data-model.md)' do
      by_name = flavor.task_types.to_h { |t| [t.name, t] }

      required_task_types.each do |required_name|
        next unless by_name.key?(required_name)

        description = by_name.fetch(required_name).description
        expect(description).to be_a(String).and(satisfy { |d| !d.strip.empty? }),
                               "expected #{required_name.inspect} to ship a non-empty description"
      end
    end
  end
end
