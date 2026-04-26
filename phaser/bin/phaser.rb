# frozen_string_literal: true

# Ruby entry point for the phaser engine CLI (feature
# 007-multi-phase-pipeline; T036, FR-008, FR-041, FR-043,
# contracts/phaser-cli.md). The shell wrapper at `phaser/bin/phaser`
# `exec`s Ruby against this file; keeping the implementation in a
# `.rb` companion lets the wrapper focus on environment hygiene
# (stripping the parent's bundler env so stderr stays free of rubygems
# warnings).
#
# This file is the operator-facing wrapper around `Phaser::Engine#process`.
# It reads commits from the current Git working directory's history,
# loads the named flavor via `Phaser::FlavorLoader`, runs the engine,
# and maps the engine's outcome onto the exit-code table documented in
# `contracts/phaser-cli.md`:
#
#   0  — success; manifest path printed on stdout
#   1  — validation failure (engine raised); status file written
#   2  — configuration error (unknown flavor, malformed catalog)
#   3  — operational error (cannot read Git history, FS permission)
#   64 — usage error (invalid arguments)
#
# Stream discipline (FR-043):
#
#   * stdout is reserved for the absolute path to the written manifest
#     on success. On any non-zero exit, stdout is empty.
#   * stderr carries one JSON object per line via `Phaser::Observability`.
#
# Test seam:
#
#   * The `PHASER_FLAVORS_ROOT` environment variable overrides the
#     default flavors root (`phaser/flavors/`). Hermetic CLI specs use
#     this to point the loader at a temp-directory catalog without
#     shipping any files into the production tree (T028).

require 'English'
require 'open3'
require 'optparse'

# Ensure `require 'phaser'` resolves regardless of how the binary is
# invoked. The wrapper lives at `phaser/bin/phaser`; the library lives
# at `phaser/lib/phaser.rb`. Adding `phaser/lib` to `$LOAD_PATH` keeps
# the binary self-contained — operators can run it directly without a
# `bundle exec` wrapper as long as Ruby 3.2+ is available.
$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'phaser'

module Phaser
  # Operator-facing CLI for the phaser engine. Kept as a small command
  # object so the binary's top-level script body is a one-liner that
  # delegates to `Phaser::CLI.run(ARGV)`.
  class CLI
    EXIT_SUCCESS = 0
    EXIT_VALIDATION = 1
    EXIT_CONFIGURATION = 2
    EXIT_OPERATIONAL = 3
    EXIT_USAGE = 64

    # The fields the CLI parses out of ARGV. Bundled into a value
    # object so the parsing surface (option parser) and the consuming
    # surface (engine wiring) read against the same shape.
    Options = Data.define(
      :feature_dir, :flavor_name, :default_branch, :clock,
      :show_help, :show_version, :help_text
    )

    def self.run(argv, stdout: $stdout, stderr: $stderr, env: ENV)
      new(stdout: stdout, stderr: stderr, env: env).run(argv)
    end

    def initialize(stdout:, stderr:, env:)
      @stdout = stdout
      @stderr = stderr
      @env = env
    end

    # Top-level dispatch. Returns the integer exit code so the wrapper
    # can `exit(code)` once and the spec harness can also assert on the
    # mapping in-process if it ever needs to.
    def run(argv)
      options = parse_options(argv)
      return handle_help(options) if options.show_help
      return handle_version if options.show_version

      validate_required_options!(options)
      execute_pipeline(options)
    rescue UsageError => e
      @stderr.puts(e.message)
      EXIT_USAGE
    rescue ConfigurationError => e
      @stderr.puts(e.message)
      EXIT_CONFIGURATION
    rescue OperationalError => e
      @stderr.puts(e.message)
      EXIT_OPERATIONAL
    end

    # Internal exception families. Each one corresponds to one row of
    # the exit-code table in `contracts/phaser-cli.md` so the rescue
    # clauses above are a literal mapping from failure family to exit
    # code. Validation failures from the engine are NOT wrapped here —
    # they flow through `execute_pipeline` which catches the engine's
    # `Phaser::ValidationError` / `Phaser::ClassificationError` and
    # returns `EXIT_VALIDATION` directly because the engine has already
    # written the status file and emitted the ERROR record.
    class UsageError < StandardError; end
    class ConfigurationError < StandardError; end
    class OperationalError < StandardError; end

    # Map of `git diff-tree --raw` status letters to the
    # `Phaser::FileChange#change_kind` enum the engine consumes
    # (data-model.md "FileChange"). Defined at class scope so
    # `change_kind_for` can fetch from it without re-allocating per
    # commit. `T` (type change) is treated as `:modified` because the
    # engine has no separate enum for it.
    CHANGE_KIND_MAP = {
      'A' => :added, 'M' => :modified, 'D' => :deleted,
      'R' => :renamed, 'C' => :copied, 'T' => :modified
    }.freeze

    # Each entry maps an OptionParser switch to the values-hash key it
    # populates. Defined at class scope so `build_option_parser` has
    # only declarative wiring, keeping its ABC size below the
    # community-default budget. Bundled into a Data.define so
    # `register_option` can take a single Option argument and stay
    # within the project's parameter-count limit.
    Option = Data.define(:switch, :desc, :key, :kind)

    OPTION_DEFS = [
      Option.new('--feature-dir PATH', 'Path to the feature spec directory', :feature_dir, :value),
      Option.new('--flavor NAME', 'Override the flavor name', :flavor_name, :value),
      Option.new('--default-branch BRANCH', 'Override the default integration branch', :default_branch, :value),
      Option.new('--clock ISO8601', 'Pin the generation timestamp (test seam)', :clock, :value),
      Option.new('--help', 'Print usage and exit 0', :show_help, :flag),
      Option.new('--version', 'Print engine version and exit 0', :show_version, :flag)
    ].freeze

    private_constant :Option, :OPTION_DEFS

    private

    # OptionParser surface per `contracts/phaser-cli.md`. The parser
    # captures `--help`'s rendered usage string into the returned
    # Options value object so `handle_help` can print the same text
    # that `--help` advertised, including the option summary.
    def parse_options(argv)
      values = {
        feature_dir: nil,
        flavor_name: nil,
        default_branch: nil,
        clock: nil,
        show_help: false,
        show_version: false
      }

      parser = build_option_parser(values)

      begin
        parser.parse(argv)
      rescue OptionParser::InvalidOption, OptionParser::MissingArgument => e
        raise UsageError, e.message
      end

      Options.new(**values, help_text: parser.help)
    end

    def build_option_parser(values)
      OptionParser.new do |opts|
        opts.banner = 'Usage: phaser --feature-dir <path> [options]'
        OPTION_DEFS.each { |opt| register_option(opts, values, opt) }
      end
    end

    def register_option(opts, values, opt)
      if opt.kind == :flag
        opts.on(opt.switch, opt.desc) { values[opt.key] = true }
      else
        opts.on(opt.switch, opt.desc) { |v| values[opt.key] = v }
      end
    end

    def handle_help(options)
      @stdout.puts(options.help_text)
      EXIT_SUCCESS
    end

    def handle_version
      @stdout.puts(Phaser::VERSION)
      EXIT_SUCCESS
    end

    def validate_required_options!(options)
      raise UsageError, 'missing required argument: --feature-dir' if options.feature_dir.nil?
    end

    # Resolve the flavor, build the engine, run `#process`, and map the
    # outcome onto the exit-code table. The engine has already taken
    # care of writing the status file and emitting the ERROR record on
    # validation failure (FR-041, FR-042); this layer's only job on
    # that path is to translate the raised exception into exit code 1
    # without printing the manifest path on stdout (FR-043).
    def execute_pipeline(options)
      flavor = load_flavor(options)
      observability = build_observability(options)
      engine = build_engine(options, observability)
      commits = read_commits(options)
      manifest_path = engine.process(commits, flavor)
      @stdout.puts(manifest_path)
      EXIT_SUCCESS
    rescue Phaser::ValidationError, Phaser::ClassificationError
      EXIT_VALIDATION
    end

    # Load the named flavor honoring the `PHASER_FLAVORS_ROOT` test
    # seam. Resolution order matches `contracts/phaser-cli.md`: an
    # explicit `--flavor` argument wins; otherwise read the flavor
    # name from `.specify/flavor.yaml` in the current working
    # directory.
    def load_flavor(options)
      flavor_name = options.flavor_name || read_configured_flavor_name
      raise ConfigurationError, 'no flavor specified and .specify/flavor.yaml not found' if flavor_name.nil?

      loader = Phaser::FlavorLoader.new(**flavor_loader_kwargs)
      loader.load(flavor_name)
    rescue Phaser::FlavorLoadError => e
      raise ConfigurationError, e.message
    end

    def flavor_loader_kwargs
      root = @env['PHASER_FLAVORS_ROOT']
      root.nil? || root.empty? ? {} : { flavors_root: root }
    end

    def read_configured_flavor_name
      path = File.join(Dir.pwd, '.specify', 'flavor.yaml')
      return nil unless File.file?(path)

      catalog = Psych.safe_load(File.read(path), permitted_classes: [], aliases: false)
      catalog.is_a?(Hash) ? catalog['flavor'] : nil
    rescue Psych::SyntaxError => e
      raise ConfigurationError, ".specify/flavor.yaml has invalid YAML: #{e.message}"
    end

    def build_observability(options)
      Phaser::Observability.new(stderr: @stderr, now: clock_callable(options))
    end

    def build_engine(options, observability)
      clock = clock_callable(options)
      Phaser::Engine.new(
        feature_dir: options.feature_dir,
        feature_branch: detect_feature_branch,
        default_branch: options.default_branch || detect_default_branch,
        observability: observability,
        status_writer: Phaser::StatusWriter.new(now: clock),
        manifest_writer: Phaser::ManifestWriter.new,
        clock: clock
      )
    end

    # The clock callable is cached per-run so `Observability` and
    # `StatusWriter` see the same value when the operator pins
    # `--clock` for determinism (SC-002). When `--clock` is omitted
    # the callable falls back to the current ISO-8601 UTC instant.
    def clock_callable(options)
      @clock_callable ||= if options.clock
                            pinned = options.clock
                            -> { pinned }
                          else
                            -> { Time.now.utc.strftime('%Y-%m-%dT%H:%M:%S.%LZ') }
                          end
    end

    # Detect the current branch via `git rev-parse --abbrev-ref HEAD`.
    # Used for both the engine's `feature_branch` field on the manifest
    # and the lower bound of the `git log <default>..HEAD` range that
    # builds the input commit list.
    def detect_feature_branch
      git_reader.detect_feature_branch
    end

    def detect_default_branch
      git_reader.detect_default_branch
    end

    # Build the `Phaser::Commit` list from the Git history between the
    # default branch and HEAD. The CLI reads the full SHA, subject,
    # author timestamp, and trailers per commit, then runs
    # `git diff-tree` to assemble the per-file change set the engine
    # consumes for inference and forbidden-operation detection.
    def read_commits(options)
      default_branch = options.default_branch || detect_default_branch
      git_reader.read_commits(default_branch)
    end

    # The Git reader is constructed lazily so unit tests that exercise
    # only the option-parser surface (e.g., `--help` / `--version`) do
    # not need a Git working directory.
    def git_reader
      @git_reader ||= GitCommitReader.new
    end
  end

  # Reads commits from the current Git working directory's history and
  # converts them into `Phaser::Commit` value objects the engine
  # consumes (feature 007-multi-phase-pipeline; T036). Extracted from
  # `Phaser::CLI` so the CLI's own surface stays focused on argument
  # parsing, exit-code mapping, and engine wiring while this class
  # owns every `git` subprocess invocation. Failures bubble up as
  # `Phaser::CLI::OperationalError` so the CLI's outer rescue maps
  # them to exit code 3 per `contracts/phaser-cli.md`.
  class GitCommitReader
    def detect_feature_branch
      run_git('rev-parse', '--abbrev-ref', 'HEAD').strip
    end

    def detect_default_branch
      stdout = run_git('symbolic-ref', '--quiet', '--short', 'refs/remotes/origin/HEAD').strip
      stdout.empty? ? 'main' : stdout.split('/', 2).last
    rescue Phaser::CLI::OperationalError
      'main'
    end

    def read_commits(default_branch)
      shas = list_commit_shas(default_branch)
      shas.map { |sha| build_commit(sha) }
    end

    private

    def list_commit_shas(default_branch)
      output = run_git('log', '--reverse', '--format=%H', "#{default_branch}..HEAD")
      output.each_line.map(&:strip).reject(&:empty?)
    end

    def build_commit(sha)
      header = run_git('show', '--no-patch',
                       '--format=%H%x1f%s%x1f%aI%x1f%(trailers:only,unfold)', sha)
      hash, subject, author_iso, trailer_block = header.chomp.split("\x1f", 4)
      Phaser::Commit.new(
        hash: hash,
        subject: subject,
        message_trailers: parse_trailers(trailer_block || ''),
        diff: build_diff(sha),
        author_timestamp: author_iso
      )
    end

    # Parse the `git --format=%(trailers:only)` block (one
    # `Key: value` per line) into a Hash. Lines without a colon are
    # ignored — `git interpret-trailers` already filters anything that
    # is not a well-formed trailer when `:only` is passed.
    def parse_trailers(block)
      trailers = {}
      block.each_line do |line|
        line = line.strip
        next if line.empty?

        key, value = line.split(':', 2)
        next if value.nil?

        trailers[key.strip] = value.strip
      end
      trailers
    end

    # Build a `Phaser::Diff` from a commit SHA. Uses
    # `git diff-tree --no-commit-id --raw -r --root <sha>` to enumerate
    # changed paths (with the change-kind status letter) and
    # `git show -p --no-color --format= -- <path>` to capture the
    # per-file hunks the engine forwards to inference rules and
    # forbidden-operation detectors.
    def build_diff(sha)
      raw = run_git('diff-tree', '--no-commit-id', '--raw', '-r', '--root', sha)
      file_changes = raw.each_line.map { |line| parse_diff_tree_line(line, sha) }.compact
      Phaser::Diff.new(files: file_changes)
    end

    # Each `git diff-tree --raw` line has the shape:
    #   :100644 100644 <src-sha> <dst-sha> M\tpath
    # for modifications, with `R<score>\told\tnew` for renames. We
    # only need the change kind and the (post-rename) path, plus the
    # per-file hunks read separately so inference rules can
    # pattern-match on the diff body. Returns nil on a malformed line
    # so the caller's `compact` strips it (defensive: `git diff-tree`
    # is well-defined but the parser is forgiving).
    def parse_diff_tree_line(line, sha)
      parts = line.chomp.split("\t")
      return nil if parts.length < 2
      return nil unless parts.first.start_with?(':')

      meta_fields = parts.first.split
      status_letter = meta_fields.last
      path = parts.last

      Phaser::FileChange.new(
        path: path,
        change_kind: change_kind_for(status_letter),
        hunks: read_file_hunks(sha, path)
      )
    end

    def change_kind_for(status_letter)
      key = status_letter.to_s[0]
      Phaser::CLI::CHANGE_KIND_MAP.fetch(key, :modified)
    end

    def read_file_hunks(sha, path)
      output = run_git('show', '--no-color', '--format=', '-p', sha, '--', path)
      [output]
    end

    # Run a Git subprocess against the current working directory.
    # Captures both stdout and stderr; raises
    # `Phaser::CLI::OperationalError` on non-zero status so the outer
    # rescue maps to exit code 3 per `contracts/phaser-cli.md`.
    def run_git(*args)
      stdout, stderr, status = Open3.capture3('git', *args)
      raise Phaser::CLI::OperationalError, "git #{args.join(' ')} failed: #{stderr.strip}" unless status.success?

      stdout
    end
  end
end

exit(Phaser::CLI.run(ARGV)) if $PROGRAM_NAME == __FILE__
