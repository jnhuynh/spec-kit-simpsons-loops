# frozen_string_literal: true

require 'digest'
require 'pathname'
require 'spec_helper'

# Regression spec for SC-006 / FR-025 — the no-flavor zero-regression
# contract for the SpecKit pipeline (feature 007-multi-phase-pipeline;
# T056, plan.md D-008, quickstart.md "Pattern: Conditional Pipeline
# Behavior").
#
# The contract under test:
#
#   When `.specify/flavor.yaml` is ABSENT at the repository root, the
#   modified `speckit.pipeline.md` MUST behave byte-identically to the
#   pre-feature pipeline: no phaser stage runs, no phase manifest is
#   emitted, marge is invoked once holistically, a single PR is
#   produced, and no phaser-related output (log lines, status files,
#   pipeline announcements) appears anywhere in the captured pipeline
#   stdout/stderr stream.
#
# How the regression is verified (per SC-006's wording: "verified by a
# regression test that diffs the pipeline output against a captured
# baseline"):
#
#   1. T064 captures the pipeline's stdout/stderr stream on the
#      `example-minimal` fixture branch with `.specify/flavor.yaml`
#      absent and stores the captured bytes at
#      `phaser/spec/fixtures/baselines/pipeline-no-flavor.txt`.
#
#   2. Whenever a contributor needs to verify a change preserves the
#      no-flavor zero-regression contract, they re-run the same fixture
#      capture and place the fresh stream at the path named by the
#      `PHASER_PIPELINE_CAPTURE` environment variable. This spec then
#      diffs the fresh capture against the stored baseline byte-for-
#      byte. Any mismatch — even a single trailing-newline drift — is a
#      regression and fails the spec with the offending diff hunk.
#
#   3. When `PHASER_PIPELINE_CAPTURE` is unset (the common case in CI
#      that does not have a pre-captured fresh stream), the spec still
#      enforces the load-bearing baseline invariants: the baseline file
#      MUST exist (so the regression contract is not vacuously
#      satisfied), MUST be non-empty, MUST contain no phaser-related
#      tokens (asserting the captured baseline truly represents the
#      no-flavor pipeline), and MUST NOT contain any credential-shaped
#      substrings (a SC-013-adjacent backstop that catches an operator
#      accidentally pasting a token into the captured stream).
#
# The dual mode — strict diff when the fresh capture is provided,
# baseline-shape assertions when it is not — is what lets this spec
# live in the regular `bundle exec rspec` run without forcing every
# developer to re-capture the pipeline output on every commit, while
# still failing loudly the moment a baseline drift is detected.
#
# Why a separate `PHASER_PIPELINE_CAPTURE` capture file rather than
# invoking the pipeline from the spec directly: the SpecKit pipeline
# is a Markdown command interpreted by the Claude CLI, not a Ruby
# library. Spawning `claude` from RSpec would couple the test to a
# non-deterministic LLM execution surface and break the determinism
# contract (FR-002, SC-002) that every other phaser spec relies on.
# Capturing the stream out-of-band and diffing it byte-for-byte is the
# narrow, deterministic surface SC-006 actually requires.
#
# Acceptance:
#
#   * Without `PHASER_PIPELINE_CAPTURE`:
#       - the baseline file exists, is non-empty, contains no
#         phaser-related tokens, and contains no credential-shaped
#         substrings.
#   * With `PHASER_PIPELINE_CAPTURE` pointing at a readable file:
#       - the file's bytes are byte-identical to the baseline.

# Module-scoped constants so rubocop's `Lint/ConstantDefinitionInBlock`
# and `RSpec/LeakyConstantDeclaration` cops are satisfied while keeping
# the contract surface easy to import from any future companion spec
# (e.g., a captured-baseline test for the with-flavor pipeline path).
module PipelineNoFlavorBaseline
  PHASER_ROOT = Pathname.new(File.expand_path('..', __dir__))

  # The captured baseline file. Created by T064 by running the pipeline
  # on the example-minimal fixture branch with `.specify/flavor.yaml`
  # absent and tee-ing the combined stdout/stderr stream into this
  # path. This spec deliberately does NOT regenerate the file — that
  # would defeat the regression-detection purpose of SC-006.
  BASELINE_PATH = PHASER_ROOT.join('spec', 'fixtures', 'baselines', 'pipeline-no-flavor.txt')

  # The env var that points at a fresh out-of-band capture for byte-
  # diff comparison. Optional in the common case; required only when a
  # contributor wants to verify their changes preserve the contract.
  CAPTURE_ENV = 'PHASER_PIPELINE_CAPTURE'

  # Tokens that, if present in the captured baseline, would prove the
  # capture was taken with the phaser stage active — exactly what SC-006
  # forbids. The list mirrors the phaser-specific surface introduced by
  # this feature: the stage name, the manifest filename, the status
  # filename, the per-phase marge flag, the structured-log event names
  # (contracts/observability-events.md), and the stacked-PR creator's
  # entry-point name. Case-insensitive match because pipeline log lines
  # are mixed case.
  FORBIDDEN_PHASER_TOKENS = [
    'phase-manifest.yaml',
    'phase-creation-status.yaml',
    'phaser-engine',
    'stacked-pr-creation',
    'commit-classified',
    'phase-emitted',
    'commit-skipped-empty-diff',
    'validation-failed',
    'phaser-stacked-prs',
    'phaser-flavor-init',
    '--phase ',
    'PHASER_ENABLED'
  ].freeze

  # Credential-shaped substrings that MUST NEVER appear in the
  # baseline. Mirrors the SC-013 detector list (T070); duplicating it
  # here keeps this spec self-contained and gives a second backstop
  # against a baseline accidentally containing an operator's token.
  # The list intentionally errs on the side of false positives — a
  # legitimate baseline has no reason to mention any of these prefixes.
  CREDENTIAL_PATTERNS = [
    /ghp_[A-Za-z0-9]{20,}/,   # GitHub personal access token
    /gho_[A-Za-z0-9]{20,}/,   # GitHub OAuth token
    /ghu_[A-Za-z0-9]{20,}/,   # GitHub user-to-server token
    /ghs_[A-Za-z0-9]{20,}/,   # GitHub server-to-server token
    /ghr_[A-Za-z0-9]{20,}/,   # GitHub refresh token
    /\bBearer\s+[A-Za-z0-9._-]{20,}/, # Generic bearer header
    /xox[abprs]-[A-Za-z0-9-]{10,}/    # Slack-style token (defensive)
  ].freeze

  # Compute the skip reason for the byte-diff example at load time so
  # the value can be passed inline as the example's `skip:` metadata.
  # Returns a truthy reason string when the byte-diff cannot run (no
  # capture configured, or the configured capture path is missing) and
  # `false` when the example should run.
  def self.byte_diff_skip_reason
    capture = ENV.fetch(CAPTURE_ENV, nil)
    return "set #{CAPTURE_ENV} to a fresh capture path to enable byte-diff" if capture.nil? || capture.empty?

    return "#{CAPTURE_ENV}=#{capture} does not exist" unless File.exist?(capture)

    false
  end
end

RSpec.describe 'pipeline no-flavor baseline regression' do # rubocop:disable RSpec/DescribeClass
  let(:baseline_path) { PipelineNoFlavorBaseline::BASELINE_PATH }
  let(:capture_env)   { PipelineNoFlavorBaseline::CAPTURE_ENV }
  let(:capture_path)  { ENV.fetch(capture_env, nil) }

  describe 'baseline file invariants' do
    # The baseline file's existence is load-bearing for SC-006: without
    # it, every other assertion in this spec is vacuously satisfied and
    # the regression contract silently regresses. T064's job is to
    # populate this file; until it does, this spec is expected to fail
    # — that failure is the test-first signal that the implementation
    # task is still outstanding.
    it 'has a captured baseline file at the documented path' do
      missing_message = <<~MSG.strip
        Baseline file missing: #{baseline_path}.

        Run T064 to capture the no-flavor pipeline output on the
        example-minimal fixture branch with `.specify/flavor.yaml`
        absent and tee the combined stdout/stderr stream into this
        path. Without the baseline, SC-006's regression contract is
        unverifiable.
      MSG
      expect(baseline_path).to exist, missing_message
    end

    it 'has a non-empty baseline file (a 0-byte file would vacuously match)' do
      skip 'baseline file does not exist yet (see T064)' unless baseline_path.exist?

      expect(baseline_path.size).to be > 0,
                                    "Baseline file is empty: #{baseline_path}. " \
                                    'A zero-byte baseline would byte-match any ' \
                                    'capture and silently disable SC-006.'
    end

    it 'contains no phaser-related tokens (the capture must be the no-flavor path)' do
      skip 'baseline file does not exist yet (see T064)' unless baseline_path.exist?

      contents = baseline_path.read
      offenders = PipelineNoFlavorBaseline::FORBIDDEN_PHASER_TOKENS.select do |token|
        contents.downcase.include?(token.downcase)
      end

      failure_message = <<~MSG.strip
        Baseline at #{baseline_path} contains phaser-related token(s):
        #{offenders.map { |t| "  * #{t.inspect}" }.join("\n")}

        SC-006 requires the no-flavor pipeline to behave byte-identically
        to the pre-feature pipeline: no phaser stage, no phase manifest,
        no per-phase marge invocation. The presence of these tokens
        proves the baseline was captured with the phaser stage active —
        re-capture with `.specify/flavor.yaml` absent.
      MSG
      expect(offenders).to be_empty, failure_message
    end

    it 'contains no credential-shaped substrings (SC-013 backstop)' do
      skip 'baseline file does not exist yet (see T064)' unless baseline_path.exist?

      contents = baseline_path.read
      hits = PipelineNoFlavorBaseline::CREDENTIAL_PATTERNS.flat_map do |pattern|
        contents.scan(pattern).map { |match| [pattern.source, match] }
      end

      failure_message = <<~MSG.strip
        Baseline at #{baseline_path} contains credential-shaped match(es):
        #{hits.map { |pat, m| "  * pattern=#{pat.inspect} matched=#{m.inspect}" }.join("\n")}

        Even captured baseline files MUST NOT contain credentials.
        Re-capture in a sandbox with no real tokens, or sanitize the
        existing capture before checking it in.
      MSG
      expect(hits).to be_empty, failure_message
    end
  end

  describe 'byte-identical diff against fresh out-of-band capture' do
    # This block runs only when an operator has captured a fresh
    # pipeline stream and pointed `PHASER_PIPELINE_CAPTURE` at it. The
    # diff is intentionally strict: even a single byte of drift fails
    # the spec, because SC-006's "byte-identical" wording does not
    # admit any tolerance.
    it 'matches the captured baseline byte-for-byte', skip: PipelineNoFlavorBaseline.byte_diff_skip_reason do # rubocop:disable RSpec/ExampleLength
      capture = Pathname.new(capture_path)
      baseline_bytes = baseline_path.binread
      capture_bytes  = capture.binread

      identical = baseline_bytes == capture_bytes
      unless identical
        baseline_digest = Digest::SHA256.hexdigest(baseline_bytes)
        capture_digest  = Digest::SHA256.hexdigest(capture_bytes)
        failure_message = <<~MSG.strip
          Pipeline-no-flavor capture drift detected (SC-006 / FR-025):

            baseline: #{baseline_path} (#{baseline_bytes.bytesize} bytes, sha256=#{baseline_digest})
            capture:  #{capture_path} (#{capture_bytes.bytesize} bytes, sha256=#{capture_digest})

          The no-flavor pipeline output is no longer byte-identical to
          the captured baseline. Either:

            (a) the change under review legitimately alters pre-feature
                pipeline behavior — re-run T064 to refresh the baseline
                AFTER establishing the change is intentional, OR

            (b) the change unintentionally leaks phaser-related behavior
                into the no-flavor path — fix the regression so the
                output matches the baseline again.
        MSG
        expect(identical).to be(true), failure_message
      end
    end
  end
end
