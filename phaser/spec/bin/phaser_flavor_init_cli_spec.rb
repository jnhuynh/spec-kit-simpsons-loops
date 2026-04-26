# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'open3'
require 'tmpdir'
require 'yaml'
require 'phaser/version'

# Specs for `phaser/bin/phaser-flavor-init` — the standalone command-line
# entry point that wraps `Phaser::FlavorInit::StackDetector` for
# operator-facing project opt-in (feature 007-multi-phase-pipeline;
# T080/T082, FR-031, FR-032, FR-033, FR-034,
# contracts/flavor-init-cli.md, R-015).
#
# This file pins the externally observable contract: the synopsis flags
# the binary accepts, the streams it writes to (stdout for the success
# message and the user-facing zero/multi-match prose; stderr for the
# auto-detection details), the exit codes it returns, and the
# side-effect file (`.specify/flavor.yaml`) it produces in the project
# root. Every assertion here is grounded in
# `specs/007-multi-phase-pipeline/contracts/flavor-init-cli.md`; the
# test does not depend on any internal CLI implementation detail beyond
# the contract.
#
# The CLI is not yet implemented (T082 lands later in the dependency
# chain), so the suite is expected to fail in red until then. That
# matches the constitution's Test-First Development principle: this
# spec is observed failing first, and T082 implements the binary in a
# minimum-viable way to make every example below pass.
#
# Test seams
# ----------
#
# The CLI binary cannot run against the real shipped `phaser/flavors/`
# tree without coupling every example to whatever flavors are shipped
# at the time the spec runs. Two seams keep each example hermetic:
#
#   1. A `PHASER_FLAVORS_ROOT` environment variable overrides the
#      `FlavorLoader` default (the same seam exercised by the engine
#      CLI spec). Each example writes a tiny flavor catalog into a
#      temp directory and points the CLI at it via this variable.
#
#   2. The CLI runs from a per-example project root (the temp directory
#      its subprocess CWD is set to) so the `.specify/flavor.yaml` it
#      writes lands in a hermetic location and the stack-detection
#      signals consult only the files that example sets up.
#
# Each example below builds a hermetic flavors root and a hermetic
# project root, points the CLI at both via the documented seams, and
# asserts a single contract property. The CLI's stdin handling for the
# confirmation prompt (FR-032) is exercised both via `--yes` (the
# documented non-interactive path) and via piping `y` / empty input on
# stdin so the interactive surface is also pinned.
RSpec.describe 'phaser-flavor-init CLI' do # rubocop:disable RSpec/DescribeClass
  # Absolute path to the binary under test. Resolved relative to this
  # spec file so the suite runs correctly regardless of the working
  # directory `rspec` is invoked from (the project's CI invokes
  # `cd phaser && bundle exec rspec`, but a single-file run from the
  # repo root must work too).
  let(:phaser_flavor_init_bin) do
    File.expand_path('../../bin/phaser-flavor-init', __dir__)
  end

  # Per-example project root. The CLI writes
  # `.specify/flavor.yaml` here on success, and consults the same
  # directory tree for the stack-detection signals declared by the
  # candidate flavors.
  attr_reader :project_root

  # Per-example flavors root that the test seam (PHASER_FLAVORS_ROOT)
  # points the CLI's FlavorLoader at. Each example writes the flavor
  # catalogs it needs into this directory before invoking the binary.
  attr_reader :flavors_root

  around do |example|
    Dir.mktmpdir('phaser-flavor-init-spec-project-') do |project|
      Dir.mktmpdir('phaser-flavor-init-spec-flavors-') do |flavors|
        @project_root = project
        @flavors_root = flavors
        example.run
      end
    end
  end

  # Build a minimal-but-schema-valid flavor catalog with the given
  # `stack_detection.signals` list. Mirrors the catalog shape used by
  # `flavor_loader_spec.rb` so the two spec files exercise the same
  # production loader path without diverging on shape. Split into
  # smaller helpers so each one stays under the community-default
  # method-length budget.
  def base_catalog(name)
    {
      'name' => name,
      'version' => '0.1.0',
      'default_type' => 'misc',
      'task_types' => base_task_types,
      'precedent_rules' => base_precedent_rules,
      'inference_rules' => base_inference_rules,
      'forbidden_operations' => [],
      'stack_detection' => { 'signals' => [] }
    }
  end

  def base_task_types
    [
      { 'name' => 'schema', 'isolation' => 'alone',
        'description' => 'Schema-level change requiring its own phase.' },
      { 'name' => 'misc', 'isolation' => 'groups',
        'description' => 'Default catch-all for unclassified commits.' }
    ]
  end

  def base_precedent_rules
    [{ 'name' => 'misc-after-schema', 'subject_type' => 'misc',
       'predecessor_type' => 'schema',
       'error_message' => 'A misc commit must follow a schema commit.' }]
  end

  def base_inference_rules
    [{ 'name' => 'schema-by-path', 'precedence' => 100,
       'task_type' => 'schema',
       'match' => { 'kind' => 'file_glob', 'pattern' => 'db/migrate/*.rb' } }]
  end

  # Write a shipped flavor's `flavor.yaml` under the per-example
  # flavors root. Returns the flavor name so the calling test reads at
  # a glance "this flavor exists; this is its name."
  def write_flavor(name, signals:)
    catalog = base_catalog(name).merge(
      'stack_detection' => { 'signals' => signals }
    )
    flavor_dir = File.join(flavors_root, name)
    FileUtils.mkdir_p(flavor_dir)
    File.write(File.join(flavor_dir, 'flavor.yaml'), YAML.dump(catalog))
    name
  end

  # Write a file under the per-example project root with the given
  # relative path and contents. Used to satisfy `file_present` /
  # `file_contains` signals from the test side.
  def write_project_file(relative_path, contents)
    absolute_path = File.join(project_root, relative_path)
    FileUtils.mkdir_p(File.dirname(absolute_path))
    File.write(absolute_path, contents)
  end

  # Run the CLI binary as a subprocess from the project root with the
  # test seam env var set. Returns `[stdout, stderr, exit_status]`.
  # Every example uses this single entry point so the subprocess
  # invocation pattern stays consistent and the test suite can be
  # audited at a glance for "is the env var set, is the working
  # directory correct, what was on stdin".
  def run_cli(*args, env_overrides: {}, stdin_data: '')
    env = { 'PHASER_FLAVORS_ROOT' => flavors_root }.merge(env_overrides)
    Open3.capture3(env, phaser_flavor_init_bin, *args,
                   stdin_data: stdin_data, chdir: project_root)
  end

  # The single signal used by the most basic happy-path examples: a
  # `file_present: Gemfile` check that matches when the project root
  # contains a Gemfile. Pulled out so multiple examples reuse the same
  # flavor shape.
  def gemfile_present_signals
    [{ 'type' => 'file_present', 'path' => 'Gemfile', 'required' => true }]
  end

  describe 'binary surface' do
    it 'is a file at phaser/bin/phaser-flavor-init' do
      expect(File.file?(phaser_flavor_init_bin)).to be(true)
    end

    it 'is executable' do
      expect(File.executable?(phaser_flavor_init_bin)).to be(true)
    end
  end

  describe '--help' do
    it 'exits 0 (per contracts/flavor-init-cli.md exit-code table)' do
      _stdout, _stderr, status = run_cli('--help')
      expect(status.exitstatus).to eq(0)
    end

    it 'prints usage information naming each documented argument' do
      stdout, _stderr, _status = run_cli('--help')
      %w[--flavor --force --yes --help --version].each do |arg|
        expect(stdout).to include(arg),
                          "expected --help output to mention #{arg}"
      end
    end
  end

  describe '--version' do
    it 'exits 0 (per contracts/flavor-init-cli.md exit-code table)' do
      _stdout, _stderr, status = run_cli('--version')
      expect(status.exitstatus).to eq(0)
    end

    it 'prints the engine version (Phaser::VERSION) on stdout' do
      stdout, _stderr, _status = run_cli('--version')
      expect(stdout).to include(Phaser::VERSION)
    end
  end

  describe 'single-match auto-detection (FR-031, FR-032)' do
    # Exactly one shipped flavor matches the project's stack. The CLI
    # MUST suggest it, prompt for confirmation (or accept --yes), and
    # write `.specify/flavor.yaml` referencing that flavor on
    # confirmation.
    before do
      write_flavor('example-minimal', signals: gemfile_present_signals)
      write_project_file('Gemfile', "source 'https://rubygems.org'\n")
    end

    describe 'with --yes (non-interactive confirmation)' do
      let(:invoke) { run_cli('--yes') }

      it 'exits 0 (per contracts/flavor-init-cli.md exit-code table)' do
        _stdout, _stderr, status = invoke
        expect(status.exitstatus).to eq(0)
      end

      it 'writes .specify/flavor.yaml under the project root' do
        invoke
        expect(File.file?(File.join(project_root, '.specify', 'flavor.yaml'))).to be(true)
      end

      it 'records the suggested flavor name in the written .specify/flavor.yaml' do
        invoke
        catalog = YAML.safe_load_file(File.join(project_root, '.specify', 'flavor.yaml'))
        expect(catalog).to include('flavor' => 'example-minimal')
      end

      it 'prints the success message naming the written file path on stdout' do
        stdout, _stderr, _status = invoke
        expect(stdout).to include('.specify/flavor.yaml')
        expect(stdout).to include('example-minimal')
      end

      it 'creates the .specify directory if it does not yet exist' do
        # Sanity check: the project root starts with no .specify dir; the
        # CLI is responsible for creating it (per contract Side Effects).
        expect(Dir.exist?(File.join(project_root, '.specify'))).to be(false)
        invoke
        expect(Dir.exist?(File.join(project_root, '.specify'))).to be(true)
      end
    end

    describe 'interactive confirmation (operator types y)' do
      let(:invoke) { run_cli(stdin_data: "y\n") }

      it 'exits 0 when the operator confirms with y' do
        _stdout, _stderr, status = invoke
        expect(status.exitstatus).to eq(0)
      end

      it 'writes .specify/flavor.yaml when the operator confirms' do
        invoke
        expect(File.file?(File.join(project_root, '.specify', 'flavor.yaml'))).to be(true)
      end
    end

    describe 'interactive confirmation (operator declines)' do
      # Anything other than `y` / `yes` (case-insensitive) declines per
      # the contract's Confirmation Prompt section. Exit code 4.
      let(:invoke) { run_cli(stdin_data: "n\n") }

      it 'exits 4 when the operator declines (per contract exit-code table)' do
        _stdout, _stderr, status = invoke
        expect(status.exitstatus).to eq(4)
      end

      it 'does NOT write .specify/flavor.yaml when the operator declines' do
        invoke
        expect(File.exist?(File.join(project_root, '.specify', 'flavor.yaml'))).to be(false)
      end
    end
  end

  describe 'zero-match auto-detection (FR-033)' do
    # No shipped flavor's required signals match the project. The CLI
    # MUST exit 1 with the documented `No shipped flavor matched`
    # message and MUST NOT write `.specify/flavor.yaml`.
    before do
      write_flavor('example-minimal', signals: gemfile_present_signals)
      # No Gemfile is written under project_root, so the only shipped
      # flavor's only required signal cannot match.
    end

    let(:invoke) { run_cli('--yes') }

    it 'exits 1 when no shipped flavor matches (per contract exit-code table)' do
      _stdout, _stderr, status = invoke
      expect(status.exitstatus).to eq(1)
    end

    it 'prints the documented zero-match message on stdout' do
      stdout, _stderr, _status = invoke
      expect(stdout).to include('No shipped flavor matched')
    end

    it 'does NOT write .specify/flavor.yaml on zero match' do
      invoke
      expect(File.exist?(File.join(project_root, '.specify', 'flavor.yaml'))).to be(false)
    end
  end

  describe 'multi-match auto-detection (R-015)' do
    # Two or more shipped flavors match the project's stack and the
    # operator did not pass `--flavor`. The CLI MUST exit 2 with the
    # documented multi-match message that lists every matching flavor
    # and instructs `--flavor <name>`. No file is written.
    before do
      write_flavor('example-minimal', signals: gemfile_present_signals)
      write_flavor('alt-minimal', signals: gemfile_present_signals)
      write_project_file('Gemfile', "source 'https://rubygems.org'\n")
    end

    let(:invoke) { run_cli('--yes') }

    it 'exits 2 when more than one flavor matches (per contract exit-code table)' do
      _stdout, _stderr, status = invoke
      expect(status.exitstatus).to eq(2)
    end

    it 'lists every matching flavor in the multi-match message' do
      stdout, _stderr, _status = invoke
      expect(stdout).to include('example-minimal')
      expect(stdout).to include('alt-minimal')
    end

    it 'instructs the operator to re-run with --flavor <name>' do
      stdout, _stderr, _status = invoke
      expect(stdout).to include('--flavor')
    end

    it 'does NOT write .specify/flavor.yaml on multi-match' do
      invoke
      expect(File.exist?(File.join(project_root, '.specify', 'flavor.yaml'))).to be(false)
    end

    describe 'with --flavor <name> disambiguating the multi-match' do
      # When the operator re-runs with `--flavor` naming one of the
      # matching flavors, the CLI MUST write that flavor and exit 0.
      let(:disambiguated) { run_cli('--yes', '--flavor', 'example-minimal') }

      it 'exits 0 when --flavor disambiguates the multi-match' do
        _stdout, _stderr, status = disambiguated
        expect(status.exitstatus).to eq(0)
      end

      it 'writes the disambiguated flavor to .specify/flavor.yaml' do
        disambiguated
        catalog = YAML.safe_load_file(File.join(project_root, '.specify', 'flavor.yaml'))
        expect(catalog).to include('flavor' => 'example-minimal')
      end
    end
  end

  describe 'existing-file refusal (FR-034)' do
    # `.specify/flavor.yaml` already exists. Without `--force` the CLI
    # MUST exit 3 with the documented refusal message and leave the
    # existing file untouched. With `--force`, the CLI proceeds and
    # overwrites the existing file with the suggested flavor.
    let(:existing_path) { File.join(project_root, '.specify', 'flavor.yaml') }
    let(:original_contents) { "flavor: pre-existing-flavor\n" }

    before do
      write_flavor('example-minimal', signals: gemfile_present_signals)
      write_project_file('Gemfile', "source 'https://rubygems.org'\n")
      FileUtils.mkdir_p(File.dirname(existing_path))
      File.write(existing_path, original_contents)
    end

    describe 'without --force' do
      let(:invoke) { run_cli('--yes') }

      it 'exits 3 when the file already exists (per contract exit-code table)' do
        _stdout, _stderr, status = invoke
        expect(status.exitstatus).to eq(3)
      end

      it 'prints the documented refusal message on stdout' do
        stdout, _stderr, _status = invoke
        expect(stdout).to include('.specify/flavor.yaml already exists')
        expect(stdout).to include('--force')
      end

      it 'leaves the existing .specify/flavor.yaml byte-for-byte untouched' do
        invoke
        expect(File.read(existing_path)).to eq(original_contents)
      end
    end

    describe 'with --force' do
      let(:invoke) { run_cli('--yes', '--force') }

      it 'exits 0 when --force is supplied' do
        _stdout, _stderr, status = invoke
        expect(status.exitstatus).to eq(0)
      end

      it 'overwrites the existing .specify/flavor.yaml with the suggested flavor' do
        invoke
        catalog = YAML.safe_load_file(existing_path)
        expect(catalog).to include('flavor' => 'example-minimal')
      end
    end
  end

  describe 'unknown --flavor argument' do
    # When `--flavor <name>` references a flavor that is not shipped,
    # the CLI MUST exit 5 (per contract exit-code table) and MUST NOT
    # write `.specify/flavor.yaml`.
    before do
      write_flavor('example-minimal', signals: gemfile_present_signals)
      write_project_file('Gemfile', "source 'https://rubygems.org'\n")
    end

    let(:invoke) { run_cli('--yes', '--flavor', 'no-such-flavor') }

    it 'exits 5 when the named flavor is not shipped (per contract exit-code table)' do
      _stdout, _stderr, status = invoke
      expect(status.exitstatus).to eq(5)
    end

    it 'does NOT write .specify/flavor.yaml when the named flavor is unknown' do
      invoke
      expect(File.exist?(File.join(project_root, '.specify', 'flavor.yaml'))).to be(false)
    end
  end

  describe 'usage error (unrecognized argument)' do
    # Any unrecognized argument must produce exit code 64 (the standard
    # sysexits.h EX_USAGE; mirrors the engine CLI surface). No file is
    # written.
    before do
      write_flavor('example-minimal', signals: gemfile_present_signals)
      write_project_file('Gemfile', "source 'https://rubygems.org'\n")
    end

    it 'exits 64 on an unknown argument (per contract exit-code table)' do
      _stdout, _stderr, status = run_cli('--bogus-flag')
      expect(status.exitstatus).to eq(64)
    end

    it 'does NOT write .specify/flavor.yaml on usage error' do
      run_cli('--bogus-flag')
      expect(File.exist?(File.join(project_root, '.specify', 'flavor.yaml'))).to be(false)
    end
  end

  describe 'auto-detection details on stderr (per contract stderr section)' do
    # The contract pins stderr to "auto-detection details written as
    # plain prose, not JSON" (it is an interactive setup tool, not part
    # of the streaming-log surface). The minimum we assert is that
    # stderr names the suggested flavor on a single-match run so a
    # human running the command sees which flavor was chosen and why.
    before do
      write_flavor('example-minimal', signals: gemfile_present_signals)
      write_project_file('Gemfile', "source 'https://rubygems.org'\n")
    end

    it 'mentions the suggested flavor name on stderr' do
      _stdout, stderr, _status = run_cli('--yes')
      expect(stderr).to include('example-minimal')
    end
  end
end
