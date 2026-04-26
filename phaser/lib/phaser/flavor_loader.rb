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
      load_companion_ruby_files(name, catalog)
      build_flavor(catalog)
    end

    # Resolve a fully-qualified Ruby module name (e.g.,
    # `"Phaser::Flavors::RailsPostgresStrongMigrations::Inference"`) into
    # the actual Module constant the classifier and forbidden-operations
    # gate dispatch through. Returns nil when the catalog declared no
    # module string (the YAML field is optional) OR when the named
    # constant cannot be resolved (e.g., the companion Ruby file has not
    # been shipped yet). Callers that depend on the resolved module
    # treating nil as "fall through to default" — the classifier's
    # `module_method_match?` and the gate's `module_method_match?` both
    # handle a nil module gracefully (the classifier returns false; the
    # gate raises a configuration error so the operator notices).
    #
    # NOTE: T055 will tighten this to fail fast when a declared module
    # cannot be resolved. Until then we degrade gracefully so tests for
    # individual flavor modules (T051, T052, T053, T054, T054b) can land
    # incrementally without each one having to ship every other module's
    # companion Ruby file.
    def self.resolve_module_constant(module_name)
      return nil if module_name.nil? || module_name.empty?

      Object.const_get(module_name)
    rescue NameError
      nil
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
        inference_module: self.class.resolve_module_constant(catalog['inference_module']),
        forbidden_module: self.class.resolve_module_constant(catalog['forbidden_module'])
      }
    end

    # The classifier and forbidden-operations gate dispatch through real
    # Module constants, not through the raw `inference_module` /
    # `forbidden_module` strings. Companion Ruby files
    # (`inference.rb`, `forbidden_operations.rb`, plus any per-flavor
    # validator files referenced by the `validators:` list) are loaded
    # here BEFORE constant resolution so the operator sees a single
    # `FlavorLoadError` if a file is missing instead of a NameError later
    # in the pipeline.
    #
    # Files that don't exist yet are simply skipped — incremental
    # implementation (T051..T054b) lands one module at a time, and a
    # missing file should not break flavors whose other modules ARE
    # shipped. T055 will tighten this once every reference-flavor module
    # is in place.
    def load_companion_ruby_files(name, catalog)
      flavor_dir = File.join(@flavors_root, name)
      %w[inference.rb forbidden_operations.rb].each do |file|
        path = File.join(flavor_dir, file)
        require path if File.file?(path)
      end
      Array(catalog['validators']).each do |validator|
        require_validator_file(flavor_dir, validator)
      end
    end

    # The `validators:` list in flavor.yaml references constants by their
    # fully-qualified Ruby name (e.g.,
    # `Phaser::Flavors::RailsPostgresStrongMigrations::BackfillValidator`).
    # Convert the trailing constant name to a snake_case filename and
    # require it from the flavor's directory if a matching file exists.
    def require_validator_file(flavor_dir, validator)
      constant_name = validator.split('::').last
      snake_case = constant_name
                   .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
                   .gsub(/([a-z\d])([A-Z])/, '\1_\2')
                   .downcase
      path = File.join(flavor_dir, "#{snake_case}.rb")
      require path if File.file?(path)
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
