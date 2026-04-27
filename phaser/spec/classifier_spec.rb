# frozen_string_literal: true

require 'phaser'

# Specs for Phaser::Classifier — the operator-tag → inference → default
# classification cascade that assigns one task type to each non-empty
# commit (feature 007-multi-phase-pipeline; T021/T030, FR-004, FR-007,
# FR-036, data-model.md "ClassificationResult" / "Error Conditions"
# table).
#
# The classifier is the second stage of the engine's per-commit
# pipeline (after the empty-diff filter (FR-009) and the
# forbidden-operations gate (FR-049) have run; see quickstart.md
# "Pattern: Pre-Classification Gate Discipline"). The classifier itself
# is a pure function of `(commit, flavor)` returning a
# `Phaser::ClassificationResult`.
#
# Cascade contract per FR-004:
#
#   1. If the commit's `Phase-Type:` trailer (FR-016) names a task type
#      that exists in the active flavor's catalog, that type wins.
#      `source = :operator_tag`.
#
#   2. Otherwise, evaluate every inference rule against the commit's
#      diff. Among the matching rules, the one with the HIGHEST
#      `precedence` integer wins (FR-036). Ties on `precedence` are
#      broken alphabetically by rule `name` so two operators running
#      the same flavor on the same commits produce the same manifest
#      (FR-002, SC-002). When at least one rule matches,
#      `source = :inference` and `rule_name` is set to the winning
#      rule's name.
#
#   3. Otherwise, the flavor's `default_type` is assigned.
#      `source = :default` and `rule_name` is nil.
#
# Error contract per FR-007 (data-model.md "Error Conditions" row 1):
#
#   * If the operator tag names a type that is NOT in the flavor's
#     catalog, the classifier raises `Phaser::UnknownTypeTagError`
#     (subclass of `Phaser::ClassificationError`) carrying the unknown
#     tag, the offending commit's hash, and the canonical
#     `failing_rule = "unknown-type-tag"` value the engine emits as the
#     `validation-failed` ERROR record's `failing_rule` field per
#     FR-041. The error message lists the valid tags from the active
#     flavor so the operator can correct the typo.
#
# The classifier never inspects the diff for forbidden operations —
# that is the FR-049 pre-classification gate's job, validated by the
# T022/T031 spec for `Phaser::ForbiddenOperationsGate`. The classifier
# is ONLY responsible for the cascade defined above.
RSpec.describe Phaser::Classifier do # rubocop:disable RSpec/SpecFilePathFormat
  subject(:classifier) { described_class.new }

  # Build a minimal flavor with two task types and a configurable
  # inference-rule set so each example can declare exactly the rules
  # it needs without re-stating the full catalog. The shape mirrors the
  # `Phaser::Flavor` value object the FlavorLoader produces (T019),
  # which is what the engine passes to the classifier in production.
  def build_flavor(
    task_type_names: %w[schema misc],
    default_type: 'misc',
    inference_rules: []
  )
    Phaser::Flavor.new(
      name: 'classifier-spec',
      version: '0.1.0',
      default_type: default_type,
      task_types: task_type_names.map do |name|
        Phaser::FlavorTaskType.new(
          name: name,
          isolation: name == 'schema' ? :alone : :groups,
          description: "#{name} task type for classifier specs."
        )
      end,
      precedent_rules: [],
      inference_rules: inference_rules,
      forbidden_operations: [],
      stack_detection: Phaser::FlavorStackDetection.new(signals: [])
    )
  end

  # File-glob inference-rule shorthand (the most common form in the
  # catalog). Specs that need other Match variants use `inference_rule`
  # below.
  def file_glob_rule(name:, precedence:, task_type:, pattern:)
    Phaser::FlavorInferenceRule.new(
      name: name,
      precedence: precedence,
      task_type: task_type,
      match: { 'kind' => 'file_glob', 'pattern' => pattern }
    )
  end

  # Generic inference-rule helper for path_regex, content_regex, and
  # module_method match payloads.
  def inference_rule(name:, precedence:, task_type:, match:)
    Phaser::FlavorInferenceRule.new(
      name: name,
      precedence: precedence,
      task_type: task_type,
      match: match
    )
  end

  # Build a Commit value object with a single FileChange. Specs that
  # need a different file path or different hunk content pass a `file:`
  # Hash with `path:` / `hunks:` / `change_kind:` keys (all optional).
  # Keeps the construction noise out of the individual `it` blocks.
  def build_commit(hash: 'a' * 40, subject: 'Some commit', trailers: {}, file: {})
    Phaser::Commit.new(
      hash: hash,
      subject: subject,
      message_trailers: trailers,
      diff: Phaser::Diff.new(files: [build_file_change(file)]),
      author_timestamp: '2026-04-25T00:00:00Z'
    )
  end

  def build_file_change(file)
    Phaser::FileChange.new(
      path: file.fetch(:path, 'app/models/user.rb'),
      change_kind: file.fetch(:change_kind, :modified),
      hunks: file.fetch(:hunks, ["@@ -1 +1 @@\n-old\n+new\n"])
    )
  end

  describe '#classify — operator-tag wins (FR-004 highest precedence)' do
    let(:flavor) do
      build_flavor(
        inference_rules: [
          file_glob_rule(name: 'schema-by-path', precedence: 100,
                         task_type: 'schema', pattern: 'db/migrate/*.rb')
        ]
      )
    end

    it 'returns :operator_tag as the source when a Phase-Type trailer is present and valid' do
      commit = build_commit(trailers: { 'Phase-Type' => 'schema' })

      result = classifier.classify(commit, flavor)

      expect(result.source).to eq(:operator_tag)
      expect(result.task_type).to eq('schema')
    end

    it 'records the operator-tagged commit hash on the result' do
      commit = build_commit(hash: 'b' * 40, trailers: { 'Phase-Type' => 'misc' })

      result = classifier.classify(commit, flavor)

      expect(result.commit_hash).to eq('b' * 40)
    end

    it 'copies the isolation kind from the assigned task type onto the result' do
      commit = build_commit(trailers: { 'Phase-Type' => 'schema' })

      result = classifier.classify(commit, flavor)

      expect(result.isolation).to eq(:alone)
    end

    it 'leaves rule_name nil when classification came from the operator tag' do
      commit = build_commit(trailers: { 'Phase-Type' => 'schema' })

      result = classifier.classify(commit, flavor)

      expect(result.rule_name).to be_nil
    end

    it 'overrides an inference rule that would otherwise match (operator tag beats inference)' do
      # The diff would match `schema-by-path` (precedence 100), but the
      # operator tag names `misc` — the tag MUST win per FR-004.
      commit = build_commit(
        file: { path: 'db/migrate/202604250001_add_email.rb' },
        trailers: { 'Phase-Type' => 'misc' }
      )

      result = classifier.classify(commit, flavor)

      expect(result.source).to eq(:operator_tag)
      expect(result.task_type).to eq('misc')
    end

    it 'emits the source symbol the ClassificationResult value object expects' do
      # data-model.md "ClassificationResult" enum names the source
      # `operator-tag` (kebab-case in the YAML / JSON surface). The
      # value object uses the snake_case symbol `:operator_tag` (Ruby
      # convention; T009 spec for ClassificationResult locks this in).
      # The classifier MUST emit the symbol so the manifest writer can
      # serialize it to the canonical kebab-case string at the YAML
      # boundary.
      commit = build_commit(trailers: { 'Phase-Type' => 'schema' })

      result = classifier.classify(commit, flavor)

      expect(result.source).to eq(:operator_tag)
    end
  end

  describe '#classify — inference layer (FR-004 second precedence; FR-036 ordering)' do
    let(:schema_by_path) do
      file_glob_rule(name: 'schema-by-path', precedence: 100,
                     task_type: 'schema', pattern: 'db/migrate/*.rb')
    end
    let(:db_migration_commit) do
      build_commit(file: { path: 'db/migrate/202604250001_add_email.rb' })
    end

    it 'returns :inference when an inference rule matches and no operator tag is present' do
      flavor = build_flavor(inference_rules: [schema_by_path])

      result = classifier.classify(db_migration_commit, flavor)

      expect(result.source).to eq(:inference)
      expect(result.task_type).to eq('schema')
    end

    it 'records the winning rule_name on the result so logs can attribute the decision (SC-011)' do
      flavor = build_flavor(inference_rules: [schema_by_path])

      result = classifier.classify(db_migration_commit, flavor)

      expect(result.rule_name).to eq('schema-by-path')
    end

    it 'picks the highest-precedence rule when multiple rules match (FR-036)' do
      flavor = build_flavor(inference_rules: [
                              file_glob_rule(name: 'low-precedence', precedence: 10,
                                             task_type: 'misc', pattern: 'db/migrate/*.rb'),
                              file_glob_rule(name: 'high-precedence', precedence: 100,
                                             task_type: 'schema', pattern: 'db/migrate/*.rb')
                            ])

      result = classifier.classify(db_migration_commit, flavor)

      expect(result.task_type).to eq('schema')
      expect(result.rule_name).to eq('high-precedence')
    end

    it 'breaks precedence ties alphabetically by rule name (FR-036, SC-002 determinism)' do
      flavor = build_flavor(inference_rules: [
                              file_glob_rule(name: 'zebra-rule', precedence: 50,
                                             task_type: 'misc', pattern: 'app/**/*.rb'),
                              file_glob_rule(name: 'alpha-rule', precedence: 50,
                                             task_type: 'schema', pattern: 'app/**/*.rb')
                            ])
      commit = build_commit(file: { path: 'app/models/user.rb' })

      result = classifier.classify(commit, flavor)

      expect(result.rule_name).to eq('alpha-rule')
      expect(result.task_type).to eq('schema')
    end

    it 'evaluates path_regex matches against any file path in the diff' do
      flavor = build_flavor(inference_rules: [
                              inference_rule(
                                name: 'rake-by-regex', precedence: 50, task_type: 'misc',
                                match: { 'kind' => 'path_regex',
                                         'pattern' => '\\Alib/tasks/.*\\.rake\\z' }
                              )
                            ])
      commit = build_commit(file: { path: 'lib/tasks/backfill.rake' })

      result = classifier.classify(commit, flavor)

      expect(result.source).to eq(:inference)
      expect(result.rule_name).to eq('rake-by-regex')
    end

    it 'evaluates content_regex matches against the hunks of files matching path_glob' do
      flavor = build_flavor(inference_rules: [
                              inference_rule(
                                name: 'backfill-by-content', precedence: 75, task_type: 'misc',
                                match: { 'kind' => 'content_regex',
                                         'path_glob' => 'lib/tasks/*.rake',
                                         'pattern' => 'find_each' }
                              )
                            ])
      commit = build_commit(file: {
                              path: 'lib/tasks/backfill.rake',
                              hunks: ["@@ -0,0 +1 @@\n+User.find_each { |u| u.touch }\n"]
                            })

      result = classifier.classify(commit, flavor)

      expect(result.source).to eq(:inference)
      expect(result.rule_name).to eq('backfill-by-content')
    end

    it 'does not match content_regex when no file matches the path_glob' do
      flavor = build_flavor(inference_rules: [
                              inference_rule(
                                name: 'backfill-by-content', precedence: 75, task_type: 'misc',
                                match: { 'kind' => 'content_regex',
                                         'path_glob' => 'lib/tasks/*.rake',
                                         'pattern' => 'find_each' }
                              )
                            ])
      commit = build_commit(file: {
                              path: 'app/models/user.rb',
                              hunks: ["@@ -0,0 +1 @@\n+User.find_each { |u| u.touch }\n"]
                            })

      result = classifier.classify(commit, flavor)

      # No inference rule matched ⇒ falls through to default.
      expect(result.source).to eq(:default)
    end

    it 'leaves precedents_consulted nil at the classifier boundary (precedent rules run later)' do
      flavor = build_flavor(inference_rules: [schema_by_path])

      result = classifier.classify(db_migration_commit, flavor)

      # The classifier does not consult precedent rules; that is the
      # PrecedentValidator's job (T023/T032). The field exists on the
      # ClassificationResult so the validator can populate it
      # downstream.
      expect(result.precedents_consulted).to be_nil
    end

    it 'records the assigned task type isolation onto the result' do
      flavor = build_flavor(inference_rules: [schema_by_path])

      result = classifier.classify(db_migration_commit, flavor)

      expect(result.isolation).to eq(:alone)
    end
  end

  describe '#classify — default type cascade fallback (FR-004 third precedence)' do
    it 'assigns the flavor default_type when no operator tag and no inference rule match' do
      flavor = build_flavor(
        default_type: 'misc',
        inference_rules: [
          file_glob_rule(name: 'schema-by-path', precedence: 100,
                         task_type: 'schema', pattern: 'db/migrate/*.rb')
        ]
      )
      commit = build_commit(file: { path: 'app/models/user.rb' })

      result = classifier.classify(commit, flavor)

      expect(result.task_type).to eq('misc')
      expect(result.source).to eq(:default)
    end

    it 'leaves rule_name nil when the default type is assigned' do
      flavor = build_flavor(default_type: 'misc')
      commit = build_commit(file: { path: 'app/models/user.rb' })

      result = classifier.classify(commit, flavor)

      expect(result.rule_name).to be_nil
    end

    it 'still copies the default task type isolation onto the result' do
      flavor = build_flavor(default_type: 'misc')
      commit = build_commit(file: { path: 'app/models/user.rb' })

      result = classifier.classify(commit, flavor)

      # `misc` is declared with `:groups` isolation in build_flavor.
      expect(result.isolation).to eq(:groups)
    end

    it 'falls back to the default type when there are no inference rules at all' do
      flavor = build_flavor(default_type: 'misc', inference_rules: [])
      commit = build_commit(file: { path: 'app/models/user.rb' })

      result = classifier.classify(commit, flavor)

      expect(result.source).to eq(:default)
      expect(result.task_type).to eq('misc')
    end
  end

  describe '#classify — unknown operator-tag rejection (FR-007, error-table row)' do
    let(:flavor) { build_flavor(task_type_names: %w[schema misc]) }

    it 'raises Phaser::UnknownTypeTagError when the Phase-Type trailer names a tag not in the catalog' do
      commit = build_commit(trailers: { 'Phase-Type' => 'phantom-type' })

      expect { classifier.classify(commit, flavor) }
        .to raise_error(Phaser::UnknownTypeTagError)
    end

    it 'names the unknown tag in the error message so the operator can correct the typo' do
      commit = build_commit(trailers: { 'Phase-Type' => 'phantom-type' })

      classifier.classify(commit, flavor)
    rescue Phaser::UnknownTypeTagError => e
      expect(e.message).to include('phantom-type')
    end

    it 'lists every valid tag from the active flavor in the error message' do
      commit = build_commit(trailers: { 'Phase-Type' => 'phantom-type' })

      classifier.classify(commit, flavor)
    rescue Phaser::UnknownTypeTagError => e
      expect(e.message).to include('schema')
      expect(e.message).to include('misc')
    end

    it 'exposes the offending commit hash on the error for the engine to relay to status writer' do
      commit = build_commit(hash: 'c' * 40, trailers: { 'Phase-Type' => 'phantom-type' })

      classifier.classify(commit, flavor)
    rescue Phaser::UnknownTypeTagError => e
      expect(e.commit_hash).to eq('c' * 40)
    end

    it 'exposes the unknown tag value on the error so callers do not have to parse the message' do
      commit = build_commit(trailers: { 'Phase-Type' => 'phantom-type' })

      classifier.classify(commit, flavor)
    rescue Phaser::UnknownTypeTagError => e
      expect(e.unknown_tag).to eq('phantom-type')
    end

    it 'exposes the canonical failing_rule name `unknown-type-tag` for the validation-failed ERROR record' do
      commit = build_commit(trailers: { 'Phase-Type' => 'phantom-type' })

      classifier.classify(commit, flavor)
    rescue Phaser::UnknownTypeTagError => e
      # data-model.md "Error Conditions" table row 1: the failing_rule
      # field on the validation-failed ERROR record (FR-041) is the
      # constant string `unknown-type-tag` for this rejection class.
      expect(e.failing_rule).to eq('unknown-type-tag')
    end

    it 'descends from Phaser::ClassificationError so engine wrapper can rescue uniformly' do
      expect(Phaser::UnknownTypeTagError).to be < Phaser::ClassificationError
    end

    it 'declares Phaser::ClassificationError as the rescuable ancestor' do
      expect(Phaser::ClassificationError).to be < StandardError
    end
  end

  describe '#classify — empty trailer map (operator-tag absent)' do
    let(:flavor) do
      build_flavor(
        default_type: 'misc',
        inference_rules: [
          file_glob_rule(name: 'schema-by-path', precedence: 100,
                         task_type: 'schema', pattern: 'db/migrate/*.rb')
        ]
      )
    end

    it 'falls through to inference when message_trailers is empty' do
      commit = build_commit(trailers: {},
                            file: { path: 'db/migrate/202604250001_add_email.rb' })

      result = classifier.classify(commit, flavor)

      expect(result.source).to eq(:inference)
      expect(result.task_type).to eq('schema')
    end

    it 'ignores trailers other than Phase-Type (only the documented trailer is operator-supplied)' do
      # FR-016 / Assumptions in spec.md: the operator-supplied per-commit
      # type tag is delivered via the `Phase-Type:` trailer specifically.
      # Other trailer keys (e.g., `Co-authored-by`, `Reviewed-by`) MUST
      # NOT be consulted by the classifier.
      commit = build_commit(
        trailers: { 'Co-authored-by' => 'Someone <x@y.z>' },
        file: { path: 'db/migrate/202604250001_add_email.rb' }
      )

      result = classifier.classify(commit, flavor)

      expect(result.source).to eq(:inference)
    end
  end
end
