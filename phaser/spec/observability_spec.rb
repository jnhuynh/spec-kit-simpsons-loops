# frozen_string_literal: true

require 'json'
require 'stringio'
require 'phaser'

# Specs for Phaser::Observability — the JSON-line stderr logger that the
# phaser engine and the stacked-PR creator emit through (feature
# 007-multi-phase-pipeline, T012/T013, FR-041, FR-043, FR-047, SC-011,
# SC-013, plan.md D-011).
#
# The logger is the single observability surface for the phaser
# subsystem. Its contract is narrow but load-bearing for several
# Success Criteria, so the test suite below pins every one of them
# explicitly:
#
#   1. JSON-line format on stderr only — every emitted record is a
#      single JSON object terminated by `\n` written to the stderr
#      stream the logger was constructed with. No bytes ever reach
#      stdout (FR-043, plan.md D-011).
#
#   2. Mandatory common envelope — every record carries `level`,
#      `timestamp`, and `event` keys with the documented types
#      (contracts/observability-events.md "Common Fields"; data-model.md
#      "ObservabilityEvent").
#
#   3. Deterministic clock injection — the `now:` constructor argument
#      lets the engine and tests pin the timestamp to a fixed clock so
#      the `timestamp` field is reproducible (FR-002, SC-002, SC-011).
#      A real clock defaults are exercised by checking the format only.
#
#   4. Per-event payload schemas — the four engine-facing methods
#      (`log_commit_classified`, `log_phase_emitted`,
#      `log_commit_skipped_empty_diff`, `log_validation_failed`) emit
#      records whose payload fields match the schemas in
#      contracts/observability-events.md.
#
#   5. Credential-leak guard — every string-typed field value is scanned
#      for credential patterns before the record is written
#      (contracts/observability-events.md "Credential-Leak Guard",
#      FR-047, SC-013). When a pattern matches, the field is replaced
#      with the redaction marker and a separate WARN record
#      `credential-pattern-redacted` is emitted naming the field.
RSpec.describe Phaser::Observability do # rubocop:disable RSpec/SpecFilePathFormat
  # The system-under-test: a fresh logger wired to the captured stderr
  # stream and the fixed clock. Constructing one this way is the
  # single supported instantiation path used by the engine (T013) and
  # the stacked-PR creator (T072..T075).
  subject(:logger) { described_class.new(stderr: stderr, now: clock) }

  # A captured stderr stream — `StringIO` lets the specs read back the
  # bytes the logger emitted without touching the real `$stderr`.
  let(:stderr) { StringIO.new }

  # Pin the clock so the `timestamp` field is reproducible across runs.
  # The logger calls `clock.call` each time it stamps a record; the
  # contract is "ISO-8601 UTC string with millisecond precision"
  # (contracts/observability-events.md).
  let(:fixed_timestamp) { '2026-04-25T12:00:01.123Z' }
  let(:clock) { -> { fixed_timestamp } }

  # Helper: parse the captured stderr buffer into one JSON object per
  # line, enforcing the "exactly one object per `\n`-terminated line"
  # invariant (FR-041). Returns the parsed Hash list in emission order.
  def captured_records
    stderr.string.each_line.map do |line|
      expect(line).to end_with("\n"),
                      "expected every record to be \\n-terminated, got: #{line.inspect}"
      JSON.parse(line.chomp)
    end
  end

  describe 'common envelope (contracts/observability-events.md "Common Fields")' do
    it 'emits exactly one JSON object per record, terminated by a newline' do
      logger.log_commit_skipped_empty_diff(commit_hash: 'a' * 40)

      expect(stderr.string.lines.length).to eq(1)
      expect(stderr.string).to end_with("\n")
      expect { JSON.parse(stderr.string.chomp) }.not_to raise_error
    end

    it 'never writes any bytes to stdout (FR-043, plan.md D-011)' do
      # Use RSpec's `output(...).to_stdout` matcher to assert nothing
      # reaches the real stdout for the duration of the call. The
      # matcher captures the actual `$stdout` writes performed by the
      # logger and the matcher fails if anything other than the empty
      # string is emitted.
      expect do
        logger.log_commit_skipped_empty_diff(commit_hash: 'a' * 40)
        logger.log_phase_emitted(
          phase_number: 1,
          branch_name: 'feat-foo-phase-1',
          base_branch: 'main',
          tasks: [{ commit_hash: 'a' * 40, task_type: 'example' }]
        )
      end.not_to output.to_stdout
    end

    it 'includes the level, timestamp, and event keys on every record' do
      logger.log_commit_classified(
        commit_hash: 'b' * 40,
        task_type: 'schema add-nullable-column',
        source: :inference,
        rule_name: 'add-nullable-column-via-migration',
        isolation: :alone
      )

      record = captured_records.first
      expect(record).to include('level', 'timestamp', 'event')
      expect(record['timestamp']).to eq(fixed_timestamp)
    end

    it 'serializes the level as one of INFO, WARN, ERROR' do
      logger.log_commit_classified(
        commit_hash: 'b' * 40,
        task_type: 'example',
        source: :default,
        isolation: :alone
      )
      logger.log_commit_skipped_empty_diff(commit_hash: 'c' * 40)
      logger.log_validation_failed(failing_rule: 'unknown-type-tag', commit_hash: 'd' * 40)

      levels = captured_records.map { |r| r['level'] }
      expect(levels).to eq(%w[INFO WARN ERROR])
    end

    it 'uses the injected clock so timestamps are reproducible' do
      logger.log_commit_skipped_empty_diff(commit_hash: 'a' * 40)
      logger.log_commit_skipped_empty_diff(commit_hash: 'b' * 40)

      timestamps = captured_records.map { |r| r['timestamp'] }
      expect(timestamps).to all(eq(fixed_timestamp))
    end

    it 'falls back to a real ISO-8601 UTC clock when no clock is injected' do
      real_clock_logger = described_class.new(stderr: stderr)
      real_clock_logger.log_commit_skipped_empty_diff(commit_hash: 'a' * 40)

      timestamp = captured_records.first['timestamp']
      # ISO-8601 UTC with millisecond precision per the contract.
      expect(timestamp).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z\z/)
    end
  end

  describe '#log_commit_classified (INFO)' do
    let(:required_payload) do
      {
        commit_hash: 'a' * 40,
        task_type: 'schema add-nullable-column',
        source: :inference,
        isolation: :alone
      }
    end

    it 'emits a commit-classified INFO record with the required fields' do
      logger.log_commit_classified(**required_payload, rule_name: 'add-nullable-column-via-migration')

      record = captured_records.first
      expect(record).to include(
        'level' => 'INFO',
        'event' => 'commit-classified',
        'commit_hash' => 'a' * 40,
        'task_type' => 'schema add-nullable-column',
        'source' => 'inference',
        'rule_name' => 'add-nullable-column-via-migration',
        'isolation' => 'alone'
      )
    end

    it 'omits rule_name when classification source is not inference' do
      logger.log_commit_classified(**required_payload, source: :default)

      record = captured_records.first
      expect(record).not_to have_key('rule_name')
      expect(record['source']).to eq('default')
    end

    it 'serializes precedents_consulted as a JSON array when provided' do
      logger.log_commit_classified(
        **required_payload,
        precedents_consulted: %w[drop-column-requires-cleanup]
      )

      record = captured_records.first
      expect(record['precedents_consulted']).to eq(%w[drop-column-requires-cleanup])
    end
  end

  describe '#log_phase_emitted (INFO)' do
    let(:phase_tasks) do
      [
        { commit_hash: 'a' * 40, task_type: 'schema add-nullable-column' },
        { commit_hash: 'b' * 40, task_type: 'app dual-write' }
      ]
    end

    let(:expected_serialized_tasks) do
      [
        { 'commit_hash' => 'a' * 40, 'task_type' => 'schema add-nullable-column' },
        { 'commit_hash' => 'b' * 40, 'task_type' => 'app dual-write' }
      ]
    end

    it 'emits a phase-emitted INFO record carrying the phase metadata and tasks' do
      logger.log_phase_emitted(
        phase_number: 2,
        branch_name: 'feat-foo-phase-2',
        base_branch: 'feat-foo-phase-1',
        tasks: phase_tasks
      )

      record = captured_records.first
      expect(record).to include(
        'level' => 'INFO',
        'event' => 'phase-emitted',
        'phase_number' => 2,
        'branch_name' => 'feat-foo-phase-2',
        'base_branch' => 'feat-foo-phase-1'
      )
      expect(record['tasks']).to eq(expected_serialized_tasks)
    end
  end

  describe '#log_commit_skipped_empty_diff (WARN)' do
    it 'emits a commit-skipped-empty-diff WARN record with the commit hash and constant reason' do
      logger.log_commit_skipped_empty_diff(commit_hash: 'a' * 40)

      record = captured_records.first
      expect(record).to include(
        'level' => 'WARN',
        'event' => 'commit-skipped-empty-diff',
        'commit_hash' => 'a' * 40,
        'reason' => 'empty-diff'
      )
    end
  end

  describe '#log_validation_failed (ERROR)' do
    it 'emits a validation-failed ERROR with the failing rule and commit hash' do
      logger.log_validation_failed(
        failing_rule: 'direct-column-rename',
        commit_hash: 'a' * 40,
        forbidden_operation: 'direct-column-rename',
        decomposition_message: 'Decompose column rename into add-nullable, dual-write, backfill...'
      )

      record = captured_records.first
      expect(record).to include(
        'level' => 'ERROR',
        'event' => 'validation-failed',
        'failing_rule' => 'direct-column-rename',
        'commit_hash' => 'a' * 40,
        'forbidden_operation' => 'direct-column-rename',
        'decomposition_message' => 'Decompose column rename into add-nullable, dual-write, backfill...'
      )
    end

    it 'omits commit_hash for feature-too-large failures (no single commit at fault)' do
      logger.log_validation_failed(
        failing_rule: 'feature-too-large',
        commit_count: 250,
        phase_count: 60,
        decomposition_message: 'Split this feature into smaller batches.'
      )

      record = captured_records.first
      expect(record).not_to have_key('commit_hash')
      expect(record).to include(
        'failing_rule' => 'feature-too-large',
        'commit_count' => 250,
        'phase_count' => 60
      )
    end

    it 'includes missing_precedent on precedent-rule failures' do
      logger.log_validation_failed(
        failing_rule: 'drop-column-requires-cleanup',
        commit_hash: 'a' * 40,
        missing_precedent: 'app remove-references'
      )

      record = captured_records.first
      expect(record['missing_precedent']).to eq('app remove-references')
    end
  end

  describe 'credential-leak guard (FR-047, SC-013, contracts/observability-events.md)' do
    # The guard scans every string-typed field for credential patterns
    # before the record reaches stderr. When a match is found, the
    # field is replaced with the redaction marker and a separate WARN
    # record `credential-pattern-redacted` is emitted naming the field
    # (but never the matching value).

    {
      'GitHub PAT (ghp_)' => 'ghp_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
      'GitHub OAuth (gho_)' => 'gho_BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB',
      'GitHub user-to-server (ghu_)' => 'ghu_CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC',
      'GitHub server-to-server (ghs_)' => 'ghs_DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD',
      'GitHub refresh (ghr_)' => 'ghr_EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE',
      'Bearer header' => 'Bearer eyJhbGciOiJIUzI1NiJ9',
      'Authorization header' => 'Authorization: token-value-here',
      'Cookie header' => 'Cookie: session=abc123'
    }.each do |label, leak|
      it "redacts a #{label} embedded in a string-typed field" do
        logger.log_validation_failed(
          failing_rule: 'unknown-type-tag',
          commit_hash: 'a' * 40,
          decomposition_message: "Operator may have leaked a token: #{leak}"
        )

        records = captured_records
        leak_record = records.find { |r| r['event'] == 'validation-failed' }
        expect(leak_record['decomposition_message']).to eq('[REDACTED:credential-pattern-match]')
        expect(stderr.string).not_to include(leak)
      end

      it "emits a credential-pattern-redacted WARN record naming the field for #{label}" do
        logger.log_validation_failed(
          failing_rule: 'unknown-type-tag',
          commit_hash: 'a' * 40,
          decomposition_message: "Token leak: #{leak}"
        )

        warn_record = captured_records.find { |r| r['event'] == 'credential-pattern-redacted' }
        expect(warn_record).not_to be_nil
        expect(warn_record).to include(
          'level' => 'WARN',
          'event' => 'credential-pattern-redacted',
          'field' => 'decomposition_message'
        )
        # The redaction record MUST NOT contain the matching value.
        expect(warn_record.values.join(' ')).not_to include(leak)
      end
    end

    it 'leaves clean string fields untouched and emits no redaction record' do
      logger.log_validation_failed(
        failing_rule: 'unknown-type-tag',
        commit_hash: 'a' * 40,
        decomposition_message: 'Use one of the documented type tags.'
      )

      records = captured_records
      expect(records.length).to eq(1)
      expect(records.first['decomposition_message']).to eq('Use one of the documented type tags.')
    end

    it 'scans every string field on a single record (multi-field leak surfaces)' do
      logger.log_validation_failed(
        failing_rule: 'ghp_FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF',
        commit_hash: 'a' * 40,
        decomposition_message: 'Bearer eyJleaky'
      )

      validation_record = captured_records.find { |r| r['event'] == 'validation-failed' }
      expect(validation_record['failing_rule']).to eq('[REDACTED:credential-pattern-match]')
      expect(validation_record['decomposition_message']).to eq('[REDACTED:credential-pattern-match]')

      redaction_records = captured_records.select { |r| r['event'] == 'credential-pattern-redacted' }
      expect(redaction_records.map { |r| r['field'] }).to contain_exactly(
        'failing_rule', 'decomposition_message'
      )
    end
  end
end
