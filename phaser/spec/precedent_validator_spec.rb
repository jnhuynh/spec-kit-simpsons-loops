# frozen_string_literal: true

require 'phaser'

# Specs for Phaser::PrecedentValidator — the FR-006 enforcement of a
# flavor's precedent rules over the post-classification commit list
# (feature 007-multi-phase-pipeline; T023/T032, FR-006, FR-041, FR-042,
# data-model.md "PrecedentRule" / "Error Conditions" table row
# "Precedent rule violated").
#
# Position in the engine pipeline (per quickstart.md "Pattern:
# Pre-Classification Gate Discipline" and T035 in tasks.md):
#
#   empty-diff filter (FR-009)
#     → forbidden-operations gate (FR-049)
#     → classifier (FR-004)
#     → PRECEDENT VALIDATOR (FR-006)            <-- this module
#     → size guard (FR-048)
#     → isolation resolver (FR-005)
#     → manifest writer (FR-002, FR-038)
#
# The validator runs over the FULL list of classified commits in
# commit-emission order. For every flavor `PrecedentRule` it asserts
# that each commit whose `task_type == rule.subject_type` is preceded
# by at least one earlier commit (strictly earlier in the input list)
# whose `task_type == rule.predecessor_type`. The "strictly later
# phase" requirement of FR-006 is enforced jointly: the validator
# guarantees the predecessor exists earlier in the commit sequence;
# the IsolationResolver (T024/T033) downstream guarantees the subject
# lands in a strictly later phase. A precedent rule violation here
# halts the engine BEFORE the size guard, isolation resolver, or
# manifest writer is invoked, so no manifest is produced on failure
# (data-model.md "Error Conditions" table — exit non-zero, no manifest).
#
# Surface (T032 / data-model.md "ClassificationResult" extension):
#
#   * `Phaser::PrecedentValidator.new` — stateless; constructed once
#     per engine run with no arguments. (The validator is a pure
#     function over `(classification_results, flavor)` so there is no
#     per-run configuration to inject; this also keeps the bypass
#     surface empty by construction, mirroring the
#     ForbiddenOperationsGate's D-016 stance.)
#
#   * `#validate(classification_results, flavor)` — given the
#     post-classifier list of `Phaser::ClassificationResult`s in
#     commit-emission order and the active `Phaser::Flavor`, returns a
#     NEW list of `ClassificationResult` instances with
#     `precedents_consulted` populated for every commit whose type
#     participates as a subject in at least one of the flavor's
#     precedent rules. The original results are unchanged
#     (`ClassificationResult` is `Data.define` and therefore
#     immutable). On the first violation the validator raises
#     `Phaser::PrecedentError`; classifications that already passed
#     the validator before the violation are NOT returned because the
#     engine never proceeds past a precedent failure.
#
#   * `Phaser::PrecedentError` — exception raised by the validator.
#     Carries the offending commit hash, the violating rule's `name`
#     (canonical `failing_rule` for the validation-failed ERROR record
#     per FR-041), and the rule's `predecessor_type` (canonical
#     `missing_precedent` field per FR-041 and the
#     `phase-creation-status.yaml` schema). Descends from
#     `Phaser::ValidationError` so the engine's outer `rescue` clause
#     handles it uniformly with the other validation failure modes
#     (forbidden-operation, backfill-safety, feature-too-large,
#     unknown-type-tag).
#
# Determinism contract (FR-002, SC-002):
#
#   * The input ordering is the canonical commit-emission order the
#     engine receives from `git log` of the feature branch. The
#     validator MUST iterate rules in the order declared by the flavor
#     and commits in input order so the FIRST violation reported is
#     reproducible across runs. Two operators running the same flavor
#     against the same commits MUST see the same offending commit
#     reported, with the same `failing_rule` and `missing_precedent`
#     values.
#
# Logging / status-file contract (FR-041, FR-042, data-model.md
# "PhaseCreationStatus"):
#
#   * The engine relays `error.to_validation_failed_payload` to
#     `Observability#log_validation_failed` and `StatusWriter#write`.
#     The payload carries exactly `{commit_hash, failing_rule,
#     missing_precedent}` — no `forbidden_operation`, no
#     `decomposition_message`, no `commit_count`/`phase_count` keys
#     (those belong to other failure classes). The validator does NOT
#     write to stderr or to the status file directly; emission is the
#     engine's responsibility (FR-041 mandates exactly one
#     `validation-failed` ERROR record per failure).
RSpec.describe Phaser::PrecedentValidator do # rubocop:disable RSpec/SpecFilePathFormat
  subject(:validator) { described_class.new }

  # Build a minimal flavor with task types and precedent rules
  # configurable per example. Mirrors the shape produced by
  # `Phaser::FlavorLoader` (T019) so the validator sees the exact
  # value-object surface it consumes in production.
  def build_flavor(
    task_type_names: %w[ignore-column drop-column misc],
    default_type: 'misc',
    precedent_rules: []
  )
    Phaser::Flavor.new(
      name: 'precedent-validator-spec',
      version: '0.1.0',
      default_type: default_type,
      task_types: task_type_names.map do |name|
        Phaser::FlavorTaskType.new(
          name: name,
          isolation: name == 'misc' ? :groups : :alone,
          description: "#{name} task type for precedent-validator specs."
        )
      end,
      precedent_rules: precedent_rules,
      inference_rules: [],
      forbidden_operations: [],
      stack_detection: Phaser::FlavorStackDetection.new(signals: [])
    )
  end

  def precedent_rule(name:, subject_type:, predecessor_type:,
                     error_message: 'precedent violated')
    Phaser::FlavorPrecedentRule.new(
      name: name,
      subject_type: subject_type,
      predecessor_type: predecessor_type,
      error_message: error_message
    )
  end

  # Build a ClassificationResult value object directly. The validator
  # consumes the post-classifier output, so each spec composes the
  # exact list of results it wants to test against without going
  # through the classifier itself (the classifier has its own spec at
  # spec/classifier_spec.rb).
  #
  # The keyword surface is bundled into a single options hash to keep
  # the helper's parameter count within rubocop's community-default
  # limit while still being called with the explicit keyword-argument
  # style the spec body uses for readability.
  def classified(**options)
    Phaser::ClassificationResult.new(
      commit_hash: options.fetch(:commit_hash),
      task_type: options.fetch(:task_type),
      source: options.fetch(:source, :inference),
      isolation: options.fetch(:isolation, :alone),
      rule_name: options[:rule_name],
      precedents_consulted: options[:precedents_consulted]
    )
  end

  describe '#validate — happy paths (no precedent rules / no subjects)' do
    it 'returns the input list unchanged when the flavor declares no precedent rules' do
      flavor = build_flavor(precedent_rules: [])
      results = [
        classified(commit_hash: 'a' * 40, task_type: 'misc', isolation: :groups),
        classified(commit_hash: 'b' * 40, task_type: 'ignore-column')
      ]

      validated = validator.validate(results, flavor)

      expect(validated).to eq(results)
    end

    it 'returns an empty list unchanged' do
      flavor = build_flavor(precedent_rules: [
                              precedent_rule(name: 'drop-after-ignore',
                                             subject_type: 'drop-column',
                                             predecessor_type: 'ignore-column')
                            ])

      expect(validator.validate([], flavor)).to eq([])
    end

    it 'returns the input list unchanged when no commit has a subject_type for any rule' do
      flavor = build_flavor(precedent_rules: [
                              precedent_rule(name: 'drop-after-ignore',
                                             subject_type: 'drop-column',
                                             predecessor_type: 'ignore-column')
                            ])
      results = [
        classified(commit_hash: 'a' * 40, task_type: 'misc', isolation: :groups),
        classified(commit_hash: 'b' * 40, task_type: 'ignore-column')
      ]

      validated = validator.validate(results, flavor)

      expect(validated.map(&:task_type)).to eq(%w[misc ignore-column])
    end
  end

  describe '#validate — predecessor present in earlier position (passes)' do
    let(:flavor) do
      build_flavor(precedent_rules: [
                     precedent_rule(name: 'drop-after-ignore',
                                    subject_type: 'drop-column',
                                    predecessor_type: 'ignore-column')
                   ])
    end

    it 'accepts the subject when its predecessor appears earlier in the list' do
      results = [
        classified(commit_hash: 'a' * 40, task_type: 'ignore-column'),
        classified(commit_hash: 'b' * 40, task_type: 'drop-column')
      ]

      expect { validator.validate(results, flavor) }.not_to raise_error
    end

    it 'accepts the subject when an unrelated commit sits between predecessor and subject' do
      results = [
        classified(commit_hash: 'a' * 40, task_type: 'ignore-column'),
        classified(commit_hash: 'b' * 40, task_type: 'misc', isolation: :groups),
        classified(commit_hash: 'c' * 40, task_type: 'drop-column')
      ]

      expect { validator.validate(results, flavor) }.not_to raise_error
    end

    it 'accepts multiple subjects when each is preceded by at least one predecessor' do
      results = [
        classified(commit_hash: 'a' * 40, task_type: 'ignore-column'),
        classified(commit_hash: 'b' * 40, task_type: 'drop-column'),
        classified(commit_hash: 'c' * 40, task_type: 'drop-column')
      ]

      expect { validator.validate(results, flavor) }.not_to raise_error
    end
  end

  describe '#validate — predecessor missing (fails per FR-006)' do
    let(:flavor) do
      build_flavor(precedent_rules: [
                     precedent_rule(name: 'drop-after-ignore',
                                    subject_type: 'drop-column',
                                    predecessor_type: 'ignore-column')
                   ])
    end

    it 'raises Phaser::PrecedentError when the subject has no predecessor anywhere in the list' do
      results = [classified(commit_hash: 'a' * 40, task_type: 'drop-column')]

      expect { validator.validate(results, flavor) }
        .to raise_error(Phaser::PrecedentError)
    end

    it 'raises Phaser::PrecedentError when the only predecessor appears AFTER the subject' do
      # FR-006: predecessor must appear in a STRICTLY EARLIER phase.
      # The validator enforces the necessary condition on input order;
      # the IsolationResolver enforces the strictly-later-phase
      # condition downstream. A predecessor that sits later in commit
      # order can never be placed in an earlier phase, so this is a
      # precedent violation as well.
      results = [
        classified(commit_hash: 'a' * 40, task_type: 'drop-column'),
        classified(commit_hash: 'b' * 40, task_type: 'ignore-column')
      ]

      expect { validator.validate(results, flavor) }
        .to raise_error(Phaser::PrecedentError)
    end

    it 'names the offending commit hash on the error (FR-006)' do
      results = [classified(commit_hash: 'd' * 40, task_type: 'drop-column')]

      validator.validate(results, flavor)
    rescue Phaser::PrecedentError => e
      expect(e.commit_hash).to eq('d' * 40)
    end

    it 'names the missing predecessor type on the error (FR-006, FR-041)' do
      results = [classified(commit_hash: 'd' * 40, task_type: 'drop-column')]

      validator.validate(results, flavor)
    rescue Phaser::PrecedentError => e
      expect(e.missing_precedent).to eq('ignore-column')
    end

    it 'exposes the violating rule name as failing_rule for the validation-failed ERROR record' do
      # data-model.md "Error Conditions" table row "Precedent rule
      # violated": failing_rule = <rule-name>. The engine relays this
      # value verbatim into the validation-failed ERROR record (FR-041)
      # and into phase-creation-status.yaml's `failing_rule` field
      # (FR-042, contracts/phase-creation-status.schema.yaml).
      results = [classified(commit_hash: 'd' * 40, task_type: 'drop-column')]

      validator.validate(results, flavor)
    rescue Phaser::PrecedentError => e
      expect(e.failing_rule).to eq('drop-after-ignore')
    end

    it 'puts the offending commit hash and missing predecessor in the human-readable message' do
      # SC-008 (precise error messages) requires a maintainer can
      # diagnose the failure from the message alone, without reading
      # the engine source. The two facts that uniquely identify the
      # failure are the offending commit hash and the missing
      # predecessor type.
      results = [classified(commit_hash: 'd' * 40, task_type: 'drop-column')]

      validator.validate(results, flavor)
    rescue Phaser::PrecedentError => e
      expect(e.message).to include('d' * 40)
      expect(e.message).to include('ignore-column')
    end

    it 'descends from Phaser::ValidationError so the engine can rescue uniformly' do
      expect(Phaser::PrecedentError).to be < Phaser::ValidationError
    end
  end

  describe '#validate — error reporting determinism (FR-002, SC-002)' do
    it 'reports the FIRST subject in input order when multiple subjects lack predecessors' do
      flavor = build_flavor(precedent_rules: [
                              precedent_rule(name: 'drop-after-ignore',
                                             subject_type: 'drop-column',
                                             predecessor_type: 'ignore-column')
                            ])
      results = [
        classified(commit_hash: 'a' * 40, task_type: 'drop-column'),
        classified(commit_hash: 'b' * 40, task_type: 'drop-column')
      ]

      validator.validate(results, flavor)
    rescue Phaser::PrecedentError => e
      expect(e.commit_hash).to eq('a' * 40)
    end

    # Multi-violation scenario: a single subject violates two precedent
    # rules. The rule listed first in flavor.precedent_rules MUST be
    # the one reported. This makes the failure reproducible across runs
    # regardless of any future internal iteration order changes.
    context 'when one subject violates multiple rules' do
      let(:flavor) do
        build_flavor(
          task_type_names: %w[drop-column ignore-column reference-removal misc],
          precedent_rules: [
            precedent_rule(name: 'drop-after-ignore',
                           subject_type: 'drop-column',
                           predecessor_type: 'ignore-column'),
            precedent_rule(name: 'drop-after-reference-removal',
                           subject_type: 'drop-column',
                           predecessor_type: 'reference-removal')
          ]
        )
      end
      let(:results) { [classified(commit_hash: 'a' * 40, task_type: 'drop-column')] }

      it 'reports the FIRST rule in declared order' do
        validator.validate(results, flavor)
      rescue Phaser::PrecedentError => e
        expect(e.failing_rule).to eq('drop-after-ignore')
        expect(e.missing_precedent).to eq('ignore-column')
      end
    end
  end

  describe '#validate — multiple precedent rules (independent)' do
    let(:flavor) do
      build_flavor(
        task_type_names: %w[a b c d],
        precedent_rules: [
          precedent_rule(name: 'b-after-a', subject_type: 'b', predecessor_type: 'a'),
          precedent_rule(name: 'd-after-c', subject_type: 'd', predecessor_type: 'c')
        ]
      )
    end

    it 'accepts an input that satisfies every rule independently' do
      results = [
        classified(commit_hash: 'a' * 40, task_type: 'a'),
        classified(commit_hash: 'b' * 40, task_type: 'b'),
        classified(commit_hash: 'c' * 40, task_type: 'c'),
        classified(commit_hash: 'd' * 40, task_type: 'd')
      ]

      expect { validator.validate(results, flavor) }.not_to raise_error
    end

    it 'rejects an input that satisfies one rule but violates the other' do
      # First rule (b-after-a) is satisfied; second rule (d-after-c)
      # is violated. The error MUST name the second rule, since the
      # subject `d` has no predecessor `c` anywhere in the input.
      results = [
        classified(commit_hash: 'a' * 40, task_type: 'a'),
        classified(commit_hash: 'b' * 40, task_type: 'b'),
        classified(commit_hash: 'd' * 40, task_type: 'd')
      ]

      validator.validate(results, flavor)
    rescue Phaser::PrecedentError => e
      expect(e.failing_rule).to eq('d-after-c')
      expect(e.missing_precedent).to eq('c')
    end
  end

  describe '#validate — ClassificationResult enrichment (precedents_consulted)' do
    # data-model.md "ClassificationResult": `precedents_consulted` is
    # an optional list of precedent-rule names checked for the commit.
    # The classifier (T030) leaves it nil; the validator (this module)
    # populates it for any commit whose type participates as a subject
    # in at least one of the flavor's precedent rules so the
    # observability layer (FR-041 commit-classified record's optional
    # `precedents_consulted` field) can attribute the consultation
    # downstream (SC-011).
    let(:flavor) do
      build_flavor(
        task_type_names: %w[ignore-column reference-removal drop-column misc],
        precedent_rules: [
          precedent_rule(name: 'drop-after-ignore',
                         subject_type: 'drop-column',
                         predecessor_type: 'ignore-column'),
          precedent_rule(name: 'drop-after-reference-removal',
                         subject_type: 'drop-column',
                         predecessor_type: 'reference-removal')
        ]
      )
    end

    let(:results) do
      [
        classified(commit_hash: 'a' * 40, task_type: 'ignore-column'),
        classified(commit_hash: 'b' * 40, task_type: 'reference-removal'),
        classified(commit_hash: 'c' * 40, task_type: 'drop-column')
      ]
    end

    it 'populates precedents_consulted on the subject commit with every rule that named it' do
      validated = validator.validate(results, flavor)

      drop_column = validated.find { |r| r.task_type == 'drop-column' }
      expect(drop_column.precedents_consulted)
        .to contain_exactly('drop-after-ignore', 'drop-after-reference-removal')
    end

    it 'leaves precedents_consulted nil for commits whose type is not a subject of any rule' do
      validated = validator.validate(results, flavor)

      ignore = validated.find { |r| r.task_type == 'ignore-column' }
      reference = validated.find { |r| r.task_type == 'reference-removal' }
      expect(ignore.precedents_consulted).to be_nil
      expect(reference.precedents_consulted).to be_nil
    end

    it 'preserves the input ordering of classification results' do
      validated = validator.validate(results, flavor)

      expect(validated.map(&:commit_hash)).to eq([
                                                   'a' * 40, 'b' * 40, 'c' * 40
                                                 ])
    end

    it 'preserves every other ClassificationResult attribute on the enriched copy' do
      validated = validator.validate(results, flavor)

      drop_column = validated.find { |r| r.task_type == 'drop-column' }
      expect(drop_column.commit_hash).to eq('c' * 40)
      expect(drop_column.task_type).to eq('drop-column')
      expect(drop_column.source).to eq(:inference)
      expect(drop_column.isolation).to eq(:alone)
    end

    it 'does not mutate the input ClassificationResult instances' do
      # ClassificationResult is Data.define and therefore immutable, but
      # the validator could plausibly construct a new list while still
      # sharing references with the original entries. We assert the
      # original entries' precedents_consulted remains nil so callers
      # holding a reference to the pre-validation results are not
      # surprised by an in-place change.
      validator.validate(results, flavor)

      expect(results.find { |r| r.task_type == 'drop-column' }.precedents_consulted)
        .to be_nil
    end
  end

  describe 'Phaser::PrecedentError — payload contract (FR-041, FR-042)' do
    let(:flavor) do
      build_flavor(precedent_rules: [
                     precedent_rule(name: 'drop-after-ignore',
                                    subject_type: 'drop-column',
                                    predecessor_type: 'ignore-column')
                   ])
    end

    it 'is raisable with the offending classification result and the violating rule' do
      result = classified(commit_hash: 'e' * 40, task_type: 'drop-column')
      rule = flavor.precedent_rules.first

      error = Phaser::PrecedentError.new(classification_result: result, rule: rule)

      expect(error).to be_a(Phaser::PrecedentError)
    end

    it 'serializes to the validation-failed ERROR payload shape per FR-041' do
      # The engine relays the three payload fields to
      # `Observability#log_validation_failed` (FR-041) and to
      # `StatusWriter#write` (FR-042). The error object exposes
      # `to_validation_failed_payload` so the engine does not need to
      # know the precedent-rule's internal layout.
      result = classified(commit_hash: 'f' * 40, task_type: 'drop-column')
      rule = flavor.precedent_rules.first

      error = Phaser::PrecedentError.new(classification_result: result, rule: rule)

      expect(error.to_validation_failed_payload).to eq(
        commit_hash: 'f' * 40,
        failing_rule: 'drop-after-ignore',
        missing_precedent: 'ignore-column'
      )
    end

    it 'omits fields the precedent failure mode does not populate' do
      # The validation-failed schema permits these keys for OTHER
      # failure modes (`feature-too-large` populates commit_count /
      # phase_count; forbidden-operation populates forbidden_operation
      # / decomposition_message). The precedent path MUST NOT emit
      # them so the operator-facing record is precise about which rule
      # fired.
      result = classified(commit_hash: 'g' * 40, task_type: 'drop-column')
      rule = flavor.precedent_rules.first

      error = Phaser::PrecedentError.new(classification_result: result, rule: rule)
      payload = error.to_validation_failed_payload

      expect(payload).not_to include(
        :forbidden_operation,
        :decomposition_message,
        :commit_count,
        :phase_count
      )
    end
  end
end
