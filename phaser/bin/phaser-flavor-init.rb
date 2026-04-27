# frozen_string_literal: true

# Ruby entry point for the phaser flavor-init CLI (feature
# 007-multi-phase-pipeline; T082, FR-031, FR-032, FR-033, FR-034,
# contracts/flavor-init-cli.md). The shell wrapper at
# `phaser/bin/phaser-flavor-init` `exec`s Ruby against this file;
# keeping the implementation in a `.rb` companion lets the wrapper
# focus on environment hygiene (stripping the parent's bundler env so
# stderr stays clean).
#
# This file is the operator-facing wrapper around
# `Phaser::FlavorInit::StackDetector`. It:
#
#   1. Parses the documented option surface
#      (`--flavor`, `--force`, `--yes`, `--help`, `--version`).
#
#   2. Refuses to overwrite an existing `.specify/flavor.yaml` unless
#      `--force` is supplied (FR-034, exit 3).
#
#   3. Picks a flavor either from the explicit `--flavor` argument or
#      from auto-detection across the shipped flavors via
#      `Phaser::FlavorInit::StackDetector` (FR-031). On zero matches
#      exits 1 with the documented prose; on multi-match without
#      `--flavor` exits 2 listing the matching flavors (R-015).
#
#   4. Prompts for confirmation on stdin (FR-032), unless `--yes`. On
#      decline exits 4 without writing anything.
#
#   5. Writes `.specify/flavor.yaml` with `flavor: <name>` and prints
#      the success message on stdout.
#
# Stream discipline (per contracts/flavor-init-cli.md "stdout" /
# "stderr" sections):
#
#   * stdout receives the one-line outcome message: success, zero-match,
#     multi-match, or existing-file refusal.
#   * stderr receives the auto-detection details as plain prose
#     (which flavor was suggested and why).
#
# Test seam:
#
#   * The `PHASER_FLAVORS_ROOT` environment variable overrides the
#     default flavors root used by `Phaser::FlavorLoader`. Hermetic
#     CLI specs use this to point the loader at a temp-directory
#     catalog without shipping any files into the production tree
#     (T080 — `phaser/spec/bin/phaser_flavor_init_cli_spec.rb`).

require 'English'
require 'fileutils'

# Ensure `require 'phaser'` resolves regardless of how the binary is
# invoked. The wrapper lives at `phaser/bin/phaser-flavor-init`; the
# library lives at `phaser/lib/phaser.rb`.
$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'phaser'
require 'phaser/internal/cli_option_parser'

module Phaser
  module FlavorInit
    # Operator-facing CLI for the flavor-init command. Kept as a small
    # command object so the binary's top-level script body is a one-liner
    # that delegates to `Phaser::FlavorInit::CLI.run(ARGV)`.
    class CLI
      EXIT_SUCCESS = 0
      EXIT_ZERO_MATCH = 1
      EXIT_MULTI_MATCH = 2
      EXIT_EXISTING_FILE = 3
      EXIT_DECLINED = 4
      EXIT_UNKNOWN_FLAVOR = 5
      EXIT_USAGE = 64

      # The fields the CLI parses out of ARGV. Bundled into a value
      # object so the parsing surface (option parser) and the consuming
      # surface (selection + confirmation + write) read against the same
      # shape.
      Options = Data.define(
        :flavor_name, :force, :yes, :show_help, :show_version, :help_text
      )

      # Switches accepted by `phaser-flavor-init`. Wired through
      # `Phaser::Internal::CliOptionParser` so the OptionParser
      # scaffolding stays in one place across all three phaser CLIs.
      OPTION_DEFS = [
        Phaser::Internal::CliOptionParser::Option.new(
          '--flavor NAME', 'Skip auto-detection; select named flavor', :flavor_name, :value
        ),
        Phaser::Internal::CliOptionParser::Option.new(
          '--force', 'Overwrite an existing .specify/flavor.yaml', :force, :flag
        ),
        Phaser::Internal::CliOptionParser::Option.new(
          '--yes', 'Skip the confirmation prompt', :yes, :flag
        ),
        Phaser::Internal::CliOptionParser::Option.new(
          '--help', 'Print usage and exit 0', :show_help, :flag
        ),
        Phaser::Internal::CliOptionParser::Option.new(
          '--version', 'Print version and exit 0', :show_version, :flag
        )
      ].freeze

      OPTION_DEFAULTS = {
        flavor_name: nil,
        force: false,
        yes: false,
        show_help: false,
        show_version: false
      }.freeze

      private_constant :OPTION_DEFS, :OPTION_DEFAULTS

      def self.run(argv, stdout: $stdout, stderr: $stderr, stdin: $stdin, env: ENV)
        new(stdout: stdout, stderr: stderr, stdin: stdin, env: env).run(argv)
      end

      def initialize(stdout:, stderr:, stdin:, env:)
        @stdout = stdout
        @stderr = stderr
        @stdin = stdin
        @env = env
      end

      # Top-level dispatch. Returns the integer exit code so the wrapper
      # can `exit(code)` once and the spec harness can also assert on
      # the mapping in-process if it ever needs to.
      def run(argv)
        options = parse_options(argv)
        return handle_help(options) if options.show_help
        return handle_version if options.show_version

        execute(options)
      rescue Phaser::Internal::CliOptionParser::UsageError => e
        @stderr.puts(e.message)
        EXIT_USAGE
      end

      private

      def parse_options(argv)
        values, help_text = Phaser::Internal::CliOptionParser.parse(
          argv,
          defaults: OPTION_DEFAULTS,
          banner: 'Usage: phaser-flavor-init [--flavor <name>] [--force] [--yes]',
          options: OPTION_DEFS
        )
        Options.new(**values, help_text: help_text)
      end

      def handle_help(options)
        @stdout.puts(options.help_text)
        EXIT_SUCCESS
      end

      def handle_version
        @stdout.puts(Phaser::VERSION)
        EXIT_SUCCESS
      end

      # Drive the full opt-in pipeline. Each step that produces a
      # terminal exit path returns early so the surface stays linear and
      # the exit-code mapping is auditable at a glance against the
      # contract's exit-code table.
      def execute(options)
        target_path = File.join(Dir.pwd, '.specify', 'flavor.yaml')
        return refuse_existing(target_path) if existing_refusal?(target_path, options)

        loader = build_flavor_loader
        selection = select_flavor(options, loader)
        return selection.exit_code unless selection.flavor_name

        return EXIT_DECLINED unless confirm(selection.flavor_name, selection.signals, options)

        write_flavor_file(target_path, selection.flavor_name)
        EXIT_SUCCESS
      end

      def existing_refusal?(target_path, options)
        File.file?(target_path) && !options.force
      end

      def refuse_existing(_target_path)
        @stdout.puts('.specify/flavor.yaml already exists. Re-run with --force to overwrite.')
        EXIT_EXISTING_FILE
      end

      def build_flavor_loader
        root = @env['PHASER_FLAVORS_ROOT']
        if root.nil? || root.empty?
          Phaser::FlavorLoader.new
        else
          Phaser::FlavorLoader.new(flavors_root: root)
        end
      end

      # Selection result: the chosen flavor name (nil when a terminal
      # zero-match / multi-match / unknown-flavor path was taken), the
      # exit code to surface in those terminal cases, and the matched
      # signals describing why the flavor was suggested (used by the
      # confirmation prompt prose).
      Selection = Data.define(:flavor_name, :exit_code, :signals)

      private_constant :Selection

      # Pick the flavor honoring the explicit `--flavor` override first,
      # then falling back to auto-detection via the StackDetector
      # against the project root.
      def select_flavor(options, loader)
        if options.flavor_name
          select_explicit_flavor(options.flavor_name, loader)
        else
          select_detected_flavor(loader)
        end
      end

      def select_explicit_flavor(flavor_name, loader)
        unless loader.shipped_flavor_names.include?(flavor_name)
          @stderr.puts("flavor #{flavor_name.inspect} is not shipped")
          return Selection.new(flavor_name: nil, exit_code: EXIT_UNKNOWN_FLAVOR, signals: [])
        end

        @stderr.puts("Using explicitly selected flavor: #{flavor_name}")
        Selection.new(flavor_name: flavor_name, exit_code: EXIT_SUCCESS, signals: [])
      end

      def select_detected_flavor(loader)
        detector = Phaser::FlavorInit::StackDetector.new(flavor_loader: loader)
        matches = detector.detect(project_root: Dir.pwd)
        return zero_match_selection if matches.empty?
        return multi_match_selection(matches) if matches.length > 1

        single_match_selection(matches.first, loader)
      end

      def zero_match_selection
        @stdout.puts("No shipped flavor matched this project's stack.")
        Selection.new(flavor_name: nil, exit_code: EXIT_ZERO_MATCH, signals: [])
      end

      def multi_match_selection(matches)
        @stdout.puts("Multiple shipped flavors matched: #{matches.join(', ')}. " \
                     'Re-run with --flavor <name>.')
        Selection.new(flavor_name: nil, exit_code: EXIT_MULTI_MATCH, signals: [])
      end

      def single_match_selection(flavor_name, loader)
        signals = matched_signals_for(flavor_name, loader)
        @stderr.puts("Suggested flavor: #{flavor_name}")
        signals.each { |signal| @stderr.puts("  matched signal: #{describe_signal(signal)}") }
        Selection.new(flavor_name: flavor_name, exit_code: EXIT_SUCCESS, signals: signals)
      end

      # Re-load the flavor and pull its required signals so the
      # confirmation prompt can echo back to the operator which signals
      # justified the suggestion (per the contract's prompt example).
      def matched_signals_for(flavor_name, loader)
        flavor = loader.load(flavor_name)
        Array(flavor.stack_detection.signals).select { |signal| signal['required'] }
      rescue Phaser::FlavorLoadError
        []
      end

      def describe_signal(signal)
        case signal['type']
        when 'file_present'
          "file_present: #{signal['path']}"
        when 'file_contains'
          "file_contains: #{signal['path']} pattern #{signal['pattern'].inspect}"
        else
          signal.inspect
        end
      end

      # The confirmation prompt is skipped when `--yes` is passed (the
      # documented non-interactive path used by automation). Otherwise
      # the prompt is rendered on stdout and the response is read from
      # stdin; only `y` / `yes` (case-insensitive) confirms.
      def confirm(flavor_name, signals, options)
        return true if options.yes

        render_confirmation_prompt(flavor_name, signals)
        response = read_confirmation_response
        confirmation_response?(response)
      end

      def render_confirmation_prompt(flavor_name, signals)
        @stdout.puts("Suggested flavor: #{flavor_name}")
        unless signals.empty?
          @stdout.puts('Matched signals:')
          signals.each { |signal| @stdout.puts("  - #{describe_signal(signal)}") }
        end
        @stdout.puts('Write this flavor to .specify/flavor.yaml? [y/N]')
      end

      def read_confirmation_response
        line = @stdin.gets
        line.nil? ? '' : line.strip
      end

      def confirmation_response?(response)
        %w[y yes].include?(response.downcase)
      end

      def write_flavor_file(target_path, flavor_name)
        FileUtils.mkdir_p(File.dirname(target_path))
        File.write(target_path, "flavor: #{flavor_name}\n")
        @stdout.puts("Wrote .specify/flavor.yaml (flavor: #{flavor_name}).")
      end
    end
  end
end

exit(Phaser::FlavorInit::CLI.run(ARGV)) if $PROGRAM_NAME == __FILE__
