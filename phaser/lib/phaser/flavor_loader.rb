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
    # module string (the YAML field is optional). Raises
    # `FlavorLoadError` when the catalog DECLARED a module string but
    # the constant cannot be resolved — a misdeclared flavor must fail
    # at load time rather than silently misclassify commits later (T055,
    # FR-007 spirit).
    def self.resolve_module_constant(module_name)
      return nil if module_name.nil? || module_name.empty?

      Object.const_get(module_name)
    rescue NameError
      raise FlavorLoadError,
            "flavor declared module #{module_name.inspect} but the constant could not be resolved; " \
            'check that the companion Ruby file is shipped under the flavor directory ' \
            'and defines the named constant'
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
        **catalog_collections(catalog),
        **dispatch_attributes(catalog)
      )
    end

    def catalog_collections(catalog)
      {
        task_types: catalog['task_types'].map { |t| build_task_type(t) },
        precedent_rules: catalog['precedent_rules'].map { |r| build_precedent_rule(r) },
        inference_rules: catalog['inference_rules'].map { |r| build_inference_rule(r) },
        forbidden_operations: catalog['forbidden_operations'],
        stack_detection: build_stack_detection(catalog['stack_detection'])
      }
    end

    def dispatch_attributes(catalog)
      {
        validators: resolve_validator_constants(catalog['validators']),
        irreversible_task_types: catalog['irreversible_task_types'] || [],
        allow_parallel_backfills: catalog.fetch('allow_parallel_backfills', false)
      }
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

    # Resolve every entry in the catalog's `validators:` list to the
    # actual Ruby constant the engine instantiates and invokes (T055,
    # plan.md "Validators-list dispatch"). The companion Ruby files
    # were already required by `load_companion_ruby_files` so the
    # constants exist by the time this runs. A missing constant raises
    # `FlavorLoadError` so a misdeclared catalog fails fast at load time
    # rather than silently skipping a validator.
    def resolve_validator_constants(validators)
      Array(validators).map do |constant_name|
        self.class.resolve_module_constant(constant_name)
      end
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
    # `inference.rb` / `forbidden_operations.rb` are loaded only when the
    # catalog DECLARED a corresponding `inference_module:` /
    # `forbidden_module:` field — flavors that ship neither (e.g.,
    # `example-minimal` test fixtures) keep working without those files.
    # When the field IS declared but the file is absent, the constant
    # resolver in `resolve_module_constant` raises so the operator sees a
    # single descriptive FlavorLoadError (T055).
    def load_companion_ruby_files(name, catalog)
      flavor_dir = File.join(@flavors_root, name)
      load_inference_file(flavor_dir, catalog) if catalog['inference_module']
      load_forbidden_file(flavor_dir, catalog) if catalog['forbidden_module']
      Array(catalog['validators']).each do |validator|
        require_validator_file(flavor_dir, validator)
      end
    end

    def load_inference_file(flavor_dir, _catalog)
      path = File.join(flavor_dir, 'inference.rb')
      require path if File.file?(path)
    end

    def load_forbidden_file(flavor_dir, _catalog)
      path = File.join(flavor_dir, 'forbidden_operations.rb')
      require path if File.file?(path)
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
