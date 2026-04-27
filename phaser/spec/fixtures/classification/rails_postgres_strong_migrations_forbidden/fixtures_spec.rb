# frozen_string_literal: true

require 'spec_helper'
require_relative 'fixtures'

# Smoke spec for the `rails-postgres-strong-migrations` forbidden-operation
# fixture set (feature 007-multi-phase-pipeline; T049, FR-015, SC-005,
# SC-015).
#
# T049 ships per-registry-entry commit fixtures plus operator-tag-bypass
# variants the per-identifier regression specs (T044's
# `forbidden_operations_spec.rb`) and the SC-015 bypass spec (T045's
# `operator_tag_cannot_bypass_gate_spec.rb`) consume. Pinning the suite's
# structural integrity here means a future edit that drops a registry
# identifier or breaks a fixture entry surfaces as a clear smoke-test
# failure rather than as a confusing `KeyError` deep inside one of the
# consumer specs.
#
# This spec deliberately does NOT exercise the gate or the engine — that
# is the consumer specs' job. The smoke spec is purely about the fixture
# data's structural integrity (FR-002, SC-002 reproducibility prerequisite).
RSpec.describe 'rails-postgres-strong-migrations forbidden-operation fixture set' do # rubocop:disable RSpec/DescribeClass
  let(:offending_fixtures) do
    RailsPostgresStrongMigrationsForbiddenFixtures::OFFENDING_FIXTURES
  end

  let(:bypass_fixtures) do
    RailsPostgresStrongMigrationsForbiddenFixtures::BYPASS_ATTEMPT_FIXTURES
  end

  let(:required_identifiers) do
    RailsPostgresStrongMigrationsForbiddenFixtures::REQUIRED_FORBIDDEN_IDENTIFIERS
  end

  describe 'FR-015 registry coverage' do
    it 'enumerates exactly seven required forbidden-operation identifiers' do
      expect(required_identifiers.length).to eq(7)
    end

    it 'declares one offending-commit fixture per required identifier' do
      expect(offending_fixtures.keys).to match_array(required_identifiers)
    end

    it 'declares one operator-tag-bypass-attempt fixture per required identifier (SC-015)' do
      expect(bypass_fixtures.keys).to match_array(required_identifiers)
    end
  end

  describe 'offending-commit fixture entry shape' do
    it 'declares :path as a non-empty String for every entry' do
      bad = offending_fixtures.reject { |_id, f| f[:path].is_a?(String) && !f[:path].empty? }
      expect(bad.keys).to eq([]), "fixtures missing/blank :path: #{bad.keys.inspect}"
    end

    it 'declares :hunks as a non-empty Array of non-empty Strings for every entry' do
      bad = offending_fixtures.reject do |_id, f|
        f[:hunks].is_a?(Array) && !f[:hunks].empty? &&
          f[:hunks].all? { |h| h.is_a?(String) && !h.empty? }
      end
      expect(bad.keys).to eq([]), "fixtures with malformed :hunks: #{bad.keys.inspect}"
    end

    it 'declares :safe_replacement_keywords as a non-empty Array of non-empty Strings' do
      bad = offending_fixtures.reject do |_id, f|
        f[:safe_replacement_keywords].is_a?(Array) &&
          !f[:safe_replacement_keywords].empty? &&
          f[:safe_replacement_keywords].all? { |k| k.is_a?(String) && !k.empty? }
      end
      expect(bad.keys).to eq([]),
                          "fixtures with malformed :safe_replacement_keywords: #{bad.keys.inspect}"
    end

    it 'declares :description as a non-empty String for every entry' do
      bad = offending_fixtures.reject { |_id, f| f[:description].is_a?(String) && !f[:description].empty? }
      expect(bad.keys).to eq([]), "fixtures missing/blank :description: #{bad.keys.inspect}"
    end
  end

  describe 'operator-tag-bypass fixture entry shape (SC-015)' do
    it 'declares :path as a non-empty String for every entry' do
      bad = bypass_fixtures.reject { |_id, f| f[:path].is_a?(String) && !f[:path].empty? }
      expect(bad.keys).to eq([]), "bypass fixtures missing/blank :path: #{bad.keys.inspect}"
    end

    it 'declares :hunks as a non-empty Array of non-empty Strings for every entry' do
      bad = bypass_fixtures.reject do |_id, f|
        f[:hunks].is_a?(Array) && !f[:hunks].empty? &&
          f[:hunks].all? { |h| h.is_a?(String) && !h.empty? }
      end
      expect(bad.keys).to eq([]), "bypass fixtures with malformed :hunks: #{bad.keys.inspect}"
    end

    it 'declares :phase_type_tag as a non-empty String for every entry' do
      bad = bypass_fixtures.reject { |_id, f| f[:phase_type_tag].is_a?(String) && !f[:phase_type_tag].empty? }
      expect(bad.keys).to eq([]), "bypass fixtures missing/blank :phase_type_tag: #{bad.keys.inspect}"
    end

    it 'never tags a bypass-attempt fixture with the forbidden identifier itself' do
      bad = bypass_fixtures.select { |id, f| f[:phase_type_tag] == id }
      expect(bad.keys).to eq([]),
                          "bypass-attempt fixtures must use a DIFFERENT task type than the forbidden " \
                          "operation; offenders: #{bad.keys.inspect}"
    end

    it 'reuses the same :path and :hunks shape as the matching offending fixture' do
      # The bypass-attempt commit MUST trip the same detector as the
      # untagged offending commit; the only legitimate difference is the
      # operator tag riding on the commit message. Drift between the two
      # populations would let a regression hide behind "different diff,
      # different result".
      bypass_fixtures.each do |identifier, bypass|
        offending = offending_fixtures.fetch(identifier)
        expect(bypass[:path]).to eq(offending[:path]),
                                 "bypass fixture for #{identifier.inspect} drifted from offending fixture's :path"
        expect(bypass[:hunks]).to eq(offending[:hunks]),
                                  "bypass fixture for #{identifier.inspect} drifted from offending fixture's :hunks"
      end
    end
  end

  describe 'build_offending_commit helper' do
    it 'builds a Phaser::Commit from every offending fixture without raising' do
      required_identifiers.each do |identifier|
        commit = RailsPostgresStrongMigrationsForbiddenFixtures.build_offending_commit(identifier)
        expect(commit).to be_a(Phaser::Commit),
                          "offending fixture for #{identifier.inspect} did not build a Phaser::Commit"
      end
    end

    it 'uses a stable 40-character hash keyed off the identifier' do
      hashes = required_identifiers.map do |identifier|
        RailsPostgresStrongMigrationsForbiddenFixtures.build_offending_commit(identifier).hash
      end
      expect(hashes.uniq.length).to eq(hashes.length)
      expect(hashes.all? { |h| h.is_a?(String) && h.length == 40 }).to be(true)
    end

    it 'builds a commit with NO operator tag (untagged offending case)' do
      required_identifiers.each do |identifier|
        commit = RailsPostgresStrongMigrationsForbiddenFixtures.build_offending_commit(identifier)
        expect(commit.message_trailers).to eq({}),
                                           "offending fixture for #{identifier.inspect} should have no trailers"
      end
    end
  end

  describe 'build_bypass_attempt_commit helper (SC-015)' do
    it 'builds a Phaser::Commit from every bypass fixture without raising' do
      required_identifiers.each do |identifier|
        commit = RailsPostgresStrongMigrationsForbiddenFixtures.build_bypass_attempt_commit(identifier)
        expect(commit).to be_a(Phaser::Commit),
                          "bypass fixture for #{identifier.inspect} did not build a Phaser::Commit"
      end
    end

    it 'attaches a Phase-Type trailer carrying the bypass-attempt task type' do
      required_identifiers.each do |identifier|
        commit = RailsPostgresStrongMigrationsForbiddenFixtures.build_bypass_attempt_commit(identifier)
        expected_tag = bypass_fixtures.fetch(identifier).fetch(:phase_type_tag)
        expect(commit.message_trailers).to eq('Phase-Type' => expected_tag),
                                           "bypass fixture for #{identifier.inspect} carries wrong trailer"
      end
    end

    it 'uses the same stable hash as the offending commit (same root cause, different tag)' do
      required_identifiers.each do |identifier|
        offending_hash = RailsPostgresStrongMigrationsForbiddenFixtures.build_offending_commit(identifier).hash
        bypass_hash = RailsPostgresStrongMigrationsForbiddenFixtures.build_bypass_attempt_commit(identifier).hash
        expect(bypass_hash).to eq(offending_hash),
                               "bypass fixture for #{identifier.inspect} should reuse the offending hash"
      end
    end
  end
end
