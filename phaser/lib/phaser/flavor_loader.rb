# frozen_string_literal: true

require 'psych'
require 'phaser/flavor_catalog_validator'

module Phaser
  # Rescuable ancestor for every load-time failure surfaced by
  # `Phaser::FlavorLoader`. The engine wraps `loader.load(name)` in a
  # single `rescue Phaser::FlavorLoadError` clause so any malformed
  # catalog (or unknown flavor name) is reported uniformly.
  class FlavorLoadError < StandardError; end

  # Raised when `.specify/flavor.yaml` (or a CLI argument) names a
  # flavor that has not been shipped under `phaser/flavors/`. The error
  # message lists every shipped flavor so the operator can correct the
  # typo or pick a real flavor name without inspecting the source tree.
  class FlavorNotFoundError < FlavorLoadError; end

  # Reads a shipped flavor catalog from
  # `phaser/flavors/<name>/flavor.yaml`, validates it via
  # `Phaser::FlavorCatalogValidator`, and returns a `Phaser::Flavor`
  # value object the engine can consume (feature
  # 007-multi-phase-pipeline; T019, plan.md "Pattern: Flavor Loader" /
  # D-002, research.md R-003).
  #
  # The loader is the single ingress for flavor data. Validation is
  # fail-fast and load-time so a malformed catalog can never reach the
  # engine and corrupt the manifest. Filesystem IO and the conversion
  # from raw catalog Hash to immutable value object live here; the
  # schema/cross-field rules live in `FlavorCatalogValidator` so each
  # surface stays small and testable.
  class FlavorLoader
    DEFAULT_FLAVORS_ROOT = File.expand_path('../../flavors', __dir__)

    # Construct a loader pointed at the given flavors root directory.
    # Defaults to the shipped `phaser/flavors/` tree so production
    # callers don't need to know the path; tests inject a temp directory
    # to keep fixtures hermetic.
    def initialize(flavors_root: DEFAULT_FLAVORS_ROOT)
      @flavors_root = flavors_root
    end

    # Load and validate the named flavor. Returns a `Phaser::Flavor`.
    #
    # Raises:
    #   * `Phaser::FlavorNotFoundError` when no `flavor.yaml` exists
    #     under `<flavors_root>/<name>/`. Message lists shipped flavors.
    #   * `Phaser::FlavorLoadError` when the YAML is unparseable, the
    #     schema is violated, a cross-field rule fails, or the catalog's
    #     own `name` does not match the directory it ships under.
    def load(name)
      catalog = parse_catalog(name)
      FlavorCatalogValidator.new(name, catalog).validate!
      build_flavor(catalog)
    end

    # Names of every shipped flavor under the loader's flavors root.
    # Reused by `phaser-flavor-init` to enumerate candidates and by the
    # FlavorNotFoundError message body.
    def shipped_flavor_names
      return [] unless Dir.exist?(@flavors_root)

      Dir.children(@flavors_root).select do |entry|
        File.file?(File.join(@flavors_root, entry, 'flavor.yaml'))
      end.sort
    end

    private

    def parse_catalog(name)
      path = File.join(@flavors_root, name, 'flavor.yaml')
      raise FlavorNotFoundError, flavor_not_found_message(name) unless File.file?(path)

      begin
        Psych.safe_load(File.read(path), permitted_classes: [], aliases: false)
      rescue Psych::SyntaxError => e
        raise FlavorLoadError, "flavor #{name.inspect} has invalid YAML: #{e.message}"
      end
    end

    def flavor_not_found_message(name)
      shipped = shipped_flavor_names
      shipped_list = shipped.empty? ? '(none shipped)' : shipped.join(', ')
      "flavor #{name.inspect} not found under #{@flavors_root}; " \
        "shipped flavors: #{shipped_list}"
    end

    # Convert the validated raw catalog Hash into the immutable Flavor
    # value object the engine consumes. Nested catalog entries are
    # wrapped in their own Data.define value objects so the engine can
    # read attributes via accessors (and `isolation` is normalized to a
    # Ruby symbol so the IsolationResolver does not have to re-parse the
    # YAML string per commit).
    def build_flavor(catalog)
      Flavor.new(
        **identity_attributes(catalog),
        task_types: catalog['task_types'].map { |t| build_task_type(t) },
        precedent_rules: catalog['precedent_rules'].map { |r| build_precedent_rule(r) },
        inference_rules: catalog['inference_rules'].map { |r| build_inference_rule(r) },
        forbidden_operations: catalog['forbidden_operations'],
        stack_detection: build_stack_detection(catalog['stack_detection']),
        validators: catalog['validators'] || [],
        allow_parallel_backfills: catalog.fetch('allow_parallel_backfills', false)
      )
    end

    def identity_attributes(catalog)
      {
        name: catalog['name'],
        version: catalog['version'],
        default_type: catalog['default_type'],
        inference_module: catalog['inference_module'],
        forbidden_module: catalog['forbidden_module']
      }
    end

    def build_task_type(task_type)
      FlavorTaskType.new(
        name: task_type['name'],
        isolation: task_type['isolation'].to_sym,
        description: task_type['description']
      )
    end

    def build_precedent_rule(rule)
      FlavorPrecedentRule.new(
        name: rule['name'],
        subject_type: rule['subject_type'],
        predecessor_type: rule['predecessor_type'],
        error_message: rule['error_message']
      )
    end

    def build_inference_rule(rule)
      FlavorInferenceRule.new(
        name: rule['name'],
        precedence: rule['precedence'],
        task_type: rule['task_type'],
        match: rule['match']
      )
    end

    def build_stack_detection(stack_detection)
      FlavorStackDetection.new(signals: stack_detection['signals'])
    end
  end
end
