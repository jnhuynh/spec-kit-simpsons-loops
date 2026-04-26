# frozen_string_literal: true

require 'spec_helper'
require_relative 'fixtures'

# Smoke spec for the `rails-postgres-strong-migrations` per-type
# classification fixture set (feature 007-multi-phase-pipeline; T047,
# FR-010, FR-012).
#
# T047 ships a richer per-type fixture suite than the inline fixture
# set in `phaser/spec/flavors/rails_postgres_strong_migrations/
# inference_spec.rb`. Downstream specs (the inference layer's
# variant-coverage spec under T051, the backfill validator's
# happy-path spec under T053, and any future regression test that
# wants a known-good fixture for a specific task type) consume
# `RailsPostgresStrongMigrationsFixtures::ALL_FIXTURES` and expect:
#
#   1. Every task type FR-010 enumerates is covered by at least one
#      fixture entry (no silently-missing types).
#   2. Every fixture entry is well-shaped (`expected_type`, `paths`,
#      `hunks`, `description` all present and non-empty).
#   3. Every fixture entry can be turned into a `Phaser::Commit` value
#      object via the module's `build_commit` helper without raising.
#
# Pinning these properties here means a future edit to the fixture
# module that breaks one of them surfaces as a clear smoke-test
# failure pointing at the offending entry, rather than as a confusing
# `KeyError` or `NoMethodError` deep inside an inference spec that
# happens to consume the suite.
#
# This spec deliberately does NOT exercise the inference layer
# itself — that is the inference spec's job (T041) and the
# variant-coverage spec's job (a future task under T051). The smoke
# spec is purely about the fixture data's structural integrity.
RSpec.describe 'rails-postgres-strong-migrations classification fixture set' do # rubocop:disable RSpec/DescribeClass
  let(:all_fixtures) { RailsPostgresStrongMigrationsFixtures::ALL_FIXTURES }
  let(:required_task_types) { RailsPostgresStrongMigrationsFixtures::REQUIRED_TASK_TYPES }

  describe 'FR-010 coverage' do
    it 'enumerates exactly 28 required task types (matches catalog_spec.rb)' do
      expect(required_task_types.length).to eq(28)
    end

    it 'covers every required task type with at least one fixture entry' do
      covered_types = all_fixtures.map { |fixture| fixture[:expected_type] }.uniq
      missing = required_task_types - covered_types

      expect(missing).to eq([]),
                        "every FR-010 task type must have at least one fixture entry; missing: #{missing.inspect}"
    end

    it 'never references a task type not declared in REQUIRED_TASK_TYPES' do
      covered_types = all_fixtures.map { |fixture| fixture[:expected_type] }.uniq
      unexpected = covered_types - required_task_types

      expect(unexpected).to eq([]),
                            "fixture set declares unknown task types: #{unexpected.inspect}"
    end
  end

  describe 'fixture entry shape' do
    it 'declares expected_type as a non-empty String for every entry' do
      bad = all_fixtures.reject { |f| f[:expected_type].is_a?(String) && !f[:expected_type].empty? }
      expect(bad).to eq([]), "fixtures missing/blank :expected_type: #{bad.inspect}"
    end

    it 'declares paths as a non-empty Array of non-empty Strings for every entry' do
      bad = all_fixtures.reject do |f|
        f[:paths].is_a?(Array) && !f[:paths].empty? &&
          f[:paths].all? { |p| p.is_a?(String) && !p.empty? }
      end
      expect(bad).to eq([]), "fixtures with malformed :paths: #{bad.map { |f| f[:expected_type] }.inspect}"
    end

    it 'declares hunks as an Array of Strings for every entry (may be empty for path-only matches)' do
      bad = all_fixtures.reject do |f|
        f[:hunks].is_a?(Array) && f[:hunks].all? { |h| h.is_a?(String) }
      end
      expect(bad).to eq([]), "fixtures with malformed :hunks: #{bad.map { |f| f[:expected_type] }.inspect}"
    end

    it 'declares description as a non-empty String for every entry' do
      bad = all_fixtures.reject { |f| f[:description].is_a?(String) && !f[:description].empty? }
      expect(bad).to eq([]), "fixtures missing/blank :description: #{bad.map { |f| f[:expected_type] }.inspect}"
    end
  end

  describe 'build_commit helper' do
    it 'builds a Phaser::Commit from every fixture entry without raising' do
      all_fixtures.each_with_index do |fixture, index|
        commit = RailsPostgresStrongMigrationsFixtures.build_commit(fixture, index)
        expect(commit).to be_a(Phaser::Commit),
                          "fixture #{index} (#{fixture[:expected_type]}) did not build a Phaser::Commit"
      end
    end

    it 'gives every constructed commit a unique 40-character hash' do
      hashes = all_fixtures.each_with_index.map do |fixture, index|
        RailsPostgresStrongMigrationsFixtures.build_commit(fixture, index).hash
      end

      expect(hashes.uniq.length).to eq(hashes.length)
      expect(hashes.all? { |h| h.is_a?(String) && h.length == 40 }).to be(true)
    end

    it 'preserves every fixture path in the constructed commit diff' do
      all_fixtures.each_with_index do |fixture, index|
        commit = RailsPostgresStrongMigrationsFixtures.build_commit(fixture, index)
        diff_paths = commit.diff.files.map(&:path)
        expect(diff_paths).to eq(fixture[:paths]),
                              "fixture #{index} (#{fixture[:expected_type]}) lost paths during build"
      end
    end
  end

  describe 'fixtures_by_type grouping' do
    it 'returns one entry per required task type in catalog order' do
      grouped = RailsPostgresStrongMigrationsFixtures.fixtures_by_type
      expect(grouped.map(&:first)).to eq(required_task_types)
    end

    it 'pairs every required task type with at least one fixture' do
      grouped = RailsPostgresStrongMigrationsFixtures.fixtures_by_type
      empty_types = grouped.select { |(_type, fixtures)| fixtures.empty? }.map(&:first)
      expect(empty_types).to eq([]), "task types with zero fixtures: #{empty_types.inspect}"
    end
  end
end
