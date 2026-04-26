# frozen_string_literal: true

require 'phaser'

# Specs for Phaser::StackedPrs::FailureClassifier — the pure decision
# function that maps a `gh` subprocess outcome (exit code + stderr text)
# onto one of the five FR-046 `failure_class` values (feature
# 007-multi-phase-pipeline; T066/T073, FR-044, FR-045, FR-046, FR-047,
# SC-012, SC-013, plan.md R-009 / D-012, research.md R-009).
#
# The classifier is the single load-bearing surface for the stacked-PR
# creator's "every failure is recorded with the correct remediation
# label" guarantee. Its contract is narrow but every line of it carries
# a Success Criterion, so the test suite below pins each one explicitly:
#
#   1. Every (exit_code, stderr) pair maps to exactly one of the five
#      enum values defined by FR-046:
#
#        * `auth-missing`            — `gh` reports no authenticated
#                                      identity (e.g., "not logged in"
#                                      or "no GitHub hosts" message).
#        * `auth-insufficient-scope` — `gh` reports the authenticated
#                                      identity lacks a required scope
#                                      (typically `repo`).
#        * `rate-limit`              — `gh` returns HTTP 429 / abuse
#                                      detection signal.
#        * `network`                 — DNS, TCP, or TLS error from the
#                                      transport layer.
#        * `other`                   — anything not matched by the prior
#                                      four; the catch-all so callers
#                                      always receive a value.
#
#   2. Pure function — `classify(exit_code:, stderr:)` returns a Symbol
#      and has no side effects: no IO, no exceptions on unrecognized
#      input (the catch-all bucket exists precisely so the classifier
#      never raises), and no observability calls.
#
#   3. Classification source — the decision is derived ONLY from the
#      exit code and stderr text the wrapper hands in (per FR-046:
#      "derived from the host CLI's exit code or response, not guessed
#      from the operator's environment"). The classifier MUST NOT read
#      any environment variable, any file, or any other ambient state
#      to reach its decision.
#
#   4. Token-shaped substrings in stderr never alter the verdict and
#      are never inspected as if they were classification signals
#      (FR-047, SC-013). The classifier's only string operations on
#      stderr are case-insensitive substring/regex matches against the
#      documented marker strings (e.g., "not logged in", "rate limit").
#      A stderr value full of `ghp_...` tokens MUST classify the same
#      way a token-free stderr would.
RSpec.describe 'Phaser::StackedPrs::FailureClassifier' do
  # The system-under-test is a fresh classifier per example so the
  # contract that "the classifier holds no state between calls" is
  # exercised implicitly by every assertion.
  subject(:classifier) { Phaser::StackedPrs::FailureClassifier.new }

  describe '#classify return-type contract' do
    it 'returns a Symbol for a recognized auth-missing input' do
      result = classifier.classify(exit_code: 1, stderr: 'You are not logged into any GitHub hosts.')

      expect(result).to be_a(Symbol)
    end

    it 'returns a Symbol for an unrecognized input (catch-all)' do
      result = classifier.classify(exit_code: 99, stderr: 'completely unrecognized error string')

      expect(result).to be_a(Symbol)
    end

    it 'never raises on completely empty input — the catch-all covers it' do
      expect { classifier.classify(exit_code: 0, stderr: '') }.not_to raise_error
    end

    it 'never raises on a nil-ish stderr — the catch-all covers it' do
      expect { classifier.classify(exit_code: 1, stderr: '') }.not_to raise_error
    end

    it 'returns one of the five FR-046 enum values for any input' do
      allowed = %i[auth-missing auth-insufficient-scope rate-limit network other]

      result = classifier.classify(exit_code: 42, stderr: 'mystery output')

      expect(allowed).to include(result)
    end
  end

  describe 'auth-missing — gh reports no authenticated identity' do
    # The canonical `gh auth status` failure messages for an
    # unauthenticated host are documented in research.md R-009 and
    # exercised by auth_probe_spec.rb. The classifier matches on the
    # stable substrings from those messages so it is resilient to small
    # cosmetic changes to the rest of `gh`'s output.
    it 'classifies "You are not logged into any GitHub hosts" as auth-missing' do
      result = classifier.classify(
        exit_code: 1,
        stderr: "You are not logged into any GitHub hosts. To log in, run: gh auth login\n"
      )

      expect(result).to eq(:'auth-missing')
    end

    it 'classifies a "not logged in" stderr as auth-missing regardless of casing' do
      result = classifier.classify(exit_code: 1, stderr: 'NOT LOGGED IN to github.com')

      expect(result).to eq(:'auth-missing')
    end

    it 'classifies "no authenticated host" wording as auth-missing' do
      result = classifier.classify(
        exit_code: 1,
        stderr: 'gh: no authenticated host found; run gh auth login first'
      )

      expect(result).to eq(:'auth-missing')
    end
  end

  describe 'auth-insufficient-scope — authenticated but missing required scope' do
    it 'classifies a stderr that names a missing required scope as auth-insufficient-scope' do
      result = classifier.classify(
        exit_code: 1,
        stderr: "error: your authentication token is missing required scopes [repo]\n"
      )

      expect(result).to eq(:'auth-insufficient-scope')
    end

    it 'classifies the gh "missing required scopes" wording as auth-insufficient-scope' do
      result = classifier.classify(
        exit_code: 1,
        stderr: 'HTTP 403: Resource not accessible by integration (missing scope: repo)'
      )

      expect(result).to eq(:'auth-insufficient-scope')
    end

    # Even on exit 0 from `gh auth status`, the auth probe explicitly
    # asks the classifier whether the reported scope set is sufficient
    # (auth_probe_spec.rb's "fail-fast on auth-insufficient-scope"
    # group). The classifier surfaces the scope-deficiency case from
    # the stderr text the probe captured.
    it 'classifies an authenticated-but-no-repo-scope stderr as auth-insufficient-scope' do
      result = classifier.classify(
        exit_code: 0,
        stderr: "Logged in to github.com as alice (oauth_token)\n  Token scopes: 'gist', 'read:org'\n"
      )

      expect(result).to eq(:'auth-insufficient-scope')
    end
  end

  describe 'rate-limit — HTTP 429 or abuse detection signal' do
    it 'classifies an HTTP 429 stderr as rate-limit' do
      result = classifier.classify(
        exit_code: 1,
        stderr: 'gh: HTTP 429: API rate limit exceeded for user'
      )

      expect(result).to eq(:'rate-limit')
    end

    it 'classifies an "API rate limit exceeded" stderr as rate-limit' do
      result = classifier.classify(
        exit_code: 1,
        stderr: 'API rate limit exceeded; retry after 3600 seconds'
      )

      expect(result).to eq(:'rate-limit')
    end

    it 'classifies a GitHub abuse-detection stderr as rate-limit' do
      result = classifier.classify(
        exit_code: 1,
        stderr: 'You have triggered an abuse detection mechanism. Please wait a few minutes.'
      )

      expect(result).to eq(:'rate-limit')
    end

    it 'classifies a "secondary rate limit" stderr as rate-limit' do
      result = classifier.classify(
        exit_code: 1,
        stderr: 'You have exceeded a secondary rate limit. Please wait before retrying.'
      )

      expect(result).to eq(:'rate-limit')
    end
  end

  describe 'network — DNS / TCP / TLS transport failure' do
    it 'classifies a DNS-resolution failure as network' do
      result = classifier.classify(
        exit_code: 1,
        stderr: 'dial tcp: lookup api.github.com: no such host'
      )

      expect(result).to eq(:network)
    end

    it 'classifies a TCP connection-reset stderr as network' do
      result = classifier.classify(
        exit_code: 1,
        stderr: 'read tcp 10.0.0.1:443: connection reset by peer'
      )

      expect(result).to eq(:network)
    end

    it 'classifies a TLS handshake error as network' do
      result = classifier.classify(
        exit_code: 1,
        stderr: 'tls: handshake failure: x509: certificate signed by unknown authority'
      )

      expect(result).to eq(:network)
    end

    it 'classifies a connection-refused stderr as network' do
      result = classifier.classify(
        exit_code: 1,
        stderr: 'dial tcp 140.82.121.5:443: connect: connection refused'
      )

      expect(result).to eq(:network)
    end

    it 'classifies a generic "i/o timeout" stderr as network' do
      result = classifier.classify(
        exit_code: 1,
        stderr: 'Get "https://api.github.com/repos/owner/repo": net/http: TLS handshake timeout'
      )

      expect(result).to eq(:network)
    end
  end

  describe 'other — catch-all for anything not matching the prior four' do
    it 'classifies a 500 server error as other' do
      result = classifier.classify(
        exit_code: 1,
        stderr: 'HTTP 500: Internal Server Error'
      )

      expect(result).to eq(:other)
    end

    it 'classifies an entirely unrecognized stderr as other' do
      result = classifier.classify(
        exit_code: 1,
        stderr: 'gh: an unexpected condition happened that we have never seen before'
      )

      expect(result).to eq(:other)
    end

    it 'classifies a non-zero exit with empty stderr as other' do
      result = classifier.classify(exit_code: 2, stderr: '')

      expect(result).to eq(:other)
    end

    it 'classifies a non-FR-046 422-validation error as other' do
      result = classifier.classify(
        exit_code: 1,
        stderr: 'HTTP 422: Validation Failed (the branch already exists)'
      )

      expect(result).to eq(:other)
    end
  end

  describe 'priority ordering — auth signals win over generic HTTP errors' do
    # Some `gh` error messages embed multiple signals (e.g., a 403 with
    # the "missing scope" wording). The classifier MUST prefer the
    # most-specific FR-046 bucket so the operator gets the most
    # actionable remediation. Auth signals win over rate-limit signals
    # which win over network signals which win over the catch-all.
    it 'prefers auth-insufficient-scope over rate-limit when both signals appear' do
      result = classifier.classify(
        exit_code: 1,
        stderr: 'HTTP 403: missing scope: repo (also: API rate limit exceeded)'
      )

      expect(result).to eq(:'auth-insufficient-scope')
    end

    it 'prefers auth-missing over network when both signals appear' do
      result = classifier.classify(
        exit_code: 1,
        stderr: 'You are not logged in. Also: dial tcp: no such host'
      )

      expect(result).to eq(:'auth-missing')
    end

    it 'prefers rate-limit over network when both signals appear' do
      result = classifier.classify(
        exit_code: 1,
        stderr: 'API rate limit exceeded; underlying: connection reset by peer'
      )

      expect(result).to eq(:'rate-limit')
    end
  end

  describe 'derives only from inputs (FR-046, FR-047)' do
    # The classifier MUST NOT consult environment variables, files, or
    # any other ambient state. The strongest test for "no ambient
    # reads" is to assert the same (exit_code, stderr) pair always
    # yields the same classification regardless of the surrounding
    # environment.
    it 'is deterministic — same inputs yield the same output across calls' do
      args = { exit_code: 1, stderr: 'You are not logged into any GitHub hosts.' }

      results = Array.new(20) { classifier.classify(**args) }

      expect(results.uniq).to eq([:'auth-missing'])
    end

    it 'returns the same verdict regardless of GITHUB_TOKEN being set or unset' do
      args = { exit_code: 1, stderr: 'API rate limit exceeded' }

      with_token = with_env('GITHUB_TOKEN' => 'ghp_FAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKE') do
        classifier.classify(**args)
      end
      without_token = with_env('GITHUB_TOKEN' => nil) do
        classifier.classify(**args)
      end

      expect(with_token).to eq(without_token)
      expect(with_token).to eq(:'rate-limit')
    end

    it 'never inspects the GH_TOKEN environment variable when classifying' do
      args = { exit_code: 1, stderr: 'dial tcp: lookup api.github.com: no such host' }

      result = with_env('GH_TOKEN' => 'gho_FAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKE') do
        classifier.classify(**args)
      end

      expect(result).to eq(:network)
    end

    # Helper: temporarily set environment variables for the duration of
    # a block, restoring the previous values afterward. Used by the
    # "ambient state is never consulted" specs above so the classifier's
    # output is observably independent of the surrounding environment.
    def with_env(overrides)
      previous = overrides.to_h { |key, _| [key, ENV.fetch(key, nil)] }
      overrides.each { |key, value| ENV[key] = value }
      yield
    ensure
      previous.each { |key, value| ENV[key] = value }
    end
  end

  describe 'credential-leak resistance (FR-047, SC-013)' do
    # The classifier MUST NOT change its verdict based on the presence
    # of token-shaped substrings in stderr. This pins the behavior
    # that token characters are never interpreted as classification
    # signals — so a malicious or accidental embedding of `ghp_...` in
    # `gh`'s stderr cannot trick the classifier into miscategorizing
    # the failure.
    it 'classifies the same stderr identically with and without an embedded ghp_ token' do
      base_stderr = 'You are not logged into any GitHub hosts.'
      with_token = "#{base_stderr} (token: ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789)"

      expect(classifier.classify(exit_code: 1, stderr: base_stderr)).to eq(
        classifier.classify(exit_code: 1, stderr: with_token)
      )
    end

    it 'classifies the same stderr identically with and without a Bearer-token header' do
      base_stderr = 'API rate limit exceeded'
      with_bearer = "Authorization: Bearer ghp_FAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKE\n#{base_stderr}"

      expect(classifier.classify(exit_code: 1, stderr: base_stderr)).to eq(
        classifier.classify(exit_code: 1, stderr: with_bearer)
      )
    end

    it 'never returns the credential string itself (the verdict is always a Symbol)' do
      result = classifier.classify(
        exit_code: 1,
        stderr: 'Authorization: Bearer ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
      )

      expect(result).to be_a(Symbol)
      expect(result.to_s).not_to include('ghp_')
      expect(result.to_s).not_to include('Bearer')
    end
  end
end
