# frozen_string_literal: true

require 'optparse'

module Phaser
  module Internal
    # Shared OptionParser plumbing for the three phaser CLI entry
    # points (`phaser`, `phaser-flavor-init`, `phaser-stacked-prs`).
    # Each CLI varies in its switches, banner, and the keys it parses
    # — they all share the same scaffolding around OptionParser.
    #
    # Each CLI declares its switches as an array of `Option` value
    # objects, names the keys whose default value is `false` (flags)
    # vs. `nil` (value-bearing options) by passing `kind: :flag` or
    # `kind: :value`, and calls `parse(argv, defaults:, banner:,
    # options:)` to receive the parsed values Hash plus the rendered
    # `--help` text. On any `OptionParser::InvalidOption` /
    # `MissingArgument` the parser raises `UsageError` with the
    # underlying message — every CLI maps that to its own
    # `EXIT_USAGE` rescue.
    module CliOptionParser
      # Declarative description of one CLI switch. Bundled into a
      # value object so per-switch wiring stays a single
      # `Option.new(...)` call at the use site, regardless of which
      # CLI surfaces the switch.
      Option = Data.define(:switch, :desc, :key, :kind)

      # Internal exception family for argument-parsing problems. Each
      # CLI rescues this in its top-level `run` dispatch and maps it
      # to its documented `EXIT_USAGE` value (64 in every CLI).
      class UsageError < StandardError; end

      module_function

      # Parse `argv` against `options` (an Array of `Option`
      # entries). Returns `[values, help_text]` where `values` is
      # the populated keys-Hash (seeded from `defaults`) and
      # `help_text` is the OptionParser-rendered `--help` block.
      # Raises `UsageError` (with the underlying OptionParser message)
      # on any unknown switch or missing required value.
      def parse(argv, defaults:, banner:, options:)
        values = defaults.dup
        parser = build_parser(banner, values, options)

        begin
          parser.parse(argv)
        rescue OptionParser::InvalidOption, OptionParser::MissingArgument => e
          raise UsageError, e.message
        end

        [values, parser.help]
      end

      def build_parser(banner, values, options)
        OptionParser.new do |opts|
          opts.banner = banner
          options.each { |opt| register_option(opts, values, opt) }
        end
      end

      def register_option(opts, values, opt)
        if opt.kind == :flag
          opts.on(opt.switch, opt.desc) { values[opt.key] = true }
        else
          opts.on(opt.switch, opt.desc) { |v| values[opt.key] = v }
        end
      end
    end
  end
end
