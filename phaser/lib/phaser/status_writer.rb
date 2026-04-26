# frozen_string_literal: true

require 'phaser/internal/atomic_yaml_writer'
require 'phaser/internal/iso8601_clock'

module Phaser
  # Stable-key-order YAML emitter that serializes
  # `<FEATURE_DIR>/phase-creation-status.yaml` whenever the phaser engine
  # or the stacked-PR creator exits non-zero (feature
  # 007-multi-phase-pipeline; T017, FR-039, FR-040, FR-041, FR-042,
  # FR-046, FR-047, SC-013, plan.md "Pattern: Status File Reuse" / D-012).
  #
  # The writer is the single load-bearing surface for two contracts:
  #
  #   1. The on-disk YAML matches the schema in
  #      `contracts/phase-creation-status.schema.yaml`. The same file is
  #      written by two callers (the engine on validation failure and
  #      the stacked-PR creator on subprocess failure); each populates a
  #      different subset of fields per the schema's cross-field rules.
  #
  #   2. No string written by this surface — anywhere — may contain
  #      credential material (FR-047, SC-013). Every string-typed
  #      payload value is scanned against the same credential-pattern
  #      list the observability logger uses; any match is replaced with
  #      the redaction marker before bytes reach disk.
  #
  # The writer also exposes `delete_if_present(path)` so the engine and
  # the stacked-PR creator can clear the status file on a successful
  # re-run (FR-040).
  class StatusWriter
    REDACTION_MARKER = '[REDACTED:credential-pattern-match]'

    # Mirrors Observability::CREDENTIAL_PATTERNS so both the log surface
    # and the on-disk status file enforce the same backstop. Kept inline
    # (rather than imported) so a future change to one surface does not
    # silently weaken the other; the credential-leak regression test
    # (T070) scans every byte produced by both surfaces against the
    # same external pattern set.
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

    VALID_STAGES = %w[phaser-engine stacked-pr-creation].freeze

    # The five FR-046 failure classes for stacked-pr-creation.
    VALID_FAILURE_CLASSES = %w[
      auth-missing
      auth-insufficient-scope
      rate-limit
      network
      other
    ].freeze

    # Per-stage key ordering. Each stage emits its envelope keys
    # (`stage`, `timestamp`) first, then the rule-specific or
    # creator-specific keys in the order declared by
    # `contracts/phase-creation-status.schema.yaml`.
    PHASER_ENGINE_KEY_ORDER = %w[
      stage
      timestamp
      commit_hash
      failing_rule
      missing_precedent
      forbidden_operation
      decomposition_message
      commit_count
      phase_count
    ].freeze

    STACKED_PR_KEY_ORDER = %w[
      stage
      timestamp
      failure_class
      first_uncreated_phase
    ].freeze

    # Construct a writer.
    #
    #   * now — zero-arg callable returning the timestamp string for the
    #           current emission. Defaults to a real ISO-8601 UTC clock
    #           with millisecond precision so production callers do not
    #           have to inject one.
    def initialize(now: nil)
      @now = now || Internal::Iso8601Clock.method(:now)
    end

    # Serialize the given payload to the given path under the given
    # stage. Returns the destination path so callers can chain. Raises
    # ArgumentError when the cross-field rules in the schema are
    # violated; raises the underlying IO error when the on-disk write
    # fails (in which case the previous destination content is
    # preserved).
    def write(path, stage:, **payload)
      validate_stage!(stage)
      validate_payload!(stage, payload)

      sanitized_payload = sanitize_payload(payload)
      hash = build_hash(stage, sanitized_payload)

      Internal::AtomicYamlWriter.atomic_write(path, Internal::AtomicYamlWriter.dump_yaml(hash))
      path
    end

    # Delete the status file at `path` if it exists. Returns the path
    # so callers can chain (e.g., to log the cleared status path on
    # successful re-run).
    def delete_if_present(path)
      FileUtils.rm_f(path)
      path
    end

    private

    def validate_stage!(stage)
      return if VALID_STAGES.include?(stage)

      raise ArgumentError,
            "stage must be one of #{VALID_STAGES.inspect}, got #{stage.inspect}"
    end

    def validate_payload!(stage, payload)
      case stage
      when 'phaser-engine' then validate_phaser_engine_payload!(payload)
      when 'stacked-pr-creation' then validate_stacked_pr_payload!(payload)
      end
    end

    def validate_phaser_engine_payload!(payload)
      raise ArgumentError, 'failing_rule is required for stage=phaser-engine' unless payload.key?(:failing_rule)

      if payload.key?(:failure_class)
        raise ArgumentError,
              'failure_class MUST NOT be present when stage=phaser-engine'
      end
      return unless payload.key?(:first_uncreated_phase)

      raise ArgumentError,
            'first_uncreated_phase MUST NOT be present when stage=phaser-engine'
    end

    def validate_stacked_pr_payload!(payload)
      unless payload.key?(:failure_class)
        raise ArgumentError,
              'failure_class is required for stage=stacked-pr-creation'
      end

      unless VALID_FAILURE_CLASSES.include?(payload[:failure_class])
        raise ArgumentError,
              "failure_class must be one of #{VALID_FAILURE_CLASSES.inspect}, " \
              "got #{payload[:failure_class].inspect}"
      end

      return if payload.key?(:first_uncreated_phase)

      raise ArgumentError,
            'first_uncreated_phase is required for stage=stacked-pr-creation'
    end

    # Build the explicitly ordered Hash that Psych will dump. Iterates
    # the per-stage key order and includes only those keys the caller
    # actually supplied, so optional fields that were omitted by the
    # caller are not emitted as YAML nulls.
    def build_hash(stage, payload)
      envelope = { 'stage' => stage, 'timestamp' => @now.call }
      key_order = stage == 'phaser-engine' ? PHASER_ENGINE_KEY_ORDER : STACKED_PR_KEY_ORDER

      key_order.each_with_object({}) do |key, acc|
        if envelope.key?(key)
          acc[key] = envelope[key]
        elsif payload.key?(key.to_sym)
          acc[key] = payload[key.to_sym]
        end
      end
    end

    # Replace any credential-shaped string value with the redaction
    # marker before it reaches disk. Non-string values pass through
    # untouched so integer payload fields (commit_count, phase_count,
    # first_uncreated_phase) are preserved as integers.
    def sanitize_payload(payload)
      payload.each_with_object({}) do |(key, value), acc|
        acc[key] = if value.is_a?(String) && credential_pattern_match?(value)
                     REDACTION_MARKER
                   else
                     value
                   end
      end
    end

    def credential_pattern_match?(string)
      CREDENTIAL_PATTERNS.any? { |pattern| string.match?(pattern) }
    end
  end
end
