# frozen_string_literal: true

require 'phaser'

# Specs for the three commit-side value objects that the phaser engine
# consumes (feature 007-multi-phase-pipeline):
#
#   * Phaser::Commit      — a single Git commit's hash, subject, message
#                           trailers, parsed diff, and author timestamp.
#   * Phaser::Diff        — a list of FileChange entries plus an
#                           `empty?` predicate the FR-009 empty-diff
#                           filter relies on before classification.
#   * Phaser::FileChange  — one entry per file touched by a commit
#                           (path, change kind, hunks).
#
# These objects are the boundary between the Git layer (`bin/phaser`,
# fixture repos) and the pure-Ruby engine. They MUST be:
#
#   1. Constructible with the required fields documented in
#      data-model.md "Commit", "Diff", "FileChange".
#   2. Immutable: `Data.define` instances disallow attribute mutation
#      so the engine can pass them between pipeline stages without
#      defensive copies (plan.md "Project Structure").
#   3. Predicate-correct: `Diff#empty?` returns true exactly when the
#      diff has zero file entries — the precondition for the FR-009
#      empty-diff skip in `Engine#process_commit` (per quickstart.md
#      "Pattern: Pre-Classification Gate Discipline").
RSpec.describe 'commit-side value objects' do # rubocop:disable RSpec/DescribeClass
  describe Phaser::FileChange do
    let(:attributes) do
      {
        path: 'db/migrate/001_add_email_address.rb',
        change_kind: :added,
        hunks: ["@@ -0,0 +1,5 @@\n+class AddEmailAddress < ActiveRecord::Migration\n"]
      }
    end

    it 'constructs from path, change_kind, and hunks' do
      change = described_class.new(**attributes)

      expect(change.path).to eq('db/migrate/001_add_email_address.rb')
      expect(change.change_kind).to eq(:added)
      expect(change.hunks).to eq(attributes[:hunks])
    end

    it 'is frozen / immutable: attempting to mutate an attribute raises' do
      change = described_class.new(**attributes)

      # Data.define instances do not expose writers at all; assigning
      # via `instance_variable_set` is the only way to mutate state and
      # `freeze` (called below) blocks even that. We assert the public
      # surface has no writer for any attribute.
      attributes.each_key do |attr_name|
        expect(change).not_to respond_to("#{attr_name}=")
      end
    end

    it 'requires every documented attribute' do
      expect { described_class.new(path: 'x', change_kind: :added) }
        .to raise_error(ArgumentError, /hunks/)
      expect { described_class.new(change_kind: :added, hunks: []) }
        .to raise_error(ArgumentError, /path/)
      expect { described_class.new(path: 'x', hunks: []) }
        .to raise_error(ArgumentError, /change_kind/)
    end
  end

  describe Phaser::Diff do
    let(:file_change) do
      Phaser::FileChange.new(
        path: 'db/migrate/001_add_email_address.rb',
        change_kind: :added,
        hunks: ['@@ -0,0 +1,1 @@']
      )
    end

    it 'constructs from a list of FileChange entries' do
      diff = described_class.new(files: [file_change])

      expect(diff.files).to eq([file_change])
    end

    it 'is constructible with an empty file list' do
      expect { described_class.new(files: []) }.not_to raise_error
    end

    it 'requires the files attribute' do
      expect { described_class.new }.to raise_error(ArgumentError, /files/)
    end

    it 'has no public attribute writers' do
      diff = described_class.new(files: [file_change])

      expect(diff).not_to respond_to(:files=)
    end

    describe '#empty?' do
      # FR-009: empty-diff commits (merge commits with no conflict
      # resolution, tag-only commits, `--allow-empty` commits) are
      # skipped before classification and do not count toward the
      # FR-048 size bound. The engine relies on this predicate to make
      # that decision.
      it 'returns true when the diff has zero file entries' do
        expect(described_class.new(files: []).empty?).to be(true)
      end

      it 'returns false when the diff has at least one file entry' do
        expect(described_class.new(files: [file_change]).empty?).to be(false)
      end
    end
  end

  describe Phaser::Commit do
    let(:diff) do
      Phaser::Diff.new(
        files: [
          Phaser::FileChange.new(
            path: 'db/migrate/001_add_email_address.rb',
            change_kind: :added,
            hunks: ['@@ -0,0 +1,1 @@']
          )
        ]
      )
    end

    let(:attributes) do
      {
        hash: 'a' * 40,
        subject: 'Add nullable email_address column',
        message_trailers: { 'Phase-Type' => 'schema add-nullable-column' },
        diff: diff,
        author_timestamp: '2026-04-25T00:00:00+00:00'
      }
    end

    it 'constructs from hash, subject, message_trailers, diff, and author_timestamp' do
      commit = described_class.new(**attributes)

      expect(commit.hash).to eq('a' * 40)
      expect(commit.subject).to eq('Add nullable email_address column')
      expect(commit.message_trailers).to eq({ 'Phase-Type' => 'schema add-nullable-column' })
      expect(commit.diff).to be(diff)
      expect(commit.author_timestamp).to eq('2026-04-25T00:00:00+00:00')
    end

    it 'requires every documented attribute' do
      attributes.each_key do |missing|
        partial = attributes.reject { |k, _| k == missing }
        expect { described_class.new(**partial) }
          .to raise_error(ArgumentError, /#{missing}/),
              "expected missing #{missing} to raise ArgumentError"
      end
    end

    it 'has no public attribute writers (immutable value object)' do
      commit = described_class.new(**attributes)

      attributes.each_key do |attr_name|
        expect(commit).not_to respond_to("#{attr_name}=")
      end
    end

    it 'compares equal when all attributes match (Data.define value semantics)' do
      first  = described_class.new(**attributes)
      second = described_class.new(**attributes)

      expect(first).to eq(second)
      expect(first.hash).to eq(second.hash)
    end

    it 'compares unequal when any attribute differs' do
      original = described_class.new(**attributes)
      different_subject = described_class.new(**attributes, subject: 'Different subject')

      expect(original).not_to eq(different_subject)
    end
  end
end
