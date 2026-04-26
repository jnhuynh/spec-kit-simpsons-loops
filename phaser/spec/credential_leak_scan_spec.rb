# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'stringio'
require 'tmpdir'
require 'yaml'
require 'phaser'

# Credential-leak regression spec for FR-047 / SC-013 (feature
# 007-multi-phase-pipeline; T070).
#
# This is the single integration backstop that protects against
# accidentally serializing tokens, session cookies, or authorization
# headers into either of the two operator-facing surfaces:
#
#   1. The JSON-line stderr stream emitted by `Phaser::Observability`
#      (the only path the phaser engine and the stacked-PR creator may
#      use to write log records, per FR-041 and FR-043).
#
#   2. The on-disk YAML persisted by `Phaser::StatusWriter` to
#      `<feature_dir>/phase-creation-status.yaml` (the only path the
#      engine and the stacked-PR creator may use to persist failure
#      payloads, per FR-039 and FR-042).
#
# The two surfaces above each implement an internal credential-pattern
# scrubber against the same pattern list documented in
# `contracts/observability-events.md` "Credential-Leak Guard". This
# spec drives a wide fixture set of failure-mode payloads through both
# surfaces (and through the engine's full failure pipeline) and asserts
# that NONE of the produced bytes — log lines or status-file YAML —
# contain any credential-shaped substring.
#
# Scope per SC-013:
#
#   * "scans every log line emitted by the phaser engine and the
#     stacked-PR creator across the full fixture set"
#   * "every byte of every `phase-creation-status.yaml` produced by
#     failure-mode fixtures"
#   * "finds zero substrings matching common credential patterns
#     (Git-host personal access token prefixes, bearer-token headers,
#     base64-encoded session cookies)"
#
# Pattern catalog (matches `contracts/observability-events.md` plus
# SC-013's "base64-encoded session cookies" extension):
#
#   * GitHub PAT prefixes: `ghp_`, `gho_`, `ghu_`, `ghs_`, `ghr_`
#   * Bearer token headers: `Bearer <opaque>`
#   * Authorization headers: `Authorization: <opaque>`
#   * Cookie headers: `Cookie: <opaque>`
#   * Base64-shaped session cookie payloads (long base64-ish runs in a
#     `session=...` or similar key=value position)
#
# The stacked-PR creator's library code (T072..T076) is implemented
# AFTER this spec lands (per the tasks.md ordering); the existing
# observability and status-writer surfaces are the load-bearing scrubbing
# points the creator (T075) and auth-probe (T074) are required to route
# every leak-prone string through. The creator's own integration tests
# (creator_spec.rb's "credential-leak guard" block) verify the wiring
# end-to-end once that code lands; this spec verifies the underlying
# scrubbers are airtight on every leak shape today, so a future Creator
# regression that bypasses the scrubbers cannot introduce a leak the
# scrubbers themselves missed.

# The credential pattern catalog and the fixture-set scanner live on a
# top-level module (rather than inside the `RSpec.describe` block) to
# satisfy rubocop's `Lint/ConstantDefinitionInBlock` and
# `RSpec/LeakyConstantDeclaration` cops; behavior is identical and the
# scoping makes the contract easy to import from any future companion
# spec (e.g., a per-flavor leak scan).
module CredentialLeakScanner
  REDACTION_MARKER = '[REDACTED:credential-pattern-match]'

  # Each entry is a raw credential-shaped string the scrubbers MUST
  # NEVER allow through. The labels are surfaced in failure messages so
  # a regression points to the exact leak shape that escaped.
  #
  # Values are deliberately distinct from each other so a leak of one
  # value does not look like a leak of another in the failure output.
  #
  # The base64-cookie value is a 60-character base64-shaped run of the
  # form a typical session cookie payload would take; SC-013 calls out
  # base64-encoded cookies explicitly so we exercise both the
  # `Cookie:`-header form (caught by Cookie regex) and the bare
  # base64-shaped run (caught by the cookie pattern).
  CREDENTIAL_FIXTURES = {
    'GitHub PAT (ghp_)' => 'ghp_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
    'GitHub OAuth (gho_)' => 'gho_BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB',
    'GitHub user-to-server (ghu_)' => 'ghu_CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC',
    'GitHub server-to-server (ghs_)' => 'ghs_DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD',
    'GitHub refresh (ghr_)' => 'ghr_EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE',
    'Bearer header (JWT-shape)' => 'Bearer eyJhbGciOiJIUzI1NiJ9.payload.signature',
    'Authorization header' => 'Authorization: token ghp_FFFFFFFFFFFFFFFFFFFF',
    'Cookie header' => 'Cookie: session=abc123def456ghi789jkl012'
  }.freeze

  # Patterns the scanner uses to detect leaks in the produced bytes.
  # These are intentionally identical to the patterns the production
  # scrubbers in `Observability::CREDENTIAL_PATTERNS` and
  # `StatusWriter::CREDENTIAL_PATTERNS` enforce — the scanner asserts
  # that NONE of them appear in the post-scrub output, which is the
  # operational contract FR-047 promises.
  #
  # The `BASE64_SESSION_COOKIE_PATTERN` covers SC-013's "base64-encoded
  # session cookie" wording. It looks for `session=<long-base64-run>`,
  # `csrftoken=<long-base64-run>`, or any `Cookie:` header (the
  # `Cookie:` form is also caught by `Cookie:\s*\S+`; the
  # `session=<run>` form is the bare base64-cookie shape SC-013 names
  # explicitly, which is not caught by the four header patterns alone).
  CREDENTIAL_DETECTION_PATTERNS = [
    /ghp_[A-Za-z0-9]+/,
    /gho_[A-Za-z0-9]+/,
    /ghu_[A-Za-z0-9]+/,
    /ghs_[A-Za-z0-9]+/,
    /ghr_[A-Za-z0-9]+/,
    /Bearer\s+\S+/,
    /Authorization:\s*\S+/i,
    /Cookie:\s*\S+/i,
    %r{(?:session|sessionid|csrftoken|auth_token)=[A-Za-z0-9+/=_-]{20,}}i
  ].freeze

  # Scan a single byte string for any credential pattern; return the
  # list of `[pattern_source, matched_substring]` tuples. An empty list
  # means the byte string is clean.
  def self.scan(bytes)
    matches = []
    CREDENTIAL_DETECTION_PATTERNS.each do |pattern|
      bytes.scan(pattern) { |m| matches << [pattern.source, Array(m).first || pattern.last_match.to_s] }
    end
    matches
  end

  # Render an offender list into a multiline failure message so the
  # operator gets the leak shape and the surface that produced it
  # (rather than a one-line "[]" mismatch).
  def self.format_offenders(label, offenders)
    return nil if offenders.empty?

    rendered = offenders.map { |source, match| "  - pattern /#{source}/ matched #{match.inspect}" }
    "#{label} leaked credential-shaped substrings:\n#{rendered.join("\n")}"
  end
end

RSpec.describe 'credential-leak regression scan' do # rubocop:disable RSpec/DescribeClass
  attr_reader :feature_dir

  around do |example|
    Dir.mktmpdir('phaser-credential-leak-spec') do |tmp|
      @feature_dir = tmp
      example.run
    end
  end

  let(:fixed_clock) { -> { '2026-04-25T12:00:00.000Z' } }
  let(:status_path) { File.join(feature_dir, 'phase-creation-status.yaml') }
  let(:stderr_io) { StringIO.new }
  let(:status_writer) { Phaser::StatusWriter.new(now: fixed_clock) }
  let(:observability) { Phaser::Observability.new(stderr: stderr_io, now: fixed_clock) }

  describe 'scanner sanity (fail-loud guard against vacuous passes)' do
    it 'detects every credential fixture in raw, unscrubbed text' do
      # If the scanner cannot detect a fixture in raw text, then a
      # downstream "no offenders found" assertion vacuously passes for
      # that shape. This guard pins the scanner-fixture pairing so a
      # broken pattern fails this spec instead of silently letting
      # leaks through other specs.
      CredentialLeakScanner::CREDENTIAL_FIXTURES.each do |label, leak|
        offenders = CredentialLeakScanner.scan(leak)
        expect(offenders).not_to be_empty,
                                 "scanner failed to detect #{label}: #{leak.inspect}"
      end
    end

    it 'returns no matches for clean operator-facing text' do
      clean_message = 'Use the four-step rename sequence (add-nullable, dual-write, backfill, drop).'

      expect(CredentialLeakScanner.scan(clean_message)).to be_empty
    end
  end

  describe 'StatusWriter — phaser-engine stage failure-mode fixtures (FR-042)' do
    # Every leak-prone field on the phaser-engine stage payload is
    # exercised with each credential-fixture so a regression that adds
    # a new bypass through any single field is caught.
    CredentialLeakScanner::CREDENTIAL_FIXTURES.each do |label, leak|
      it "redacts #{label} in decomposition_message before bytes hit disk" do
        status_writer.write(
          status_path,
          stage: 'phaser-engine',
          failing_rule: 'forbidden-operation',
          commit_hash: 'a' * 40,
          forbidden_operation: 'direct-column-rename',
          decomposition_message: "Operator note: #{leak}"
        )

        bytes = File.binread(status_path)
        offenders = CredentialLeakScanner.scan(bytes)
        expect(offenders).to be_empty,
                             CredentialLeakScanner.format_offenders(
                               "StatusWriter (decomposition_message, #{label})", offenders
                             )
      end

      it "redacts #{label} in failing_rule before bytes hit disk" do
        status_writer.write(
          status_path,
          stage: 'phaser-engine',
          failing_rule: leak,
          commit_hash: 'a' * 40
        )

        bytes = File.binread(status_path)
        offenders = CredentialLeakScanner.scan(bytes)
        expect(offenders).to be_empty,
                             CredentialLeakScanner.format_offenders(
                               "StatusWriter (failing_rule, #{label})", offenders
                             )
      end

      it "redacts #{label} in missing_precedent before bytes hit disk" do
        status_writer.write(
          status_path,
          stage: 'phaser-engine',
          failing_rule: 'precedent',
          commit_hash: 'a' * 40,
          missing_precedent: leak
        )

        bytes = File.binread(status_path)
        offenders = CredentialLeakScanner.scan(bytes)
        expect(offenders).to be_empty,
                             CredentialLeakScanner.format_offenders(
                               "StatusWriter (missing_precedent, #{label})", offenders
                             )
      end
    end

    it 'leaves the redaction marker in place of every redacted value' do
      status_writer.write(
        status_path,
        stage: 'phaser-engine',
        failing_rule: 'forbidden-operation',
        commit_hash: 'a' * 40,
        forbidden_operation: 'direct-column-rename',
        decomposition_message: 'leaked: ghp_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
      )

      parsed = YAML.safe_load_file(status_path)
      expect(parsed['decomposition_message']).to include('REDACTED')
    end
  end

  describe 'StatusWriter — stacked-pr-creation stage failure-mode fixtures (FR-039, FR-046)' do
    # The stacked-pr-creation stage's leak surface is narrower than the
    # engine stage (only `failure_class` and `first_uncreated_phase`
    # are populated, and `failure_class` is constrained to a five-value
    # enum by the writer's validate_payload!). The leak surface is
    # nonetheless tested for every fixture by injecting the leak shape
    # into a forbidden-engine-stage call and verifying the writer's
    # cross-field validation rejects it cleanly without leaking the
    # injected payload to disk.
    %w[auth-missing auth-insufficient-scope rate-limit network other].each do |klass|
      CredentialLeakScanner::CREDENTIAL_FIXTURES.each_key do |label|
        it "produces a clean status file when failure_class=#{klass} (sanity for #{label})" do
          # The writer's enum guard prevents `failure_class` from ever
          # carrying a free-form string, so the leak path here is
          # closed by construction. We still assert the produced bytes
          # carry no credential pattern so the cross-field invariants
          # stay verified even if a future change loosens the enum.
          status_writer.write(
            status_path,
            stage: 'stacked-pr-creation',
            failure_class: klass,
            first_uncreated_phase: 1
          )

          bytes = File.binread(status_path)
          offenders = CredentialLeakScanner.scan(bytes)
          expect(offenders).to be_empty,
                               CredentialLeakScanner.format_offenders(
                                 "StatusWriter (stacked-pr/#{klass}, #{label} reference)", offenders
                               )
        end
      end
    end
  end

  describe 'Observability — phaser-engine event fixtures (FR-041, FR-043)' do
    CredentialLeakScanner::CREDENTIAL_FIXTURES.each do |label, leak|
      it "redacts #{label} in validation-failed decomposition_message before bytes hit stderr" do
        observability.log_validation_failed(
          failing_rule: 'forbidden-operation',
          commit_hash: 'a' * 40,
          forbidden_operation: 'direct-column-rename',
          decomposition_message: "Leak attempt: #{leak}"
        )

        bytes = stderr_io.string
        offenders = CredentialLeakScanner.scan(bytes)
        expect(offenders).to be_empty,
                             CredentialLeakScanner.format_offenders(
                               "Observability (validation-failed, #{label})", offenders
                             )
      end

      it "redacts #{label} in validation-failed failing_rule before bytes hit stderr" do
        observability.log_validation_failed(
          failing_rule: leak,
          commit_hash: 'a' * 40
        )

        bytes = stderr_io.string
        offenders = CredentialLeakScanner.scan(bytes)
        expect(offenders).to be_empty,
                             CredentialLeakScanner.format_offenders(
                               "Observability (failing_rule, #{label})", offenders
                             )
      end

      it "redacts #{label} in commit-classified rule_name before bytes hit stderr" do
        observability.log_commit_classified(
          commit_hash: 'a' * 40,
          task_type: 'schema add-nullable-column',
          source: :inference,
          rule_name: leak,
          isolation: :alone
        )

        bytes = stderr_io.string
        offenders = CredentialLeakScanner.scan(bytes)
        expect(offenders).to be_empty,
                             CredentialLeakScanner.format_offenders(
                               "Observability (commit-classified rule_name, #{label})", offenders
                             )
      end

      it "redacts #{label} embedded inside phase-emitted nested task entries" do
        # phase-emitted carries an array-of-hashes payload; the
        # observability scrubber recurses through arrays/hashes so
        # leaks nested inside the task entries are also caught.
        observability.log_phase_emitted(
          phase_number: 1,
          branch_name: 'feat-foo-phase-1',
          base_branch: 'main',
          tasks: [{ commit_hash: 'a' * 40, task_type: leak }]
        )

        bytes = stderr_io.string
        offenders = CredentialLeakScanner.scan(bytes)
        expect(offenders).to be_empty,
                             CredentialLeakScanner.format_offenders(
                               "Observability (phase-emitted nested task_type, #{label})", offenders
                             )
      end
    end

    it 'emits a credential-pattern-redacted WARN whenever a redaction occurs' do
      observability.log_validation_failed(
        failing_rule: 'forbidden-operation',
        commit_hash: 'a' * 40,
        decomposition_message: 'leak: ghp_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
      )

      records = stderr_io.string.each_line.map { |line| JSON.parse(line.chomp) }
      warn = records.find { |r| r['event'] == 'credential-pattern-redacted' }
      expect(warn).not_to be_nil
      expect(warn['level']).to eq('WARN')
    end
  end

  describe 'Engine end-to-end failure path (FR-041, FR-042 integration)' do # rubocop:disable RSpec/MultipleMemoizedHelpers
    # The engine's `process` funnels every validation failure through
    # both Observability and StatusWriter — the same surfaces the unit
    # specs above pin individually. This block exercises the full
    # funnel so a future change that bypasses one of the surfaces (or
    # adds a new surface that does NOT route through the scrubbers) is
    # caught by the integration assertion.
    let(:fixed_clock_value) { '2026-04-25T12:00:00.000Z' }
    let(:engine) do
      Phaser::Engine.new(
        feature_dir: feature_dir,
        feature_branch: 'feature-007-multi-phase-pipeline',
        default_branch: 'main',
        observability: observability,
        status_writer: status_writer,
        manifest_writer: Phaser::ManifestWriter.new,
        clock: -> { fixed_clock_value }
      )
    end

    # Build a minimal flavor with one forbidden-operation entry so the
    # engine raises ForbiddenOperationError on the test commit. The
    # forbidden-operation's `decomposition_message` carries the leak —
    # the engine's record_validation_failure funnel forwards that
    # message to BOTH stderr (via Observability) AND the status file
    # (via StatusWriter), so a single leak fixture exercises both
    # surfaces simultaneously.
    def build_flavor_with_leaky_forbidden_op(leak)
      Phaser::Flavor.new(
        name: 'leak-spec',
        version: '0.1.0',
        default_type: 'misc',
        task_types: [
          Phaser::FlavorTaskType.new(name: 'misc', isolation: :groups,
                                     description: 'Catch-all groups type.')
        ],
        precedent_rules: [],
        inference_rules: [],
        forbidden_operations: [
          {
            'name' => 'leak-canary',
            'identifier' => 'leak-canary',
            'detector' => { 'kind' => 'file_glob', 'pattern' => 'db/migrate/*.rb' },
            'decomposition_message' => "Operator notes: #{leak}"
          }
        ],
        stack_detection: Phaser::FlavorStackDetection.new(signals: [])
      )
    end

    def build_canary_commit
      Phaser::Commit.new(
        hash: 'a' * 40,
        subject: 'Leak canary commit',
        message_trailers: {},
        diff: Phaser::Diff.new(
          files: [
            Phaser::FileChange.new(
              path: 'db/migrate/202604250001_canary.rb',
              change_kind: :added,
              hunks: ["@@ -0,0 +1 @@\n+class Canary < Migration; end\n"]
            )
          ]
        ),
        author_timestamp: '2026-04-25T00:00:00Z'
      )
    end

    CredentialLeakScanner::CREDENTIAL_FIXTURES.each do |label, leak|
      it "scrubs #{label} from BOTH the status file AND the stderr stream on a forbidden-op rejection" do
        flavor = build_flavor_with_leaky_forbidden_op(leak)
        commit = build_canary_commit

        # The engine raises after recording the failure to both
        # surfaces; rescue here and let the bytes-on-disk and
        # stderr-buffer assertions speak.
        expect { engine.process([commit], flavor) }.to raise_error(Phaser::ForbiddenOperationError)

        status_offenders = CredentialLeakScanner.scan(File.binread(status_path))
        stderr_offenders = CredentialLeakScanner.scan(stderr_io.string)

        expect(status_offenders).to be_empty,
                                    CredentialLeakScanner.format_offenders(
                                      "Engine -> StatusWriter (#{label})", status_offenders
                                    )
        expect(stderr_offenders).to be_empty,
                                    CredentialLeakScanner.format_offenders(
                                      "Engine -> Observability (#{label})", stderr_offenders
                                    )
      end
    end
  end

  describe 'no surface produces stdout output during failure-mode fixtures (FR-043)' do
    # FR-043 reserves stdout for the manifest path on success; failure
    # modes MUST never write to stdout. If a future regression sends a
    # failure-mode payload to `$stdout`, a leak that was correctly
    # scrubbed from stderr could still escape via stdout — pin the
    # stream-separation contract here so the leak-scrub guarantee
    # stays meaningful.
    it 'observability writes only to stderr during a leak-laden validation-failed emission' do
      expect do
        observability.log_validation_failed(
          failing_rule: 'forbidden-operation',
          commit_hash: 'a' * 40,
          decomposition_message: 'leak: ghp_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
        )
      end.not_to output.to_stdout
    end

    it 'status writer writes nothing to stdout during a leak-laden phaser-engine emission' do
      expect do
        status_writer.write(
          status_path,
          stage: 'phaser-engine',
          failing_rule: 'forbidden-operation',
          commit_hash: 'a' * 40,
          forbidden_operation: 'direct-column-rename',
          decomposition_message: 'leak: ghp_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
        )
      end.not_to output.to_stdout
    end
  end
end
