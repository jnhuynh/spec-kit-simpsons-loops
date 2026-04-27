# frozen_string_literal: true

require 'phaser/flavor_loader'

module Phaser
  module FlavorInit
    # Pure stack-detection surface consulted by the
    # `phaser-flavor-init` CLI to suggest a shipped flavor for a project
    # that has not yet opted in (feature 007-multi-phase-pipeline; T081,
    # FR-031, data-model.md "StackDetection" / "Signal",
    # contracts/flavor.schema.yaml, contracts/flavor-init-cli.md
    # "Auto-Detection (FR-031)").
    #
    # The detector is a pure function over the cross-product of:
    #
    #   * The set of shipped flavors under the loader's flavors root,
    #     each of which declares a `stack_detection.signals` list of
    #     `file_present` and `file_contains` checks.
    #
    #   * The project root the operator is running `phaser-flavor-init`
    #     in.
    #
    # Behavior:
    #
    #   1. Iterate every shipped flavor (via
    #      `Phaser::FlavorLoader#shipped_flavor_names` so the detector
    #      reuses the loader's single source of truth for what "shipped"
    #      means).
    #
    #   2. For each flavor, evaluate the `stack_detection.signals` from
    #      its `flavor.yaml`, checking each `required: true` signal
    #      against the project root per the data-model.md StackDetection
    #      table:
    #
    #        * file_present   — the file exists at the given path.
    #        * file_contains  — the file exists AND its contents match
    #                           the given regex pattern.
    #
    #   3. Return the list of flavors whose required signals ALL match,
    #      sorted alphabetically by flavor name so the CLI can rely on a
    #      deterministic order when surfacing multi-match disambiguation
    #      (R-015 / contracts/flavor-init-cli.md exit code 2).
    #
    # Signals with `required: false` are informational and MUST NOT
    # gate matching — only the `required: true` signals determine
    # whether a flavor is a candidate (data-model.md "StackDetection").
    #
    # Determinism (FR-002, SC-002): the detector consults only the
    # filesystem and the loaded flavor catalogs. No environment
    # variables, network calls, or clock reads. Two runs against the
    # same project root and the same flavors root return identical
    # results.
    class StackDetector
      # Construct a detector backed by the given flavor loader.
      # Production callers use `Phaser::FlavorLoader.new` (which points
      # at the shipped `phaser/flavors/` tree); tests inject a loader
      # rooted at a temp directory so fixtures stay hermetic.
      def initialize(flavor_loader: Phaser::FlavorLoader.new)
        @flavor_loader = flavor_loader
      end

      # Return the list of shipped flavor names whose required
      # stack-detection signals all match the project at `project_root`.
      # The returned list is sorted alphabetically for deterministic
      # disambiguation rendering by the CLI; `shipped_flavor_names`
      # already returns its list sorted so `select` preserves that
      # order without an additional `.sort` pass.
      def detect(project_root:)
        @flavor_loader.shipped_flavor_names.select do |flavor_name|
          flavor = @flavor_loader.load(flavor_name)
          flavor_matches?(flavor, project_root)
        end
      end

      private

      def flavor_matches?(flavor, project_root)
        required_signals(flavor).all? do |signal|
          signal_matches?(signal, project_root)
        end
      end

      def required_signals(flavor)
        Array(flavor.stack_detection.signals).select { |signal| signal['required'] }
      end

      def signal_matches?(signal, project_root)
        case signal['type']
        when 'file_present'
          file_present?(project_root, signal['path'])
        when 'file_contains'
          file_contains?(project_root, signal['path'], signal['pattern'])
        else
          false
        end
      end

      def file_present?(project_root, relative_path)
        File.file?(File.join(project_root, relative_path))
      end

      def file_contains?(project_root, relative_path, pattern)
        absolute_path = File.join(project_root, relative_path)
        return false unless File.file?(absolute_path)

        File.read(absolute_path).match?(Regexp.new(pattern))
      end
    end
  end
end
