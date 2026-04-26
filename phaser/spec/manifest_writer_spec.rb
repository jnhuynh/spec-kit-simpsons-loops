# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'open3'
require 'stringio'
require 'tmpdir'
require 'yaml'
require 'phaser'

# Pull in the CLI's GitCommitReader so the end-to-end determinism check
# below (T039) reads commits from the example-minimal fixture repo via
# the same code path the production CLI uses. The bin file is gated by a
# `$PROGRAM_NAME == __FILE__` guard so requiring it here does not
# accidentally invoke the CLI.
require_relative '../bin/phaser'

# Specs for Phaser::ManifestWriter — the stable-key-order YAML emitter
# that serializes a Phaser::PhaseManifest to disk as
# `<FEATURE_DIR>/phase-manifest.yaml` (feature 007-multi-phase-pipeline,
# T014/T015, FR-002, FR-038, SC-002, plan.md "Pattern: Manifest Writer").
#
# The writer is the single load-bearing surface for the engine's
# byte-identical output guarantee. Its contract is narrow but every line
# of it carries a Success Criterion, so the test suite below pins each
# one explicitly:
#
#   1. Byte-identical determinism across 100 consecutive runs (SC-002)
#      — the same `(manifest, path)` pair must produce a byte-identical
#      file every time. The underlying Hash construction MUST be
#      explicitly ordered so Ruby's Hash insertion order does not leak
#      into the YAML output.
#
#   2. Fixed key ordering per the schema (FR-038) — the keys at every
#      level of the YAML document are emitted in the order declared by
#      `contracts/phase-manifest.schema.yaml`, regardless of how the
#      caller's Ruby Hash was ordered.
#
#   3. Atomic write via temp file + rename (quickstart.md "Pattern:
#      Manifest Writer") — the writer MUST NOT leave a partially written
#      file at the destination if an error occurs mid-write. A reader
#      observing the destination path always sees either the previous
#      content or the new complete content, never a half-written file.
#
#   4. Schema-conformant shape — the emitted YAML is a top-level mapping
#      with the five required keys (`flavor_name`, `flavor_version`,
#      `feature_branch`, `generated_at`, `phases`) in declared order,
#      and each phase entry has its seven keys (`number`, `name`,
#      `branch_name`, `base_branch`, `tasks`, `ci_gates`,
#      `rollback_note`) in declared order, and each task entry has its
#      keys in declared order with the optional
#      `safety_assertion_precedents` only present when set.
RSpec.describe Phaser::ManifestWriter do # rubocop:disable RSpec/SpecFilePathFormat
  # The system-under-test: a default-constructed writer. The writer is
  # stateless so a single instance per example is sufficient.
  subject(:writer) { described_class.new }

  # A scratch directory per example so writes are isolated and the
  # `around` hook can reliably clean up. `Dir.mktmpdir` is the standard
  # Ruby idiom for this and matches the pattern used by other specs in
  # this codebase (see spec_helper.rb). The directory is exposed via a
  # plain reader method so the rubocop-rspec InstanceVariable cop stays
  # happy while still letting the surrounding `let` blocks reference it.
  attr_reader :tmp_dir

  around do |example|
    Dir.mktmpdir('phaser-manifest-writer-spec') do |tmp|
      @tmp_dir = tmp
      example.run
    end
  end

  # The destination path the writer writes to. Lives inside the
  # per-example scratch directory so cleanup is automatic.
  let(:destination) { File.join(tmp_dir, 'phase-manifest.yaml') }

  # A canonical task that every fixture phase below references.
  let(:task) do
    Phaser::Task.new(
      id: 'phase-1-task-1',
      task_type: 'schema add-nullable-column',
      commit_hash: 'b' * 40,
      commit_subject: 'Add nullable email_address column'
    )
  end

  # A canonical phase that the single-phase manifest fixture references.
  let(:phase) do
    Phaser::Phase.new(
      number: 1,
      name: 'Schema: add nullable email_address column',
      branch_name: '007-multi-phase-pipeline-phase-1',
      base_branch: 'main',
      tasks: [task],
      ci_gates: %w[rspec rubocop],
      rollback_note: 'Drop the nullable column to revert.'
    )
  end

  # A canonical single-phase manifest used by the basic shape tests.
  let(:manifest) do
    Phaser::PhaseManifest.new(
      flavor_name: 'example-minimal',
      flavor_version: '0.1.0',
      feature_branch: '007-multi-phase-pipeline',
      generated_at: '2026-04-25T12:00:01.123Z',
      phases: [phase]
    )
  end

  describe '#write — basic happy path' do
    it 'writes a YAML file at the destination path' do
      writer.write(manifest, destination)

      expect(File.exist?(destination)).to be(true)
    end

    it 'returns the destination path on success so callers can chain' do
      result = writer.write(manifest, destination)

      expect(result).to eq(destination)
    end

    it 'emits parseable YAML that round-trips to a Hash with the manifest fields' do
      writer.write(manifest, destination)
      parsed = YAML.safe_load_file(destination)

      expect(parsed).to include(
        'flavor_name' => 'example-minimal',
        'flavor_version' => '0.1.0',
        'feature_branch' => '007-multi-phase-pipeline',
        'generated_at' => '2026-04-25T12:00:01.123Z'
      )
    end

    it 'serializes the phases array with one entry per Phase' do
      writer.write(manifest, destination)
      parsed = YAML.safe_load_file(destination)

      expect(parsed['phases'].length).to eq(1)
      expect(parsed['phases'].first).to include(
        'number' => 1,
        'branch_name' => '007-multi-phase-pipeline-phase-1',
        'base_branch' => 'main'
      )
    end

    it 'serializes each task entry with the documented required keys' do
      writer.write(manifest, destination)
      parsed = YAML.safe_load_file(destination)

      expect(parsed['phases'].first['tasks'].first).to include(
        'id' => 'phase-1-task-1',
        'task_type' => 'schema add-nullable-column',
        'commit_hash' => 'b' * 40,
        'commit_subject' => 'Add nullable email_address column'
      )
    end
  end

  describe 'fixed key ordering (FR-038, contracts/phase-manifest.schema.yaml)' do
    # Helper: read the on-disk YAML and return the order in which the
    # given keys appear at the top level. Uses a simple regex scan
    # because the writer's YAML is intentionally flat at the top.
    def top_level_key_order(path)
      File.readlines(path).filter_map do |line|
        match = line.match(/\A([a-z_]+):/)
        match && match[1]
      end
    end

    it 'emits the top-level keys in the schema-declared order' do
      writer.write(manifest, destination)

      expected = %w[flavor_name flavor_version feature_branch generated_at phases]
      observed = top_level_key_order(destination) & expected
      expect(observed).to eq(expected)
    end

    it 'emits the keys inside each phase in the schema-declared order' do
      writer.write(manifest, destination)
      parsed = YAML.safe_load_file(destination)

      expected = %w[number name branch_name base_branch tasks ci_gates rollback_note]
      expect(parsed['phases'].first.keys).to eq(expected)
    end

    it 'emits the required keys inside each task in the schema-declared order' do
      writer.write(manifest, destination)
      parsed = YAML.safe_load_file(destination)

      task_keys = parsed['phases'].first['tasks'].first.keys
      expect(task_keys).to eq(%w[id task_type commit_hash commit_subject])
    end
  end

  # The optional safety_assertion_precedents key needs its own fixtures,
  # so it lives in a focused describe block. The required-key tests above
  # already cover the Task happy path; this section pins the optional
  # behavior. Helpers live in plain methods (not `let`) so the surrounding
  # example group stays under the rubocop-rspec memoized-helpers cap.
  describe 'optional safety_assertion_precedents key (Task schema, FR-018)' do
    def build_drop_column_phase
      Phaser::Phase.new(
        number: 1,
        name: 'Schema: drop email column',
        branch_name: '007-multi-phase-pipeline-phase-1',
        base_branch: 'main',
        tasks: [
          Phaser::Task.new(
            id: 'phase-1-task-1',
            task_type: 'schema drop-column',
            commit_hash: 'b' * 40,
            commit_subject: 'Drop deprecated email column',
            safety_assertion_precedents: ['c' * 40, 'd' * 40]
          )
        ],
        ci_gates: %w[rspec],
        rollback_note: 'Restore the dropped column from backup.'
      )
    end

    def build_manifest_with_precedents
      Phaser::PhaseManifest.new(
        flavor_name: 'rails-postgres-strong-migrations',
        flavor_version: '0.1.0',
        feature_branch: '007-multi-phase-pipeline',
        generated_at: '2026-04-25T12:00:01.123Z',
        phases: [build_drop_column_phase]
      )
    end

    it 'emits the optional safety_assertion_precedents key when the task carries it' do
      writer.write(build_manifest_with_precedents, destination)
      parsed = YAML.safe_load_file(destination)

      task_entry = parsed['phases'].first['tasks'].first
      expect(task_entry['safety_assertion_precedents']).to eq(['c' * 40, 'd' * 40])
    end

    it 'omits the optional safety_assertion_precedents key when the task does not carry it' do
      writer.write(manifest, destination)
      parsed = YAML.safe_load_file(destination)

      task_entry = parsed['phases'].first['tasks'].first
      expect(task_entry).not_to have_key('safety_assertion_precedents')
    end

    it 'places safety_assertion_precedents after the required task keys when present' do
      writer.write(build_manifest_with_precedents, destination)
      parsed = YAML.safe_load_file(destination)

      task_keys = parsed['phases'].first['tasks'].first.keys
      expect(task_keys).to eq(
        %w[id task_type commit_hash commit_subject safety_assertion_precedents]
      )
    end
  end

  describe 'byte-identical determinism (SC-002, FR-002)' do
    # Helper: build a phase 2 fixture used by the ordering test below.
    # Lives in a method (not a `let`) so the surrounding example group
    # stays under the rubocop-rspec memoized-helpers cap.
    def build_phase_two
      task_two = Phaser::Task.new(
        id: 'phase-2-task-1',
        task_type: 'schema add-nullable-column',
        commit_hash: 'e' * 40,
        commit_subject: 'Phase 2 work'
      )
      Phaser::Phase.new(
        number: 2,
        name: 'Schema: phase two',
        branch_name: '007-multi-phase-pipeline-phase-2',
        base_branch: '007-multi-phase-pipeline-phase-1',
        tasks: [task_two],
        ci_gates: %w[rspec],
        rollback_note: 'Revert phase two.'
      )
    end

    # The headline determinism test: 100 consecutive writes against the
    # same input MUST produce a byte-identical file. This is the
    # property that lets reviewers trust that re-running the phaser on
    # the same feature branch is a no-op for the manifest under
    # version control.
    it 'produces a byte-identical file across 100 consecutive runs' do
      writer.write(manifest, destination)
      baseline_bytes = File.binread(destination)

      99.times do |iteration|
        writer.write(manifest, destination)
        observed_bytes = File.binread(destination)

        expect(observed_bytes).to eq(baseline_bytes),
                                  "iteration #{iteration + 2}/100 diverged from baseline"
      end
    end

    # A second writer instance over a fresh destination MUST produce the
    # same bytes as the first writer. This covers the case where the
    # writer carries any per-instance state that could leak into the
    # output (it MUST NOT).
    it 'produces the same bytes from independent writer instances' do
      first_path = File.join(tmp_dir, 'first.yaml')
      second_path = File.join(tmp_dir, 'second.yaml')

      described_class.new.write(manifest, first_path)
      described_class.new.write(manifest, second_path)

      expect(File.binread(first_path)).to eq(File.binread(second_path))
    end

    # The output MUST NOT depend on whether Ruby's Hash interpolation
    # happened to walk in declaration order during this process. We
    # simulate a hostile Hash ordering by constructing a manifest whose
    # phases were inserted in reverse-number order; the writer MUST
    # still emit them in number order.
    it 'emits phases in numeric order regardless of input list order' do
      out_of_order = Phaser::PhaseManifest.new(
        flavor_name: 'example-minimal',
        flavor_version: '0.1.0',
        feature_branch: '007-multi-phase-pipeline',
        generated_at: '2026-04-25T12:00:01.123Z',
        phases: [build_phase_two, phase]
      )

      writer.write(out_of_order, destination)
      parsed = YAML.safe_load_file(destination)

      expect(parsed['phases'].map { |p| p['number'] }).to eq([1, 2])
    end
  end

  describe 'atomic write via temp file + rename (quickstart.md "Pattern: Manifest Writer")' do
    # The writer MUST write to a temporary file first, then rename it
    # over the destination. We assert the property by stubbing
    # File.rename and verifying the destination is untouched until the
    # rename happens.
    it 'writes to a temp file under the destination directory before renaming' do
      destination_dir = File.dirname(destination)
      temp_path_observed = nil

      allow(File).to receive(:rename).and_wrap_original do |original, source, target|
        temp_path_observed = source
        original.call(source, target)
      end

      writer.write(manifest, destination)

      expect(temp_path_observed).not_to be_nil
      expect(File.dirname(temp_path_observed)).to eq(destination_dir)
      expect(temp_path_observed).not_to eq(destination)
    end

    it 'leaves the previous destination intact when the write step raises mid-flight' do
      File.write(destination, "previous: content\n")
      previous_bytes = File.binread(destination)

      # Force the write step to fail. Stub File.rename so even if the
      # writer's serialization succeeds, it cannot replace the
      # destination.
      allow(File).to receive(:rename).and_raise(Errno::EIO, 'simulated failure')

      expect { writer.write(manifest, destination) }.to raise_error(Errno::EIO)
      expect(File.binread(destination)).to eq(previous_bytes)
    end

    it 'cleans up the temp file when the rename step raises' do
      File.write(destination, "previous: content\n")
      destination_dir = File.dirname(destination)

      allow(File).to receive(:rename).and_raise(Errno::EIO, 'simulated failure')

      expect { writer.write(manifest, destination) }.to raise_error(Errno::EIO)

      stragglers = Dir.children(destination_dir).reject do |entry|
        entry == File.basename(destination)
      end
      expect(stragglers).to be_empty,
                            "expected no leftover temp files, found: #{stragglers.inspect}"
    end

    it 'overwrites an existing destination file with the new content' do
      File.write(destination, "stale: content\n")

      writer.write(manifest, destination)

      parsed = YAML.safe_load_file(destination)
      expect(parsed['flavor_name']).to eq('example-minimal')
    end
  end

  describe 'YAML emission flags (Psych.dump line_width: -1, header: false)' do
    # Helpers: build a manifest whose only task carries an unusually long
    # commit subject. Split into two methods so each stays under the
    # rubocop Metrics/MethodLength cap, and live as plain methods (not
    # `let`s) so the surrounding example group stays under the rubocop-rspec
    # memoized-helpers cap.
    def build_long_subject_phase(long_subject)
      task = Phaser::Task.new(
        id: 'phase-1-task-1',
        task_type: 'schema add-nullable-column',
        commit_hash: 'b' * 40,
        commit_subject: long_subject
      )
      Phaser::Phase.new(
        number: 1,
        name: 'Long subject phase',
        branch_name: '007-multi-phase-pipeline-phase-1',
        base_branch: 'main',
        tasks: [task],
        ci_gates: %w[rspec],
        rollback_note: 'Revert.'
      )
    end

    def build_long_subject_manifest(long_subject)
      Phaser::PhaseManifest.new(
        flavor_name: 'example-minimal',
        flavor_version: '0.1.0',
        feature_branch: '007-multi-phase-pipeline',
        generated_at: '2026-04-25T12:00:01.123Z',
        phases: [build_long_subject_phase(long_subject)]
      )
    end

    # The contract for the writer (T015 implementation, plan.md
    # "Pattern: Manifest Writer") is `Psych.dump(hash, line_width: -1,
    # header: false)`. line_width: -1 disables Psych's default
    # 80-column line wrapping (which would make the output sensitive to
    # subject-line lengths and break SC-002 across hosts with different
    # locale settings); header: false suppresses the `---` document
    # marker so the file is a single mapping document.
    it 'does not include the YAML document header (---)' do
      writer.write(manifest, destination)

      first_line = File.readlines(destination).first
      expect(first_line).not_to start_with('---')
    end

    it 'does not wrap long subject lines at 80 columns' do
      long_subject = 'X' * 200

      writer.write(build_long_subject_manifest(long_subject), destination)

      expect(File.read(destination)).to include(long_subject)
    end
  end

  # End-to-end determinism check (feature 007-multi-phase-pipeline; T039,
  # FR-002, SC-002). The earlier 100-iteration test in this file pins the
  # writer's own determinism in isolation; this one drives the full engine
  # pipeline (empty-diff filter → forbidden-ops gate → classifier →
  # precedent validator → size guard → isolation resolver → manifest
  # writer) against the example-minimal Git fixture so we verify the
  # composition is deterministic, not just the writer in isolation.
  #
  # Running the engine 100 times surfaces any nondeterminism leaked by an
  # internal Hash insertion order, a wall-clock read, an ENV-dependent
  # branch, or a filesystem listing order. The clock is pinned via
  # `fixed_clock` so `generated_at` is stable; commits are read from the
  # fixture once and reused across iterations so the assertion isolates
  # "is the engine deterministic on identical inputs" from any drift in
  # the GitCommitReader.
  describe 'end-to-end determinism through the engine (T039, SC-002)' do
    after { cleanup_fixture_repos }

    let(:fixed_clock) { -> { '2026-04-25T12:00:00.000Z' } }

    def example_minimal_flavor
      Phaser::FlavorLoader.new.load('example-minimal')
    end

    # Build the fixture once and read its five commits via the same
    # GitCommitReader the production CLI uses, so the engine sees the
    # exact Phaser::Commit shape the operator-facing path produces. The
    # fixture build is a per-example temp directory; the read happens
    # inside `Dir.chdir` because GitCommitReader inherits the process CWD
    # (matching how the CLI inherits it from the operator's shell).
    def build_and_read_fixture_commits
      repo_path = ExampleMinimalFixture.build(self)
      Dir.chdir(repo_path) do
        reader = Phaser::GitCommitReader.new
        reader.read_commits(ExampleMinimalFixture::DEFAULT_BRANCH)
      end
    end

    # The system-under-test for this block is the full engine pipeline
    # (which happens to terminate in `Phaser::ManifestWriter` — the
    # surrounding spec's described_class). The engine is reconstructed
    # per iteration so any per-instance caching cannot leak across runs
    # and falsely satisfy the byte-identical assertion.
    def build_engine_for(feature_dir)
      Phaser::Engine.new(
        feature_dir: feature_dir,
        feature_branch: ExampleMinimalFixture::FEATURE_BRANCH,
        default_branch: ExampleMinimalFixture::DEFAULT_BRANCH,
        observability: Phaser::Observability.new(stderr: StringIO.new, now: fixed_clock),
        status_writer: Phaser::StatusWriter.new(now: fixed_clock),
        manifest_writer: described_class.new,
        clock: fixed_clock
      )
    end

    # Run the engine once into the given feature_dir and return the
    # bytes of the written manifest. The feature_dir is fresh per call
    # so a stale prior write cannot mask a regression.
    def run_engine_and_capture_bytes(commits, flavor, feature_dir)
      engine = build_engine_for(feature_dir)
      manifest_path = engine.process(commits, flavor)
      File.binread(manifest_path)
    end

    it 'produces byte-identical manifests across 100 consecutive engine runs' do
      commits = build_and_read_fixture_commits
      flavor = example_minimal_flavor

      Dir.mktmpdir('phaser-engine-determinism-baseline') do |baseline_dir|
        baseline_bytes = run_engine_and_capture_bytes(commits, flavor, baseline_dir)

        99.times do |iteration|
          Dir.mktmpdir('phaser-engine-determinism-run') do |run_dir|
            observed_bytes = run_engine_and_capture_bytes(commits, flavor, run_dir)
            expect(observed_bytes).to eq(baseline_bytes),
                                      "iteration #{iteration + 2}/100 diverged from baseline"
          end
        end
      end
    end
  end
end
