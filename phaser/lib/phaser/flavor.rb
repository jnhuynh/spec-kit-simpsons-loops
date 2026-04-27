# frozen_string_literal: true

module Phaser
  # The in-memory representation of a shipped flavor catalog after the
  # `Phaser::FlavorLoader` has read `phaser/flavors/<name>/flavor.yaml`,
  # validated it against `contracts/flavor.schema.yaml`, and wrapped the
  # validated content in a stable, immutable value object the engine can
  # consume (feature 007-multi-phase-pipeline; T019, data-model.md
  # "Flavor").
  #
  # Attributes correspond one-to-one with the Flavor entity in
  # data-model.md. Nested catalog entries (task types, precedent rules,
  # inference rules) are themselves `Data.define` value objects so the
  # engine never has to dig through raw Hashes when reasoning about a
  # rule. The `stack_detection`, `forbidden_operations`, and `match`
  # payloads remain as Hashes (with string keys) because their content is
  # consumed directly by the matcher / signal evaluators which already
  # know how to interpret the shapes declared in `contracts/`.
  #
  # Implemented as a plain class (rather than `Data.define`) so test
  # seams can extend a constructed flavor with `define_singleton_method`
  # — the safety-assertion validator's spec (T046b) uses that surface to
  # mirror the future `irreversible_task_types` accessor without
  # prematurely committing the test to the loader's exact field name.
  # The public surface still exposes only readers (no writers) and
  # raises ArgumentError naming the missing keyword for any required
  # attribute, matching what the codebase relied on from `Data.define`.
  class Flavor
    REQUIRED_ATTRIBUTES = %i[
      name version default_type task_types precedent_rules
      inference_rules forbidden_operations stack_detection
    ].freeze

    OPTIONAL_ATTRIBUTES = {
      inference_module: nil,
      forbidden_module: nil,
      validators: [],
      irreversible_task_types: [],
      allow_parallel_backfills: false
    }.freeze

    attr_reader :name, :version, :default_type, :task_types,
                :precedent_rules, :inference_rules, :forbidden_operations,
                :stack_detection, :inference_module, :forbidden_module,
                :validators, :irreversible_task_types,
                :allow_parallel_backfills

    # rubocop:disable Metrics/ParameterLists
    def initialize(name:, version:, default_type:, task_types:,
                   precedent_rules:, inference_rules:, forbidden_operations:,
                   stack_detection:, inference_module: nil,
                   forbidden_module: nil, validators: [],
                   irreversible_task_types: [],
                   allow_parallel_backfills: false)
      # rubocop:enable Metrics/ParameterLists
      @name = name
      @version = version
      @default_type = default_type
      @task_types = task_types
      @precedent_rules = precedent_rules
      @inference_rules = inference_rules
      @forbidden_operations = forbidden_operations
      @stack_detection = stack_detection
      @inference_module = inference_module
      @forbidden_module = forbidden_module
      @validators = validators
      @irreversible_task_types = irreversible_task_types
      @allow_parallel_backfills = allow_parallel_backfills
    end
  end

  # A named category of work declared by a flavor.
  #
  # `isolation` is normalized to a Ruby symbol (`:alone` or `:groups`) at
  # load time so the engine can pattern-match on it directly without
  # re-parsing the YAML string on every lookup.
  FlavorTaskType = Data.define(:name, :isolation, :description)

  # A flavor-declared statement that one task type must appear in a
  # strictly later phase than another.
  FlavorPrecedentRule = Data.define(
    :name, :subject_type, :predecessor_type, :error_message
  )

  # A file-pattern or content-pattern rule that classifies a commit
  # without operator intervention.
  FlavorInferenceRule = Data.define(:name, :precedence, :task_type, :match)

  # Stack-detection signals consumed by `phaser-flavor-init`. Signals
  # remain as Hashes (string keys) because the StackDetector evaluates
  # them directly per the `contracts/flavor.schema.yaml` Signal variants.
  FlavorStackDetection = Data.define(:signals)
end
