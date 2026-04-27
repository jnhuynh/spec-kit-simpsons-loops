# frozen_string_literal: true

require 'phaser/internal/atomic_yaml_writer'

module Phaser
  # Stable-key-order YAML emitter that serializes a Phaser::PhaseManifest
  # to disk as `<FEATURE_DIR>/phase-manifest.yaml` (feature
  # 007-multi-phase-pipeline; T015, FR-002, FR-038, SC-002; plan.md
  # "Pattern: Manifest Writer").
  #
  # The writer is the single load-bearing surface for the engine's
  # byte-identical output guarantee. Its narrow contract:
  #
  #   1. Build an explicitly ordered Hash matching the schema in
  #      `contracts/phase-manifest.schema.yaml` so Ruby's Hash
  #      insertion-order does not leak into the YAML output.
  #   2. Call `Psych.dump(hash, line_width: -1, header: false)` so the
  #      output is a single mapping document with no `---` header and no
  #      80-column line wrapping (long commit subjects MUST stay on one
  #      line for byte-identical determinism across hosts).
  #   3. Write atomically: write to a temp file under the destination
  #      directory and rename over the destination so a crash mid-write
  #      never leaves a half-written or corrupt file at the destination.
  #
  # The writer is stateless; a single instance per run (or per spec) is
  # sufficient, and independent instances produce identical bytes.
  class ManifestWriter
    # Top-level keys in the order declared by
    # `contracts/phase-manifest.schema.yaml`. Iterated when building the
    # output Hash so insertion order matches the schema verbatim.
    MANIFEST_KEYS = %w[
      flavor_name
      flavor_version
      feature_branch
      generated_at
      phases
    ].freeze

    # Per-phase keys in the order declared by the schema's `Phase`
    # definition.
    PHASE_KEYS = %w[
      number
      name
      branch_name
      base_branch
      tasks
      ci_gates
      rollback_note
    ].freeze

    # Required per-task keys in the order declared by the schema's
    # `Task` definition. The optional `safety_assertion_precedents` key
    # is appended only when the source Task carries it (FR-018,
    # plan.md D-017); see `serialize_task` below.
    TASK_REQUIRED_KEYS = %w[
      id
      task_type
      commit_hash
      commit_subject
    ].freeze

    # Serialize the given manifest to the given path.
    #
    # Returns the destination path so callers can chain (e.g., to log
    # the path on stdout from the engine CLI). Raises if the underlying
    # write or rename fails; in that case the previous destination
    # content (if any) is preserved.
    def write(manifest, path)
      yaml = Internal::AtomicYamlWriter.dump_yaml(build_manifest_hash(manifest))
      Internal::AtomicYamlWriter.atomic_write(path, yaml)
      path
    end

    private

    # Build the top-level explicitly ordered Hash that Psych will dump.
    # Phases are sorted by `number` so the output ordering is a function
    # of phase identity, not the caller's input list order — this is the
    # property that the determinism test pins (SC-002).
    def build_manifest_hash(manifest)
      hash = {}
      MANIFEST_KEYS.each do |key|
        hash[key] = case key
                    when 'phases' then serialize_phases(manifest.phases)
                    else manifest.public_send(key)
                    end
      end
      hash
    end

    def serialize_phases(phases)
      phases.sort_by(&:number).map { |phase| serialize_phase(phase) }
    end

    def serialize_phase(phase)
      hash = {}
      PHASE_KEYS.each do |key|
        hash[key] = case key
                    when 'tasks' then phase.tasks.map { |task| serialize_task(task) }
                    when 'ci_gates' then Array(phase.ci_gates)
                    else phase.public_send(key)
                    end
      end
      hash
    end

    # Serialize a single Task. The four required keys are always emitted
    # in the schema-declared order; the optional
    # `safety_assertion_precedents` key is appended only when the Task
    # value object carries it, so commits whose task type is not
    # declared irreversible by the active flavor produce a Task entry
    # without the optional key (matching the schema's optionality).
    def serialize_task(task)
      hash = {}
      TASK_REQUIRED_KEYS.each { |key| hash[key] = task.public_send(key) }
      precedents = task.safety_assertion_precedents
      hash['safety_assertion_precedents'] = precedents unless precedents.nil?
      hash
    end
  end
end
