# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'open3'
require 'tmpdir'
require 'yaml'
require 'phaser/version'

# Specs for `phaser/bin/phaser` — the standalone command-line entry point
# that wraps `Phaser::Engine#process` for operator-facing invocation
# (feature 007-multi-phase-pipeline; T028/T036, FR-008, FR-041, FR-043,
# contracts/phaser-cli.md).
#
# This file pins the externally observable contract: the synopsis flags
# the binary accepts, the streams it writes to (stdout for the manifest
# path; stderr for JSON-line observability records), the exit codes it
# returns, and the side-effect files it produces in the feature
# directory. Every assertion here is grounded in
# `specs/007-multi-phase-pipeline/contracts/phaser-cli.md`; the test
# does not depend on any internal CLI implementation detail beyond the
# contract.
#
# The CLI is not yet implemented (T036 lands later in the dependency
# chain), so the suite is expected to fail in red until then. That
# matches the constitution's Test-First Development principle: this
# spec is observed failing first, and T036 implements the binary in a
# minimum-viable way to make every example below pass.
#
# Test seams
# ----------
#
# The CLI binary cannot run against a brand-new on-disk flavor directory
# without one of two seams:
#
#   1. The `--flavor <name>` argument resolves against the shipped
#      `phaser/flavors/` tree (the production default, per
#      contracts/phaser-cli.md). At T028 time no flavor is shipped yet
#      (T037 ships `example-minimal`), so this spec cannot rely on a
#      shipped catalog.
#
#   2. An environment variable `PHASER_FLAVORS_ROOT` overrides the
#      `FlavorLoader` default. The variable is the documented seam for
#      hermetic tests (and for fixture repos used by future flavors'
#      end-to-end tests). T036's implementation MUST honor it.
#
# Each example below builds a hermetic flavors root under a temp
# directory, points the CLI at it via the env var, and constructs a
# real Git fixture repo (built by `GitFixtureHelper#make_fixture_repo`)
# so the binary can read commits via `git log`. The fixture repo's
# working directory is the spec's CWD for the subprocess so the CLI
# does not need any flag for "which repo am I in" — it inherits CWD
# the same way it does in production.
RSpec.describe 'phaser CLI' do # rubocop:disable RSpec/DescribeClass
  # Absolute path to the binary under test. Resolved relative to this
  # spec file so the suite runs correctly regardless of the working
  # directory `rspec` is invoked from (the project's CI invokes
  # `cd phaser && bundle exec rspec`, but a single-file run from the
  # repo root must work too).
  let(:phaser_bin) do
    File.expand_path('../../bin/phaser', __dir__)
  end

  # Per-example feature-spec directory. The CLI writes
  # `phase-manifest.yaml` and (on validation failure)
  # `phase-creation-status.yaml` here. A scratch directory keeps writes
  # isolated and lets the suite assert byte-level properties of the
  # produced files.
  attr_reader :feature_dir

  # Per-example flavors root that the test seam (PHASER_FLAVORS_ROOT)
  # points the CLI's FlavorLoader at. Each example writes the flavor
  # catalog it needs into this directory before invoking the binary.
  attr_reader :flavors_root

  # Per-example Git fixture repo — the CLI inherits the subprocess's
  # CWD, so the fixture repo path is also the directory we Open3.spawn
  # the binary from.
  attr_reader :fixture_repo

  around do |example|
    Dir.mktmpdir('phaser-cli-spec-feature') do |feature|
      Dir.mktmpdir('phaser-cli-spec-flavors') do |flavors|
        @feature_dir = feature
        @flavors_root = flavors
        example.run
      end
    end
  end

  after { cleanup_fixture_repos }

  # Write a minimal but schema-valid flavor catalog the CLI's
  # FlavorLoader can parse. The catalog declares two task types
  # (`schema` :alone and `misc` :groups), one inference rule that
  # matches `db/migrate/*.rb`, an empty precedent-rules list, an empty
  # forbidden-operations registry, an empty stack-detection signals
  # list, and a default type of `misc`. This is the same shape used by
  # the engine_spec.rb harness; reusing it keeps the CLI test focused
  # on the binary's contract (streams, exit codes, side effects) rather
  # than on flavor-format edge cases (which `flavor_loader_spec.rb`
  # already covers).
  def write_minimal_flavor(name: 'cli-spec')
    dir = File.join(flavors_root, name)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, 'flavor.yaml'), minimal_flavor_yaml(name))
    name
  end

  def minimal_flavor_yaml(name)
    YAML.dump(
      'name' => name,
      'version' => '0.1.0',
      'default_type' => 'misc',
      'task_types' => [
        { 'name' => 'schema', 'isolation' => 'alone',
          'description' => 'Schema change.' },
        { 'name' => 'misc', 'isolation' => 'groups',
          'description' => 'Catch-all groups type.' }
      ],
      'precedent_rules' => [],
      'inference_rules' => [
        {
          'name' => 'schema-by-path', 'precedence' => 100, 'task_type' => 'schema',
          'match' => { 'kind' => 'file_glob', 'pattern' => 'db/migrate/*.rb' }
        }
      ],
      'forbidden_operations' => [],
      'stack_detection' => { 'signals' => [] }
    )
  end

  # Build a Git fixture repo with a single schema commit. The
  # fixture's `db/migrate/...` path matches the inference rule above
  # so the engine classifies the commit as `schema` (an :alone type)
  # and emits exactly one phase. The fixture's `main` branch is the
  # default integration branch; the feature branch carries the schema
  # commit on top.
  def build_single_commit_fixture
    @fixture_repo = make_fixture_repo('cli-single-commit') do |repo|
      repo.commit(
        subject: 'Add nullable email column',
        files: { 'README.md' => "initial\n" }
      )
      repo.checkout('feature-cli-spec', create: true)
      repo.commit(
        subject: 'Add nullable email_address column',
        files: { 'db/migrate/202604250001_add_email.rb' => "# add email\n" }
      )
    end
  end

  # Run the CLI binary as a subprocess from the fixture repo's working
  # directory with the test seam env var set. Returns
  # `[stdout, stderr, exit_status]`. Every example uses this single
  # entry point so the subprocess invocation pattern stays consistent
  # and the test suite can be audited at a glance for "is the env var
  # set, is the working directory correct".
  def run_cli(*args, env_overrides: {})
    env = { 'PHASER_FLAVORS_ROOT' => flavors_root }.merge(env_overrides)
    Open3.capture3(env, phaser_bin, *args, chdir: fixture_repo)
  end

  describe 'binary surface' do
    it 'is a file at phaser/bin/phaser' do
      expect(File.file?(phaser_bin)).to be(true)
    end

    it 'is executable' do
      expect(File.executable?(phaser_bin)).to be(true)
    end
  end

  describe '--help' do
    before do
      build_single_commit_fixture
      write_minimal_flavor
    end

    it 'exits 0 (per contracts/phaser-cli.md exit-code table)' do
      _stdout, _stderr, status = run_cli('--help')
      expect(status.exitstatus).to eq(0)
    end

    it 'prints usage information naming each documented argument' do
      stdout, _stderr, _status = run_cli('--help')
      %w[--feature-dir --flavor --default-branch --clock --help --version].each do |arg|
        expect(stdout).to include(arg),
                          "expected --help output to mention #{arg}"
      end
    end
  end

  describe '--version' do
    before do
      build_single_commit_fixture
      write_minimal_flavor
    end

    it 'exits 0 (per contracts/phaser-cli.md exit-code table)' do
      _stdout, _stderr, status = run_cli('--version')
      expect(status.exitstatus).to eq(0)
    end

    it 'prints the engine version (Phaser::VERSION) on stdout' do
      stdout, _stderr, _status = run_cli('--version')
      expect(stdout).to include(Phaser::VERSION)
    end
  end

  describe 'successful run' do
    before do
      build_single_commit_fixture
      write_minimal_flavor
    end

    let(:invoke) do
      run_cli(
        '--feature-dir', feature_dir,
        '--flavor', 'cli-spec',
        '--default-branch', 'main',
        '--clock', '2026-04-25T12:00:00.000Z'
      )
    end

    it 'exits 0 (per contracts/phaser-cli.md exit-code table)' do
      _stdout, _stderr, status = invoke
      expect(status.exitstatus).to eq(0)
    end

    it 'writes exactly one line to stdout: the absolute path to the manifest (FR-043)' do
      stdout, _stderr, _status = invoke
      expect(stdout.lines.length).to eq(1)
      expect(stdout.chomp).to eq(File.join(feature_dir, 'phase-manifest.yaml'))
    end

    it 'terminates the stdout line with \n (per contracts/phaser-cli.md stdout section)' do
      stdout, _stderr, _status = invoke
      expect(stdout).to end_with("\n")
    end

    it 'creates the manifest file at <feature-dir>/phase-manifest.yaml' do
      invoke
      expect(File.file?(File.join(feature_dir, 'phase-manifest.yaml'))).to be(true)
    end

    it 'emits at least one JSON-line record on stderr (FR-041)' do
      _stdout, stderr, _status = invoke
      lines = stderr.each_line.to_a
      expect(lines).not_to be_empty
      lines.each do |line|
        expect { JSON.parse(line) }.not_to raise_error,
                                           "expected stderr line to be valid JSON: #{line.inspect}"
      end
    end

    it 'emits a commit-classified INFO record for the schema commit (SC-011)' do
      _stdout, stderr, _status = invoke
      records = stderr.each_line.map { |l| JSON.parse(l) }
      classified = records.select { |r| r['event'] == 'commit-classified' }
      expect(classified.length).to eq(1)
      expect(classified.first['task_type']).to eq('schema')
    end

    it 'emits a phase-emitted INFO record for the resolved phase (SC-011)' do
      _stdout, stderr, _status = invoke
      records = stderr.each_line.map { |l| JSON.parse(l) }
      phase_records = records.select { |r| r['event'] == 'phase-emitted' }
      expect(phase_records.length).to eq(1)
      expect(phase_records.first['phase_number']).to eq(1)
    end

    it 'pins generated_at to the --clock value (SC-002 determinism seam)' do
      invoke
      manifest = YAML.load_file(File.join(feature_dir, 'phase-manifest.yaml'))
      expect(manifest['generated_at']).to eq('2026-04-25T12:00:00.000Z')
    end

    it 'deletes any pre-existing phase-creation-status.yaml on success (FR-040)' do
      stale_status = File.join(feature_dir, 'phase-creation-status.yaml')
      File.write(stale_status, "stage: phaser-engine\nstale: true\n")

      invoke
      expect(File.exist?(stale_status)).to be(false)
    end
  end

  describe 'validation failure (forbidden operation)' do
    # A forbidden-operations registry that rejects any commit touching
    # `db/forbidden/*.rb`. The fixture below carries exactly such a
    # commit so the engine raises ForbiddenOperationError, which the
    # CLI must translate into exit code 1 with a status file written
    # and an empty stdout.
    def write_forbidden_flavor(name: 'cli-spec-forbidden')
      catalog = YAML.safe_load(minimal_flavor_yaml(name))
      catalog['forbidden_operations'] = [{
        'name' => 'direct-column-rename',
        'identifier' => 'direct-column-rename',
        'detector' => { 'kind' => 'file_glob', 'pattern' => 'db/forbidden/*.rb' },
        'decomposition_message' => 'Decompose direct rename into add+dual-write+backfill+switch+drop.'
      }]
      dir = File.join(flavors_root, name)
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, 'flavor.yaml'), YAML.dump(catalog))
      name
    end

    before do
      @fixture_repo = make_fixture_repo('cli-forbidden') do |repo|
        repo.commit(subject: 'init', files: { 'README.md' => "initial\n" })
        repo.checkout('feature-cli-spec-forbidden', create: true)
        repo.commit(
          subject: 'Direct rename forbidden',
          files: { 'db/forbidden/202604250001_rename.rb' => "# rename\n" }
        )
      end
    end

    let(:invoke) do
      run_cli(
        '--feature-dir', feature_dir,
        '--flavor', write_forbidden_flavor,
        '--default-branch', 'main',
        '--clock', '2026-04-25T12:00:00.000Z'
      )
    end

    it 'exits 1 on validation failure (per contracts/phaser-cli.md exit-code table)' do
      _stdout, _stderr, status = invoke
      expect(status.exitstatus).to eq(1)
    end

    it 'writes nothing to stdout on validation failure (FR-043)' do
      stdout, _stderr, _status = invoke
      expect(stdout).to eq('')
    end

    it 'writes a validation-failed ERROR record to stderr (FR-041)' do
      _stdout, stderr, _status = invoke
      records = stderr.each_line.map { |l| JSON.parse(l) }
      failures = records.select { |r| r['event'] == 'validation-failed' }
      expect(failures.length).to eq(1)
      expect(failures.first['failing_rule']).to eq('direct-column-rename')
    end

    it 'writes phase-creation-status.yaml with stage: phaser-engine (FR-042)' do
      invoke
      status_path = File.join(feature_dir, 'phase-creation-status.yaml')
      expect(File.file?(status_path)).to be(true)
      expect(YAML.load_file(status_path)['stage']).to eq('phaser-engine')
    end

    it 'does NOT write a manifest file on validation failure' do
      invoke
      expect(File.exist?(File.join(feature_dir, 'phase-manifest.yaml'))).to be(false)
    end
  end

  describe 'configuration error (unknown flavor)' do
    before do
      build_single_commit_fixture
      # Deliberately do NOT write any flavor under flavors_root.
    end

    let(:invoke) do
      run_cli(
        '--feature-dir', feature_dir,
        '--flavor', 'no-such-flavor',
        '--default-branch', 'main'
      )
    end

    it 'exits 2 on configuration error (per contracts/phaser-cli.md exit-code table)' do
      _stdout, _stderr, status = invoke
      expect(status.exitstatus).to eq(2)
    end

    it 'writes nothing to stdout on configuration error (FR-043)' do
      stdout, _stderr, _status = invoke
      expect(stdout).to eq('')
    end

    it 'does NOT write phase-creation-status.yaml (configuration is not a per-commit failure)' do
      invoke
      expect(File.exist?(File.join(feature_dir, 'phase-creation-status.yaml'))).to be(false)
    end
  end

  describe 'usage error (missing required argument)' do
    before do
      build_single_commit_fixture
      write_minimal_flavor
    end

    it 'exits 64 when --feature-dir is omitted (per contracts/phaser-cli.md exit-code table)' do
      _stdout, _stderr, status = run_cli('--flavor', 'cli-spec')
      expect(status.exitstatus).to eq(64)
    end

    it 'writes nothing to stdout on usage error (FR-043)' do
      stdout, _stderr, _status = run_cli('--flavor', 'cli-spec')
      expect(stdout).to eq('')
    end
  end
end
