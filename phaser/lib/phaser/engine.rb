# frozen_string_literal: true

module Phaser
  # Orchestration shell that wires every per-commit and per-feature
  # validator into a single deterministic pipeline that produces a
  # `Phaser::PhaseManifest` and writes it to disk via
  # `Phaser::ManifestWriter` (feature 007-multi-phase-pipeline; T035,
  # FR-002, FR-009, FR-038, FR-041, FR-042, FR-043, FR-049, SC-002,
  # SC-008, SC-011, SC-014).
  #
  # Position in the engine pipeline (per quickstart.md "Pattern:
  # Pre-Classification Gate Discipline"):
  #
  #   #process(feature_branch_commits, flavor)
  #     for each commit in feature_branch_commits:
  #       empty-diff filter (FR-009)              -- skip + WARN
  #         -> forbidden-operations gate (FR-049) -- raise + ERROR + status
  #         -> classifier (FR-004)                -- INFO commit-classified
  #     precedent validator (FR-006)              -- raise + ERROR + status
  #     size guard (FR-048)                       -- raise + ERROR + status
  #     isolation resolver (FR-005)               -- INFO phase-emitted
  #     manifest writer (FR-002, FR-038)          -- writes YAML + returns path
  #
  # On any validation failure, the engine emits exactly one
  # `validation-failed` ERROR record on stderr (FR-041) and persists the
  # same payload to `<feature_dir>/phase-creation-status.yaml` via
  # `StatusWriter#write(stage: 'phaser-engine', ...)` per FR-042 BEFORE
  # re-raising the error so the CLI can map the exception to a non-zero
  # exit code per `contracts/phaser-cli.md`.
  #
  # On success, the engine deletes any pre-existing
  # `<feature_dir>/phase-creation-status.yaml` so a successful re-run
  # clears the prior failure status (FR-040 read-through to the engine
  # side; the same convention covers the stacked-PR creator).
  #
  # Determinism contract (FR-002, SC-002): the engine MUST be a pure
  # function of `(commits, flavor, feature_branch, default_branch,
  # clock)`. The clock is injected so `generated_at` is reproducible;
  # the manifest writer's stable-key ordering takes care of YAML-side
  # determinism. Two operators running the same flavor on the same
  # commits MUST see byte-identical manifests.
  class Engine
    MANIFEST_FILENAME = 'phase-manifest.yaml'
    STATUS_FILENAME = 'phase-creation-status.yaml'

    # Construct the engine. Required keyword arguments cover the per-run
    # identity (feature_dir, feature_branch, default_branch, clock) and
    # the IO surface (observability, status_writer, manifest_writer).
    # Internal collaborators (Classifier, PrecedentValidator, SizeGuard,
    # IsolationResolver) are stateless and always constructed internally
    # — they have no per-run configuration the caller needs to inject.
    # The keyword surface is bundled into a single options hash so the
    # method honors the project's parameter-count limit while still
    # being called with explicit keyword arguments at every call site.
    REQUIRED_INIT_KEYS = %i[
      feature_dir feature_branch default_branch
      observability status_writer manifest_writer clock
    ].freeze

    def initialize(**options)
      assign_required_options(options)
      build_internal_collaborators
    end

    private

    def assign_required_options(options)
      REQUIRED_INIT_KEYS.each do |key|
        raise ArgumentError, "missing keyword: :#{key}" unless options.key?(key)

        instance_variable_set("@#{key}", options.fetch(key))
      end
    end

    def build_internal_collaborators
      @classifier = Classifier.new
      @precedent_validator = PrecedentValidator.new
      @size_guard = SizeGuard.new
      @isolation_resolver = IsolationResolver.new
    end

    public

    # Single public entry point. On success returns the absolute path to
    # the written manifest. On any validation failure raises a subclass
    # of `Phaser::ValidationError` (or `Phaser::ClassificationError`,
    # which the engine treats as a validation failure for FR-041 / FR-042
    # purposes) AFTER persisting the failure payload and emitting the
    # ERROR record.
    # ClassificationError and ValidationError are sibling families
    # (ClassificationError descends from StandardError; ValidationError
    # also descends from StandardError) — both are caught here so a
    # rejection from any stage of the pipeline (the classifier, the
    # forbidden-ops gate, the precedent validator, or the size guard)
    # is funneled through the same record-failure path before being
    # re-raised. The two rescue clauses share an identical body but are
    # kept separate so the rescued error families read clearly at the
    # call site; the rubocop Lint/DuplicateBranch warning is silenced
    # because collapsing the clauses with `=>` would obscure that
    # intent.
    def process(commits, flavor)
      run_pipeline(commits, flavor)
    rescue ClassificationError, ValidationError => e
      record_validation_failure(e)
      raise
    end

    private

    # Walk the per-commit and per-feature stages in the order documented
    # in quickstart.md "Pattern: Pre-Classification Gate Discipline". A
    # raise from any stage is caught by `process`'s outer rescue so the
    # validation-failed payload reaches both stderr and the on-disk
    # status file via a single funnel.
    def run_pipeline(commits, flavor)
      forbidden_gate = build_forbidden_gate(flavor)
      non_empty_commits = filter_empty_diff_commits(commits)
      classification_results = classify_commits(
        non_empty_commits, flavor, forbidden_gate
      )

      validated_results = @precedent_validator.validate(
        classification_results, flavor
      )
      validated_results = run_flavor_validators(
        validated_results, non_empty_commits, flavor
      )
      @size_guard.enforce(validated_results, flavor)
      phase_groups = @isolation_resolver.resolve(validated_results, flavor)

      manifest = build_manifest(phase_groups, non_empty_commits, flavor)
      write_manifest(manifest)
      emit_phase_records(manifest.phases)
      clear_prior_status_file
      manifest_path
    end

    # Per-flavor validators are wired through `flavor_loader.rb` (T055).
    # Each entry in `flavor.validators` is a class constant the loader
    # resolved at load time; we instantiate it (no arguments — the
    # bypass-empty contract requires a parameterless constructor) and
    # invoke its `#validate(classification_results, commits, flavor)`
    # method. Each validator returns a NEW list of classification
    # results (possibly with audit-trail fields like
    # `safety_assertion_precedents` populated) which becomes the input
    # to the next validator in the list. Validators may raise any
    # `Phaser::ValidationError` descendant; the engine's outer rescue
    # in `#process` funnels the failure to stderr and the status file
    # via the same path the engine-level validators use.
    def run_flavor_validators(classification_results, commits, flavor)
      flavor.validators.reduce(classification_results) do |results, validator_class|
        validator_class.new.validate(results, commits, flavor)
      end
    end

    # FR-009 empty-diff filter. An empty-diff commit is logged once and
    # then dropped; it never reaches the forbidden-ops gate, the
    # classifier, the precedent validator, the size guard, the isolation
    # resolver, or the manifest writer.
    def filter_empty_diff_commits(commits)
      commits.reject do |commit|
        next false unless commit.diff.empty?

        @observability.log_commit_skipped_empty_diff(commit_hash: commit.hash)
        true
      end
    end

    # Per-commit pipeline run BEFORE feature-level validators: the
    # forbidden-operations gate (FR-049) runs FIRST, so a forbidden
    # commit short-circuits without ever reaching the classifier (D-016
    # / SC-015 — the operator-tag bypass is impossible by construction).
    # On a clean classification, emit one `commit-classified` INFO
    # record per non-empty commit (SC-011).
    def classify_commits(commits, flavor, forbidden_gate)
      commits.map do |commit|
        reject_forbidden!(commit, forbidden_gate)
        result = @classifier.classify(commit, flavor)
        log_classification(result)
        result
      end
    end

    def reject_forbidden!(commit, forbidden_gate)
      entry = forbidden_gate.evaluate(commit)
      return if entry.nil?

      raise ForbiddenOperationError.new(commit: commit, entry: entry)
    end

    def log_classification(result)
      @observability.log_commit_classified(
        commit_hash: result.commit_hash,
        task_type: result.task_type,
        source: result.source,
        isolation: result.isolation,
        rule_name: result.rule_name,
        precedents_consulted: result.precedents_consulted
      )
    end

    # The forbidden-operations gate is built from the active flavor on
    # every #process invocation rather than cached on the engine
    # instance. The engine instance is reused across runs in long-lived
    # callers; the per-run construction makes the bypass-surface
    # contract trivial to audit (no detector list survives across runs).
    def build_forbidden_gate(flavor)
      ForbiddenOperationsGate.new(
        forbidden_operations: flavor.forbidden_operations,
        forbidden_module: flavor.forbidden_module
      )
    end

    # Translate the resolver's `Array<Array<ClassificationResult>>`
    # output into a `Phaser::PhaseManifest` populated with `Phaser::Phase`
    # and `Phaser::Task` value objects. Branch naming follows FR-026:
    # phase 1's `base_branch` is the engine's `default_branch`; phases
    # 2..N's `base_branch` is the previous phase's `branch_name`.
    def build_manifest(phase_groups, non_empty_commits, flavor)
      commit_index = non_empty_commits.to_h { |commit| [commit.hash, commit] }

      phases = phase_groups.each_with_index.map do |group, index|
        build_phase(group, index + 1, commit_index)
      end

      PhaseManifest.new(
        flavor_name: flavor.name,
        flavor_version: flavor.version,
        feature_branch: @feature_branch,
        generated_at: @clock.call,
        phases: phases
      )
    end

    def build_phase(group, number, commit_index)
      tasks = build_tasks(group, number, commit_index)
      Phase.new(
        number: number,
        name: derive_phase_name(group, commit_index),
        branch_name: phase_branch_name(number),
        base_branch: phase_base_branch(number),
        tasks: tasks,
        ci_gates: [],
        rollback_note: derive_rollback_note(group)
      )
    end

    def build_tasks(group, phase_number, commit_index)
      group.each_with_index.map do |result, task_index|
        commit = commit_index.fetch(result.commit_hash)
        Task.new(
          id: "phase-#{phase_number}-task-#{task_index + 1}",
          task_type: result.task_type,
          commit_hash: result.commit_hash,
          commit_subject: commit.subject,
          safety_assertion_precedents: result.safety_assertion_precedents
        )
      end
    end

    # Phase 1 is based on the project's default integration branch.
    # Phases 2..N are based on the previous phase's branch_name so a
    # stacked-PR consumer can chain reviews left-to-right (FR-026).
    def phase_base_branch(number)
      return @default_branch if number == 1

      phase_branch_name(number - 1)
    end

    def phase_branch_name(number)
      "#{@feature_branch}-phase-#{number}"
    end

    # Sentence-case human-readable phase name derived from the first
    # task in the phase: `"<task-type>: <commit-subject>"`. Keeps the
    # name informative without parsing flavor metadata the engine has no
    # reason to interpret.
    def derive_phase_name(group, commit_index)
      first_result = group.first
      first_commit = commit_index.fetch(first_result.commit_hash)
      "#{first_result.task_type}: #{first_commit.subject}"
    end

    # Operator-facing rollback guidance derived from the assigned task
    # types in this phase. Concrete rollback playbooks live in flavor
    # documentation; the engine surfaces only the type-name list so
    # reviewers know which task families to consult.
    def derive_rollback_note(group)
      type_names = group.map(&:task_type).uniq
      "Rollback guidance for task types: #{type_names.join(', ')}."
    end

    def write_manifest(manifest)
      @manifest_writer.write(manifest, manifest_path)
    end

    def emit_phase_records(phases)
      phases.each do |phase|
        @observability.log_phase_emitted(
          phase_number: phase.number,
          branch_name: phase.branch_name,
          base_branch: phase.base_branch,
          tasks: phase.tasks
        )
      end
    end

    # FR-040 read-through: a successful run clears any prior failure
    # status file so the on-disk state reflects the most recent outcome.
    def clear_prior_status_file
      @status_writer.delete_if_present(status_path)
    end

    # Funnel both `Phaser::ValidationError` descendants and the
    # classifier's `Phaser::ClassificationError` family through the same
    # ERROR-record + status-file path. Each error class exposes a
    # canonical payload contract (`failing_rule` plus the payload
    # fields the failure mode populates); the funnel forwards that
    # payload verbatim to both surfaces so the wire shape stays
    # consistent across rejection modes.
    def record_validation_failure(error)
      payload = validation_failed_payload(error)
      @observability.log_validation_failed(**payload)
      @status_writer.write(status_path, stage: 'phaser-engine', **payload)
    end

    # Each error class carries the exact field set its rejection mode
    # populates; we deliberately ask the error for its payload rather
    # than reconstructing it here so a future change to a rejection-mode
    # contract has a single source of truth (the error class itself).
    def validation_failed_payload(error)
      if error.respond_to?(:to_validation_failed_payload)
        error.to_validation_failed_payload
      else
        # Fallback for ClassificationError descendants that predate the
        # to_validation_failed_payload convention (UnknownTypeTagError):
        # carry the canonical failing_rule plus the offending commit.
        {
          failing_rule: error.failing_rule,
          commit_hash: error.commit_hash
        }
      end
    end

    def manifest_path
      File.join(@feature_dir, MANIFEST_FILENAME)
    end

    def status_path
      File.join(@feature_dir, STATUS_FILENAME)
    end
  end
end
