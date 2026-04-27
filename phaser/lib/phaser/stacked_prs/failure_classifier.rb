# frozen_string_literal: true

module Phaser
  module StackedPrs
    # Pure decision function that maps a host-CLI subprocess outcome
    # (exit code + stderr text) onto one of the five FR-046
    # `failure_class` enum values used by the stacked-PR creator's
    # observability surface and `phase-creation-status.yaml` payload
    # (feature 007-multi-phase-pipeline; T073, FR-044, FR-045, FR-046,
    # FR-047, SC-012, SC-013, plan.md R-009 / D-012, research.md R-009).
    #
    # Why this class exists:
    #
    #   The stacked-PR creator must record every host-CLI failure with
    #   the single most-actionable remediation label. Centralising the
    #   exit-code/stderr -> label decision here gives the codebase three
    #   load-bearing properties:
    #
    #   1. **One classification surface.** AuthProbe (T074) and Creator
    #      (T075) both consume the same five-value enum, so an operator
    #      who sees `failure_class: rate-limit` in one status file means
    #      exactly the same thing as the same value in any other.
    #
    #   2. **No ambient reads.** The classifier derives its verdict
    #      ONLY from the `(exit_code, stderr)` pair handed to it. It
    #      MUST NOT consult `ENV['GITHUB_TOKEN']`, `ENV['GH_TOKEN']`,
    #      any file, or any other ambient state — per FR-046's
    #      "derived from the host CLI's exit code or response, not
    #      guessed from the operator's environment".
    #
    #   3. **Credential-leak resistance.** The only string operations
    #      performed on stderr are case-insensitive substring/regex
    #      matches against the documented marker strings (e.g.,
    #      "not logged in", "rate limit"). Token-shaped substrings are
    #      never inspected as classification signals, so an
    #      accidentally-embedded `ghp_...` value in the host CLI's
    #      stderr cannot trick the classifier (FR-047, SC-013).
    #
    # The classifier deliberately:
    #   - never raises (the `:other` catch-all bucket exists so every
    #     input maps to a value),
    #   - holds no per-instance state (the `#classify` method is
    #     idempotent and thread-safe across calls),
    #   - prefers the most-specific FR-046 bucket when multiple signals
    #     appear in the same stderr (auth signals win over rate-limit
    #     signals, which win over network signals, which win over the
    #     catch-all).
    class FailureClassifier
      # The five FR-046 `failure_class` enum values, ordered from
      # most-specific to least-specific. The order is load-bearing:
      # `#classify` consults the bucket detectors in this exact
      # priority order so a stderr embedding multiple signals returns
      # the most-actionable remediation label (auth issues are the
      # operator's fastest unblock, network issues are the slowest).
      FAILURE_CLASSES = %i[
        auth-missing
        auth-insufficient-scope
        rate-limit
        network
        other
      ].freeze

      # Auth-missing markers — host CLI reports no authenticated
      # identity. Drawn from research.md R-009's documented
      # 'gh auth status' failure messages and the canonical
      # "no authenticated host" phrasing the auth probe (T074)
      # exercises.
      AUTH_MISSING_PATTERNS = [
        /not logged in/i,
        /no authenticated host/i,
        /you are not logged into/i
      ].freeze

      # Auth-insufficient-scope markers — host CLI reports an
      # authenticated identity that lacks a required scope (typically
      # 'repo'). The auth probe (T074) also feeds the classifier the
      # captured 'gh auth status' stderr on exit 0 to detect scope
      # deficiency in the listed "Token scopes:" line, so the
      # classifier matches both the explicit "missing required scopes"
      # wording and the implicit "Token scopes: ..." absence-of-'repo'
      # case.
      AUTH_INSUFFICIENT_SCOPE_PATTERNS = [
        /missing required scopes?/i,
        /missing scopes?:/i
      ].freeze

      # Rate-limit markers — HTTP 429, primary rate limit, secondary
      # rate limit, and abuse-detection signals all collapse to this
      # bucket because their remediation is identical (wait + retry).
      RATE_LIMIT_PATTERNS = [
        /rate limit/i,
        /abuse detection/i,
        /\bhttp 429\b/i
      ].freeze

      # Network markers — DNS, TCP, TLS transport failures. Drawn from
      # the canonical Go-runtime error strings the host CLI surfaces
      # when its underlying net/http client cannot reach
      # api.github.com.
      NETWORK_PATTERNS = [
        /no such host/i,
        /connection reset/i,
        /connection refused/i,
        /tls.*handshake/i,
        /handshake.*timeout/i,
        %r{i/o timeout}i,
        /dial tcp/i
      ].freeze

      # Token scopes parser — extracts the comma-separated scope list
      # from a 'gh auth status' stdout/stderr fragment shaped like:
      #
      #   Token scopes: 'gist', 'read:org'
      #
      # Used to detect the auth-insufficient-scope case where exit was
      # 0 but the listed scopes do not include 'repo'.
      TOKEN_SCOPES_PATTERN = /token scopes?:\s*([^\n]+)/i

      # Map a host-CLI subprocess outcome to one of the five FR-046
      # `failure_class` enum values.
      #
      # The decision is derived solely from the inputs; no environment
      # variable, file, or other ambient state is consulted. The method
      # never raises — unrecognised inputs fall through to `:other`.
      #
      # Priority order is load-bearing: when stderr embeds multiple
      # signals (e.g., a 403 with both "missing scope" and "rate limit"
      # wording), the most-specific FR-046 bucket wins so the operator
      # sees the most-actionable remediation label.
      def classify(exit_code:, stderr:)
        text = stderr.to_s

        return :'auth-missing'            if auth_missing?(text)
        return :'auth-insufficient-scope' if auth_insufficient_scope?(exit_code, text)
        return :'rate-limit'              if rate_limit?(text)
        return :network                   if network?(text)

        :other
      end

      private

      # Detect the auth-missing bucket — host CLI says no
      # authenticated identity exists for the host. Match is
      # substring/regex only; token-shaped substrings in the
      # surrounding text are never inspected as classification signals
      # (FR-047, SC-013).
      def auth_missing?(text)
        AUTH_MISSING_PATTERNS.any? { |pattern| text.match?(pattern) }
      end

      # Detect the auth-insufficient-scope bucket. Two distinct shapes
      # qualify:
      #
      #   1. An explicit "missing required scopes" / "missing scope:"
      #      phrase from the host CLI's API-error surface (covers
      #      exit 1 paths where the host CLI itself flagged the
      #      deficiency).
      #
      #   2. A 'gh auth status' exit-0 surface that lists the token's
      #      scopes but does NOT include 'repo'. The auth probe (T074)
      #      explicitly feeds the classifier this stderr so the
      #      "authenticated but under-scoped" case is detectable.
      def auth_insufficient_scope?(exit_code, text)
        return true if AUTH_INSUFFICIENT_SCOPE_PATTERNS.any? { |pattern| text.match?(pattern) }

        token_scopes_without_repo?(exit_code, text)
      end

      # Helper for the exit-0 'gh auth status' scope-deficiency case.
      # When the host CLI succeeded (exit 0) and the captured
      # stderr/stdout carries a "Token scopes:" line, the listed
      # scopes are split on comma and inspected for the 'repo' token.
      # Absence of 'repo' is the signal that the auth probe must
      # surface as `auth-insufficient-scope` rather than treating the
      # run as fully authorised.
      def token_scopes_without_repo?(exit_code, text)
        return false unless exit_code.zero?

        match = text.match(TOKEN_SCOPES_PATTERN)
        return false unless match

        scopes = match[1].scan(/[a-z_:]+/i).map(&:downcase)
        !scopes.include?('repo')
      end

      # Detect the rate-limit bucket — HTTP 429, primary/secondary
      # rate limits, and the abuse-detection surface all collapse here
      # because their remediation is identical (wait + retry).
      def rate_limit?(text)
        RATE_LIMIT_PATTERNS.any? { |pattern| text.match?(pattern) }
      end

      # Detect the network bucket — DNS, TCP, TLS transport failures
      # surfaced by the host CLI's underlying Go net/http client.
      def network?(text)
        NETWORK_PATTERNS.any? { |pattern| text.match?(pattern) }
      end
    end
  end
end
