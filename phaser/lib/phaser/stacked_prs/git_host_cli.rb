# frozen_string_literal: true

require 'open3'

module Phaser
  module StackedPrs
    # Single, narrow subprocess wrapper that invokes the `gh` CLI on
    # behalf of every stacked-PR-creator surface (feature
    # 007-multi-phase-pipeline; T072, FR-044, FR-045, FR-046, FR-047,
    # SC-012, SC-013, plan.md "Pattern: gh Subprocess Wrapper" / D-009).
    #
    # Why this wrapper exists:
    #
    #   The wrapper is the SOLE in-process path that ever shells out to
    #   `gh`. Centralising the call here gives the codebase four
    #   load-bearing properties for free that would otherwise have to be
    #   re-proven at every downstream call site:
    #
    #   1. **One subprocess invocation path.** `Open3.capture3('gh',
    #      *args)` is the ONLY mechanism used to spawn `gh`. T071's
    #      grep-based regression test asserts no `system('gh', ...)` or
    #      backtick-`gh` exists anywhere under `phaser/lib/`; every
    #      downstream caller (AuthProbe, Creator, FailureClassifier
    #      consumers) routes through `#run` here.
    #
    #   2. **No environment-variable token reads.** The wrapper neither
    #      adds nor removes anything from the subprocess environment. It
    #      also does not consult any `*TOKEN*` / `*KEY*` / `*SECRET*` /
    #      `*PASSWORD*` env var to decide whether or how to invoke `gh`.
    #      Authentication is opaque: `gh` itself owns the credential
    #      surface (per `contracts/stacked-pr-creator-cli.md`
    #      "Authentication Surface").
    #
    #   3. **Stderr-credential sanitisation.** The wrapper captures the
    #      full subprocess stderr but only forwards the FIRST LINE to
    #      callers, scanning that line against the FR-047 credential
    #      patterns. On any match, the offending substring is replaced
    #      with the documented redaction marker before the result reaches
    #      the caller — a downstream JSON-serialised observability event
    #      or YAML status file therefore can never embed a token,
    #      regardless of which call site emits it.
    #
    #   4. **Result-shape stability.** `#run` returns a small value
    #      object that responds to `#stdout`, `#stderr`, and `#status`
    #      (a `Process::Status`-shaped reader). AuthProbe (T074) and
    #      Creator (T075) consume exactly that surface; pinning the
    #      shape here means any change ripples through one place.
    #
    # The wrapper is deliberately a thin facade: it does NOT retry, it
    # does NOT classify failures (that is FailureClassifier's job —
    # T073), and it does NOT raise on non-zero exit (that is the
    # caller's policy). Its sole responsibilities are the four bullets
    # above.
    class GitHostCli
      # Mirrors the redaction marker used by Phaser::Observability and
      # Phaser::StatusWriter so a downstream caller serialising the
      # wrapper's result into a log line or status file produces
      # byte-identical redaction output regardless of which surface
      # observed the leak first.
      REDACTION_MARKER = '[REDACTED:credential-pattern-match]'

      # Patterns drawn from contracts/observability-events.md
      # "Credential-Leak Guard". Kept inline (rather than imported from
      # `Phaser::Observability`) so a future change to one surface does
      # not silently weaken the other; the credential-leak regression
      # test (T070) scans every byte produced by all three surfaces
      # against the same external pattern set.
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

      # The result object returned by `#run`. Defined as a `Data` class
      # (Ruby 3.2+) so it is immutable and value-equal — callers can
      # compare results in tests without worrying about identity. The
      # readers `#stdout`, `#stderr`, `#status` are exactly the surface
      # that Creator (T075) consumes; `#full_stderr` is the full
      # multi-line capture (with credential redaction applied across
      # every line) that AuthProbe (T074) consumes when it must parse
      # multi-line output from `gh auth status` (the canonical example:
      # the "Token scopes:" line is on stderr line 3, not line 1).
      # Both stderr surfaces run through the same credential-pattern
      # redaction so neither path can serialise a token byte.
      Result = Data.define(:stdout, :stderr, :full_stderr, :status)

      # Invoke `gh` with the given argv-style array and return a Result.
      #
      # The args are SPLATTED into the `Open3.capture3` positional
      # parameters so each entry stays its own argv token — re-joining
      # would silently break commands like
      # `gh pr create --title "long title with spaces"` by passing the
      # whole quoted string as one token.
      #
      # The wrapper does NOT alter the subprocess environment in any
      # way (no env hash is passed as the first positional to
      # `Open3.capture3`); the operator's environment is inherited
      # unchanged so `gh` can resolve its own credential sources.
      def run(args)
        stdout, stderr, status = Open3.capture3('gh', *args)
        Result.new(
          stdout: stdout,
          stderr: sanitize_stderr(stderr),
          full_stderr: sanitize_full_stderr(stderr),
          status: status
        )
      end

      private

      # Reduce the full stderr capture to a SINGLE sanitised line so the
      # wrapper's contract (plan.md "Pattern: gh Subprocess Wrapper")
      # holds: callers see only the first line, and that line has every
      # credential-shaped substring replaced with the redaction marker.
      #
      # The order matters: line-truncation runs first (so a credential
      # buried on line N never even enters the sanitiser's scope), then
      # the credential scan runs on the surviving first line. Both
      # passes are unconditional — they run on success and failure
      # alike, because the credential-leak guard MUST hold on every
      # outcome.
      def sanitize_stderr(stderr)
        return '' if stderr.nil? || stderr.empty?

        first_line = stderr.each_line.first.to_s.chomp
        redact_credentials(first_line)
      end

      # Replace any credential-shaped substring with the redaction
      # marker. Every pattern in `CREDENTIAL_PATTERNS` is applied so a
      # line carrying multiple distinct token shapes is fully scrubbed.
      # The non-credential context around each match is preserved so
      # the caller still has actionable text to log or display.
      def redact_credentials(line)
        CREDENTIAL_PATTERNS.reduce(line) do |scrubbed, pattern|
          scrubbed.gsub(pattern, REDACTION_MARKER)
        end
      end

      # Apply the credential-pattern redaction across every line of the
      # full multi-line stderr capture. Returned as `#full_stderr` for
      # the AuthProbe (T074) which must parse multi-line `gh auth status`
      # output (host on line 1, "Token scopes:" on line 3). The stderr
      # first-line surface remains the canonical caller-facing field
      # for one-shot summary use.
      def sanitize_full_stderr(stderr)
        return '' if stderr.nil? || stderr.empty?

        redact_credentials(stderr.to_s)
      end
    end
  end
end
