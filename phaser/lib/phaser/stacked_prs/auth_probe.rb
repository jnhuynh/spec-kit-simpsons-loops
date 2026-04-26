# frozen_string_literal: true

module Phaser
  module StackedPrs
    # One-shot `gh auth status` probe that gates every
    # `phaser-stacked-prs` invocation (feature 007-multi-phase-pipeline;
    # T074, FR-044, FR-045, FR-046, FR-047, SC-012, SC-013, plan.md
    # R-009 / D-012).
    #
    # Why this class exists:
    #
    #   The probe is the single load-bearing surface for the stacked-PR
    #   creator's "fail-fast before any branch is created" guarantee.
    #   It runs exactly once per `phaser-stacked-prs` invocation,
    #   delegates the exit-code → failure_class decision to
    #   `Phaser::StackedPrs::FailureClassifier`, and persists any
    #   failure to `<feature_dir>/phase-creation-status.yaml` via
    #   `Phaser::StatusWriter` so a re-run can resume cleanly. Any
    #   downstream `gh` invocation that follows assumes the probe has
    #   already returned a successful result.
    #
    # Contract pinned by spec/stacked_prs/auth_probe_spec.rb:
    #
    #   1. Exactly one `gh auth status` invocation per probe (FR-045).
    #      No retries, no per-phase re-probing.
    #
    #   2. Result caching across `#probe` calls on the same instance —
    #      a second call returns the same Result object without
    #      consulting `gh` again. The Creator (T075) relies on this so
    #      subsequent code paths cannot accidentally re-probe.
    #
    #   3. Fail-fast semantics:
    #      - On `gh auth status` exit non-zero, the FailureClassifier
    #        is consulted with the captured exit code and stderr; the
    #        returned `failure_class` is recorded in the result, the
    #        status file, and the `phase-creation-failed` ERROR event.
    #      - On `gh auth status` exit zero, the probe inspects the
    #        captured "Token scopes:" listing for the `repo` scope; if
    #        absent, the FailureClassifier is consulted (it returns
    #        `:auth-insufficient-scope` from the same scope-parsing
    #        logic) and the failure path runs identically.
    #      - On exit zero with the `repo` scope present, the probe
    #        records a successful `auth-probe-result` event and
    #        returns a Result with `success?=true`.
    #
    #   4. Status-file shape (FR-039, FR-045):
    #        stage: stacked-pr-creation
    #        failure_class: <one of the five FR-046 enum values>
    #        first_uncreated_phase: 1
    #
    #   5. Observability (contracts/observability-events.md):
    #      - One `auth-probe-result` INFO record per probe (regardless
    #        of outcome) — host, authenticated, scopes.
    #      - One additional `phase-creation-failed` ERROR record on
    #        failure with `phase_number: 1`, the matching
    #        `failure_class`, the `gh_exit_code`, and the captured
    #        stderr first line as `summary`.
    #
    #   6. Credential-leak guard (FR-047, SC-013): the captured `gh`
    #      stderr is passed verbatim to `Phaser::Observability` (which
    #      sanitises string-typed fields against the credential pattern
    #      list) and to `Phaser::StatusWriter` (which sanitises payload
    #      strings the same way). Neither path may serialise a
    #      credential-shaped substring under any input.
    class AuthProbe
      # Result object returned by `#probe`. A successful result
      # carries no `failure_class`; a failed result carries the
      # FR-046 enum value as a String (matching the spec's expectation
      # that callers compare against `'auth-missing'` etc., not the
      # symbol form).
      Result = Data.define(:success?, :failure_class, :host, :authenticated, :scopes, :gh_exit_code, :summary)

      # Path of the status file the probe writes on failure, relative
      # to the feature dir. Mirrors the Creator's path so a re-run sees
      # the same on-disk artifact.
      STATUS_FILENAME = 'phase-creation-status.yaml'

      # Token scopes parser — extracts the comma-separated scope list
      # from a `gh auth status` stdout/stderr fragment shaped like:
      #
      #   Token scopes: 'gist', 'read:org'
      #
      # Mirrors FailureClassifier::TOKEN_SCOPES_PATTERN; duplicated
      # here so the probe can decide whether to consult the classifier
      # WITHOUT first delegating (per spec: success path MUST NOT
      # consult the classifier at all).
      TOKEN_SCOPES_PATTERN = /token scopes?:\s*([^\n]+)/i

      # Host parser — pulls the first hostname-like token from the
      # `gh auth status` output. The canonical output line is:
      #
      #   github.com
      #     Logged in to github.com as alice (oauth_token)
      #
      # so we match a leading bare hostname on its own line. The
      # parser is best-effort: when the output does not match (e.g.,
      # auth-missing stderr), the probe records `nil` for `host` and
      # the observability record carries that nil through.
      HOST_PATTERN = /^([a-z0-9.-]+\.[a-z]{2,})\s*$/i

      # Construct a probe.
      #
      #   * git_host_cli       — Phaser::StackedPrs::GitHostCli (or a
      #                          test double); the probe calls
      #                          `#run(['auth', 'status'])` exactly once
      #                          per `#probe` instance.
      #
      #   * failure_classifier — Phaser::StackedPrs::FailureClassifier
      #                          (or a test double); the probe asks
      #                          `#classify(exit_code:, stderr:)` to map
      #                          the gh outcome onto an FR-046 enum
      #                          value. Only consulted on failure paths.
      #
      #   * status_writer      — Phaser::StatusWriter; the probe writes
      #                          `phase-creation-status.yaml` through
      #                          this collaborator on failure (never
      #                          directly via File IO) so the
      #                          credential-leak guard runs.
      #
      #   * observability      — Phaser::Observability; the probe emits
      #                          `auth-probe-result` once per probe and
      #                          `phase-creation-failed` once per
      #                          failure through this collaborator.
      def initialize(git_host_cli:, failure_classifier:, status_writer:, observability:)
        @git_host_cli = git_host_cli
        @failure_classifier = failure_classifier
        @status_writer = status_writer
        @observability = observability
        @cached_result = nil
      end

      # Probe `gh auth status` once. On the first call, invoke the host
      # CLI, classify the outcome, persist any failure, emit the
      # corresponding observability records, and return a Result. On
      # any subsequent call with the same instance, return the cached
      # Result without consulting `gh` again (FR-045: exactly one
      # invocation per run).
      def probe(feature_dir:)
        return @cached_result if @cached_result

        gh_result = @git_host_cli.run(%w[auth status])
        exit_code = gh_result.status.exitstatus
        stderr_text = gh_result.stderr.to_s
        stdout_text = gh_result.stdout.to_s
        combined_text = "#{stdout_text}\n#{stderr_text}"

        host = parse_host(combined_text)
        scopes = parse_scopes(combined_text)

        @cached_result = if exit_code.zero? && scopes.include?('repo')
                           record_success(host: host, scopes: scopes)
                         else
                           record_failure(
                             feature_dir: feature_dir,
                             exit_code: exit_code,
                             stderr_text: stderr_text,
                             host: host,
                             scopes: scopes
                           )
                         end
      end

      private

      # Success path — emit the auth-probe-result event and return a
      # successful Result. Does NOT consult the failure classifier
      # (per spec: "does not consult the failure classifier").
      def record_success(host:, scopes:)
        @observability.log_auth_probe_result(
          host: host,
          authenticated: true,
          scopes: scopes
        )
        Result.new(
          success?: true,
          failure_class: nil,
          host: host,
          authenticated: true,
          scopes: scopes,
          gh_exit_code: 0,
          summary: nil
        )
      end

      # Failure path — consult the classifier, persist the status
      # file, emit both observability records, and return a failed
      # Result. The order is load-bearing:
      #
      #   1. Classify first so the failure_class is known to the rest
      #      of the path.
      #   2. Write the status file BEFORE emitting the
      #      phase-creation-failed event so an operator scanning the
      #      stderr log can immediately read the on-disk artifact.
      #   3. Emit auth-probe-result (negative) before
      #      phase-creation-failed so a top-down stderr scan sees the
      #      probe outcome before the consequent error.
      def record_failure(feature_dir:, exit_code:, stderr_text:, host:, scopes:)
        failure_class = @failure_classifier.classify(exit_code: exit_code, stderr: stderr_text).to_s
        summary = first_line(stderr_text)

        write_status_file(feature_dir: feature_dir, failure_class: failure_class)
        emit_failure_events(
          host: host, scopes: scopes,
          failure_class: failure_class,
          exit_code: exit_code, summary: summary
        )

        Result.new(
          success?: false,
          failure_class: failure_class,
          host: host,
          authenticated: false,
          scopes: scopes,
          gh_exit_code: exit_code,
          summary: summary
        )
      end

      # Emit the two observability records that accompany every
      # failure path. Order is load-bearing: auth-probe-result
      # (negative) before phase-creation-failed so a top-down stderr
      # scan reads the probe outcome before the consequent error
      # record.
      def emit_failure_events(host:, scopes:, failure_class:, exit_code:, summary:)
        @observability.log_auth_probe_result(
          host: host,
          authenticated: false,
          scopes: scopes
        )
        @observability.log_phase_creation_failed(
          phase_number: 1,
          failure_class: failure_class,
          gh_exit_code: exit_code,
          summary: summary
        )
      end

      # Persist the failure to <feature_dir>/phase-creation-status.yaml
      # via the StatusWriter. The writer enforces the schema (stage +
      # failure_class + first_uncreated_phase) and runs the
      # credential-leak sanitisation pass on every string-typed field
      # before bytes reach disk.
      def write_status_file(feature_dir:, failure_class:)
        path = File.join(feature_dir, STATUS_FILENAME)
        @status_writer.write(
          path,
          stage: 'stacked-pr-creation',
          failure_class: failure_class,
          first_uncreated_phase: 1
        )
      end

      # Parse the host name from the combined stdout/stderr capture.
      # Returns nil when no hostname-shaped token is present (e.g.,
      # the auth-missing stderr "You are not logged into any GitHub
      # hosts."). The probe still emits the auth-probe-result event
      # in that case; the field carries nil through to the operator.
      def parse_host(text)
        text.each_line do |line|
          stripped = line.strip
          match = stripped.match(HOST_PATTERN)
          return match[1] if match
        end
        nil
      end

      # Parse the comma-separated scope list from the captured
      # "Token scopes:" line. Returns [] when no such line is
      # present (e.g., auth-missing stderr). The scopes are
      # downcased so callers can compare against canonical names
      # without re-normalising.
      def parse_scopes(text)
        match = text.match(TOKEN_SCOPES_PATTERN)
        return [] unless match

        match[1].scan(/[a-z_:]+/i).map(&:downcase)
      end

      # First non-empty line of the captured stderr, used as the
      # `summary` field on the phase-creation-failed event. Returns
      # an empty string when stderr is empty/nil so the event payload
      # always carries a defined string for the field.
      def first_line(text)
        return '' if text.nil? || text.empty?

        text.each_line.first.to_s.chomp
      end
    end
  end
end
