# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'json'
require 'open3'
require 'tmpdir'
require 'yaml'
require 'phaser/version'

# Specs for `phaser/bin/phaser-stacked-prs` — the standalone command-line
# entry point that wraps `Phaser::StackedPrs::AuthProbe` +
# `Phaser::StackedPrs::Creator` for operator-facing invocation
# (feature 007-multi-phase-pipeline; T069/T076, FR-026..FR-030, FR-039,
# FR-040, FR-044..FR-047, contracts/stacked-pr-creator-cli.md).
#
# This file pins the externally observable contract: the synopsis flags
# the binary accepts, the streams it writes to (stdout for the JSON run
# summary on success; stderr for JSON-line observability records), the
# exit codes it returns, and the side-effect files it produces in the
# feature directory. Every assertion here is grounded in
# `specs/007-multi-phase-pipeline/contracts/stacked-pr-creator-cli.md`;
# the test does not depend on any internal CLI implementation detail
# beyond the contract.
#
# The CLI is not yet implemented (T076 lands later in the dependency
# chain), so the suite is expected to fail in red until then. That
# matches the constitution's Test-First Development principle: this
# spec is observed failing first, and T076 implements the binary in a
# minimum-viable way to make every example below pass.
#
# Test seams
# ----------
#
# The CLI binary cannot run a real `gh` subprocess in CI without an
# authenticated GitHub host, so the spec uses two seams:
#
#   1. A `PHASER_GH_BIN` environment variable overrides the binary the
#      `Phaser::StackedPrs::GitHostCli` wrapper invokes. Each example
#      writes a tiny shell script that records its arguments to a log
#      file and prints scripted stdout/stderr with a configured exit
#      code. This is the documented seam for hermetic CLI tests.
#
#   2. The CLI accepts `--feature-dir <path>` per the contract; the
#      spec writes a synthetic `phase-manifest.yaml` into a temp dir
#      and points the CLI at it. The CLI also writes
#      `phase-creation-status.yaml` into the same directory on failure.
#
# Each example below builds a hermetic feature directory and a hermetic
# fake-gh script, points the CLI at both via the documented seams, and
# asserts a single contract property. The fake-gh log lets the spec
# observe the exact `gh` argument vectors the CLI emits without
# binding to GitHostCli's internal Open3 invocation pattern.
RSpec.describe 'phaser-stacked-prs CLI' do # rubocop:disable RSpec/DescribeClass
  # Absolute path to the binary under test. Resolved relative to this
  # spec file so the suite runs correctly regardless of the working
  # directory `rspec` is invoked from (the project's CI invokes
  # `cd phaser && bundle exec rspec`, but a single-file run from the
  # repo root must work too).
  let(:phaser_stacked_prs_bin) do
    File.expand_path('../../bin/phaser-stacked-prs', __dir__)
  end

  # Per-example feature-spec directory. The CLI reads
  # `phase-manifest.yaml` and (on failure) writes
  # `phase-creation-status.yaml` here. A scratch directory keeps writes
  # isolated and lets the suite assert byte-level properties of the
  # produced files.
  attr_reader :feature_dir

  # Per-example fake-gh script directory. The CLI's `PHASER_GH_BIN`
  # seam points the GitHostCli wrapper at this script so each test can
  # script the gh outcome it needs without touching the real `gh`.
  attr_reader :gh_dir

  # Path the fake-gh script appends each invocation's argv to (one
  # JSON object per line). The spec parses this log to assert the CLI
  # invoked gh with the expected argument vectors and in the expected
  # order.
  attr_reader :gh_log_path

  around do |example|
    Dir.mktmpdir('phaser-stacked-prs-spec-feature') do |feature|
      Dir.mktmpdir('phaser-stacked-prs-spec-gh') do |gh|
        @feature_dir = feature
        @gh_dir = gh
        @gh_log_path = File.join(gh, 'gh-invocations.log')
        example.run
      end
    end
  end

  # Build a fake `gh` script that records its argv to `gh_log_path` and
  # responds based on a small lookup table. Each entry in the table is
  # a Hash with `match` (a substring tested against the JSON-encoded
  # argv), `stdout`, `stderr`, and `exitstatus` keys. The first match
  # wins; the catch-all entry returns exit 0 with empty output.
  #
  # Why a shell script rather than stubbing inside Ruby: the CLI runs
  # in a child process, so we cannot stub `Open3.capture3` from this
  # process. The script is the test seam GitHostCli's PHASER_GH_BIN
  # contract documents (T072). The script is also the simplest way to
  # observe the exact argv the CLI emits — JSON-encode the argv,
  # append it to the log, then exit with the scripted status.
  def write_fake_gh(scripts)
    script_path = File.join(gh_dir, 'gh')
    table_path = File.join(gh_dir, 'gh-script-table.json')
    File.write(table_path, JSON.generate(scripts))
    File.write(script_path, fake_gh_source(table_path))
    File.chmod(0o755, script_path)
    script_path
  end

  # The fake-gh script body. Written in /usr/bin/env ruby so the test
  # does not depend on jq, awk, or any other tool not guaranteed to be
  # present. The script reads its scripted-response table from the JSON
  # file written by `write_fake_gh`, finds the first matching entry,
  # writes stdout/stderr, appends an audit-log line, and exits.
  def fake_gh_source(table_path)
    <<~RUBY
      #!/usr/bin/env ruby
      require 'json'
      argv = ARGV.dup
      File.open(#{gh_log_path.inspect}, 'a') do |f|
        f.puts(JSON.generate({ 'argv' => argv }))
      end
      table = JSON.parse(File.read(#{table_path.inspect}))
      # The match column is a substring searched against BOTH the
      # space-joined argv form (so an entry like "auth status" matches
      # ARGV ["auth", "status"]) AND the JSON-serialised argv form (so
      # an entry like "ref=refs/heads/..." matches a single argv token
      # carrying that literal substring). Searching both forms keeps
      # the test fixture's match column human-readable while still
      # supporting matchers that target a single argv element verbatim.
      argv_joined = argv.join(' ')
      argv_json = JSON.generate(argv)
      match = table.find do |entry|
        needle = entry['match'].to_s
        argv_joined.include?(needle) || argv_json.include?(needle)
      end
      match ||= { 'stdout' => '', 'stderr' => '', 'exitstatus' => 0 }
      $stdout.write(match['stdout']) if match['stdout']
      $stderr.write(match['stderr']) if match['stderr']
      exit(match['exitstatus'].to_i)
    RUBY
  end

  # Read the gh-invocations log written by the fake-gh script. Returns
  # an Array of argv-Arrays, one per gh invocation, in order.
  def gh_invocations
    return [] unless File.file?(gh_log_path)

    File.readlines(gh_log_path).map { |line| JSON.parse(line.chomp).fetch('argv') }
  end

  # Write a synthetic N-phase manifest to disk so the CLI has something
  # to read. The manifest follows the schema from
  # contracts/phase-manifest.schema.yaml so we exercise the production
  # read path, not a stripped-down stub.
  def write_manifest(phase_count: 2, feature_branch: 'feat-007-multi-phase-pipeline',
                     default_branch: 'main')
    phases = (1..phase_count).map { |n| build_phase_hash(n, feature_branch, default_branch) }
    manifest = {
      'flavor_name' => 'example-minimal',
      'flavor_version' => '0.1.0',
      'feature_branch' => feature_branch,
      'generated_at' => '2026-04-25T12:00:00.000Z',
      'phases' => phases
    }
    File.write(File.join(feature_dir, 'phase-manifest.yaml'), YAML.dump(manifest))
  end

  # Build one phase Hash for `write_manifest`. Extracted so the
  # surrounding method stays under the community-default Metrics
  # method-length budget.
  def build_phase_hash(number, feature_branch, default_branch)
    {
      'number' => number,
      'name' => "Phase #{number}: example task",
      'branch_name' => "#{feature_branch}-phase-#{number}",
      'base_branch' => number == 1 ? default_branch : "#{feature_branch}-phase-#{number - 1}",
      'tasks' => [{
        'id' => "phase-#{number}-task-1",
        'task_type' => 'example task',
        'commit_hash' => format('%040x', number),
        'commit_subject' => "Example commit for phase #{number}"
      }],
      'ci_gates' => [],
      'rollback_note' => "Rollback guidance for phase #{number}."
    }
  end

  # Default scripted-gh table for a happy-path 2-phase manifest run. The
  # entries cover, in this order:
  #
  #   1. `gh auth status` — authenticated with `repo` scope.
  #   2. Branch existence queries — both phases report 404 (not yet
  #      created).
  #   3. PR existence queries — both phases report empty list.
  #   4. Branch creation — both phases succeed.
  #   5. PR creation — both phases succeed; PR numbers 101 and 102.
  def happy_path_gh_table
    [
      { 'match' => 'auth status',
        'stderr' => "github.com\n  Logged in to github.com as alice (oauth_token)\n  " \
                    "Token scopes: 'repo', 'workflow'\n",
        'exitstatus' => 0 },
      { 'match' => 'branches/feat-007-multi-phase-pipeline-phase-1',
        'stdout' => '', 'stderr' => 'gh: Not Found (HTTP 404)', 'exitstatus' => 1 },
      { 'match' => 'branches/feat-007-multi-phase-pipeline-phase-2',
        'stdout' => '', 'stderr' => 'gh: Not Found (HTTP 404)', 'exitstatus' => 1 },
      { 'match' => 'pr list', 'stdout' => '[]', 'exitstatus' => 0 },
      { 'match' => 'ref=refs/heads/feat-007-multi-phase-pipeline-phase-1',
        'stdout' => '{"ref":"refs/heads/feat-007-multi-phase-pipeline-phase-1"}',
        'exitstatus' => 0 },
      { 'match' => 'ref=refs/heads/feat-007-multi-phase-pipeline-phase-2',
        'stdout' => '{"ref":"refs/heads/feat-007-multi-phase-pipeline-phase-2"}',
        'exitstatus' => 0 },
      { 'match' => 'pr create',
        'stdout' => "https://github.com/owner/repo/pull/100\n", 'exitstatus' => 0 }
    ]
  end

  # Run the CLI binary as a subprocess with the test seams configured.
  # Returns `[stdout, stderr, exit_status]`. Every example uses this
  # single entry point so the subprocess invocation pattern stays
  # consistent and the test suite can be audited at a glance for "is
  # the env var set, is the working directory correct".
  def run_cli(*args, env_overrides: {})
    env = {
      'PHASER_GH_BIN' => File.join(gh_dir, 'gh'),
      'PATH' => "#{gh_dir}:#{ENV.fetch('PATH', '')}"
    }.merge(env_overrides)
    Open3.capture3(env, phaser_stacked_prs_bin, *args)
  end

  describe 'binary surface' do
    it 'is a file at phaser/bin/phaser-stacked-prs' do
      expect(File.file?(phaser_stacked_prs_bin)).to be(true)
    end

    it 'is executable' do
      expect(File.executable?(phaser_stacked_prs_bin)).to be(true)
    end
  end

  describe '--help' do
    before { write_fake_gh([]) }

    it 'exits 0 (per contracts/stacked-pr-creator-cli.md exit-code table)' do
      _stdout, _stderr, status = run_cli('--help')
      expect(status.exitstatus).to eq(0)
    end

    it 'prints usage information naming each documented argument' do
      stdout, _stderr, _status = run_cli('--help')
      %w[--feature-dir --remote --help --version].each do |arg|
        expect(stdout).to include(arg),
                          "expected --help output to mention #{arg}"
      end
    end
  end

  describe '--version' do
    before { write_fake_gh([]) }

    it 'exits 0 (per contracts/stacked-pr-creator-cli.md exit-code table)' do
      _stdout, _stderr, status = run_cli('--version')
      expect(status.exitstatus).to eq(0)
    end

    it 'prints the engine version (Phaser::VERSION) on stdout' do
      stdout, _stderr, _status = run_cli('--version')
      expect(stdout).to include(Phaser::VERSION)
    end
  end

  describe 'successful run (happy path)' do
    before do
      write_manifest(phase_count: 2)
      write_fake_gh(happy_path_gh_table)
    end

    let(:invoke) { run_cli('--feature-dir', feature_dir) }

    it 'exits 0 (per contracts/stacked-pr-creator-cli.md exit-code table)' do
      _stdout, _stderr, status = invoke
      expect(status.exitstatus).to eq(0)
    end

    it 'writes exactly one line to stdout: a JSON run summary (per contract stdout section)' do
      stdout, _stderr, _status = invoke
      expect(stdout.lines.length).to eq(1)
      expect { JSON.parse(stdout) }.not_to raise_error
    end

    it 'includes phases_created, phases_skipped_existing, and manifest in the JSON summary' do
      stdout, _stderr, _status = invoke
      summary = JSON.parse(stdout)
      expect(summary).to include('phases_created', 'phases_skipped_existing', 'manifest')
    end

    it 'reports both phases in phases_created on a fresh run' do
      stdout, _stderr, _status = invoke
      summary = JSON.parse(stdout)
      expect(summary['phases_created']).to eq([1, 2])
    end

    it 'reports an empty phases_skipped_existing on a fresh run' do
      stdout, _stderr, _status = invoke
      summary = JSON.parse(stdout)
      expect(summary['phases_skipped_existing']).to eq([])
    end

    it 'records the manifest path in the JSON summary' do
      stdout, _stderr, _status = invoke
      summary = JSON.parse(stdout)
      expect(summary['manifest']).to eq(File.join(feature_dir, 'phase-manifest.yaml'))
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

    it 'emits an auth-probe-result INFO record (per observability-events.md)' do
      _stdout, stderr, _status = invoke
      records = stderr.each_line.map { |l| JSON.parse(l) }
      probes = records.select { |r| r['event'] == 'auth-probe-result' }
      expect(probes.length).to eq(1)
      expect(probes.first['authenticated']).to be(true)
    end

    it 'emits one phase-branch-created INFO record per phase' do
      _stdout, stderr, _status = invoke
      records = stderr.each_line.map { |l| JSON.parse(l) }
      branch_records = records.select { |r| r['event'] == 'phase-branch-created' }
      expect(branch_records.length).to eq(2)
    end

    it 'emits one phase-pr-created INFO record per phase' do
      _stdout, stderr, _status = invoke
      records = stderr.each_line.map { |l| JSON.parse(l) }
      pr_records = records.select { |r| r['event'] == 'phase-pr-created' }
      expect(pr_records.length).to eq(2)
    end

    it 'invokes `gh auth status` exactly once (FR-045)' do
      invoke
      auth_calls = gh_invocations.select { |argv| argv.first == 'auth' && argv[1] == 'status' }
      expect(auth_calls.length).to eq(1)
    end

    it 'deletes any pre-existing phase-creation-status.yaml on success (FR-040)' do
      stale_status = File.join(feature_dir, 'phase-creation-status.yaml')
      File.write(stale_status, "stage: stacked-pr-creation\nstale: true\n")

      invoke
      expect(File.exist?(stale_status)).to be(false)
    end
  end

  describe 'authentication failure (auth-missing)' do
    before do
      write_manifest(phase_count: 2)
      write_fake_gh([
                      { 'match' => 'auth status',
                        'stderr' => "You are not logged into any GitHub hosts.\n",
                        'exitstatus' => 1 }
                    ])
    end

    let(:invoke) { run_cli('--feature-dir', feature_dir) }

    it 'exits 2 on authentication failure (per contract exit-code table)' do
      _stdout, _stderr, status = invoke
      expect(status.exitstatus).to eq(2)
    end

    it 'writes nothing to stdout on authentication failure (FR-043)' do
      stdout, _stderr, _status = invoke
      expect(stdout).to eq('')
    end

    it 'writes phase-creation-status.yaml with failure_class=auth-missing (FR-045, SC-012)' do
      invoke
      status_path = File.join(feature_dir, 'phase-creation-status.yaml')
      expect(File.file?(status_path)).to be(true)
      parsed = YAML.safe_load_file(status_path)
      expect(parsed).to include(
        'stage' => 'stacked-pr-creation',
        'failure_class' => 'auth-missing',
        'first_uncreated_phase' => 1
      )
    end

    it 'never queries gh for branches before failing (SC-012 fail-fast)' do
      invoke
      branch_calls = gh_invocations.select { |argv| argv.first == 'api' && argv.any? { |a| a.include?('branches/') } }
      expect(branch_calls).to be_empty
    end
  end

  describe 'stacked-PR creation failure (network) mid-run' do
    # Simulate a 3-phase manifest where phase 1 succeeds and phase 2's
    # branch creation fails with a network-class error. The CLI MUST
    # exit 1 with a status file recording first_uncreated_phase=2.
    before do
      write_manifest(phase_count: 3)
      write_fake_gh([
                      { 'match' => 'auth status',
                        'stderr' => "github.com\n  Logged in to github.com as alice (oauth_token)\n  " \
                                    "Token scopes: 'repo', 'workflow'\n",
                        'exitstatus' => 0 },
                      { 'match' => 'branches/feat-007-multi-phase-pipeline-phase-1',
                        'stderr' => 'gh: Not Found (HTTP 404)', 'exitstatus' => 1 },
                      { 'match' => 'branches/feat-007-multi-phase-pipeline-phase-2',
                        'stderr' => 'gh: Not Found (HTTP 404)', 'exitstatus' => 1 },
                      { 'match' => 'pr list', 'stdout' => '[]', 'exitstatus' => 0 },
                      { 'match' => 'ref=refs/heads/feat-007-multi-phase-pipeline-phase-1',
                        'stdout' => '{"ref":"refs/heads/feat-007-multi-phase-pipeline-phase-1"}',
                        'exitstatus' => 0 },
                      { 'match' => 'ref=refs/heads/feat-007-multi-phase-pipeline-phase-2',
                        'stderr' => 'dial tcp: lookup api.github.com: no such host',
                        'exitstatus' => 1 },
                      { 'match' => 'pr create',
                        'stdout' => "https://github.com/owner/repo/pull/101\n",
                        'exitstatus' => 0 }
                    ])
    end

    let(:invoke) { run_cli('--feature-dir', feature_dir) }

    it 'exits 1 on stacked-PR creation failure (per contract exit-code table)' do
      _stdout, _stderr, status = invoke
      expect(status.exitstatus).to eq(1)
    end

    it 'writes nothing to stdout on stacked-PR creation failure (FR-043)' do
      stdout, _stderr, _status = invoke
      expect(stdout).to eq('')
    end

    it 'writes phase-creation-status.yaml with stage=stacked-pr-creation (FR-039)' do
      invoke
      status_path = File.join(feature_dir, 'phase-creation-status.yaml')
      expect(File.file?(status_path)).to be(true)
      parsed = YAML.safe_load_file(status_path)
      expect(parsed['stage']).to eq('stacked-pr-creation')
    end

    it 'records first_uncreated_phase=2 in the status file (FR-039, SC-010)' do
      invoke
      parsed = YAML.safe_load_file(File.join(feature_dir, 'phase-creation-status.yaml'))
      expect(parsed['first_uncreated_phase']).to eq(2)
    end

    it 'records failure_class=network in the status file (FR-046)' do
      invoke
      parsed = YAML.safe_load_file(File.join(feature_dir, 'phase-creation-status.yaml'))
      expect(parsed['failure_class']).to eq('network')
    end
  end

  describe 'operational error (manifest missing)' do
    # No manifest is written; the CLI MUST exit 3 (operational error)
    # per contracts/stacked-pr-creator-cli.md exit-code table. No
    # status file is written because operational errors are not
    # per-phase failures.
    before { write_fake_gh([]) }

    let(:invoke) { run_cli('--feature-dir', feature_dir) }

    it 'exits 3 when the manifest is missing (per contract exit-code table)' do
      _stdout, _stderr, status = invoke
      expect(status.exitstatus).to eq(3)
    end

    it 'writes nothing to stdout on operational error (FR-043)' do
      stdout, _stderr, _status = invoke
      expect(stdout).to eq('')
    end

    it 'does NOT write phase-creation-status.yaml on operational error' do
      invoke
      expect(File.exist?(File.join(feature_dir, 'phase-creation-status.yaml'))).to be(false)
    end

    it 'does NOT invoke gh when the manifest is missing' do
      invoke
      expect(gh_invocations).to be_empty
    end
  end

  describe 'usage error (missing required argument)' do
    before { write_fake_gh([]) }

    it 'exits 64 when --feature-dir is omitted (per contract exit-code table)' do
      _stdout, _stderr, status = run_cli
      expect(status.exitstatus).to eq(64)
    end

    it 'writes nothing to stdout on usage error (FR-043)' do
      stdout, _stderr, _status = run_cli
      expect(stdout).to eq('')
    end
  end

  describe 'authentication-surface guard (FR-044)' do
    # The CLI MUST NOT accept any token, credential, or authentication
    # argument. The contract is enforced by OptionParser raising on
    # the unknown argument; the spec asserts exit 64 (usage error)
    # rather than any token being silently accepted.
    before do
      write_manifest(phase_count: 1)
      write_fake_gh(happy_path_gh_table)
    end

    %w[--token --auth-token --github-token --password].each do |forbidden_arg|
      it "rejects #{forbidden_arg} as an unknown argument (exits 64)" do
        _stdout, _stderr, status = run_cli('--feature-dir', feature_dir, forbidden_arg, 'secret-value')
        expect(status.exitstatus).to eq(64)
      end
    end
  end

  describe 'credential-leak guard (FR-047, SC-013)' do
    # When gh's stderr contains a token-shaped substring, neither the
    # status file nor the observability stream MAY serialize it. The
    # CLI delegates the scrubbing to its collaborators (StatusWriter,
    # Observability, GitHostCli); this spec pins the integration end-
    # to-end so a future regression where the CLI bypasses one of
    # those surfaces is caught immediately.
    let(:token) { 'ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789' }
    let(:invoke) { run_cli('--feature-dir', feature_dir) }

    before do
      write_manifest(phase_count: 1)
      write_fake_gh([
                      { 'match' => 'auth status',
                        'stderr' => "Authorization: Bearer #{token}\n",
                        'exitstatus' => 1 }
                    ])
    end

    it 'never writes the token to the status file' do
      invoke
      status_path = File.join(feature_dir, 'phase-creation-status.yaml')
      expect(File.file?(status_path)).to be(true)
      bytes = File.binread(status_path)
      expect(bytes).not_to include(token)
      expect(bytes).not_to match(/Bearer\s+\S/)
    end

    it 'never writes the token to stderr observability events' do
      _stdout, stderr, _status = invoke
      expect(stderr).not_to include(token)
    end
  end
end
