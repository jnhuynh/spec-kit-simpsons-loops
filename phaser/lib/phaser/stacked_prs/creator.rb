# frozen_string_literal: true

require 'json'
require 'yaml'

require 'phaser/internal/text_helpers'
require 'phaser/stacked_prs/creator_gh_calls'
require 'phaser/stacked_prs/creator_result'

module Phaser
  module StackedPrs
    # Idempotent stacked-PR creator that walks a feature's
    # `phase-manifest.yaml` and, for each declared phase, ensures a
    # branch + PR exist on the configured git host (feature
    # 007-multi-phase-pipeline; T075, FR-026, FR-027, FR-028, FR-029,
    # FR-039, FR-040, FR-046, FR-047, SC-010, SC-013, plan.md
    # "Pattern: Idempotent Stacked-PR Creator" / D-012).
    #
    # Why this class exists:
    #
    #   The Creator is the single load-bearing surface for the
    #   "create stacked PRs in manifest order, skip what already exists,
    #   resume cleanly after partial failure" contract documented in
    #   `contracts/stacked-pr-creator-cli.md`. Centralising the walk +
    #   idempotency logic here gives the codebase three properties that
    #   would otherwise have to be re-proven at every call site:
    #
    #   1. **Manifest-as-source-of-truth.** The Creator re-reads the
    #      manifest on every invocation and queries gh for the actual
    #      branch + PR state of every phase. The `phase-creation-status.yaml`
    #      file is a hint for the operator (and a halt marker for the
    #      pipeline) — it is NEVER the source of truth for which phases
    #      to skip on a re-run. This ensures a stale status file cannot
    #      cause an out-of-order resume.
    #
    #   2. **Per-phase atomicity, not per-run.** When phase K fails, the
    #      Creator leaves phases 1..K-1 alone, writes the status file
    #      naming K as the resume point, and stops. It NEVER deletes or
    #      modifies branches or PRs that already exist (FR-039) — the
    #      operator's manual or automated remediation surface is the
    #      authoritative cleanup path.
    #
    #   3. **No bypass of the credential-leak guard.** All status-file
    #      writes go through `Phaser::StatusWriter` and all observability
    #      records go through `Phaser::Observability`, so the FR-047
    #      sanitisation runs on every byte regardless of which code path
    #      generated the failure.
    #
    # The Creator is deliberately structured so the only gh
    # subprocess invocations happen through the injected
    # `Phaser::StackedPrs::GitHostCli` collaborator. The class never
    # shells out directly. T071's grep-based regression test asserts no
    # direct system or backtick subshell invocation of the host CLI
    # exists anywhere under phaser/lib/; the Creator's contribution is
    # routing every host-CLI call through the wrapper's `#run` method.
    class Creator
      # Public alias for the Result value object so callers (CLI in
      # T076, integration tests) can destructure
      # `Phaser::StackedPrs::Creator::Result` without reaching into the
      # `CreatorResult` helper module's namespace.
      Result = CreatorResult::Value

      # Filename of the on-disk halt marker the Creator writes on
      # failure and deletes on full success. Mirrors the AuthProbe's
      # constant so a re-run sees the same artifact regardless of which
      # surface produced it.
      STATUS_FILENAME = 'phase-creation-status.yaml'

      # Filename of the manifest the Creator reads. Centralised so a
      # future manifest-path override (e.g., for a non-default feature
      # directory layout) only needs to change in one place.
      MANIFEST_FILENAME = 'phase-manifest.yaml'

      # Construct a Creator. Collaborators (all required keyword args):
      #   * git_host_cli       — `Phaser::StackedPrs::GitHostCli` (T072).
      #   * failure_classifier — `Phaser::StackedPrs::FailureClassifier` (T073).
      #   * status_writer      — `Phaser::StatusWriter`.
      #   * observability      — `Phaser::Observability`.
      def initialize(git_host_cli:, failure_classifier:, status_writer:, observability:)
        @git_host_cli = git_host_cli
        @failure_classifier = failure_classifier
        @status_writer = status_writer
        @observability = observability
      end

      # Walk the manifest at `<feature_dir>/phase-manifest.yaml` and
      # create branches + PRs for every phase that does not already
      # exist on the host. Returns a Result describing the outcome.
      #
      # Manifest-missing precondition: when no manifest is present, the
      # Creator returns a failure Result without writing the status
      # file and without invoking gh. The CLI (T076) maps this to
      # exit 3 ("operational error") per
      # `contracts/stacked-pr-creator-cli.md`.
      def create(feature_dir:)
        manifest_path = File.join(feature_dir, MANIFEST_FILENAME)
        return manifest_missing_result(manifest_path) unless File.exist?(manifest_path)

        manifest = load_manifest(manifest_path)
        status_path = File.join(feature_dir, STATUS_FILENAME)

        process_phases(
          phases: manifest['phases'] || [],
          status_path: status_path,
          manifest_path: manifest_path
        )
      end

      private

      # Walk every phase in manifest order. On success of every phase,
      # delete any pre-existing status file and return a successful
      # Result. On the first failure, persist the status file naming
      # the failed phase as `first_uncreated_phase`, emit the
      # `phase-creation-failed` ERROR record, and return a failed
      # Result without touching any later phase.
      def process_phases(phases:, status_path:, manifest_path:)
        created = []
        skipped = []

        phases.each do |phase|
          outcome = process_phase(phase: phase, status_path: status_path)
          case outcome[:status]
          when :created then created << phase['number']
          when :skipped then skipped << phase['number']
          when :failed then return halt(created: created, skipped: skipped,
                                        outcome: outcome, phase: phase, manifest_path: manifest_path)
          end
        end

        @status_writer.delete_if_present(status_path)
        success_result(phases_created: created,
                       phases_skipped_existing: skipped,
                       manifest_path: manifest_path)
      end

      # Build the failure Result returned when the walk halts on phase K.
      # Pulled out of `process_phases` so the walker stays under the
      # community-default Metrics/MethodLength limit.
      def halt(created:, skipped:, outcome:, phase:, manifest_path:)
        failure_result(
          phases_created: created,
          phases_skipped_existing: skipped,
          failure_class: outcome[:failure_class],
          first_uncreated_phase: phase['number'],
          manifest_path: manifest_path
        )
      end

      # Decide what to do for one phase: skip if both branch and PR
      # already exist with the expected base; otherwise create the
      # missing pieces. Returns a small Hash describing the outcome
      # so the caller can build the Result without leaking the
      # branching logic into `process_phases`.
      def process_phase(phase:, status_path:)
        branch_name = phase['branch_name']
        base_branch = phase['base_branch']

        branch_exists = branch_exists?(branch_name)
        pr_data = branch_exists ? lookup_pr(branch_name) : nil

        if branch_exists && pr_matches_base?(pr_data, base_branch)
          emit_skipped(phase: phase, pr_number: pr_data['number'])
          return { status: :skipped }
        end

        # The "skip branch creation" optimisation is narrow: it only
        # applies when the branch already exists AND no PR has been
        # opened yet. A PR that exists with the WRONG base branch
        # invalidates the entire phase — the host state diverged from
        # the manifest, and the Creator must drive the branch + PR
        # back to the manifest's declared shape (per
        # contracts/stacked-pr-creator-cli.md: "creates the branch
        # and PR").
        skip_branch_create = branch_exists && pr_data.nil?

        create_phase(
          phase: phase,
          branch_name: branch_name,
          base_branch: base_branch,
          skip_branch_create: skip_branch_create,
          status_path: status_path
        )
      end

      # Create whichever pieces are missing for the phase. The branch
      # is created only when the prior existence check returned false;
      # the PR is created unconditionally (after the branch exists).
      # On any host-CLI failure, persist the status file and return a
      # failed outcome so the walker can halt.
      def create_phase(phase:, branch_name:, base_branch:, skip_branch_create:, status_path:)
        unless skip_branch_create
          branch_outcome = create_branch(phase: phase, branch_name: branch_name, base_branch: base_branch)
          unless branch_outcome[:ok]
            return record_failure(phase: phase, outcome: branch_outcome, status_path: status_path)
          end
        end

        pr_outcome = create_pr(phase: phase, branch_name: branch_name, base_branch: base_branch)
        return record_failure(phase: phase, outcome: pr_outcome, status_path: status_path) unless pr_outcome[:ok]

        { status: :created }
      end

      # Query gh for branch existence. The endpoint returns a JSON
      # body on success and exits non-zero on 404; we treat any
      # non-zero exit as "branch does not exist" for the purposes of
      # this check (the actual creation path will surface a more
      # specific error if the host is unreachable).
      def branch_exists?(branch_name)
        @git_host_cli.run(CreatorGhCalls.branch_exists_args(branch_name)).status.exitstatus.zero?
      end

      # Query gh for the first PR whose head branch matches. Returns
      # the Hash describing the PR (with keys `number`, `baseRefName`)
      # when one exists, or nil when none does.
      def lookup_pr(branch_name)
        result = @git_host_cli.run(CreatorGhCalls.lookup_pr_args(branch_name))
        return nil unless result.status.exitstatus.zero?

        parsed = JSON.parse(result.stdout.to_s)
        parsed.is_a?(Array) ? parsed.first : nil
      end

      # The "phase already exists" check requires BOTH a branch AND a
      # PR whose base matches the manifest's expected base. A PR
      # against the wrong base invalidates the skip — the Creator
      # treats the phase as uncreated and proceeds to (try to) recreate
      # it so the final on-host state matches the manifest.
      def pr_matches_base?(pr_data, expected_base)
        return false if pr_data.nil?

        pr_data['baseRefName'] == expected_base
      end

      # Create the phase branch. Argv build lives in CreatorGhCalls;
      # this surface owns only the success-callback that fires the
      # observability record after gh acknowledges the create.
      def create_branch(phase:, branch_name:, base_branch:)
        args = CreatorGhCalls.create_branch_args(branch_name: branch_name, base_branch: base_branch)
        run_and_classify(args: args, phase: phase, on_success: lambda do
          @observability.log_phase_branch_created(
            phase_number: phase['number'],
            branch_name: branch_name,
            base_branch: base_branch,
            commits: (phase['tasks'] || []).length
          )
        end)
      end

      # Create the phase PR. Argv + body build live in CreatorGhCalls;
      # this surface owns only the success-callback that fires the
      # observability record after gh acknowledges the create.
      def create_pr(phase:, branch_name:, base_branch:)
        args = CreatorGhCalls.create_pr_args(
          branch_name: branch_name, base_branch: base_branch,
          title: phase['name'] || "Phase #{phase['number']}",
          body: CreatorGhCalls.build_pr_body(phase)
        )
        linked = phase['number'] > 1
        run_and_classify(args: args, phase: phase, on_success: lambda do |stdout|
          pr_url = stdout.to_s.strip.each_line.first.to_s.chomp
          @observability.log_phase_pr_created(
            phase_number: phase['number'],
            pr_number: CreatorGhCalls.extract_pr_number(pr_url),
            pr_url: pr_url,
            linked_to_previous_pr: linked
          )
        end)
      end

      # Run a host-CLI call, classify the outcome, and invoke the
      # success callback when exit was zero. Returns a Hash describing
      # the outcome that the caller (create_phase) can pattern-match
      # on to halt or continue.
      def run_and_classify(args:, phase:, on_success:)
        result = @git_host_cli.run(args)
        return success_outcome(result: result, on_success: on_success) if result.status.exitstatus.zero?

        failure_outcome(result: result, phase: phase)
      end

      # Build the success outcome for `run_and_classify`. Invokes the
      # caller-supplied callback so the per-call observability record
      # fires before the outcome propagates back up the stack.
      def success_outcome(result:, on_success:)
        on_success.arity.zero? ? on_success.call : on_success.call(result.stdout)
        { ok: true }
      end

      # Build the failure outcome for `run_and_classify`. Delegates the
      # exit-code → failure_class mapping to the injected
      # FailureClassifier so the policy lives in exactly one place.
      def failure_outcome(result:, phase:)
        failure_class = @failure_classifier.classify(
          exit_code: result.status.exitstatus,
          stderr: result.stderr.to_s
        )
        {
          ok: false,
          failure_class: failure_class.to_s,
          gh_exit_code: result.status.exitstatus,
          stderr: result.stderr.to_s,
          phase_number: phase['number']
        }
      end

      # Persist the failure to disk and emit the ERROR observability
      # record. Returns the failure outcome so the walker can halt.
      def record_failure(phase:, outcome:, status_path:)
        @status_writer.write(
          status_path,
          stage: 'stacked-pr-creation',
          failure_class: outcome[:failure_class],
          first_uncreated_phase: phase['number']
        )
        @observability.log_phase_creation_failed(
          phase_number: phase['number'],
          failure_class: outcome[:failure_class],
          gh_exit_code: outcome[:gh_exit_code],
          summary: Phaser::Internal::TextHelpers.first_line(outcome[:stderr])
        )
        { status: :failed, failure_class: outcome[:failure_class] }
      end

      # Emit the `phase-skipped-existing` INFO record for a phase
      # whose branch + PR already match the manifest. The reason
      # field is constant per the contract.
      def emit_skipped(phase:, pr_number:)
        @observability.log_phase_skipped_existing(
          phase_number: phase['number'],
          branch_name: phase['branch_name'],
          pr_number: pr_number
        )
      end

      # Read and parse the manifest. The Creator deliberately uses
      # `YAML.safe_load` (no aliases, no permitted classes) because
      # the manifest is generated by `Phaser::ManifestWriter` which
      # only emits primitive scalars, arrays, and hashes — anything
      # else in the file is a sign of tampering and the safe-load
      # error is the right surface to halt on.
      def load_manifest(path)
        YAML.safe_load_file(path) || {}
      end

      # Forwarders to the per-variant builders in CreatorResult. The
      # builders live in their own module so the per-variant docstrings
      # stay with the value-object surface, not the orchestration
      # surface. The Creator's responsibility ends at deciding which
      # builder to call; the builder owns the field-shape contract.
      def success_result(**args)
        CreatorResult.success(**args)
      end

      def failure_result(**args)
        CreatorResult.failure(**args)
      end

      def manifest_missing_result(manifest_path)
        CreatorResult.manifest_missing(manifest_path)
      end
    end
  end
end
