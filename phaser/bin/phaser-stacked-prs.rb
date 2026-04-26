# frozen_string_literal: true

# Ruby entry point for the phaser stacked-PR creator CLI (feature
# 007-multi-phase-pipeline; T076, FR-026..FR-030, FR-039, FR-040,
# FR-044..FR-047, contracts/stacked-pr-creator-cli.md). The shell
# wrapper at `phaser/bin/phaser-stacked-prs` `exec`s Ruby against this
# file; keeping the implementation in a `.rb` companion lets the
# wrapper focus on environment hygiene (stripping the parent's bundler
# env so stderr stays free of rubygems warnings).
#
# This file is the operator-facing wrapper around
# `Phaser::StackedPrs::AuthProbe` + `Phaser::StackedPrs::Creator`.
# It probes `gh auth status` exactly once (FR-045), then walks the
# `<feature-dir>/phase-manifest.yaml` to create stacked branches and
# pull requests via the `Phaser::StackedPrs::GitHostCli` wrapper
# (FR-026..FR-029). On full success the CLI prints a one-line JSON
# run summary on stdout and deletes any pre-existing
# `phase-creation-status.yaml` (FR-040). On any failure the CLI
# writes the appropriate `phase-creation-status.yaml` payload via
# `Phaser::StatusWriter` and maps the failure family to the exit code
# documented in `contracts/stacked-pr-creator-cli.md`:
#
#   0  — success; JSON run summary on stdout
#   1  — stacked-PR creation failure (network, rate-limit, other)
#   2  — authentication failure (auth-missing, auth-insufficient-scope)
#   3  — operational error (manifest missing, gh binary missing)
#   64 — usage error (invalid arguments)
#
# Stream discipline (FR-043):
#
#   * stdout is reserved for the JSON run-summary on success. On any
#     non-zero exit, stdout is empty.
#   * stderr carries one JSON object per line via `Phaser::Observability`.
#
# Authentication-surface guard (FR-044):
#
#   * The OptionParser definition declares ONLY the documented flags
#     (`--feature-dir`, `--remote`, `--help`, `--version`). Any other
#     flag — including `--token`, `--auth-token`, `--github-token`,
#     `--password` — raises `OptionParser::InvalidOption`, which the
#     CLI maps to exit 64 (usage error). No token surface is silently
#     accepted.

require 'English'
require 'json'
require 'optparse'

# Ensure `require 'phaser'` resolves regardless of how the binary is
# invoked. The wrapper lives at `phaser/bin/phaser-stacked-prs`; the
# library lives at `phaser/lib/phaser.rb`. Adding `phaser/lib` to
# `$LOAD_PATH` keeps the binary self-contained — operators can run it
# directly without a `bundle exec` wrapper as long as Ruby 3.2+ is
# available.
$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'phaser'

module Phaser
  module StackedPrs
    # Operator-facing CLI for the stacked-PR creator. Kept as a small
    # command object so the binary's top-level script body is a one-liner
    # that delegates to `Phaser::StackedPrs::CLI.run(ARGV)`.
    class CLI
      EXIT_SUCCESS = 0
      EXIT_CREATION_FAILURE = 1
      EXIT_AUTH_FAILURE = 2
      EXIT_OPERATIONAL = 3
      EXIT_USAGE = 64

      # The fields the CLI parses out of ARGV. Bundled into a value
      # object so the parsing surface (option parser) and the consuming
      # surface (probe + creator wiring) read against the same shape.
      Options = Data.define(
        :feature_dir, :remote, :show_help, :show_version, :help_text
      )

      # Each entry maps an OptionParser switch to the values-hash key it
      # populates. Defined at class scope so `build_option_parser` has
      # only declarative wiring, keeping its method size below the
      # community-default budget.
      Option = Data.define(:switch, :desc, :key, :kind)

      OPTION_DEFS = [
        Option.new('--feature-dir PATH', 'Path to the feature spec directory', :feature_dir, :value),
        Option.new('--remote NAME', 'Git remote to push branches to (default: origin)', :remote, :value),
        Option.new('--help', 'Print usage and exit 0', :show_help, :flag),
        Option.new('--version', 'Print version and exit 0', :show_version, :flag)
      ].freeze

      private_constant :Option, :OPTION_DEFS

      def self.run(argv, stdout: $stdout, stderr: $stderr, env: ENV)
        new(stdout: stdout, stderr: stderr, env: env).run(argv)
      end

      def initialize(stdout:, stderr:, env:)
        @stdout = stdout
        @stderr = stderr
        @env = env
      end

      # Top-level dispatch. Returns the integer exit code so the wrapper
      # can `exit(code)` once and the spec harness can also assert on
      # the mapping in-process if it ever needs to.
      def run(argv)
        options = parse_options(argv)
        return handle_help(options) if options.show_help
        return handle_version if options.show_version

        validate_required_options!(options)
        execute(options)
      rescue UsageError => e
        @stderr.puts(e.message)
        EXIT_USAGE
      end

      # Internal exception family for argument-parsing problems. The
      # rescue clause above maps it to exit 64 per the contract's
      # exit-code table.
      class UsageError < StandardError; end

      private

      def parse_options(argv)
        values = {
          feature_dir: nil,
          remote: nil,
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
          opts.banner = 'Usage: phaser-stacked-prs --feature-dir <path> [--remote <name>]'
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

      # Execute the stacked-PR creation pipeline:
      #
      #   1. Operational precondition: the manifest must exist on disk.
      #      When absent, exit 3 without writing the status file or
      #      invoking gh (per the contract's "operational error" row).
      #
      #   2. Probe `gh auth status` exactly once (FR-045). On any
      #      failure, the AuthProbe writes the status file with
      #      `failure_class: auth-missing` (or `auth-insufficient-scope`)
      #      and `first_uncreated_phase: 1`; the CLI exits 2 without
      #      invoking gh for branch/PR queries (SC-012 fail-fast).
      #
      #   3. Walk the manifest via the Creator. On full success, the
      #      Creator deletes any pre-existing status file (FR-040) and
      #      returns a successful Result; the CLI prints the JSON run
      #      summary on stdout and exits 0. On per-phase failure, the
      #      Creator writes the status file with the classified
      #      `failure_class` and the failing phase number; the CLI
      #      exits 1.
      def execute(options)
        feature_dir = options.feature_dir
        manifest_path = File.join(feature_dir, 'phase-manifest.yaml')
        return EXIT_OPERATIONAL unless File.file?(manifest_path)

        observability = build_observability
        collaborators = build_collaborators(observability)

        probe_result = collaborators[:auth_probe].probe(feature_dir: feature_dir)
        return EXIT_AUTH_FAILURE unless probe_result.success?

        creator_result = collaborators[:creator].create(feature_dir: feature_dir)
        return EXIT_CREATION_FAILURE unless creator_result.success?

        emit_success_summary(creator_result)
        EXIT_SUCCESS
      end

      # Build the shared `Observability` instance threaded through both
      # the auth probe and the creator. The instance is cached so all
      # JSON-line records emitted during this run share the same clock
      # and the same stderr stream.
      def build_observability
        Phaser::Observability.new(stderr: @stderr)
      end

      # Build the collaborator graph for one CLI invocation. Returns a
      # Hash so `execute` can reach them by name; keeping the wiring in
      # one place makes the dependency surface auditable at a glance.
      #
      # The `git_host_cli`, `failure_classifier`, and `status_writer`
      # instances are SHARED between the auth probe and the creator so
      # there is exactly one configured surface per concern per run.
      def build_collaborators(observability)
        git_host_cli = Phaser::StackedPrs::GitHostCli.new
        failure_classifier = Phaser::StackedPrs::FailureClassifier.new
        status_writer = Phaser::StatusWriter.new

        shared = {
          git_host_cli: git_host_cli,
          failure_classifier: failure_classifier,
          status_writer: status_writer,
          observability: observability
        }

        {
          auth_probe: Phaser::StackedPrs::AuthProbe.new(**shared),
          creator: Phaser::StackedPrs::Creator.new(**shared)
        }
      end

      # Emit the one-line JSON run summary on stdout per the contract's
      # stdout section. Field order follows the contract example so a
      # downstream consumer parsing the line by index (rather than by
      # key) sees a stable shape.
      def emit_success_summary(result)
        summary = {
          'phases_created' => result.phases_created,
          'phases_skipped_existing' => result.phases_skipped_existing,
          'manifest' => result.manifest_path
        }
        @stdout.puts(JSON.generate(summary))
      end
    end
  end
end

exit(Phaser::StackedPrs::CLI.run(ARGV)) if $PROGRAM_NAME == __FILE__
