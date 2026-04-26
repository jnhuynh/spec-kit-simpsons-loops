# frozen_string_literal: true

module Phaser
  # Common ancestor for every validation-time error so engine callers
  # can rescue the entire family with a single `rescue
  # Phaser::ValidationError` clause and forward the payload to the
  # `validation-failed` ERROR record (FR-041) and the
  # `phase-creation-status.yaml` writer (FR-042).
  #
  # The forbidden-operations gate, the precedent validator, the size
  # guard, and the safety-assertion validator all raise descendants of
  # this class so the engine's error-handling shell does not have to
  # know which validator fired.
  class ValidationError < StandardError; end

  # Raised when the active flavor declares a `module_method` detector
  # whose `forbidden_module` was not handed to the gate constructor, or
  # whose named method does not exist on that module. This is a
  # configuration error (the flavor is misdeclared), distinct from a
  # detection error (a commit matched a registered detector), so the
  # engine can surface it differently from `ForbiddenOperationError`.
  #
  # Carries a descriptive message naming the offending detector and the
  # missing module-or-method so the operator can fix `flavor.yaml`
  # without re-deriving the failure context.
  class ForbiddenOperationsConfigurationError < StandardError; end

  # Raised by the engine (NOT by the gate itself; the gate is a pure
  # decision function) when `Phaser::ForbiddenOperationsGate#evaluate`
  # returns a matching registry entry. The exception object carries the
  # four payload fields the engine relays to
  # `Observability#log_validation_failed` (FR-041) and to
  # `StatusWriter#write` (FR-042) so neither surface has to dig into
  # the raw registry-entry Hash.
  class ForbiddenOperationError < ValidationError
    attr_reader :commit_hash, :failing_rule, :forbidden_operation,
                :decomposition_message

    def initialize(commit:, entry:)
      @commit_hash = commit.hash
      @failing_rule = entry.fetch('name')
      @forbidden_operation = entry.fetch('identifier')
      @decomposition_message = entry.fetch('decomposition_message')
      super(
        "Commit #{@commit_hash} triggers forbidden operation " \
        "#{@forbidden_operation.inspect}: #{@decomposition_message}"
      )
    end

    # The four-field Hash the engine hands to
    # `Observability#log_validation_failed` and `StatusWriter#write`.
    # The status writer adds the `stage:` discriminator and the
    # observability logger adds the envelope (`level`, `timestamp`,
    # `event`); this method intentionally returns ONLY the payload
    # fields the forbidden-operation rejection mode populates so other
    # failure modes (`feature-too-large`, missing-precedent) remain
    # visually distinct in the operator-facing record.
    def to_validation_failed_payload
      {
        commit_hash: @commit_hash,
        failing_rule: @failing_rule,
        forbidden_operation: @forbidden_operation,
        decomposition_message: @decomposition_message
      }
    end
  end

  # Pure-function pre-classification gate that rejects any commit whose
  # diff matches an entry in the active flavor's forbidden-operations
  # registry (feature 007-multi-phase-pipeline; T031, FR-015, FR-041,
  # FR-042, FR-049, D-016, SC-005, SC-008, SC-015).
  #
  # Position in the engine pipeline per quickstart.md "Pattern:
  # Pre-Classification Gate Discipline":
  #
  #   def process_commit(commit, flavor)
  #     return :skip if commit.diff.empty?                              # FR-009
  #     forbidden = flavor.forbidden_operations_gate.evaluate(commit)
  #     raise ForbiddenOperationError.new(commit, forbidden) if forbidden
  #     classifier.classify(commit, flavor)                              # FR-004
  #   end
  #
  # The gate runs BEFORE the classifier — no operator-supplied type
  # tag, inference rule, or default-type cascade is consulted when a
  # forbidden operation is detected. The classifier is never invoked
  # when the gate rejects a commit (D-016 "no bypass").
  #
  # Bypass-surface contract per D-016 (SC-015):
  #
  #   * Detection is solely a function of `(commit.diff, registry)`.
  #   * No `Phase-Type:` (or any other) trailer suppresses detection.
  #   * No environment variable suppresses detection.
  #   * The constructor's keyword surface is exactly two keys —
  #     `forbidden_operations:` (required) and `forbidden_module:`
  #     (optional). No `skip:` / `force:` / `allow:` / `bypass:` /
  #     `override:` keyword exists.
  #
  # First-match-wins for determinism (FR-002, SC-002): when more than
  # one registry entry matches a commit, the FIRST in registry order is
  # returned so the chosen `name`, `identifier`, and
  # `decomposition_message` are reproducible across runs. Flavors are
  # expected to declare the most-specific detector first.
  class ForbiddenOperationsGate
    # The exact keyword surface — pinned in tests (T022) so a future
    # contributor cannot silently add a bypass keyword. Update with
    # extreme care; any new keyword here is a new bypass surface that
    # must be re-justified against D-016 / SC-015.
    def initialize(forbidden_operations:, forbidden_module: nil)
      @forbidden_operations = forbidden_operations
      @forbidden_module = forbidden_module
    end

    # Returns the matching registry entry Hash (string keys, per the
    # validated catalog Hash that flows out of `FlavorLoader`) when ANY
    # detector in the registry matches the commit's diff; otherwise
    # returns nil. The engine wraps a non-nil return in
    # `Phaser::ForbiddenOperationError` and persists the payload via
    # `StatusWriter` per FR-042 — the gate itself never raises a
    # `ForbiddenOperationError` (it is a pure decision function).
    #
    # Raises `Phaser::ForbiddenOperationsConfigurationError` (NOT
    # `ForbiddenOperationError`) when a `module_method` detector is
    # misdeclared — this is a flavor-authoring mistake, distinct from a
    # commit-rejection event.
    def evaluate(commit)
      @forbidden_operations.each do |entry|
        return entry if detector_matches?(entry, commit)
      end
      nil
    end

    private

    def detector_matches?(entry, commit)
      detector = entry.fetch('detector')
      case detector.fetch('kind')
      when 'file_glob'     then file_glob_match?(detector, commit)
      when 'path_regex'    then path_regex_match?(detector, commit)
      when 'content_regex' then content_regex_match?(detector, commit)
      when 'module_method' then module_method_match?(detector, commit, entry)
      else
        # Unknown detector kinds are not silently accepted: the flavor
        # loader is responsible for rejecting unsupported shapes via
        # contracts/flavor.schema.yaml's Match oneOf. Fail closed if one
        # slips through so the determinism contract is not silently
        # violated.
        false
      end
    end

    def file_glob_match?(detector, commit)
      pattern = detector.fetch('pattern')
      commit.diff.files.any? do |file|
        File.fnmatch?(pattern, file.path, File::FNM_PATHNAME)
      end
    end

    def path_regex_match?(detector, commit)
      regex = Regexp.new(detector.fetch('pattern'))
      commit.diff.files.any? { |file| regex.match?(file.path) }
    end

    def content_regex_match?(detector, commit)
      path_glob = detector.fetch('path_glob')
      regex = Regexp.new(detector.fetch('pattern'))
      commit.diff.files.any? do |file|
        next false unless File.fnmatch?(path_glob, file.path, File::FNM_PATHNAME)

        file.hunks.any? { |hunk| regex.match?(hunk) }
      end
    end

    def module_method_match?(detector, commit, entry)
      method_name = detector.fetch('method').to_sym
      ensure_module_declared!(entry)
      ensure_method_present!(method_name, entry)
      @forbidden_module.public_send(method_name, commit)
    end

    def ensure_module_declared!(entry)
      return unless @forbidden_module.nil?

      raise ForbiddenOperationsConfigurationError,
            "Forbidden-operation #{entry.fetch('name').inspect} declares a " \
            'module_method detector but no forbidden_module was passed to ' \
            'Phaser::ForbiddenOperationsGate.new(forbidden_module: ...). ' \
            "Wire the flavor's forbidden_module through FlavorLoader before " \
            'invoking the gate.'
    end

    def ensure_method_present!(method_name, entry)
      return if @forbidden_module.respond_to?(method_name)

      raise ForbiddenOperationsConfigurationError,
            "Forbidden-operation #{entry.fetch('name').inspect} declares " \
            "module_method detector #{method_name.inspect} but the " \
            'configured forbidden_module does not respond to that method. ' \
            "Define ##{method_name}(commit) on the module or correct the " \
            'method name in flavor.yaml.'
    end
  end
end
