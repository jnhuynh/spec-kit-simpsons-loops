# frozen_string_literal: true

require 'phaser'

# Specs for Phaser::ForbiddenOperationsGate — the FR-049 pre-classification
# gate that rejects any commit whose diff matches an entry in the active
# flavor's forbidden-operations registry (feature
# 007-multi-phase-pipeline; T022/T031, FR-015, FR-041, FR-042, FR-049,
# D-016, SC-005, SC-008, SC-015).
#
# Contract per quickstart.md "Pattern: Pre-Classification Gate
# Discipline":
#
#   def process_commit(commit, flavor)
#     return :skip if commit.diff.empty?                              # FR-009
#     forbidden = flavor.forbidden_operations_gate.evaluate(commit)
#     raise ForbiddenOperationError.new(commit, forbidden) if forbidden
#     classifier.classify(commit, flavor)                              # FR-004
#   end
#
# The gate runs BEFORE the classifier — no operator-supplied type tag,
# inference rule, or default-type cascade is consulted when a forbidden
# operation is detected. The classifier is never invoked when the gate
# rejects a commit (D-016 "no bypass").
#
# Surface (T031):
#
#   * `Phaser::ForbiddenOperationsGate.new(forbidden_operations:,
#     forbidden_module: nil)` — constructed once per engine run; the
#     `forbidden_operations` argument is the validated list straight off
#     `Phaser::Flavor#forbidden_operations` (raw Hashes with string keys
#     per data-model.md "ForbiddenOperation" and
#     contracts/flavor.schema.yaml).
#
#   * `#evaluate(commit)` — returns the matching forbidden-operation
#     Hash (the registry entry whose `detector` matched the commit's
#     diff) or nil when no entry matched. The engine wraps a non-nil
#     return in `Phaser::ForbiddenOperationError` and persists the
#     payload to `<FEATURE_DIR>/phase-creation-status.yaml` via
#     `Phaser::StatusWriter` per FR-042.
#
#   * `Phaser::ForbiddenOperationError` — exception raised by the engine
#     (NOT by the gate itself; the gate is a pure decision function).
#     Carries the offending commit hash, the detector's `name`
#     (canonical `failing_rule` for the validation-failed ERROR record
#     per FR-041), the detector's `identifier` (canonical
#     `forbidden_operation` field per FR-041), and the detector's
#     `decomposition_message` (canonical operator-facing message per
#     FR-015 / FR-041 listing the safe replacement task sequence).
#
# Bypass-surface contract per D-016 (SC-015):
#
#   * The gate MUST evaluate every commit's diff content regardless of
#     any operator-supplied trailer (including `Phase-Type`, which
#     governs ONLY classification candidate selection per FR-004 and
#     FR-016).
#   * The gate MUST NOT consult environment variables.
#   * The gate's constructor MUST NOT accept a "skip" / "force" /
#     "allow" flag of any kind.
#   * The gate MUST NOT honor any commit-message trailer that names a
#     forbidden-operation rule for skipping.
#   * Detection MUST be solely a function of `(commit.diff, flavor's
#     forbidden_operations registry)`.
#
# Logging contract (FR-041, contracts/observability-events.md
# `validation-failed`):
#
#   * On rejection, the engine emits exactly one `validation-failed`
#     ERROR record with `failing_rule`, `forbidden_operation`,
#     `decomposition_message`, and `commit_hash` populated from the
#     matching registry entry. The same payload (minus the envelope
#     fields) is persisted to `phase-creation-status.yaml` via
#     `StatusWriter#write(stage: :phaser_engine, ...)` per FR-042 / D-012.
#   * The exception object exposes the four payload fields directly so
#     the engine can hand them to `Observability#log_validation_failed`
#     and `StatusWriter#write` without re-deriving them.
RSpec.describe Phaser::ForbiddenOperationsGate do # rubocop:disable RSpec/SpecFilePathFormat
  # Build a FileChange whose path/hunks the spec example controls. The
  # default file is a benign Ruby model so specs that need to assert
  # "no match" can omit the `file:` argument entirely.
  def build_file_change(file)
    Phaser::FileChange.new(
      path: file.fetch(:path, 'app/models/user.rb'),
      change_kind: file.fetch(:change_kind, :modified),
      hunks: file.fetch(:hunks, ["@@ -1 +1 @@\n-old\n+new\n"])
    )
  end

  # Build a Commit value object with a single FileChange. Trailers
  # default to empty so the bypass-surface specs can explicitly install
  # `Phase-Type` (and other) trailers and assert they have no effect.
  def build_commit(hash: 'a' * 40, subject: 'Some commit', trailers: {}, file: {})
    Phaser::Commit.new(
      hash: hash,
      subject: subject,
      message_trailers: trailers,
      diff: Phaser::Diff.new(files: [build_file_change(file)]),
      author_timestamp: '2026-04-25T00:00:00Z'
    )
  end

  # The canonical registry entry shape (string keys, mirroring the
  # validated catalog Hash that flows out of `FlavorLoader` per
  # data-model.md "ForbiddenOperation"). The `detector` Hash matches the
  # `Match` definition in contracts/flavor.schema.yaml.
  def file_glob_forbidden(name:, identifier:, pattern:, decomposition_message:)
    {
      'name' => name,
      'identifier' => identifier,
      'detector' => { 'kind' => 'file_glob', 'pattern' => pattern },
      'decomposition_message' => decomposition_message
    }
  end

  def path_regex_forbidden(name:, identifier:, pattern:, decomposition_message:)
    {
      'name' => name,
      'identifier' => identifier,
      'detector' => { 'kind' => 'path_regex', 'pattern' => pattern },
      'decomposition_message' => decomposition_message
    }
  end

  def content_regex_forbidden(name:, identifier:, path_glob:, pattern:, decomposition_message:)
    {
      'name' => name,
      'identifier' => identifier,
      'detector' => {
        'kind' => 'content_regex',
        'path_glob' => path_glob,
        'pattern' => pattern
      },
      'decomposition_message' => decomposition_message
    }
  end

  def module_method_forbidden(name:, identifier:, method:, decomposition_message:)
    {
      'name' => name,
      'identifier' => identifier,
      'detector' => { 'kind' => 'module_method', 'method' => method },
      'decomposition_message' => decomposition_message
    }
  end

  let(:direct_rename_entry) do
    file_glob_forbidden(
      name: 'direct-column-rename',
      identifier: 'direct-column-rename',
      pattern: 'db/forbidden/*.rb',
      decomposition_message:
        'Decompose the direct rename into: add nullable column, dual-write, ' \
        'backfill, switch reads, drop old column.'
    )
  end

  describe '#evaluate — detection contract' do
    subject(:gate) { described_class.new(forbidden_operations: [direct_rename_entry]) }

    # Shared hunk text used by the two content_regex examples below.
    # Extracted to keep each example body within rubocop's line length.
    let(:volatile_default_hunk) do
      "@@ -0,0 +1 @@\n+add_column :users, :seen_at, :datetime, " \
        "default: -> { Time.current }\n"
    end

    let(:rename_detector_module) do
      Module.new do
        module_function

        def detects_rename?(commit)
          commit.diff.files.any? { |f| f.hunks.any? { |h| h.include?('rename_column') } }
        end
      end
    end

    let(:ast_rename_entry) do
      module_method_forbidden(
        name: 'ast-detected-rename',
        identifier: 'ast-detected-rename',
        method: :detects_rename?,
        decomposition_message: 'Decompose into add + dual-write + backfill + switch + drop.'
      )
    end

    it 'returns nil when no registry entry matches the commit diff' do
      commit = build_commit(file: { path: 'app/models/user.rb' })

      expect(gate.evaluate(commit)).to be_nil
    end

    it 'returns the matching registry entry when the file_glob detector matches' do
      commit = build_commit(file: { path: 'db/forbidden/202604250001_rename.rb' })

      expect(gate.evaluate(commit)).to eq(direct_rename_entry)
    end

    it 'returns nil for an empty registry regardless of diff content' do
      empty_gate = described_class.new(forbidden_operations: [])
      commit = build_commit(file: { path: 'db/forbidden/202604250001_rename.rb' })

      expect(empty_gate.evaluate(commit)).to be_nil
    end

    it 'evaluates path_regex detectors against the file paths in the diff' do
      regex_entry = path_regex_forbidden(
        name: 'non-concurrent-index',
        identifier: 'non-concurrent-index',
        pattern: '\\Adb/migrate/.*_non_concurrent_index\\.rb\\z',
        decomposition_message:
          'Replace add_index with add_index ..., algorithm: :concurrently in a ' \
          'migration that runs disable_ddl_transaction!.'
      )
      regex_gate = described_class.new(forbidden_operations: [regex_entry])
      commit = build_commit(file: { path: 'db/migrate/202604250002_non_concurrent_index.rb' })

      expect(regex_gate.evaluate(commit)).to eq(regex_entry)
    end

    it 'evaluates content_regex detectors against hunks of files matching path_glob' do
      content_entry = content_regex_forbidden(
        name: 'volatile-default',
        identifier: 'add-column-with-volatile-default',
        path_glob: 'db/migrate/*.rb',
        pattern: 'default:\\s*->\\s*\\{\\s*Time',
        decomposition_message:
          'Add the column without a default, backfill in batches, then add the ' \
          'default in a follow-up migration.'
      )
      content_gate = described_class.new(forbidden_operations: [content_entry])
      commit = build_commit(file: {
                              path: 'db/migrate/202604250003_add_column.rb',
                              hunks: [volatile_default_hunk]
                            })

      expect(content_gate.evaluate(commit)).to eq(content_entry)
    end

    it 'returns nil when content_regex pattern matches but no file matches the path_glob' do
      content_entry = content_regex_forbidden(
        name: 'volatile-default',
        identifier: 'add-column-with-volatile-default',
        path_glob: 'db/migrate/*.rb',
        pattern: 'default:\\s*->\\s*\\{\\s*Time',
        decomposition_message: 'Decompose ...'
      )
      content_gate = described_class.new(forbidden_operations: [content_entry])
      commit = build_commit(file: {
                              path: 'app/models/user.rb',
                              hunks: [volatile_default_hunk]
                            })

      expect(content_gate.evaluate(commit)).to be_nil
    end

    it 'returns the FIRST matching entry in registry order when multiple entries match' do
      # The registry's ordering inside `flavor.yaml` IS authoritative —
      # flavors are expected to declare the most-specific detector first.
      # Determinism (FR-002, SC-002) requires a stable selection rule; we
      # pin first-match-wins so the chosen entry's `name`, `identifier`,
      # and `decomposition_message` are reproducible across runs.
      first_entry = file_glob_forbidden(
        name: 'first-match', identifier: 'first',
        pattern: 'db/forbidden/*.rb',
        decomposition_message: 'first decomposition'
      )
      second_entry = file_glob_forbidden(
        name: 'second-match', identifier: 'second',
        pattern: 'db/forbidden/202604250001_rename.rb',
        decomposition_message: 'second decomposition'
      )
      ordered_gate = described_class.new(forbidden_operations: [first_entry, second_entry])
      commit = build_commit(file: { path: 'db/forbidden/202604250001_rename.rb' })

      expect(ordered_gate.evaluate(commit)).to eq(first_entry)
    end

    it 'evaluates module_method detectors via the configured forbidden_module' do
      module_gate = described_class.new(
        forbidden_operations: [ast_rename_entry],
        forbidden_module: rename_detector_module
      )
      commit = build_commit(file: {
                              path: 'db/migrate/202604250004_rename.rb',
                              hunks: ["@@ -0,0 +1 @@\n+rename_column :users, :email, :email_address\n"]
                            })

      expect(module_gate.evaluate(commit)).to eq(ast_rename_entry)
    end

    it 'raises a descriptive error when a module_method detector references an undeclared module' do
      module_entry = module_method_forbidden(
        name: 'ast-detected-rename', identifier: 'ast-detected-rename',
        method: :detects_rename?, decomposition_message: '...'
      )
      gate_without_module = described_class.new(forbidden_operations: [module_entry])
      commit = build_commit(file: { path: 'db/migrate/202604250004_rename.rb' })

      expect { gate_without_module.evaluate(commit) }
        .to raise_error(Phaser::ForbiddenOperationsConfigurationError, /forbidden_module/)
    end

    it 'raises a descriptive error when a module_method detector references a missing method' do
      module_entry = module_method_forbidden(
        name: 'ast-detected-rename', identifier: 'ast-detected-rename',
        method: :missing_method, decomposition_message: '...'
      )
      forbidden_module = Module.new
      gate = described_class.new(
        forbidden_operations: [module_entry],
        forbidden_module: forbidden_module
      )
      commit = build_commit(file: { path: 'db/migrate/202604250004_rename.rb' })

      expect { gate.evaluate(commit) }
        .to raise_error(Phaser::ForbiddenOperationsConfigurationError, /missing_method/)
    end
  end

  describe 'pre-classification ordering (FR-049, quickstart.md gate discipline)' do
    let(:gate) { described_class.new(forbidden_operations: [direct_rename_entry]) }

    it 'detects forbidden operations regardless of whether the commit carries an operator tag' do
      # SC-015: an operator tag that names a valid task type MUST NOT
      # suppress the gate. The gate is the FIRST thing the engine does
      # for a non-empty commit (after FR-009's empty-diff filter); the
      # classifier (which is the only consumer of `Phase-Type`) is not
      # invoked when the gate matches. We assert the gate matches the
      # commit even when `Phase-Type` names a valid type, AND when it
      # names the forbidden detector itself.
      tagged_with_valid_type = build_commit(
        file: { path: 'db/forbidden/202604250001_rename.rb' },
        trailers: { 'Phase-Type' => 'schema add-nullable-column' }
      )
      tagged_with_detector_name = build_commit(
        file: { path: 'db/forbidden/202604250001_rename.rb' },
        trailers: { 'Phase-Type' => 'direct-column-rename' }
      )

      expect(gate.evaluate(tagged_with_valid_type)).to eq(direct_rename_entry)
      expect(gate.evaluate(tagged_with_detector_name)).to eq(direct_rename_entry)
    end

    # D-016: the gate's contract is "diff content only". No trailer
    # name — plausible or implausible — may suppress detection. We
    # parameterize over a constellation of plausible bypass trailer
    # names rather than testing each in its own example so the matrix
    # of forbidden trailer names lives in one obvious place.
    [
      { 'Phaser-Skip-Forbidden' => 'true' },
      { 'Phaser-Force' => 'true' },
      { 'Phaser-Allow' => 'direct-column-rename' },
      { 'Phaser-Override' => 'direct-column-rename' },
      { 'Skip-Gate' => 'yes' }
    ].each do |trailers|
      it "ignores the #{trailers.keys.first.inspect} trailer when scanning the diff (D-016)" do
        commit = build_commit(
          file: { path: 'db/forbidden/202604250001_rename.rb' },
          trailers: trailers
        )

        expect(gate.evaluate(commit)).to eq(direct_rename_entry)
      end
    end

    it 'does not consult environment variables to decide whether to evaluate (D-016)' do
      # Environment-variable bypasses are out-of-band by definition; we
      # set a constellation of plausible names with permissive values
      # and confirm the gate's decision is unchanged.
      bypass_env = {
        'PHASER_SKIP_FORBIDDEN' => '1',
        'PHASER_FORCE' => '1',
        'PHASER_ALLOW_FORBIDDEN' => 'direct-column-rename',
        'PHASER_BYPASS_GATE' => 'true',
        'SKIP_GATE' => '1'
      }
      commit = build_commit(file: { path: 'db/forbidden/202604250001_rename.rb' })

      original_env = bypass_env.keys.to_h { |k| [k, ENV.fetch(k, nil)] }
      begin
        bypass_env.each { |k, v| ENV[k] = v }

        expect(gate.evaluate(commit)).to eq(direct_rename_entry)
      ensure
        original_env.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
      end
    end

    it 'exposes no constructor option that would skip, force, or allow detection (D-016)' do
      # The constructor's keyword surface is the bypass surface that
      # matters most: if a `skip:` / `force:` / `allow:` keyword existed,
      # an operator could plausibly find a way to set it from the
      # command line. We assert the surface contains exactly the two
      # documented keywords (`forbidden_operations:` required,
      # `forbidden_module:` optional).
      keyword_params = described_class.instance_method(:initialize).parameters
                                      .slice(:key, :keyreq)
                                      .map { |_, name| name }

      expect(keyword_params).to contain_exactly(:forbidden_operations, :forbidden_module)
      forbidden_keywords = %i[skip force allow bypass override]
      expect(keyword_params & forbidden_keywords).to be_empty
    end
  end

  describe 'Phaser::ForbiddenOperationError — payload contract (FR-041, FR-042)' do
    it 'is raisable with the offending commit and the matching registry entry' do
      commit = build_commit(hash: 'b' * 40, file: { path: 'db/forbidden/x.rb' })

      error = Phaser::ForbiddenOperationError.new(commit: commit, entry: direct_rename_entry)

      expect(error).to be_a(Phaser::ForbiddenOperationError)
    end

    it 'exposes commit_hash for the validation-failed ERROR record (FR-041)' do
      commit = build_commit(hash: 'c' * 40, file: { path: 'db/forbidden/x.rb' })

      error = Phaser::ForbiddenOperationError.new(commit: commit, entry: direct_rename_entry)

      expect(error.commit_hash).to eq('c' * 40)
    end

    it 'exposes failing_rule populated from the registry entry name (FR-041)' do
      commit = build_commit(file: { path: 'db/forbidden/x.rb' })

      error = Phaser::ForbiddenOperationError.new(commit: commit, entry: direct_rename_entry)

      # data-model.md "Error Conditions" table: `failing_rule` =
      # `<detector-name>` for forbidden-operation rejections; the
      # registry entry's `name` IS the detector name (per
      # contracts/flavor.schema.yaml ForbiddenOperation.name).
      expect(error.failing_rule).to eq('direct-column-rename')
    end

    it 'exposes forbidden_operation populated from the registry entry identifier (FR-041)' do
      commit = build_commit(file: { path: 'db/forbidden/x.rb' })

      error = Phaser::ForbiddenOperationError.new(commit: commit, entry: direct_rename_entry)

      expect(error.forbidden_operation).to eq('direct-column-rename')
    end

    it 'exposes the canonical decomposition_message verbatim from the registry entry (FR-015)' do
      commit = build_commit(file: { path: 'db/forbidden/x.rb' })

      error = Phaser::ForbiddenOperationError.new(commit: commit, entry: direct_rename_entry)

      expect(error.decomposition_message).to eq(direct_rename_entry['decomposition_message'])
    end

    it 'descends from Phaser::ValidationError so the engine can rescue uniformly' do
      expect(Phaser::ForbiddenOperationError).to be < Phaser::ValidationError
    end

    it 'declares Phaser::ValidationError as the rescuable ancestor under StandardError' do
      expect(Phaser::ValidationError).to be < StandardError
    end

    it 'serializes to the validation-failed ERROR payload shape per FR-041' do
      # The engine relays the four payload fields to
      # `Observability#log_validation_failed` (FR-041) and to
      # `StatusWriter#write` (FR-042). The error object exposes
      # `to_validation_failed_payload` so the engine does not have to
      # know the registry entry's internal layout.
      commit = build_commit(hash: 'd' * 40, file: { path: 'db/forbidden/x.rb' })

      error = Phaser::ForbiddenOperationError.new(commit: commit, entry: direct_rename_entry)

      expect(error.to_validation_failed_payload).to eq(
        commit_hash: 'd' * 40,
        failing_rule: 'direct-column-rename',
        forbidden_operation: 'direct-column-rename',
        decomposition_message: direct_rename_entry['decomposition_message']
      )
    end
  end

  describe 'status-file payload integration (FR-042, D-012)' do
    it 'produces a payload the StatusWriter can persist with stage: phaser-engine' do
      # FR-042 + data-model.md "PhaseCreationStatus": on engine
      # rejection, the SAME payload (minus the validation-failed
      # envelope) is persisted to phase-creation-status.yaml with the
      # `stage: phaser-engine` discriminator. We assert the
      # payload-producing helper returns a Hash whose keys are exactly
      # the optional fields the schema permits for a forbidden-operation
      # failure (commit_hash, failing_rule, forbidden_operation,
      # decomposition_message) — so when StatusWriter#write merges in
      # `stage:` / `timestamp:`, the result conforms to
      # contracts/phase-creation-status.schema.yaml.
      commit = build_commit(hash: 'e' * 40, file: { path: 'db/forbidden/x.rb' })

      error = Phaser::ForbiddenOperationError.new(commit: commit, entry: direct_rename_entry)
      payload = error.to_validation_failed_payload

      expect(payload.keys).to contain_exactly(
        :commit_hash,
        :failing_rule,
        :forbidden_operation,
        :decomposition_message
      )
    end

    it 'omits fields the forbidden-operation mode does not populate (commit_count etc.)' do
      commit = build_commit(file: { path: 'db/forbidden/x.rb' })

      error = Phaser::ForbiddenOperationError.new(commit: commit, entry: direct_rename_entry)
      payload = error.to_validation_failed_payload

      # The schema permits these keys for OTHER failure modes
      # (`feature-too-large` populates commit_count / phase_count;
      # precedent-rule violations populate missing_precedent). The
      # forbidden-operation rejection path MUST NOT emit them so the
      # operator-facing record is precise about which rule fired.
      expect(payload).not_to include(:commit_count, :phase_count, :missing_precedent)
    end
  end
end
