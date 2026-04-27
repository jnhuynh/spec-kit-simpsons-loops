# frozen_string_literal: true

require 'phaser/precedent_rule_graph'

module Phaser
  # Validates a parsed flavor catalog Hash against
  # `contracts/flavor.schema.yaml` plus the cross-field rules listed in
  # data-model.md "Flavor" Validation rules. Used internally by
  # `Phaser::FlavorLoader#load`; exposed as a separate class so the
  # validator's surface area stays small and testable in isolation
  # (feature 007-multi-phase-pipeline; T019).
  #
  # The validator is fail-fast: the first violation it encounters is
  # raised as a descriptive `Phaser::FlavorLoadError` naming both the
  # flavor and the specific violation. Validation passes are organized
  # by schema concern (top-level keys → identity → task types → rules
  # → operations → stack detection) so the error message clearly points
  # the operator at the field they need to fix.
  #
  # This class enumerates every validation rule from
  # contracts/flavor.schema.yaml plus the cross-field rules from
  # data-model.md; splitting further would add indirection without
  # separating responsibilities.
  # rubocop:disable Metrics/ClassLength
  class FlavorCatalogValidator
    VALID_ISOLATIONS = %w[alone groups].freeze
    NAME_PATTERN = /\A[a-z][a-z0-9-]*\z/
    VERSION_PATTERN = /\A[0-9]+\.[0-9]+\.[0-9]+\z/
    VALID_MATCH_KINDS = %w[file_glob path_regex content_regex module_method].freeze
    VALID_SIGNAL_TYPES = %w[file_present file_contains].freeze

    REQUIRED_TOP_LEVEL_KEYS = %w[
      name version default_type task_types precedent_rules
      inference_rules forbidden_operations stack_detection
    ].freeze

    SIGNAL_REQUIRED_FIELDS = {
      'file_present' => %w[path required],
      'file_contains' => %w[path pattern required]
    }.freeze

    def initialize(directory_name, catalog)
      @directory_name = directory_name
      @catalog = catalog
    end

    # Run every validation pass in dependency order. Raises the first
    # violation as a `Phaser::FlavorLoadError`.
    def validate!
      raise FlavorLoadError, "flavor #{@directory_name.inspect} catalog must be a mapping" \
        unless @catalog.is_a?(Hash)

      validate_required_top_level_keys!
      validate_name_matches_directory!
      validate_version_format!
      validate_task_types!
      validate_default_type!
      validate_precedent_rules!
      validate_inference_rules!
      validate_forbidden_operations!
      validate_stack_detection!
      validate_validators_list!
      validate_irreversible_task_types!
    end

    private

    def validate_required_top_level_keys!
      REQUIRED_TOP_LEVEL_KEYS.each do |key|
        next if @catalog.key?(key)

        raise FlavorLoadError,
              "flavor #{@directory_name.inspect} is missing required key #{key.inspect}"
      end
    end

    def validate_name_matches_directory!
      name = @catalog['name']
      raise FlavorLoadError, "flavor #{@directory_name.inspect} has non-string name" \
        unless name.is_a?(String)

      unless name.match?(NAME_PATTERN)
        raise FlavorLoadError,
              "flavor #{@directory_name.inspect} name #{name.inspect} must match #{NAME_PATTERN.source}"
      end

      return if name == @directory_name

      raise FlavorLoadError,
            "flavor directory #{@directory_name.inspect} declares mismatched name #{name.inspect}; " \
            'the flavor.yaml name field MUST equal the directory name'
    end

    def validate_version_format!
      version = @catalog['version']
      return if version.is_a?(String) && version.match?(VERSION_PATTERN)

      raise FlavorLoadError,
            "flavor #{@directory_name.inspect} version #{version.inspect} must be semver (MAJOR.MINOR.PATCH)"
    end

    def validate_task_types!
      task_types = @catalog['task_types']
      raise FlavorLoadError, "flavor #{@directory_name.inspect} task_types must be a non-empty list" \
        unless task_types.is_a?(Array) && !task_types.empty?

      task_types.each_with_index { |task_type, index| validate_task_type_entry!(task_type, index) }
      validate_task_type_names_unique!(task_types)
    end

    def validate_task_type_entry!(task_type, index)
      raise_unless_mapping!(task_type, "task_types[#{index}]")
      require_present_string_fields!(task_type, %w[name isolation description], "task_types[#{index}]")
      validate_task_type_isolation!(task_type, index)
    end

    def validate_task_type_isolation!(task_type, index)
      return if VALID_ISOLATIONS.include?(task_type['isolation'])

      raise FlavorLoadError,
            "flavor #{@directory_name.inspect} task_types[#{index}] isolation " \
            "#{task_type['isolation'].inspect} must be one of #{VALID_ISOLATIONS.inspect}"
    end

    def validate_task_type_names_unique!(task_types)
      names = task_types.map { |t| t['name'] }
      duplicates = names.tally.select { |_, count| count > 1 }.keys
      return if duplicates.empty?

      raise FlavorLoadError,
            "flavor #{@directory_name.inspect} task_types contain duplicate name(s): #{duplicates.inspect}"
    end

    def validate_default_type!
      default = @catalog['default_type']
      return if task_type_names.include?(default)

      raise FlavorLoadError,
            "flavor #{@directory_name.inspect} default_type #{default.inspect} must appear in task_types " \
            "(known task_types: #{task_type_names.inspect})"
    end

    def validate_precedent_rules!
      rules = @catalog['precedent_rules']
      raise FlavorLoadError, "flavor #{@directory_name.inspect} precedent_rules must be a list" \
        unless rules.is_a?(Array)

      rules.each_with_index { |rule, index| validate_precedent_rule_entry!(rule, index) }
      validate_precedent_rule_graph_acyclic!(rules)
    end

    def validate_precedent_rule_entry!(rule, index)
      raise_unless_mapping!(rule, "precedent_rules[#{index}]")
      require_present_string_fields!(
        rule, %w[name subject_type predecessor_type error_message], "precedent_rules[#{index}]"
      )
      validate_precedent_rule_type_refs!(rule, index)
      validate_precedent_rule_not_self_loop!(rule, index)
    end

    def validate_precedent_rule_type_refs!(rule, index)
      %w[subject_type predecessor_type].each do |field|
        type_name = rule[field]
        next if task_type_names.include?(type_name)

        raise FlavorLoadError,
              "flavor #{@directory_name.inspect} precedent_rules[#{index}] #{field} " \
              "#{type_name.inspect} is not a known task type (known: #{task_type_names.inspect})"
      end
    end

    def validate_precedent_rule_not_self_loop!(rule, index)
      return unless rule['subject_type'] == rule['predecessor_type']

      raise FlavorLoadError,
            "flavor #{@directory_name.inspect} precedent_rules[#{index}] is a self-loop " \
            "(subject == predecessor == #{rule['subject_type'].inspect})"
    end

    # Reject the flavor when the precedent-rule graph contains a cycle;
    # the cycle detection itself lives in `PrecedentRuleGraph` so the
    # validator does not have to carry the topo-sort bookkeeping.
    def validate_precedent_rule_graph_acyclic!(rules)
      return if PrecedentRuleGraph.acyclic?(rules)

      raise FlavorLoadError,
            "flavor #{@directory_name.inspect} precedent_rules contain a cycle"
    end

    def validate_inference_rules!
      rules = @catalog['inference_rules']
      raise FlavorLoadError, "flavor #{@directory_name.inspect} inference_rules must be a list" \
        unless rules.is_a?(Array)

      rules.each_with_index { |rule, index| validate_inference_rule_entry!(rule, index) }
    end

    def validate_inference_rule_entry!(rule, index)
      raise_unless_mapping!(rule, "inference_rules[#{index}]")
      require_present_string_fields!(rule, %w[name task_type match], "inference_rules[#{index}]")
      validate_inference_rule_precedence!(rule, index)
      validate_inference_rule_task_type!(rule, index)
      validate_match!(rule['match'], "inference_rules[#{index}].match",
                      catalog_inference_module: @catalog['inference_module'])
    end

    def validate_inference_rule_precedence!(rule, index)
      return if rule['precedence'].is_a?(Integer) && rule['precedence'] >= 0

      raise FlavorLoadError,
            "flavor #{@directory_name.inspect} inference_rules[#{index}] precedence " \
            "#{rule['precedence'].inspect} must be a non-negative integer"
    end

    def validate_inference_rule_task_type!(rule, index)
      return if task_type_names.include?(rule['task_type'])

      raise FlavorLoadError,
            "flavor #{@directory_name.inspect} inference_rules[#{index}] task_type " \
            "#{rule['task_type'].inspect} is not a known task type " \
            "(known: #{task_type_names.inspect})"
    end

    def validate_forbidden_operations!
      operations = @catalog['forbidden_operations']
      raise FlavorLoadError, "flavor #{@directory_name.inspect} forbidden_operations must be a list" \
        unless operations.is_a?(Array)

      operations.each_with_index { |operation, index| validate_forbidden_operation_entry!(operation, index) }
    end

    def validate_forbidden_operation_entry!(operation, index)
      raise_unless_mapping!(operation, "forbidden_operations[#{index}]")
      require_present_string_fields!(
        operation, %w[name identifier detector decomposition_message], "forbidden_operations[#{index}]"
      )
      validate_match!(operation['detector'], "forbidden_operations[#{index}].detector",
                      catalog_inference_module: @catalog['forbidden_module'])
    end

    def validate_match!(match, location, catalog_inference_module:)
      raise_unless_mapping!(match, location)

      kind = match['kind']
      unless VALID_MATCH_KINDS.include?(kind)
        raise FlavorLoadError,
              "flavor #{@directory_name.inspect} #{location} kind #{kind.inspect} must be one of " \
              "#{VALID_MATCH_KINDS.inspect}"
      end

      validate_match_shape!(match, location, catalog_inference_module)
    end

    def validate_match_shape!(match, location, catalog_inference_module)
      case match['kind']
      when 'file_glob', 'path_regex'
        require_match_field!(match, location, 'pattern')
      when 'content_regex'
        require_match_field!(match, location, 'path_glob')
        require_match_field!(match, location, 'pattern')
      when 'module_method'
        require_match_field!(match, location, 'method')
        return unless catalog_inference_module.nil?

        raise FlavorLoadError,
              "flavor #{@directory_name.inspect} #{location} kind=module_method requires " \
              'the flavor to declare an inference_module or forbidden_module'
      end
    end

    def require_match_field!(match, location, field)
      value = match[field]
      return if value.is_a?(String) && !value.empty?

      raise FlavorLoadError,
            "flavor #{@directory_name.inspect} #{location} is missing #{field.inspect}"
    end

    def validate_stack_detection!
      stack_detection = @catalog['stack_detection']
      unless stack_detection.is_a?(Hash) && stack_detection['signals'].is_a?(Array)
        raise FlavorLoadError,
              "flavor #{@directory_name.inspect} stack_detection must be a mapping with a 'signals' list"
      end

      stack_detection['signals'].each_with_index do |signal, index|
        validate_stack_detection_signal!(signal, index)
      end
    end

    def validate_stack_detection_signal!(signal, index)
      raise_unless_mapping!(signal, "stack_detection.signals[#{index}]")

      type = signal['type']
      unless VALID_SIGNAL_TYPES.include?(type)
        raise FlavorLoadError,
              "flavor #{@directory_name.inspect} stack_detection.signals[#{index}] type " \
              "#{type.inspect} must be one of #{VALID_SIGNAL_TYPES.inspect}"
      end

      validate_signal_shape!(signal, index, type)
    end

    def validate_signal_shape!(signal, index, type)
      require_present_string_fields!(
        signal, SIGNAL_REQUIRED_FIELDS.fetch(type), "stack_detection.signals[#{index}]"
      )
      validate_signal_required_boolean!(signal, index)
    end

    def validate_signal_required_boolean!(signal, index)
      return if [true, false].include?(signal['required'])

      raise FlavorLoadError,
            "flavor #{@directory_name.inspect} stack_detection.signals[#{index}] required " \
            "#{signal['required'].inspect} must be a boolean"
    end

    # Memoized list of declared task type names. Reused by every
    # cross-reference check so the same Array is built once per
    # validation run (rather than once per rule entry).
    def task_type_names
      @task_type_names ||= @catalog['task_types'].map { |t| t['name'] }
    end

    def raise_unless_mapping!(value, location)
      return if value.is_a?(Hash)

      raise FlavorLoadError,
            "flavor #{@directory_name.inspect} #{location} must be a mapping"
    end

    def require_present_string_fields!(hash, fields, location)
      fields.each do |field|
        next if hash.key?(field) && !hash[field].nil? && hash[field] != ''

        raise FlavorLoadError,
              "flavor #{@directory_name.inspect} #{location} is missing #{field.inspect}"
      end
    end

    # The optional `validators:` list names per-flavor Ruby modules
    # (fully-qualified constant strings) the engine invokes after the
    # engine-level PrecedentValidator. Each entry must be a non-empty
    # string; the loader resolves the constants and raises a separate
    # FlavorLoadError when a constant cannot be resolved (T055).
    def validate_validators_list!
      validators = @catalog['validators']
      return if validators.nil?

      unless validators.is_a?(Array)
        raise FlavorLoadError,
              "flavor #{@directory_name.inspect} validators must be a list of constant names"
      end

      validators.each_with_index do |validator, index|
        next if validator.is_a?(String) && !validator.empty?

        raise FlavorLoadError,
              "flavor #{@directory_name.inspect} validators[#{index}] must be a non-empty string"
      end
    end

    # The optional `irreversible_task_types:` list names task types whose
    # commits the SafetyAssertionValidator (T054b, FR-018, plan.md D-017)
    # requires `Safety-Assertion:` trailers on. Every entry must be the
    # name of a declared task type so a typo cannot silently bypass the
    # safety-assertion contract.
    def validate_irreversible_task_types!
      irreversible = @catalog['irreversible_task_types']
      return if irreversible.nil?

      unless irreversible.is_a?(Array)
        raise FlavorLoadError,
              "flavor #{@directory_name.inspect} irreversible_task_types must be a list of task type names"
      end

      irreversible.each_with_index do |type_name, index|
        next if task_type_names.include?(type_name)

        raise FlavorLoadError,
              "flavor #{@directory_name.inspect} irreversible_task_types[#{index}] " \
              "#{type_name.inspect} is not a known task type (known: #{task_type_names.inspect})"
      end
    end
  end
  # rubocop:enable Metrics/ClassLength
end
