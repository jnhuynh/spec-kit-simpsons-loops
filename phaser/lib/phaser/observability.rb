# frozen_string_literal: true

require 'json'
require 'time'

module Phaser
  # JSON-line stderr observability surface for the phaser engine and
  # the stacked-PR creator (feature 007-multi-phase-pipeline; FR-041,
  # FR-043, FR-047, SC-011, SC-013, plan.md D-011).
  #
  # Contract (see contracts/observability-events.md):
  #
  #   * Every emitted record is a single JSON object terminated by `\n`
  #     and written to the stderr stream the logger was constructed with.
  #     stdout is reserved for downstream-consumable output (manifest
  #     path on engine success, run summary on creator success); the
  #     logger MUST never write to stdout (FR-043, plan.md D-011).
  #
  #   * Every record carries the common envelope `level`, `timestamp`,
  #     `event` (data-model.md "ObservabilityEvent").
  #
  #   * The `now:` constructor argument injects the clock so tests and
  #     deterministic engine runs can pin `timestamp` (FR-002, SC-002,
  #     SC-011). When omitted, a real ISO-8601 UTC clock with
  #     millisecond precision is used.
  #
  #   * Per-event payload shapes for `commit-classified`,
  #     `phase-emitted`, `commit-skipped-empty-diff`, and
  #     `validation-failed` match the schemas in
  #     contracts/observability-events.md.
  #
  #   * Credential-leak guard (FR-047, SC-013): every string-typed field
  #     value is scanned for credential patterns before the record is
  #     written. On a match, the field is replaced with the redaction
  #     marker and a separate WARN record `credential-pattern-redacted`
  #     is emitted naming the field (but not the matching value).
  class Observability
    REDACTION_MARKER = '[REDACTED:credential-pattern-match]'

    # Patterns drawn from contracts/observability-events.md "Credential-Leak
    # Guard". Each pattern is checked against every string-typed field
    # value (including the values nested inside arrays of strings or
    # hashes that hold strings). The patterns are intentionally broad —
    # the redaction record names the field, not the value, so a
    # false-positive is recoverable; a false-negative is not.
    CREDENTIAL_PATTERNS = [
      /ghp_[A-Za-z0-9]+/,
      /gho_[A-Za-z0-9]+/,
      /ghu_[A-Za-z0-9]+/,
      /ghs_[A-Za-z0-9]+/,
      /ghr_[A-Za-z0-9]+/,
      /Bearer\s+\S+/,
      /Authorization:\s*\S+/i,
      /Cookie:\s*\S+/i
    ].freeze

    # Construct a logger.
    #
    #   * stderr — IO-like object that responds to `write`. The engine
    #              passes `$stderr`; tests pass a `StringIO` so the
    #              emitted bytes are inspectable.
    #   * now    — zero-arg callable returning the timestamp string for
    #              the current emission. Defaults to a real ISO-8601 UTC
    #              clock with millisecond precision.
    def initialize(stderr:, now: nil)
      @stderr = stderr
      @now = now || method(:default_now)
    end

    # INFO: emitted once per non-empty commit after classification
    # succeeds. `rule_name` is only meaningful when `source = :inference`
    # and is omitted otherwise. `precedents_consulted` is omitted when
    # nil. The keyword surface is bundled into a single options hash to
    # keep the public method's parameter count within the project's
    # community-default limit while preserving the keyword-style call
    # contract documented in the spec file.
    def log_commit_classified(**options)
      payload = {
        commit_hash: options.fetch(:commit_hash),
        task_type: options.fetch(:task_type),
        source: options.fetch(:source).to_s,
        isolation: options.fetch(:isolation).to_s
      }
      rule_name = options[:rule_name]
      payload[:rule_name] = rule_name if options[:source] == :inference && rule_name
      precedents = options[:precedents_consulted]
      payload[:precedents_consulted] = precedents unless precedents.nil?
      emit(level: 'INFO', event: 'commit-classified', payload: payload)
    end

    # INFO: emitted once per phase as the phase is added to the manifest.
    # Tasks are normalized to plain hashes with string keys to match the
    # JSON shape defined in contracts/observability-events.md.
    def log_phase_emitted(phase_number:, branch_name:, base_branch:, tasks:)
      payload = {
        phase_number: phase_number,
        branch_name: branch_name,
        base_branch: base_branch,
        tasks: serialize_tasks(tasks)
      }
      emit(level: 'INFO', event: 'phase-emitted', payload: payload)
    end

    # WARN: emitted once per commit skipped under FR-009 (empty diff).
    def log_commit_skipped_empty_diff(commit_hash:)
      emit(
        level: 'WARN',
        event: 'commit-skipped-empty-diff',
        payload: { commit_hash: commit_hash, reason: 'empty-diff' }
      )
    end

    # ERROR: emitted exactly once when the engine fails on validation.
    # All payload keys other than `failing_rule` are optional — the
    # caller passes only the ones relevant to the failure class
    # (commit-attributable failures carry `commit_hash`; precedent
    # failures carry `missing_precedent`; forbidden-operation failures
    # carry `forbidden_operation` + `decomposition_message`;
    # `feature-too-large` carries `commit_count` + `phase_count` and
    # NOT `commit_hash`). The keyword surface is bundled into a single
    # options hash so the method honors the project's parameter-count
    # limit while still being called with explicit keyword arguments.
    VALIDATION_FAILED_OPTIONAL_KEYS = %i[
      commit_hash
      missing_precedent
      forbidden_operation
      decomposition_message
      commit_count
      phase_count
    ].freeze

    def log_validation_failed(**options)
      payload = { failing_rule: options.fetch(:failing_rule) }
      VALIDATION_FAILED_OPTIONAL_KEYS.each do |key|
        value = options[key]
        payload[key] = value unless value.nil?
      end
      emit(level: 'ERROR', event: 'validation-failed', payload: payload)
    end

    # INFO: emitted exactly once after the stacked-PR creator's
    # `gh auth status` probe completes (FR-045, contracts/observability-events.md
    # "auth-probe-result"). The `host` and `scopes` fields are best-effort
    # parsed by the AuthProbe; on auth-missing they may be nil/empty —
    # the contract still requires the event so the operator sees a
    # negative-result record alongside any subsequent ERROR record.
    def log_auth_probe_result(host:, authenticated:, scopes:)
      payload = {
        host: host,
        authenticated: authenticated,
        scopes: scopes
      }
      emit(level: 'INFO', event: 'auth-probe-result', payload: payload)
    end

    # ERROR: emitted exactly once on stacked-PR creator failure
    # (contracts/observability-events.md "phase-creation-failed";
    # FR-045, FR-046, FR-047, SC-012, SC-013). For auth-probe failures
    # the `phase_number` is always `1` (no branch creation has been
    # attempted yet); for per-phase failures the creator passes the
    # phase number that failed. The `summary` field carries the first
    # line of `gh`'s stderr — credential-pattern sanitization applies
    # automatically through `emit` so a stderr line that happens to
    # carry a token is redacted before the record reaches disk.
    def log_phase_creation_failed(phase_number:, failure_class:, gh_exit_code:, summary:)
      payload = {
        phase_number: phase_number,
        failure_class: failure_class,
        gh_exit_code: gh_exit_code,
        summary: summary
      }
      emit(level: 'ERROR', event: 'phase-creation-failed', payload: payload)
    end

    private

    # Apply the credential-leak guard, then write the resulting record
    # plus any redaction WARN records to stderr. The redaction WARN
    # records are emitted BEFORE the main record so an operator
    # scanning the log top-down sees the leak warning in proximity to
    # the affected event.
    def emit(level:, event:, payload:)
      sanitized_payload, redacted_fields = sanitize_payload(payload)

      redacted_fields.each do |field_name|
        write_record(
          level: 'WARN',
          event: 'credential-pattern-redacted',
          payload: { field: field_name.to_s }
        )
      end

      write_record(level: level, event: event, payload: sanitized_payload)
    end

    def write_record(level:, event:, payload:)
      record = {
        'level' => level,
        'timestamp' => @now.call,
        'event' => event
      }
      payload.each { |key, value| record[key.to_s] = value }
      @stderr.write("#{JSON.generate(record)}\n")
    end

    # Walk the payload looking for credential-shaped string values and
    # replace any matches with the redaction marker. Returns the
    # sanitized payload and the list of top-level field names whose
    # values were redacted (the redaction WARN names only the top-level
    # field — nested redactions still count as a redaction of their
    # enclosing field).
    def sanitize_payload(payload)
      redacted_fields = []
      sanitized = payload.each_with_object({}) do |(field_name, value), acc|
        if value.is_a?(String) && credential_pattern_match?(value)
          acc[field_name] = REDACTION_MARKER
          redacted_fields << field_name
        else
          sanitized_value, child_redacted = sanitize_value(value)
          acc[field_name] = sanitized_value
          redacted_fields << field_name if child_redacted
        end
      end
      [sanitized, redacted_fields]
    end

    # Recursively sanitize a non-top-level value. Returns the
    # sanitized value and a boolean indicating whether any string
    # inside it was redacted. Dispatches by type to per-shape helpers
    # that each carry a single responsibility.
    def sanitize_value(value)
      case value
      when String then sanitize_string(value)
      when Array  then sanitize_array(value)
      when Hash   then sanitize_hash(value)
      else [value, false]
      end
    end

    def sanitize_string(value)
      return [REDACTION_MARKER, true] if credential_pattern_match?(value)

      [value, false]
    end

    def sanitize_array(array)
      any_redacted = false
      sanitized = array.map do |element|
        sanitized_element, element_redacted = sanitize_value(element)
        any_redacted ||= element_redacted
        sanitized_element
      end
      [sanitized, any_redacted]
    end

    def sanitize_hash(hash)
      any_redacted = false
      sanitized = hash.each_with_object({}) do |(key, child_value), acc|
        sanitized_child, child_redacted = sanitize_value(child_value)
        acc[key] = sanitized_child
        any_redacted ||= child_redacted
      end
      [sanitized, any_redacted]
    end

    def credential_pattern_match?(string)
      CREDENTIAL_PATTERNS.any? { |pattern| string.match?(pattern) }
    end

    # Normalize tasks (which may arrive as Hashes or Phaser::Task
    # value objects) into the array-of-string-keyed-hashes shape
    # documented in contracts/observability-events.md. Each task
    # entry must be `{commit_hash, task_type}`.
    def serialize_tasks(tasks)
      tasks.map do |task|
        if task.respond_to?(:to_h)
          task_hash = task.to_h
          { 'commit_hash' => task_hash[:commit_hash] || task_hash['commit_hash'],
            'task_type' => task_hash[:task_type] || task_hash['task_type'] }
        else
          { 'commit_hash' => task[:commit_hash], 'task_type' => task[:task_type] }
        end
      end
    end

    # Default clock: ISO-8601 UTC with millisecond precision (the
    # format pinned by contracts/observability-events.md "Common
    # Fields"). Time#iso8601(3) emits the `+00:00` suffix on a UTC
    # time, so we substitute the `Z` suffix the contract requires.
    def default_now
      Time.now.utc.iso8601(3).sub(/\+00:00\z/, 'Z')
    end
  end
end
