# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require 'yaml'
require 'phaser'

# Specs for Phaser::StatusWriter — the writer that persists
# `<FEATURE_DIR>/phase-creation-status.yaml` whenever the phaser engine
# or the stacked-PR creator exits non-zero (feature
# 007-multi-phase-pipeline; T016/T017, FR-039, FR-042, FR-046, FR-047,
# FR-048, SC-013, plan.md "Pattern: Status File Reuse" / D-012).
#
# The writer is the single load-bearing surface for two contracts:
#
#   1. The on-disk YAML matches the schema in
#      `contracts/phase-creation-status.schema.yaml` — the same file is
#      written by two callers (the engine on validation failure, the
#      stacked-PR creator on subprocess failure), each populating a
#      different subset of fields per the schema's cross-field rules.
#
#   2. No string written by this surface — anywhere — may contain
#      credential material (FR-047, SC-013). The writer scans every
#      string-typed payload value against the same credential-pattern
#      list that the observability logger uses; on any match the offender
#      is replaced with the redaction marker before bytes hit disk.
#
# The writer also exposes `delete_if_present(path)` so the engine and
# the stacked-PR creator can clear the status file on a successful
# re-run (FR-040).
RSpec.describe Phaser::StatusWriter do # rubocop:disable RSpec/SpecFilePathFormat
  subject(:writer) { described_class.new(now: -> { fixed_timestamp }) }

  # A scratch directory per example so writes are isolated; mirrors the
  # idiom used by manifest_writer_spec.rb. The directory is exposed via a
  # plain reader so the rubocop-rspec InstanceVariable cop stays happy.
  attr_reader :tmp_dir

  around do |example|
    Dir.mktmpdir('phaser-status-writer-spec') do |tmp|
      @tmp_dir = tmp
      example.run
    end
  end

  let(:destination) { File.join(tmp_dir, 'phase-creation-status.yaml') }
  let(:fixed_timestamp) { '2026-04-25T12:00:00.000Z' }

  describe '#write — happy path stage discriminator' do
    it 'writes a YAML file at the destination path' do
      writer.write(
        destination,
        stage: 'phaser-engine',
        failing_rule: 'precedent'
      )

      expect(File.exist?(destination)).to be(true)
    end

    it 'returns the destination path so callers can chain' do
      result = writer.write(
        destination,
        stage: 'phaser-engine',
        failing_rule: 'precedent'
      )

      expect(result).to eq(destination)
    end

    it 'emits parseable YAML with the stage and timestamp envelope' do
      writer.write(
        destination,
        stage: 'phaser-engine',
        failing_rule: 'precedent'
      )

      parsed = YAML.safe_load_file(destination)
      expect(parsed).to include(
        'stage' => 'phaser-engine',
        'timestamp' => fixed_timestamp,
        'failing_rule' => 'precedent'
      )
    end

    it 'uses the injected clock so callers can pin the timestamp' do
      writer.write(
        destination,
        stage: 'phaser-engine',
        failing_rule: 'precedent'
      )

      parsed = YAML.safe_load_file(destination)
      expect(parsed['timestamp']).to eq(fixed_timestamp)
    end
  end

  describe 'fixed key ordering (contracts/phase-creation-status.schema.yaml)' do
    # Helper: read the on-disk YAML and return the order in which the
    # given keys appear at the top level. Mirrors the helper in
    # manifest_writer_spec.rb so the determinism guarantee is checked
    # the same way for both writers.
    def top_level_key_order(path)
      File.readlines(path).filter_map do |line|
        match = line.match(/\A([a-z_]+):/)
        match && match[1]
      end
    end

    # Helper: write a forbidden-operation failure to the destination so
    # the surrounding ordering test stays under the rubocop-rspec
    # ExampleLength cap. Lives as a plain method (not a `let`) so the
    # surrounding example group stays under the memoized-helpers cap.
    def write_forbidden_operation_failure
      writer.write(
        destination,
        stage: 'phaser-engine',
        failing_rule: 'forbidden-operation',
        commit_hash: 'a' * 40,
        forbidden_operation: 'direct-column-rename',
        decomposition_message: 'Use the four-step rename sequence.'
      )
    end

    it 'emits stage, then timestamp, then the rule-specific fields' do
      write_forbidden_operation_failure

      expected = %w[
        stage
        timestamp
        commit_hash
        failing_rule
        forbidden_operation
        decomposition_message
      ]
      expect(top_level_key_order(destination)).to eq(expected)
    end

    it 'emits stage, then timestamp, then the stacked-PR fields' do
      writer.write(
        destination,
        stage: 'stacked-pr-creation',
        failure_class: 'auth-missing',
        first_uncreated_phase: 1
      )

      observed = top_level_key_order(destination)
      expect(observed).to eq(
        %w[stage timestamp failure_class first_uncreated_phase]
      )
    end

    it 'produces byte-identical output across repeated writes of the same payload' do
      args = {
        stage: 'phaser-engine',
        failing_rule: 'precedent',
        commit_hash: 'a' * 40,
        missing_precedent: 'schema add-nullable-column'
      }

      writer.write(destination, **args)
      baseline = File.binread(destination)

      9.times do |iteration|
        writer.write(destination, **args)
        observed = File.binread(destination)
        expect(observed).to eq(baseline),
                            "iteration #{iteration + 2}/10 diverged from baseline"
      end
    end
  end

  describe 'phaser-engine stage payloads (FR-041, FR-042)' do
    it 'serializes a precedent failure with commit_hash and missing_precedent' do
      writer.write(
        destination,
        stage: 'phaser-engine',
        failing_rule: 'precedent',
        commit_hash: 'a' * 40,
        missing_precedent: 'schema add-nullable-column'
      )

      parsed = YAML.safe_load_file(destination)
      expect(parsed).to include(
        'stage' => 'phaser-engine',
        'failing_rule' => 'precedent',
        'commit_hash' => 'a' * 40,
        'missing_precedent' => 'schema add-nullable-column'
      )
    end

    it 'serializes a forbidden-operation failure with the canonical decomposition message' do
      writer.write(
        destination,
        stage: 'phaser-engine',
        failing_rule: 'forbidden-operation',
        commit_hash: 'b' * 40,
        forbidden_operation: 'direct-column-rename',
        decomposition_message: 'Use the four-step rename sequence.'
      )

      parsed = YAML.safe_load_file(destination)
      expect(parsed).to include(
        'forbidden_operation' => 'direct-column-rename',
        'decomposition_message' => 'Use the four-step rename sequence.'
      )
    end

    it 'serializes a feature-too-large failure with commit_count and phase_count' do
      writer.write(
        destination,
        stage: 'phaser-engine',
        failing_rule: 'feature-too-large',
        commit_count: 250,
        phase_count: 60,
        decomposition_message: 'Split the feature branch.'
      )

      parsed = YAML.safe_load_file(destination)
      expect(parsed).to include(
        'failing_rule' => 'feature-too-large',
        'commit_count' => 250,
        'phase_count' => 60
      )
    end

    it 'omits failure_class and first_uncreated_phase when stage = phaser-engine' do
      writer.write(
        destination,
        stage: 'phaser-engine',
        failing_rule: 'precedent',
        commit_hash: 'a' * 40,
        missing_precedent: 'schema add-nullable-column'
      )

      parsed = YAML.safe_load_file(destination)
      expect(parsed).not_to have_key('failure_class')
      expect(parsed).not_to have_key('first_uncreated_phase')
    end

    it 'omits optional fields the caller did not pass' do
      writer.write(
        destination,
        stage: 'phaser-engine',
        failing_rule: 'precedent'
      )

      parsed = YAML.safe_load_file(destination)
      expect(parsed.keys).to contain_exactly('stage', 'timestamp', 'failing_rule')
    end
  end

  describe 'stacked-pr-creation stage payloads (FR-039, FR-046)' do
    %w[auth-missing auth-insufficient-scope rate-limit network other].each do |failure_class|
      it "serializes the #{failure_class} failure_class with first_uncreated_phase" do
        writer.write(
          destination,
          stage: 'stacked-pr-creation',
          failure_class: failure_class,
          first_uncreated_phase: 3
        )

        parsed = YAML.safe_load_file(destination)
        expect(parsed).to include(
          'stage' => 'stacked-pr-creation',
          'failure_class' => failure_class,
          'first_uncreated_phase' => 3
        )
      end
    end

    it 'omits failing_rule and rule-specific payload when stage = stacked-pr-creation' do
      writer.write(
        destination,
        stage: 'stacked-pr-creation',
        failure_class: 'auth-missing',
        first_uncreated_phase: 1
      )

      parsed = YAML.safe_load_file(destination)
      expect(parsed).not_to have_key('failing_rule')
      expect(parsed).not_to have_key('commit_hash')
      expect(parsed).not_to have_key('missing_precedent')
      expect(parsed).not_to have_key('forbidden_operation')
      expect(parsed).not_to have_key('decomposition_message')
    end
  end

  describe 'cross-field validation enforced by the writer' do
    it 'raises when stage = phaser-engine carries failure_class' do
      expect do
        writer.write(
          destination,
          stage: 'phaser-engine',
          failing_rule: 'precedent',
          failure_class: 'auth-missing'
        )
      end.to raise_error(ArgumentError, /failure_class/)
    end

    it 'raises when stage = phaser-engine carries first_uncreated_phase' do
      expect do
        writer.write(
          destination,
          stage: 'phaser-engine',
          failing_rule: 'precedent',
          first_uncreated_phase: 1
        )
      end.to raise_error(ArgumentError, /first_uncreated_phase/)
    end

    it 'raises when stage = phaser-engine omits failing_rule' do
      expect do
        writer.write(destination, stage: 'phaser-engine', commit_hash: 'a' * 40)
      end.to raise_error(ArgumentError, /failing_rule/)
    end

    it 'raises when stage = stacked-pr-creation omits failure_class' do
      expect do
        writer.write(
          destination,
          stage: 'stacked-pr-creation',
          first_uncreated_phase: 1
        )
      end.to raise_error(ArgumentError, /failure_class/)
    end

    it 'raises when stage = stacked-pr-creation omits first_uncreated_phase' do
      expect do
        writer.write(
          destination,
          stage: 'stacked-pr-creation',
          failure_class: 'auth-missing'
        )
      end.to raise_error(ArgumentError, /first_uncreated_phase/)
    end

    it 'raises when stage is neither phaser-engine nor stacked-pr-creation' do
      expect do
        writer.write(destination, stage: 'mystery-stage', failing_rule: 'precedent')
      end.to raise_error(ArgumentError, /stage/)
    end

    it 'raises when stacked-pr-creation carries an unknown failure_class' do
      expect do
        writer.write(
          destination,
          stage: 'stacked-pr-creation',
          failure_class: 'mystery-class',
          first_uncreated_phase: 1
        )
      end.to raise_error(ArgumentError, /failure_class/)
    end
  end

  describe 'credential-leak guard (FR-047, SC-013)' do
    # The credential patterns are the same set the observability logger
    # protects against; the writer MUST never let a credential-shaped
    # value reach the on-disk YAML. This is the single backstop that
    # keeps tokens out of the status file.
    {
      'GitHub PAT (ghp_)' => 'ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789',
      'GitHub OAuth (gho_)' => 'gho_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789',
      'GitHub user-to-server (ghu_)' => 'ghu_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789',
      'GitHub server-to-server (ghs_)' => 'ghs_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789',
      'GitHub refresh (ghr_)' => 'ghr_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789',
      'Bearer token header' => 'Bearer abc.def.ghi-jkl_mno',
      'Authorization header' => 'Authorization: token ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ',
      'Cookie header' => 'Cookie: session=abc123def456'
    }.each do |label, leaked_value|
      it "redacts a #{label} appearing in a string-typed payload field" do
        writer.write(
          destination,
          stage: 'phaser-engine',
          failing_rule: 'forbidden-operation',
          commit_hash: 'a' * 40,
          forbidden_operation: 'direct-column-rename',
          decomposition_message: "Failed because: #{leaked_value}"
        )

        bytes = File.binread(destination)
        expect(bytes).not_to include(leaked_value)
      end
    end

    it 'replaces credential-shaped string values with the redaction marker' do
      writer.write(
        destination,
        stage: 'phaser-engine',
        failing_rule: 'forbidden-operation',
        commit_hash: 'a' * 40,
        forbidden_operation: 'direct-column-rename',
        decomposition_message: 'leaked: ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
      )

      parsed = YAML.safe_load_file(destination)
      expect(parsed['decomposition_message']).to include('REDACTED')
    end

    it 'leaves non-credential string payload values unchanged' do
      message = 'Use the four-step rename sequence (add → backfill → switch → drop).'

      writer.write(
        destination,
        stage: 'phaser-engine',
        failing_rule: 'forbidden-operation',
        commit_hash: 'a' * 40,
        forbidden_operation: 'direct-column-rename',
        decomposition_message: message
      )

      parsed = YAML.safe_load_file(destination)
      expect(parsed['decomposition_message']).to eq(message)
    end

    it 'leaves integer payload values unchanged' do
      writer.write(
        destination,
        stage: 'stacked-pr-creation',
        failure_class: 'rate-limit',
        first_uncreated_phase: 7
      )

      parsed = YAML.safe_load_file(destination)
      expect(parsed['first_uncreated_phase']).to eq(7)
    end
  end

  describe '#delete_if_present (FR-040)' do
    it 'removes the file when it exists' do
      File.write(destination, "stage: phaser-engine\n")

      writer.delete_if_present(destination)

      expect(File.exist?(destination)).to be(false)
    end

    it 'is a no-op when the file does not exist' do
      expect(File.exist?(destination)).to be(false)

      expect { writer.delete_if_present(destination) }.not_to raise_error
      expect(File.exist?(destination)).to be(false)
    end

    it 'returns the destination path so callers can chain' do
      File.write(destination, "stage: phaser-engine\n")

      expect(writer.delete_if_present(destination)).to eq(destination)
    end
  end

  describe 'atomic write (matches manifest_writer.rb pattern)' do
    it 'writes to a temp file under the destination directory before renaming' do
      destination_dir = File.dirname(destination)
      observed_temp_path = nil

      allow(File).to receive(:rename).and_wrap_original do |original, source, target|
        observed_temp_path = source
        original.call(source, target)
      end

      writer.write(
        destination,
        stage: 'phaser-engine',
        failing_rule: 'precedent'
      )

      expect(observed_temp_path).not_to be_nil
      expect(File.dirname(observed_temp_path)).to eq(destination_dir)
      expect(observed_temp_path).not_to eq(destination)
    end

    it 'leaves the previous destination intact when the rename step raises' do
      File.write(destination, "previous: content\n")
      previous_bytes = File.binread(destination)

      allow(File).to receive(:rename).and_raise(Errno::EIO, 'simulated failure')

      expect do
        writer.write(destination, stage: 'phaser-engine', failing_rule: 'precedent')
      end.to raise_error(Errno::EIO)

      expect(File.binread(destination)).to eq(previous_bytes)
    end

    it 'cleans up the temp file when the rename step raises' do
      File.write(destination, "previous: content\n")
      destination_dir = File.dirname(destination)

      allow(File).to receive(:rename).and_raise(Errno::EIO, 'simulated failure')

      expect do
        writer.write(destination, stage: 'phaser-engine', failing_rule: 'precedent')
      end.to raise_error(Errno::EIO)

      stragglers = Dir.children(destination_dir).reject do |entry|
        entry == File.basename(destination)
      end
      expect(stragglers).to be_empty,
                            "expected no leftover temp files, found: #{stragglers.inspect}"
    end
  end

  describe 'YAML emission flags (matches manifest_writer.rb)' do
    it 'does not include the YAML document header (---)' do
      writer.write(destination, stage: 'phaser-engine', failing_rule: 'precedent')

      first_line = File.readlines(destination).first
      expect(first_line).not_to start_with('---')
    end

    it 'does not wrap long decomposition_message values at 80 columns' do
      long_message = 'X' * 200

      writer.write(
        destination,
        stage: 'phaser-engine',
        failing_rule: 'forbidden-operation',
        commit_hash: 'a' * 40,
        forbidden_operation: 'direct-column-rename',
        decomposition_message: long_message
      )

      expect(File.read(destination)).to include(long_message)
    end
  end
end
