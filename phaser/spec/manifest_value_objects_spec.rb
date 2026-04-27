# frozen_string_literal: true

require 'phaser'

# Specs for the four manifest-side value objects that the phaser engine
# emits (feature 007-multi-phase-pipeline):
#
#   * Phaser::ClassificationResult — the verdict of running a single
#                                    Commit through the operator-tag →
#                                    inference → default cascade
#                                    (FR-004, data-model.md
#                                    "ClassificationResult").
#   * Phaser::Phase                — an ordered group of one or more
#                                    classified Tasks plus the stacked-PR
#                                    branch metadata that the stacked-PR
#                                    creator and the per-phase marge
#                                    consume (FR-026, data-model.md
#                                    "Phase").
#   * Phaser::Task                 — a single classified commit's
#                                    representation inside a Phase entry
#                                    of the manifest (data-model.md
#                                    "Task").
#   * Phaser::PhaseManifest        — the artifact the engine writes to
#                                    `<FEATURE_DIR>/phase-manifest.yaml`
#                                    (FR-020, FR-021, FR-035; full schema
#                                    in `contracts/phase-manifest.schema.yaml`).
#
# Like the commit-side value objects under spec/value_objects_spec.rb,
# these objects sit on the boundary between the engine and the manifest
# writer / stacked-PR creator. They MUST be:
#
#   1. Constructible with the required fields documented in
#      data-model.md.
#   2. Immutable: `Data.define` instances disallow attribute mutation
#      so the engine can pass them between pipeline stages without
#      defensive copies (plan.md "Project Structure").
#   3. Equality-by-value: two instances with the same attributes compare
#      `==` so manifest serialization round-trips cleanly and the SC-002
#      determinism check (T014) can compare manifests structurally.
#
# Optional attributes documented in data-model.md (e.g.,
# ClassificationResult#rule_name, Task#safety_assertion_precedents) are
# tested with explicit nil/empty defaults so callers do not have to
# remember which attributes are required and which are optional.
RSpec.describe 'manifest-side value objects' do # rubocop:disable RSpec/DescribeClass
  describe Phaser::ClassificationResult do
    let(:required_attributes) do
      {
        commit_hash: 'a' * 40,
        task_type: 'schema add-nullable-column',
        source: :inference,
        isolation: :alone
      }
    end

    it 'constructs from the required fields with no optional fields set' do
      result = described_class.new(**required_attributes)

      expect(result.commit_hash).to eq('a' * 40)
      expect(result.task_type).to eq('schema add-nullable-column')
      expect(result.source).to eq(:inference)
      expect(result.isolation).to eq(:alone)
    end

    it 'accepts the rule_name optional field when source is :inference' do
      result = described_class.new(
        **required_attributes,
        rule_name: 'migration-file-glob'
      )

      expect(result.rule_name).to eq('migration-file-glob')
    end

    it 'accepts the precedents_consulted optional field' do
      result = described_class.new(
        **required_attributes,
        precedents_consulted: ['drop-column-requires-cleanup']
      )

      expect(result.precedents_consulted).to eq(['drop-column-requires-cleanup'])
    end

    it 'defaults the optional fields to nil when not supplied' do
      result = described_class.new(**required_attributes)

      expect(result.rule_name).to be_nil
      expect(result.precedents_consulted).to be_nil
    end

    it 'requires every documented required attribute' do
      required_attributes.each_key do |missing|
        partial = required_attributes.reject { |k, _| k == missing }
        expect { described_class.new(**partial) }
          .to raise_error(ArgumentError, /#{missing}/),
              "expected missing #{missing} to raise ArgumentError"
      end
    end

    it 'has no public attribute writers (immutable value object)' do
      result = described_class.new(**required_attributes)

      required_attributes.each_key do |attr_name|
        expect(result).not_to respond_to("#{attr_name}=")
      end
      expect(result).not_to respond_to(:rule_name=)
      expect(result).not_to respond_to(:precedents_consulted=)
    end

    it 'compares equal when all attributes match (Data.define value semantics)' do
      first  = described_class.new(**required_attributes)
      second = described_class.new(**required_attributes)

      expect(first).to eq(second)
    end

    it 'compares unequal when any attribute differs' do
      original    = described_class.new(**required_attributes)
      different   = described_class.new(**required_attributes, source: :operator_tag)

      expect(original).not_to eq(different)
    end

    # FR-004 enumerates the three classification sources. The value
    # object accepts any symbol so the engine can use the canonical
    # set, but the engine itself is responsible for emitting only the
    # documented values. We assert the canonical set is constructible
    # to lock in the contract.
    it 'accepts each of the documented source values (operator_tag | inference | default)' do
      %i[operator_tag inference default].each do |source_value|
        expect do
          described_class.new(**required_attributes, source: source_value)
        end.not_to raise_error
      end
    end

    # data-model.md "TaskType" enumerates `alone` and `groups` as the
    # two isolation values. Both must round-trip cleanly through the
    # ClassificationResult value object.
    it 'accepts each of the documented isolation values (alone | groups)' do
      %i[alone groups].each do |isolation_value|
        expect do
          described_class.new(**required_attributes, isolation: isolation_value)
        end.not_to raise_error
      end
    end
  end

  describe Phaser::Task do
    let(:required_attributes) do
      {
        id: 'phase-1-task-1',
        task_type: 'schema add-nullable-column',
        commit_hash: 'b' * 40,
        commit_subject: 'Add nullable email_address column'
      }
    end

    it 'constructs from id, task_type, commit_hash, and commit_subject' do
      task = described_class.new(**required_attributes)

      expect(task.id).to eq('phase-1-task-1')
      expect(task.task_type).to eq('schema add-nullable-column')
      expect(task.commit_hash).to eq('b' * 40)
      expect(task.commit_subject).to eq('Add nullable email_address column')
    end

    # FR-018 / plan.md D-017: the reference flavor's
    # SafetyAssertionValidator attaches the cited precedent SHAs to the
    # corresponding Task entry so audit reviewers can trace the
    # precedent chain from the manifest alone. Absent for commits whose
    # task type is not declared irreversible by the active flavor.
    it 'accepts safety_assertion_precedents as an optional field' do
      task = described_class.new(
        **required_attributes,
        safety_assertion_precedents: ['c' * 40, 'd' * 40]
      )

      expect(task.safety_assertion_precedents).to eq(['c' * 40, 'd' * 40])
    end

    it 'defaults safety_assertion_precedents to nil when not supplied' do
      task = described_class.new(**required_attributes)

      expect(task.safety_assertion_precedents).to be_nil
    end

    it 'requires every documented required attribute' do
      required_attributes.each_key do |missing|
        partial = required_attributes.reject { |k, _| k == missing }
        expect { described_class.new(**partial) }
          .to raise_error(ArgumentError, /#{missing}/),
              "expected missing #{missing} to raise ArgumentError"
      end
    end

    it 'has no public attribute writers (immutable value object)' do
      task = described_class.new(**required_attributes)

      required_attributes.each_key do |attr_name|
        expect(task).not_to respond_to("#{attr_name}=")
      end
      expect(task).not_to respond_to(:safety_assertion_precedents=)
    end

    it 'compares equal when all attributes match (Data.define value semantics)' do
      first  = described_class.new(**required_attributes)
      second = described_class.new(**required_attributes)

      expect(first).to eq(second)
    end

    it 'compares unequal when any attribute differs' do
      original  = described_class.new(**required_attributes)
      different = described_class.new(**required_attributes, id: 'phase-1-task-2')

      expect(original).not_to eq(different)
    end
  end

  describe Phaser::Phase do
    let(:task) do
      Phaser::Task.new(
        id: 'phase-1-task-1',
        task_type: 'schema add-nullable-column',
        commit_hash: 'b' * 40,
        commit_subject: 'Add nullable email_address column'
      )
    end

    let(:required_attributes) do
      {
        number: 1,
        name: 'Schema: add nullable email_address column',
        branch_name: '007-multi-phase-pipeline-phase-1',
        base_branch: 'main',
        tasks: [task],
        ci_gates: %w[rspec rubocop],
        rollback_note: 'Drop the nullable column to revert.'
      }
    end

    it 'exposes the scalar attributes (number, name, branch_name, base_branch)' do
      phase = described_class.new(**required_attributes)

      expect(phase.number).to eq(1)
      expect(phase.name).to eq('Schema: add nullable email_address column')
      expect(phase.branch_name).to eq('007-multi-phase-pipeline-phase-1')
      expect(phase.base_branch).to eq('main')
    end

    it 'exposes the collection and rollback attributes (tasks, ci_gates, rollback_note)' do
      phase = described_class.new(**required_attributes)

      expect(phase.tasks).to eq([task])
      expect(phase.ci_gates).to eq(%w[rspec rubocop])
      expect(phase.rollback_note).to eq('Drop the nullable column to revert.')
    end

    it 'requires every documented attribute' do
      required_attributes.each_key do |missing|
        partial = required_attributes.reject { |k, _| k == missing }
        expect { described_class.new(**partial) }
          .to raise_error(ArgumentError, /#{missing}/),
              "expected missing #{missing} to raise ArgumentError"
      end
    end

    it 'has no public attribute writers (immutable value object)' do
      phase = described_class.new(**required_attributes)

      required_attributes.each_key do |attr_name|
        expect(phase).not_to respond_to("#{attr_name}=")
      end
    end

    it 'compares equal when all attributes match (Data.define value semantics)' do
      first  = described_class.new(**required_attributes)
      second = described_class.new(**required_attributes)

      expect(first).to eq(second)
    end

    it 'compares unequal when any attribute differs' do
      original  = described_class.new(**required_attributes)
      different = described_class.new(**required_attributes, number: 2)

      expect(original).not_to eq(different)
    end

    # FR-026: phase 2..N's base_branch is the previous phase's
    # branch_name. The value object accepts any string so the engine
    # can wire the relationship; the constraint itself is enforced by
    # the manifest writer / schema. We round-trip both shapes here.
    it 'accepts the previous phase branch_name as base_branch for phases 2..N' do
      phase_two = described_class.new(
        **required_attributes,
        number: 2,
        base_branch: '007-multi-phase-pipeline-phase-1',
        branch_name: '007-multi-phase-pipeline-phase-2'
      )

      expect(phase_two.base_branch).to eq('007-multi-phase-pipeline-phase-1')
      expect(phase_two.branch_name).to eq('007-multi-phase-pipeline-phase-2')
    end
  end

  describe Phaser::PhaseManifest do
    let(:phase) do
      Phaser::Phase.new(
        number: 1,
        name: 'Schema: add nullable email_address column',
        branch_name: '007-multi-phase-pipeline-phase-1',
        base_branch: 'main',
        tasks: [
          Phaser::Task.new(
            id: 'phase-1-task-1',
            task_type: 'schema add-nullable-column',
            commit_hash: 'b' * 40,
            commit_subject: 'Add nullable email_address column'
          )
        ],
        ci_gates: ['rspec'],
        rollback_note: 'Drop the nullable column to revert.'
      )
    end

    let(:required_attributes) do
      {
        flavor_name: 'rails-postgres-strong-migrations',
        flavor_version: '0.1.0',
        feature_branch: '007-multi-phase-pipeline',
        generated_at: '2026-04-25T00:00:00Z',
        phases: [phase]
      }
    end

    it 'constructs from flavor_name, flavor_version, feature_branch, generated_at, and phases' do
      manifest = described_class.new(**required_attributes)

      expect(manifest.flavor_name).to eq('rails-postgres-strong-migrations')
      expect(manifest.flavor_version).to eq('0.1.0')
      expect(manifest.feature_branch).to eq('007-multi-phase-pipeline')
      expect(manifest.generated_at).to eq('2026-04-25T00:00:00Z')
      expect(manifest.phases).to eq([phase])
    end

    it 'requires every documented attribute' do
      required_attributes.each_key do |missing|
        partial = required_attributes.reject { |k, _| k == missing }
        expect { described_class.new(**partial) }
          .to raise_error(ArgumentError, /#{missing}/),
              "expected missing #{missing} to raise ArgumentError"
      end
    end

    it 'has no public attribute writers (immutable value object)' do
      manifest = described_class.new(**required_attributes)

      required_attributes.each_key do |attr_name|
        expect(manifest).not_to respond_to("#{attr_name}=")
      end
    end

    it 'compares equal when all attributes match (Data.define value semantics)' do
      first  = described_class.new(**required_attributes)
      second = described_class.new(**required_attributes)

      expect(first).to eq(second)
    end

    it 'compares unequal when any attribute differs' do
      original  = described_class.new(**required_attributes)
      different = described_class.new(**required_attributes, flavor_version: '0.2.0')

      expect(original).not_to eq(different)
    end

    # FR-021 + the schema in contracts/phase-manifest.schema.yaml require
    # at least one phase on success. The value object itself accepts an
    # empty list so the engine can build it incrementally; the
    # minItems: 1 guarantee is enforced at the manifest writer / schema
    # boundary, not at value-object construction time. We assert the
    # value object's permissiveness to lock in the contract.
    it 'is constructible with an empty phases list (schema enforces minItems elsewhere)' do
      expect do
        described_class.new(**required_attributes, phases: [])
      end.not_to raise_error
    end
  end
end
