# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'stringio'
require 'tmpdir'
require 'yaml'
require 'phaser'

# Specs for Phaser::Engine#process — the orchestration layer that wires
# the empty-diff filter (FR-009), the forbidden-operations gate (FR-049),
# the classifier (FR-004), the precedent validator (FR-006), the size
# guard (FR-048), and the isolation resolver (FR-005) into a single
# pipeline that produces a deterministic Phaser::PhaseManifest and writes
# `<feature_dir>/phase-manifest.yaml` via Phaser::ManifestWriter (feature
# 007-multi-phase-pipeline; T026/T035, FR-002, FR-009, FR-038, FR-041,
# FR-042, FR-043, FR-049, SC-002, SC-008, SC-011, SC-014).
#
# Position of this spec in the engine pipeline (per quickstart.md
# "Pattern: Pre-Classification Gate Discipline" and T035 in tasks.md):
#
#   Phaser::Engine#process(feature_branch_commits, flavor)
#     for each commit in feature_branch_commits:
#       empty-diff filter (FR-009)              — skip + WARN
#         → forbidden-operations gate (FR-049)  — raise + ERROR + status
#         → classifier (FR-004)                 — INFO commit-classified
#     precedent validator (FR-006)              — raise + ERROR + status
#     size guard (FR-048)                       — raise + ERROR + status
#     isolation resolver (FR-005)               — INFO phase-emitted
#     manifest writer (FR-002, FR-038)          — writes YAML + returns path
#
# Engine surface (T035):
#
#   * `Phaser::Engine.new(feature_dir:, feature_branch:, default_branch:,
#     observability:, status_writer:, manifest_writer:, clock:,
#     classifier: nil, forbidden_operations_gate: nil,
#     precedent_validator: nil, size_guard: nil, isolation_resolver: nil)`
#     — the engine is constructed once per run. The required keyword
#     arguments cover the per-run identity and the IO surface
#     (feature_dir, feature_branch, default_branch, observability,
#     status_writer, manifest_writer, clock). The optional keyword
#     arguments inject the collaborators so the tests below can pass in
#     real instances without re-declaring the engine's wiring; production
#     callers (the `bin/phaser` CLI in T036) accept the defaults so the
#     engine knows how to construct each collaborator from the validated
#     flavor.
#
#   * `#process(commits, flavor)` — the single public entry point. On
#     success returns the absolute path to the written manifest (the same
#     value the `bin/phaser` CLI emits on stdout per
#     `contracts/phaser-cli.md`). On any validation failure raises a
#     subclass of `Phaser::ValidationError` AFTER persisting the failure
#     payload to `<feature_dir>/phase-creation-status.yaml` via
#     `StatusWriter#write(stage: 'phaser-engine', ...)` per FR-042 and
#     emitting the matching `validation-failed` ERROR record on stderr
#     per FR-041. The CLI maps the raised exception to exit code 1 per
#     `contracts/phaser-cli.md`.
#
# Determinism contract (FR-002, SC-002):
#
#   * The engine MUST be a pure function of `(commits, flavor,
#     feature_branch, default_branch, clock)`. The clock is injected so
#     `generated_at` is reproducible; the manifest writer's stable-key
#     ordering takes care of YAML-side determinism. Two operators
#     running the same flavor on the same commits MUST see byte-identical
#     manifests.
#
# Logging contract (FR-041, FR-043, SC-011,
# contracts/observability-events.md):
#
#   * One `commit-classified` INFO record per non-empty commit (after the
#     classifier returns).
#   * One `commit-skipped-empty-diff` WARN record per empty commit.
#   * One `phase-emitted` INFO record per phase as the manifest is
#     assembled.
#   * Exactly one `validation-failed` ERROR record on validation failure
#     (forbidden-operation, precedent, feature-too-large,
#     unknown-type-tag).
#   * stdout is reserved for the manifest path on success per FR-043;
#     the engine's IO surface for stderr is the injected Observability
#     instance and for stdout is exclusively the CLI (this spec verifies
#     the engine itself never touches `$stdout`).
#
# Status-file contract (FR-042, D-012):
#
#   * On any validation failure the engine writes the same payload it
#     emitted to the `validation-failed` ERROR record (minus the
#     envelope) to `<feature_dir>/phase-creation-status.yaml` via the
#     injected StatusWriter with `stage: 'phaser-engine'`.
#   * On success the engine deletes any pre-existing
#     `<feature_dir>/phase-creation-status.yaml` so a successful re-run
#     clears the prior failure status (FR-040 read-through to the engine
#     side; the same convention covers the stacked-PR creator).
RSpec.describe Phaser::Engine do # rubocop:disable RSpec/SpecFilePathFormat
  # The engine writes manifest + status files into `feature_dir`. Each
  # example operates inside a fresh temp directory so writes are
  # isolated and the `around` hook reliably tears down. The same
  # directory acts as the source of truth for assertions about
  # `phase-manifest.yaml` and `phase-creation-status.yaml` after the
  # engine exits.
  attr_reader :feature_dir

  around do |example|
    Dir.mktmpdir('phaser-engine-spec') do |tmp|
      @feature_dir = tmp
      example.run
    end
  end

  # Pinned clock so `generated_at` is reproducible for byte-identical
  # determinism assertions (SC-002). The clock is a zero-arg callable
  # mirroring the convention used by Observability and StatusWriter.
  let(:fixed_clock) { -> { '2026-04-25T12:00:00.000Z' } }

  # StringIO collects every stderr byte so spec examples can parse the
  # JSON-line records the engine emitted. The engine MUST NOT touch
  # `$stderr` directly — every emission flows through the injected
  # Observability — so this StringIO is the complete record of what the
  # engine logged.
  let(:stderr_io) { StringIO.new }

  let(:engine) { build_engine }

  # Helpers to keep example bodies readable. Each helper builds one
  # value-object input the engine consumes; specs compose the exact
  # commit list they want to test against rather than going through
  # `git log` parsing (which is the CLI's responsibility per T036, not
  # the engine's).
  def file_change(path:, hunks: ["@@ -1 +1 @@\n-old\n+new\n"], change_kind: :modified)
    Phaser::FileChange.new(path: path, change_kind: change_kind, hunks: hunks)
  end

  def commit(hash:, subject: 'Some commit', trailers: {}, files: nil)
    file_changes = files || [file_change(path: 'app/models/user.rb')]
    Phaser::Commit.new(
      hash: hash,
      subject: subject,
      message_trailers: trailers,
      diff: Phaser::Diff.new(files: file_changes),
      author_timestamp: '2026-04-25T00:00:00Z'
    )
  end

  def empty_commit(hash:, subject: 'Merge branch')
    Phaser::Commit.new(
      hash: hash,
      subject: subject,
      message_trailers: {},
      diff: Phaser::Diff.new(files: []),
      author_timestamp: '2026-04-25T00:00:00Z'
    )
  end

  # Build a default engine pointed at the per-example feature_dir with a
  # fresh observability/status_writer/manifest_writer wired in. Specs
  # that need a different feature_dir or clock construct their own
  # engine via this builder so the wiring stays consistent.
  def build_engine(feature_dir_override: nil, stderr: stderr_io, clock: fixed_clock)
    described_class.new(
      feature_dir: feature_dir_override || feature_dir,
      feature_branch: 'feature-007-multi-phase-pipeline',
      default_branch: 'main',
      observability: Phaser::Observability.new(stderr: stderr, now: clock),
      status_writer: Phaser::StatusWriter.new(now: clock),
      manifest_writer: Phaser::ManifestWriter.new,
      clock: clock
    )
  end

  # Build a minimal flavor with two task types, one inference rule
  # mapping `db/migrate/*.rb` to the `:alone`-isolation `schema` type,
  # plus optional precedent rules and forbidden-operations entries the
  # caller supplies. The options-hash signature keeps the parameter
  # count within the rubocop ParameterLists budget while still letting
  # each spec example pass exactly the catalog it needs.
  def build_flavor(**options)
    Phaser::Flavor.new(
      name: options.fetch(:name, 'engine-spec'),
      version: options.fetch(:version, '0.1.0'),
      default_type: options.fetch(:default_type, 'misc'),
      task_types: options.fetch(:task_types, default_task_types),
      precedent_rules: options.fetch(:precedent_rules, []),
      inference_rules: options.fetch(:inference_rules, default_inference_rules),
      forbidden_operations: options.fetch(:forbidden_operations, []),
      stack_detection: Phaser::FlavorStackDetection.new(signals: [])
    )
  end

  def default_task_types
    [
      Phaser::FlavorTaskType.new(name: 'schema', isolation: :alone,
                                 description: 'Schema change.'),
      Phaser::FlavorTaskType.new(name: 'misc', isolation: :groups,
                                 description: 'Catch-all groups type.')
    ]
  end

  def default_inference_rules
    [
      Phaser::FlavorInferenceRule.new(
        name: 'schema-by-path', precedence: 100, task_type: 'schema',
        match: { 'kind' => 'file_glob', 'pattern' => 'db/migrate/*.rb' }
      )
    ]
  end

  # Convenience: read every JSON-line record the engine emitted to
  # stderr in the order they were emitted. Each entry is a Ruby Hash with
  # string keys (matching the contracts/observability-events.md schema).
  def emitted_records
    stderr_io.string.each_line.map { |line| JSON.parse(line) }
  end

  def manifest_path
    File.join(feature_dir, 'phase-manifest.yaml')
  end

  def status_path
    File.join(feature_dir, 'phase-creation-status.yaml')
  end

  describe '#process — successful run with one schema commit' do
    let(:flavor) { build_flavor }
    let(:schema_commit) do
      commit(hash: 'a' * 40,
             subject: 'Add nullable email_address column',
             files: [file_change(path: 'db/migrate/202604250001_add_email.rb')])
    end

    it 'returns the absolute path to the written manifest' do
      expect(engine.process([schema_commit], flavor)).to eq(manifest_path)
    end

    it 'writes the manifest at <feature_dir>/phase-manifest.yaml' do
      engine.process([schema_commit], flavor)
      expect(File.file?(manifest_path)).to be(true)
    end

    it 'records the active flavor name on the manifest (FR-021)' do
      engine.process([schema_commit], flavor)
      expect(YAML.load_file(manifest_path)['flavor_name']).to eq('engine-spec')
    end

    it 'records the active flavor version on the manifest (FR-021, FR-035)' do
      engine.process([schema_commit], flavor)
      expect(YAML.load_file(manifest_path)['flavor_version']).to eq('0.1.0')
    end

    it 'records the feature branch the engine ran against on the manifest (FR-021)' do
      engine.process([schema_commit], flavor)
      expect(YAML.load_file(manifest_path)['feature_branch'])
        .to eq('feature-007-multi-phase-pipeline')
    end

    it 'records the injected clock value as generated_at (FR-021, SC-002)' do
      engine.process([schema_commit], flavor)
      expect(YAML.load_file(manifest_path)['generated_at'])
        .to eq('2026-04-25T12:00:00.000Z')
    end

    it 'emits one phase containing the single classified commit' do
      engine.process([schema_commit], flavor)
      manifest = YAML.load_file(manifest_path)
      expect(manifest['phases'].length).to eq(1)
      expect(manifest['phases'].first['tasks'].length).to eq(1)
      expect(manifest['phases'].first['tasks'].first['commit_hash']).to eq('a' * 40)
    end

    it 'numbers the single phase as 1 (1-indexed per data-model.md)' do
      engine.process([schema_commit], flavor)
      expect(YAML.load_file(manifest_path)['phases'].first['number']).to eq(1)
    end

    it 'derives the phase branch_name from the feature branch and phase number (FR-026)' do
      engine.process([schema_commit], flavor)
      expect(YAML.load_file(manifest_path)['phases'].first['branch_name'])
        .to eq('feature-007-multi-phase-pipeline-phase-1')
    end

    it 'sets phase 1 base_branch to the engine default_branch (FR-026)' do
      engine.process([schema_commit], flavor)
      expect(YAML.load_file(manifest_path)['phases'].first['base_branch']).to eq('main')
    end

    it 'assigns the inferred task type onto the manifest task entry' do
      engine.process([schema_commit], flavor)
      expect(YAML.load_file(manifest_path)['phases'].first['tasks'].first['task_type'])
        .to eq('schema')
    end

    it 'mirrors the source commit subject onto the manifest task entry' do
      engine.process([schema_commit], flavor)
      expect(YAML.load_file(manifest_path)['phases'].first['tasks'].first['commit_subject'])
        .to eq('Add nullable email_address column')
    end
  end

  describe '#process — observability emissions (FR-041, SC-011)' do
    let(:flavor) { build_flavor }
    let(:two_commits) do
      [
        commit(hash: 'a' * 40,
               files: [file_change(path: 'db/migrate/202604250001_add_email.rb')]),
        commit(hash: 'b' * 40, files: [file_change(path: 'app/models/user.rb')])
      ]
    end

    it 'emits one commit-classified INFO record per non-empty commit' do
      engine.process(two_commits, flavor)
      classified = emitted_records.select { |r| r['event'] == 'commit-classified' }
      expect(classified.length).to eq(2)
    end

    it 'attributes each commit-classified record to the correct commit and task type' do
      engine.process(two_commits, flavor)
      classified = emitted_records.select { |r| r['event'] == 'commit-classified' }
      expect(classified.map { |r| [r['commit_hash'], r['task_type']] }).to eq([
                                                                                ['a' * 40, 'schema'],
                                                                                ['b' * 40, 'misc']
                                                                              ])
    end

    it 'emits one phase-emitted INFO record per resolved phase' do
      engine.process(two_commits, flavor)
      phase_records = emitted_records.select { |r| r['event'] == 'phase-emitted' }
      # Two phases: schema (alone) + misc (groups, alone in this set).
      expect(phase_records.length).to eq(2)
    end

    it 'emits phase-emitted records with phase_number, branch_name, base_branch, tasks' do
      engine.process(
        [commit(hash: 'a' * 40,
                files: [file_change(path: 'db/migrate/202604250001_add_email.rb')])],
        flavor
      )

      record = emitted_records.find { |r| r['event'] == 'phase-emitted' }
      expect(record).to include(
        'phase_number' => 1,
        'branch_name' => 'feature-007-multi-phase-pipeline-phase-1',
        'base_branch' => 'main'
      )
      expect(record['tasks']).to eq([{ 'commit_hash' => 'a' * 40, 'task_type' => 'schema' }])
    end

    it 'emits one commit-skipped-empty-diff WARN record per empty-diff commit (FR-009)' do
      engine.process(
        [
          empty_commit(hash: 'e' * 40),
          commit(hash: 'a' * 40,
                 files: [file_change(path: 'db/migrate/202604250001_add_email.rb')])
        ],
        flavor
      )

      skipped = emitted_records.select { |r| r['event'] == 'commit-skipped-empty-diff' }
      expect(skipped.length).to eq(1)
      expect(skipped.first['commit_hash']).to eq('e' * 40)
    end

    it 'never writes a non-classified record to stderr on a clean run' do
      engine.process(
        [commit(hash: 'a' * 40,
                files: [file_change(path: 'db/migrate/202604250001_add_email.rb')])],
        flavor
      )

      expect(emitted_records.select { |r| r['event'] == 'validation-failed' }).to be_empty
    end

    it 'every emitted record carries the common envelope (level, timestamp, event)' do
      engine.process(
        [commit(hash: 'a' * 40,
                files: [file_change(path: 'db/migrate/202604250001_add_email.rb')])],
        flavor
      )

      emitted_records.each do |record|
        expect(record.keys).to include('level', 'timestamp', 'event')
        expect(record['timestamp']).to eq('2026-04-25T12:00:00.000Z')
      end
    end
  end

  describe '#process — empty-diff filter (FR-009)' do
    let(:flavor) { build_flavor }
    let(:mixed_commits) do
      [
        empty_commit(hash: 'e' * 40),
        commit(hash: 'a' * 40,
               files: [file_change(path: 'db/migrate/202604250001_add_email.rb')])
      ]
    end

    it 'skips empty-diff commits without including them in the manifest' do
      engine.process(mixed_commits, flavor)
      manifest = YAML.load_file(manifest_path)
      task_hashes = manifest['phases'].flat_map { |p| p['tasks'].map { |t| t['commit_hash'] } }
      expect(task_hashes).to eq(['a' * 40])
    end

    it 'never invokes the classifier on an empty-diff commit (no commit-classified record)' do
      engine.process(mixed_commits, flavor)
      classified = emitted_records.select { |r| r['event'] == 'commit-classified' }
      expect(classified.map { |r| r['commit_hash'] }).not_to include('e' * 40)
    end

    it 'returns a manifest path when every commit is non-empty' do
      result = engine.process(
        [commit(hash: 'a' * 40,
                files: [file_change(path: 'db/migrate/202604250001_add_email.rb')])],
        flavor
      )

      expect(result).to eq(manifest_path)
    end
  end

  describe '#process — pipeline ordering (quickstart.md gate discipline)' do
    # Forbidden-operations gate runs BEFORE the classifier (FR-049,
    # D-016, SC-015). A commit whose diff matches a forbidden-operation
    # detector AND carries an operator tag naming a valid task type
    # MUST be rejected by the gate; the classifier is never invoked.
    let(:flavor) { build_flavor(forbidden_operations: [direct_rename_entry]) }

    def direct_rename_entry
      {
        'name' => 'direct-column-rename',
        'identifier' => 'direct-column-rename',
        'detector' => { 'kind' => 'file_glob', 'pattern' => 'db/forbidden/*.rb' },
        'decomposition_message' => 'Decompose the direct rename into add+dual-write+backfill+switch+drop.'
      }
    end

    def build_forbidden_commit(trailers: {})
      commit(
        hash: 'f' * 40,
        trailers: trailers,
        files: [file_change(path: 'db/forbidden/202604250001_rename.rb')]
      )
    end

    it 'raises ForbiddenOperationError when a commit matches a forbidden detector' do
      expect { engine.process([build_forbidden_commit], flavor) }
        .to raise_error(Phaser::ForbiddenOperationError)
    end

    it 'rejects a forbidden-operation commit even when an operator tag names a valid type (SC-015)' do
      tagged_forbidden = build_forbidden_commit(trailers: { 'Phase-Type' => 'schema' })

      expect { engine.process([tagged_forbidden], flavor) }
        .to raise_error(Phaser::ForbiddenOperationError)
    end

    it 'never emits a commit-classified record for a forbidden-rejected commit' do
      begin
        engine.process([build_forbidden_commit], flavor)
      rescue Phaser::ForbiddenOperationError
        # expected
      end

      expect(emitted_records.select { |r| r['event'] == 'commit-classified' }).to be_empty
    end

    it 'writes no manifest on a forbidden-operation rejection' do
      begin
        engine.process([build_forbidden_commit], flavor)
      rescue Phaser::ForbiddenOperationError
        # expected
      end

      expect(File.exist?(manifest_path)).to be(false)
    end
  end

  describe '#process — validation failure: forbidden operation (FR-041, FR-042)' do
    let(:flavor) { build_flavor(forbidden_operations: [forbidden_entry]) }

    def forbidden_entry
      {
        'name' => 'direct-column-rename',
        'identifier' => 'direct-column-rename',
        'detector' => { 'kind' => 'file_glob', 'pattern' => 'db/forbidden/*.rb' },
        'decomposition_message' => 'Decompose the direct rename into add+dual-write+backfill+switch+drop.'
      }
    end

    def forbidden_commit
      commit(hash: 'f' * 40,
             files: [file_change(path: 'db/forbidden/202604250001_rename.rb')])
    end

    def attempt_process
      engine.process([forbidden_commit], flavor)
    rescue Phaser::ForbiddenOperationError
      # swallow to make the post-failure assertions readable
    end

    it 'emits exactly one validation-failed ERROR record on stderr (FR-041)' do
      attempt_process

      failures = emitted_records.select { |r| r['event'] == 'validation-failed' }
      expect(failures.length).to eq(1)
    end

    it 'populates failing_rule, forbidden_operation, decomposition_message, commit_hash on the ERROR record' do
      attempt_process

      record = emitted_records.find { |r| r['event'] == 'validation-failed' }
      expect(record).to include(
        'failing_rule' => 'direct-column-rename',
        'forbidden_operation' => 'direct-column-rename',
        'decomposition_message' => forbidden_entry['decomposition_message'],
        'commit_hash' => 'f' * 40
      )
    end

    it 'persists the same payload to phase-creation-status.yaml with stage: phaser-engine (FR-042)' do
      attempt_process

      expect(File.file?(status_path)).to be(true)
      status = YAML.load_file(status_path)
      expect(status).to include(
        'stage' => 'phaser-engine',
        'failing_rule' => 'direct-column-rename',
        'forbidden_operation' => 'direct-column-rename',
        'decomposition_message' => forbidden_entry['decomposition_message'],
        'commit_hash' => 'f' * 40
      )
    end
  end

  describe '#process — validation failure: precedent (FR-006, FR-041, FR-042)' do
    let(:flavor) do
      build_flavor(
        task_types: precedent_task_types,
        precedent_rules: [
          Phaser::FlavorPrecedentRule.new(
            name: 'drop-after-ignore',
            subject_type: 'drop-column',
            predecessor_type: 'ignore-column',
            error_message: 'drop-column requires a prior ignore-column'
          )
        ],
        inference_rules: []
      )
    end

    let(:drop_without_predecessor) do
      commit(hash: 'd' * 40, trailers: { 'Phase-Type' => 'drop-column' })
    end

    def precedent_task_types
      [
        Phaser::FlavorTaskType.new(name: 'ignore-column', isolation: :groups,
                                   description: 'Mark a column as ignored.'),
        Phaser::FlavorTaskType.new(name: 'drop-column', isolation: :alone,
                                   description: 'Drop a column.'),
        Phaser::FlavorTaskType.new(name: 'misc', isolation: :groups,
                                   description: 'Catch-all groups type.')
      ]
    end

    def attempt_process
      engine.process([drop_without_predecessor], flavor)
    rescue Phaser::PrecedentError
      # expected
    end

    it 'raises Phaser::PrecedentError when a subject lacks a predecessor' do
      expect { engine.process([drop_without_predecessor], flavor) }
        .to raise_error(Phaser::PrecedentError)
    end

    it 'emits exactly one validation-failed ERROR record naming the rule and missing precedent' do
      attempt_process

      record = emitted_records.find { |r| r['event'] == 'validation-failed' }
      expect(record).to include(
        'failing_rule' => 'drop-after-ignore',
        'missing_precedent' => 'ignore-column',
        'commit_hash' => 'd' * 40
      )
    end

    it 'persists the precedent failure payload to phase-creation-status.yaml with stage: phaser-engine' do
      attempt_process

      status = YAML.load_file(status_path)
      expect(status).to include(
        'stage' => 'phaser-engine',
        'failing_rule' => 'drop-after-ignore',
        'missing_precedent' => 'ignore-column',
        'commit_hash' => 'd' * 40
      )
    end

    it 'writes no manifest on a precedent failure' do
      attempt_process
      expect(File.exist?(manifest_path)).to be(false)
    end
  end

  describe '#process — validation failure: feature-too-large (FR-048, SC-014)' do
    let(:flavor) { build_flavor(inference_rules: []) }

    # 201 non-empty commits — minimal over-bound input. With the default
    # type set to `misc` (:groups isolation), 201 :groups commits project
    # to a single phase, so this isolates the COMMIT-bound rejection
    # from the phase-bound rejection covered by SizeGuard's own spec.
    let(:over_commit_bound) do
      (1..201).map do |i|
        commit(
          hash: format('%040x', i),
          files: [file_change(path: "app/models/user_#{i}.rb")]
        )
      end
    end

    def attempt_process
      engine.process(over_commit_bound, flavor)
    rescue Phaser::SizeBoundError
      # expected
    end

    it 'raises Phaser::SizeBoundError on >200 non-empty commits' do
      expect { engine.process(over_commit_bound, flavor) }
        .to raise_error(Phaser::SizeBoundError)
    end

    it 'emits the validation-failed ERROR record with feature-too-large + commit_count + phase_count' do
      attempt_process

      record = emitted_records.find { |r| r['event'] == 'validation-failed' }
      expect(record).to include(
        'failing_rule' => 'feature-too-large',
        'commit_count' => 201,
        'phase_count' => 1
      )
    end

    it 'omits commit_hash from the feature-too-large ERROR record (per validation-failed schema)' do
      attempt_process

      record = emitted_records.find { |r| r['event'] == 'validation-failed' }
      expect(record).not_to include('commit_hash')
    end

    it 'persists the feature-too-large payload to phase-creation-status.yaml with stage: phaser-engine' do
      attempt_process

      status = YAML.load_file(status_path)
      expect(status).to include(
        'stage' => 'phaser-engine',
        'failing_rule' => 'feature-too-large',
        'commit_count' => 201,
        'phase_count' => 1
      )
    end

    it 'writes no manifest on a feature-too-large rejection' do
      attempt_process
      expect(File.exist?(manifest_path)).to be(false)
    end
  end

  describe '#process — successful run clears prior status file (FR-040 read-through)' do
    let(:flavor) { build_flavor }

    it 'deletes any pre-existing phase-creation-status.yaml on success' do
      File.write(status_path, "stage: phaser-engine\nstale: true\n")

      engine.process(
        [commit(hash: 'a' * 40,
                files: [file_change(path: 'db/migrate/202604250001_add_email.rb')])],
        flavor
      )

      expect(File.exist?(status_path)).to be(false)
    end
  end

  describe '#process — determinism (FR-002, SC-002)' do
    let(:flavor) { build_flavor }
    let(:commits) do
      [
        commit(hash: 'a' * 40,
               subject: 'Add nullable email_address column',
               files: [file_change(path: 'db/migrate/202604250001_add_email.rb')]),
        commit(hash: 'b' * 40,
               subject: 'Update model logic',
               files: [file_change(path: 'app/models/user.rb')]),
        commit(hash: 'c' * 40,
               subject: 'Drop old column',
               files: [file_change(path: 'db/migrate/202604250002_drop_email.rb')])
      ]
    end

    it 'produces byte-identical manifest content across two consecutive runs (clock pinned)' do
      first_bytes = run_engine_and_capture_bytes(feature_dir)

      Dir.mktmpdir('phaser-engine-spec-second') do |second_dir|
        second_bytes = run_engine_and_capture_bytes(second_dir)
        expect(second_bytes).to eq(first_bytes)
      end
    end

    # Spawn a fresh engine pointed at the given feature_dir, run process
    # against the spec's commit list, and return the bytes of the
    # written manifest. Extracted so the example body itself stays
    # within the rubocop ExampleLength budget while the byte-identical
    # assertion is the single load-bearing line of the example.
    def run_engine_and_capture_bytes(target_dir)
      target_engine = build_engine(
        feature_dir_override: target_dir,
        stderr: StringIO.new
      )
      target_engine.process(commits, flavor)
      File.binread(File.join(target_dir, 'phase-manifest.yaml'))
    end
  end

  describe '#process — stdout/stderr separation (FR-043)' do
    let(:flavor) { build_flavor }

    it 'never writes to $stdout during a successful run' do
      schema_commit = commit(
        hash: 'a' * 40,
        files: [file_change(path: 'db/migrate/202604250001_add_email.rb')]
      )

      expect { engine.process([schema_commit], flavor) }.not_to output.to_stdout
    end

    it 'never writes to $stdout during a failed run' do
      bad_tag_commit = commit(
        hash: 'd' * 40, trailers: { 'Phase-Type' => 'phantom-type' }
      )

      expect do
        engine.process([bad_tag_commit], flavor)
      rescue Phaser::ClassificationError
        # expected
      end.not_to output.to_stdout
    end
  end
end
