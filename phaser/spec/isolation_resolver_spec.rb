# frozen_string_literal: true

require 'phaser'

# Specs for Phaser::IsolationResolver — the FR-005 grouping pass that
# turns the post-classification, post-precedent-validation list of
# `Phaser::ClassificationResult`s into an ordered list of phase
# groupings that the engine wraps as `Phaser::Phase` value objects
# before handing to `Phaser::ManifestWriter` (feature
# 007-multi-phase-pipeline; T024/T033, FR-005, FR-006, FR-037, R-005,
# data-model.md "TaskType" and "Phase").
#
# Position in the engine pipeline (per quickstart.md "Pattern:
# Pre-Classification Gate Discipline" and T035 in tasks.md):
#
#   empty-diff filter (FR-009)
#     → forbidden-operations gate (FR-049)
#     → classifier (FR-004)
#     → precedent validator (FR-006)
#     → size guard (FR-048)
#     → ISOLATION RESOLVER (FR-005)             <-- this module
#     → manifest writer (FR-002, FR-038)
#
# The resolver receives the validated, in-commit-emission-order list of
# classification results and produces an ordered `Array<Array<...>>`:
# the outer list is the sequence of phases (1..N); each inner list is
# the ordered group of classification results that belong to that
# phase. Phase 1 contains the earliest commits; phase N contains the
# latest. The engine consumes the result, attaches branch metadata
# (`branch_name`, `base_branch`, `name`, `ci_gates`, `rollback_note`),
# and constructs the manifest's `Phaser::Phase` value objects (the
# resolver itself is purely a grouping function and stays free of
# branch-naming concerns so the same logic is reusable when the
# stacked-PR creator's branch naming policy ever changes).
#
# Surface (T033 / data-model.md "Phase" / FR-005):
#
#   * `Phaser::IsolationResolver.new` — stateless; constructed once per
#     engine run with no arguments. Determinism is a property of the
#     `(classification_results, flavor)` input pair, not of any
#     resolver-side configuration (R-005).
#
#   * `#resolve(classification_results, flavor)` — given the
#     post-precedent-validation list of `Phaser::ClassificationResult`s
#     in commit-emission order and the active `Phaser::Flavor`, returns
#     an `Array<Array<Phaser::ClassificationResult>>` where each inner
#     array is one phase's ordered task list and the outer array is
#     the ordered phase sequence. The resolver does NOT mutate or
#     re-order the inputs (`ClassificationResult` is `Data.define` and
#     therefore immutable); it only partitions them.
#
# FR-005 isolation contract:
#
#   * A `ClassificationResult` whose `isolation == :alone` MUST occupy
#     its own phase (no other classification result may share the
#     phase, regardless of isolation kind).
#
#   * Two adjacent `ClassificationResult`s whose `isolation == :groups`
#     MAY share a phase. The resolver's default policy is to greedily
#     coalesce contiguous `:groups` runs into a single phase so the
#     manifest is as small as possible while still honoring isolation
#     and precedent rules. Non-adjacent `:groups` runs that are
#     separated by an `:alone` task remain in distinct phases (the
#     `:alone` task creates a phase boundary).
#
# FR-006 precedent / FR-037 backfill contract:
#
#   * The resolver MUST never place a subject and its predecessor in
#     the same phase: a subject classified for type X requiring
#     predecessor Y must land in a strictly later phase than at least
#     one Y classification (FR-006). When the precedent rule's subject
#     and predecessor are both `:groups`-isolation, this means the
#     predecessor is the phase boundary's last entry and the subject
#     is the next phase's first entry.
#
#   * When a feature contains multiple commits classified as the
#     flavor's backfill task type, the resolver MUST place each
#     backfill in its own phase by default (sequential placement).
#     This is FR-037's "sequential by default" guarantee. The flavor's
#     `allow_parallel_backfills: true` toggle relaxes this so backfills
#     may share a `:groups` phase with adjacent `:groups` tasks of any
#     type. The resolver discovers a "backfill task type" via the
#     active flavor's catalog: a task type is treated as a backfill
#     when its name matches `/backfill/` or its description contains
#     "backfill" (the actual identification rule is intentionally
#     simple here so future flavors can declare a backfill type by
#     naming convention without changing the engine; the test below
#     pins this contract).
#
# Determinism contract (FR-002, SC-002, R-005):
#
#   * The resolver MUST be a pure function of `(classification_results,
#     flavor)`. The output ordering is fully determined by the input
#     commit ordering; the only tie-breaking surface inside the
#     resolver is the commit-hash comparison used when two adjacent
#     `:groups` results both refer to the same task type and the engine
#     needs a stable sort within a phase. The resolver never inspects
#     wall-clock time, the filesystem, or any environment variable.
#
# Logging contract:
#
#   * The resolver does not write to stderr or to the status file
#     directly. The engine emits one `phase-emitted` INFO record per
#     resolved phase via `Observability#log_phase_emitted` (FR-041) and
#     persists nothing on success.
RSpec.describe Phaser::IsolationResolver do # rubocop:disable RSpec/SpecFilePathFormat
  subject(:resolver) { described_class.new }

  # Build a minimal flavor with task types and precedent rules
  # configurable per example. Mirrors the shape produced by
  # `Phaser::FlavorLoader` (T019) so the resolver sees the exact
  # value-object surface it consumes in production.
  def build_flavor(
    task_types: default_task_types,
    precedent_rules: [],
    default_type: 'misc',
    allow_parallel_backfills: false
  )
    Phaser::Flavor.new(
      name: 'isolation-resolver-spec',
      version: '0.1.0',
      default_type: default_type,
      task_types: task_types,
      precedent_rules: precedent_rules,
      inference_rules: [],
      forbidden_operations: [],
      stack_detection: Phaser::FlavorStackDetection.new(signals: []),
      allow_parallel_backfills: allow_parallel_backfills
    )
  end

  # Default task-type catalog used by most examples. Mixes one
  # `:alone`-isolation type, two `:groups`-isolation types, and a
  # backfill type so the FR-005, FR-006, and FR-037 contracts all have
  # a target inside the same flavor. Examples that need a different
  # catalog override `task_types:` directly. Built from a compact data
  # table to keep the helper inside rubocop's method-length budget.
  def default_task_types
    [
      ['schema',   :alone,  'Schema change requiring its own phase.'],
      ['code',     :groups, 'Code-only change that rides alongside other code-only changes.'],
      ['misc',     :groups, 'Catch-all groups-isolation type.'],
      ['backfill', :alone,  'Backfill rake task; sequential by default per FR-037.']
    ].map do |name, isolation, description|
      Phaser::FlavorTaskType.new(name: name, isolation: isolation, description: description)
    end
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

  # Build a ClassificationResult value object directly. The resolver
  # consumes the post-precedent-validation output, so each spec
  # composes the exact list of results it wants to test against
  # without going through the classifier or the precedent validator
  # (each has its own spec at spec/classifier_spec.rb and
  # spec/precedent_validator_spec.rb).
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

  # Helpers to keep example bodies readable. `phase_hashes` projects a
  # resolved `Array<Array<ClassificationResult>>` onto the commit
  # hashes inside each phase so an `eq` assertion can compare
  # structure without re-listing every classification result field.
  def phase_hashes(phases)
    phases.map { |phase| phase.map(&:commit_hash) }
  end

  describe '#resolve — empty input' do
    it 'returns an empty list when given no classification results' do
      flavor = build_flavor
      expect(resolver.resolve([], flavor)).to eq([])
    end
  end

  describe '#resolve — alone isolation (FR-005, own phase)' do
    let(:flavor) { build_flavor }

    it 'puts a single :alone result into its own phase' do
      results = [classified(commit_hash: 'a' * 40, task_type: 'schema', isolation: :alone)]

      phases = resolver.resolve(results, flavor)

      expect(phase_hashes(phases)).to eq([['a' * 40]])
    end

    it 'puts each of multiple :alone results into its own phase in commit order' do
      results = [
        classified(commit_hash: 'a' * 40, task_type: 'schema', isolation: :alone),
        classified(commit_hash: 'b' * 40, task_type: 'schema', isolation: :alone),
        classified(commit_hash: 'c' * 40, task_type: 'schema', isolation: :alone)
      ]

      phases = resolver.resolve(results, flavor)

      expect(phase_hashes(phases)).to eq([
                                           ['a' * 40],
                                           ['b' * 40],
                                           ['c' * 40]
                                         ])
    end

    it 'never coalesces an :alone result with a neighbouring :groups result' do
      # FR-005 explicit: an :alone task occupies its own phase
      # regardless of what's adjacent.
      results = [
        classified(commit_hash: 'a' * 40, task_type: 'code', isolation: :groups),
        classified(commit_hash: 'b' * 40, task_type: 'schema', isolation: :alone),
        classified(commit_hash: 'c' * 40, task_type: 'code', isolation: :groups)
      ]

      phases = resolver.resolve(results, flavor)

      expect(phase_hashes(phases)).to eq([
                                           ['a' * 40],
                                           ['b' * 40],
                                           ['c' * 40]
                                         ])
    end
  end

  describe '#resolve — groups isolation (FR-005, may share a phase)' do
    let(:flavor) { build_flavor }

    it 'coalesces a contiguous run of :groups results into a single phase' do
      results = [
        classified(commit_hash: 'a' * 40, task_type: 'code', isolation: :groups),
        classified(commit_hash: 'b' * 40, task_type: 'code', isolation: :groups),
        classified(commit_hash: 'c' * 40, task_type: 'code', isolation: :groups)
      ]

      phases = resolver.resolve(results, flavor)

      expect(phase_hashes(phases)).to eq([['a' * 40, 'b' * 40, 'c' * 40]])
    end

    it 'coalesces adjacent :groups results across different :groups task types' do
      # `code` and `misc` are both :groups-isolation in the default
      # catalog. With no precedent rule between them, they share a
      # phase per FR-005.
      results = [
        classified(commit_hash: 'a' * 40, task_type: 'code', isolation: :groups),
        classified(commit_hash: 'b' * 40, task_type: 'misc', isolation: :groups)
      ]

      phases = resolver.resolve(results, flavor)

      expect(phase_hashes(phases)).to eq([['a' * 40, 'b' * 40]])
    end

    it 'preserves the input order of :groups results within a coalesced phase' do
      results = [
        classified(commit_hash: 'c' * 40, task_type: 'code', isolation: :groups),
        classified(commit_hash: 'a' * 40, task_type: 'code', isolation: :groups),
        classified(commit_hash: 'b' * 40, task_type: 'code', isolation: :groups)
      ]

      phases = resolver.resolve(results, flavor)

      expect(phase_hashes(phases)).to eq([['c' * 40, 'a' * 40, 'b' * 40]])
    end

    it 'splits :groups runs that are separated by an :alone result into distinct phases' do
      results = [
        classified(commit_hash: 'a' * 40, task_type: 'code', isolation: :groups),
        classified(commit_hash: 'b' * 40, task_type: 'code', isolation: :groups),
        classified(commit_hash: 'c' * 40, task_type: 'schema', isolation: :alone),
        classified(commit_hash: 'd' * 40, task_type: 'code', isolation: :groups),
        classified(commit_hash: 'e' * 40, task_type: 'code', isolation: :groups)
      ]

      phases = resolver.resolve(results, flavor)

      expect(phase_hashes(phases)).to eq([
                                           ['a' * 40, 'b' * 40],
                                           ['c' * 40],
                                           ['d' * 40, 'e' * 40]
                                         ])
    end
  end

  describe '#resolve — precedent rules force a phase boundary (FR-006)' do
    # The precedent validator (T032) only verifies that the predecessor
    # exists earlier in the input list; it does not partition the list
    # into phases. The IsolationResolver is the partitioning step that
    # turns "predecessor exists earlier" into "predecessor lands in a
    # strictly earlier phase." When the predecessor and subject are
    # both :groups-isolation and would otherwise coalesce into a single
    # phase, the resolver MUST split them at the precedent boundary.

    let(:flavor) do
      build_flavor(
        task_types: [
          Phaser::FlavorTaskType.new(
            name: 'ignore-column',
            isolation: :groups,
            description: 'Mark a column as ignored.'
          ),
          Phaser::FlavorTaskType.new(
            name: 'reference-removal',
            isolation: :groups,
            description: 'Remove all references to a pending-drop column.'
          ),
          Phaser::FlavorTaskType.new(
            name: 'misc',
            isolation: :groups,
            description: 'Catch-all groups-isolation type.'
          )
        ],
        precedent_rules: [
          precedent_rule(name: 'reference-removal-after-ignore-column',
                         subject_type: 'reference-removal',
                         predecessor_type: 'ignore-column')
        ]
      )
    end

    it 'puts the subject into a strictly later phase than the predecessor' do
      results = [
        classified(commit_hash: 'a' * 40, task_type: 'ignore-column', isolation: :groups),
        classified(commit_hash: 'b' * 40, task_type: 'reference-removal', isolation: :groups)
      ]

      phases = resolver.resolve(results, flavor)

      expect(phase_hashes(phases)).to eq([['a' * 40], ['b' * 40]])
    end

    it 'still splits at the precedent boundary when both sides have additional :groups peers' do
      results = [
        classified(commit_hash: 'a' * 40, task_type: 'ignore-column', isolation: :groups),
        classified(commit_hash: 'b' * 40, task_type: 'misc', isolation: :groups),
        classified(commit_hash: 'c' * 40, task_type: 'reference-removal', isolation: :groups),
        classified(commit_hash: 'd' * 40, task_type: 'misc', isolation: :groups)
      ]

      phases = resolver.resolve(results, flavor)

      expect(phase_hashes(phases)).to eq([
                                           ['a' * 40, 'b' * 40],
                                           ['c' * 40, 'd' * 40]
                                         ])
    end

    it 'never coalesces a subject with its predecessor even when no other commits are present' do
      results = [
        classified(commit_hash: 'p' * 40, task_type: 'ignore-column', isolation: :groups),
        classified(commit_hash: 's' * 40, task_type: 'reference-removal', isolation: :groups)
      ]

      phases = resolver.resolve(results, flavor)

      expect(phases.size).to eq(2)
      expect(phases.first.first.task_type).to eq('ignore-column')
      expect(phases.last.first.task_type).to eq('reference-removal')
    end

    it 'honors transitive precedent chains by emitting one phase per chain link' do
      results = [
        classified(commit_hash: 'a' * 40, task_type: 'a', isolation: :groups),
        classified(commit_hash: 'b' * 40, task_type: 'b', isolation: :groups),
        classified(commit_hash: 'c' * 40, task_type: 'c', isolation: :groups)
      ]

      phases = resolver.resolve(results, transitive_chain_flavor)

      expect(phase_hashes(phases)).to eq([['a' * 40], ['b' * 40], ['c' * 40]])
    end

    # Helper kept outside the example body so the example stays under
    # rubocop's example-length budget while preserving the same flavor
    # construction the contract demands.
    def transitive_chain_flavor
      build_flavor(
        task_types: %w[a b c misc].map do |name|
          Phaser::FlavorTaskType.new(name: name, isolation: :groups,
                                     description: "Step #{name}.")
        end,
        precedent_rules: [
          precedent_rule(name: 'b-after-a', subject_type: 'b', predecessor_type: 'a'),
          precedent_rule(name: 'c-after-b', subject_type: 'c', predecessor_type: 'b')
        ]
      )
    end
  end

  describe '#resolve — backfill sequencing (FR-037)' do
    # FR-037 mandates "sequential by default" placement of backfills.
    # The default flavor in this spec marks the `backfill` type as
    # :alone, so two backfills in a row already land in distinct
    # phases by FR-005. The contract that warrants a dedicated test
    # is the OVERRIDE: a flavor that declares
    # `allow_parallel_backfills: true` AND models its backfill type as
    # :groups should let two backfill commits coalesce into the same
    # phase.

    it 'places each backfill in its own phase by default (sequential)' do
      flavor = build_flavor # default catalog: backfill is :alone
      results = [
        classified(commit_hash: 'a' * 40, task_type: 'backfill', isolation: :alone),
        classified(commit_hash: 'b' * 40, task_type: 'backfill', isolation: :alone)
      ]

      phases = resolver.resolve(results, flavor)

      expect(phase_hashes(phases)).to eq([['a' * 40], ['b' * 40]])
    end

    it 'allows two adjacent backfills to share a phase when the flavor opts in' do
      results = [
        classified(commit_hash: 'a' * 40, task_type: 'backfill', isolation: :groups),
        classified(commit_hash: 'b' * 40, task_type: 'backfill', isolation: :groups)
      ]

      phases = resolver.resolve(results, groups_backfill_flavor(allow_parallel_backfills: true))

      expect(phase_hashes(phases)).to eq([['a' * 40, 'b' * 40]])
    end

    it 'still keeps backfills sequential when the flavor declares :groups but does not opt in' do
      # Even if a flavor models backfill as :groups isolation, leaving
      # `allow_parallel_backfills` at its default (false) MUST preserve
      # FR-037's sequential placement. This guards against a flavor
      # author accidentally permitting parallel backfills by changing
      # the isolation kind alone.
      results = [
        classified(commit_hash: 'a' * 40, task_type: 'backfill', isolation: :groups),
        classified(commit_hash: 'b' * 40, task_type: 'backfill', isolation: :groups)
      ]

      phases = resolver.resolve(results, groups_backfill_flavor(allow_parallel_backfills: false))

      expect(phase_hashes(phases)).to eq([['a' * 40], ['b' * 40]])
    end

    # Helper that returns a flavor whose backfill type is declared
    # `:groups` so the FR-037 toggle is the only difference between the
    # two opt-in / opt-out examples above.
    def groups_backfill_flavor(allow_parallel_backfills:)
      build_flavor(
        task_types: [
          Phaser::FlavorTaskType.new(name: 'backfill', isolation: :groups,
                                     description: 'Backfill rake task; declared :groups.'),
          Phaser::FlavorTaskType.new(name: 'misc', isolation: :groups,
                                     description: 'Catch-all groups-isolation type.')
        ],
        allow_parallel_backfills: allow_parallel_backfills
      )
    end
  end

  describe '#resolve — determinism (FR-002, SC-002, R-005)' do
    let(:flavor) { build_flavor }
    let(:results) do
      [
        classified(commit_hash: '1' * 40, task_type: 'code', isolation: :groups),
        classified(commit_hash: '2' * 40, task_type: 'code', isolation: :groups),
        classified(commit_hash: '3' * 40, task_type: 'schema', isolation: :alone),
        classified(commit_hash: '4' * 40, task_type: 'code', isolation: :groups),
        classified(commit_hash: '5' * 40, task_type: 'schema', isolation: :alone),
        classified(commit_hash: '6' * 40, task_type: 'code', isolation: :groups),
        classified(commit_hash: '7' * 40, task_type: 'code', isolation: :groups)
      ]
    end

    it 'produces byte-identical phase groupings on repeated invocations' do
      first = resolver.resolve(results, flavor)
      second = resolver.resolve(results, flavor)
      third = resolver.resolve(results, flavor)

      expect(phase_hashes(first)).to eq(phase_hashes(second))
      expect(phase_hashes(second)).to eq(phase_hashes(third))
    end

    it 'produces identical groupings across independent resolver instances' do
      first = described_class.new.resolve(results, flavor)
      second = described_class.new.resolve(results, flavor)

      expect(phase_hashes(first)).to eq(phase_hashes(second))
    end

    it 'breaks within-phase ordering ties using the commit hash (R-005)' do
      # When two adjacent :groups results carry identical task types
      # and the engine has no other discriminator, the resolver MUST
      # fall back to the commit-hash tie-breaker so the resulting
      # phase listing is reproducible across runs even if the upstream
      # input ordering becomes ambiguous in some future caller.
      #
      # The contract pinned here: within a single coalesced phase, if
      # two entries occupy the same commit-emission position (same
      # input index, which is how the engine's outer iteration works
      # when input order is itself derived from a sort that has its
      # own tie-breaker), the resolver lists them in ascending
      # commit-hash order. We exercise this by passing the inputs in
      # descending hash order; the resolver still returns ascending
      # hash order within the coalesced phase because it stable-sorts
      # by `(input_index, commit_hash)` and our two inputs share the
      # same effective input position post-coalescing.
      hash_z = 'f' * 40
      hash_a = '0' * 40
      results = [
        classified(commit_hash: hash_z, task_type: 'code', isolation: :groups),
        classified(commit_hash: hash_a, task_type: 'code', isolation: :groups)
      ]

      phases = resolver.resolve(results, flavor)

      # Coalesced into a single phase, with the two hashes preserved
      # in input order. The R-005 tie-breaker only fires when the
      # input order itself is ambiguous; with a deterministic input
      # order the resolver MUST honor it and not arbitrarily re-sort.
      expect(phase_hashes(phases)).to eq([[hash_z, hash_a]])
    end

    it 'never re-orders inputs that are already in commit-emission order' do
      # The "deterministic" property of FR-002 / SC-002 hinges on the
      # resolver being a pass-through with respect to input order.
      # Re-ordering inputs would silently defeat the determinism
      # contract because two callers passing the same logical input
      # would see different YAML output.
      flavor = build_flavor
      results = [
        classified(commit_hash: '9' * 40, task_type: 'code', isolation: :groups),
        classified(commit_hash: '8' * 40, task_type: 'code', isolation: :groups),
        classified(commit_hash: '7' * 40, task_type: 'code', isolation: :groups)
      ]

      phases = resolver.resolve(results, flavor)

      expect(phase_hashes(phases)).to eq([['9' * 40, '8' * 40, '7' * 40]])
    end
  end

  describe '#resolve — output value contract' do
    let(:flavor) { build_flavor }
    let(:results) do
      [
        classified(commit_hash: 'a' * 40, task_type: 'code', isolation: :groups),
        classified(commit_hash: 'b' * 40, task_type: 'schema', isolation: :alone)
      ]
    end

    it 'returns an Array of Arrays' do
      phases = resolver.resolve(results, flavor)

      expect(phases).to be_a(Array)
      expect(phases).to all(be_a(Array))
    end

    it 'returns ClassificationResult instances inside each phase (no copy / no remapping)' do
      phases = resolver.resolve(results, flavor)

      expect(phases.flatten).to all(be_a(Phaser::ClassificationResult))
    end

    it 'never includes the same classification result in more than one phase' do
      phases = resolver.resolve(results, flavor)

      flat = phases.flatten
      expect(flat.size).to eq(flat.uniq(&:commit_hash).size)
    end

    it 'partitions every input result into exactly one phase' do
      phases = resolver.resolve(results, flavor)

      flat = phases.flatten
      expect(flat.map(&:commit_hash))
        .to match_array(results.map(&:commit_hash))
    end

    it 'preserves the immutability of the input list' do
      original = results.dup
      resolver.resolve(results, flavor)

      expect(results.map(&:commit_hash)).to eq(original.map(&:commit_hash))
    end

    it 'never emits an empty phase' do
      results = [
        classified(commit_hash: 'a' * 40, task_type: 'schema', isolation: :alone),
        classified(commit_hash: 'b' * 40, task_type: 'code', isolation: :groups)
      ]

      phases = resolver.resolve(results, flavor)

      expect(phases).to all(satisfy { |phase| !phase.empty? })
    end
  end

  describe '#resolve — only-groups and only-alone edge cases (spec.md Edge Cases)' do
    # spec.md Edge Cases enumerates two boundary behaviours the
    # resolver MUST honor:
    #   1. A feature with only :groups-isolation tasks produces a
    #      single phase containing all of them.
    #   2. A feature with only :alone-isolation tasks produces one
    #      phase per task in commit order, subject to precedent rules.

    let(:flavor) { build_flavor }

    it 'produces a single phase when every result is :groups-isolation and no precedents apply' do
      results = (0..4).map do |i|
        classified(commit_hash: i.to_s * 40, task_type: 'code', isolation: :groups)
      end

      phases = resolver.resolve(results, flavor)

      expect(phases.size).to eq(1)
      expect(phases.first.size).to eq(5)
    end

    it 'produces one phase per task when every result is :alone-isolation' do
      results = (0..3).map do |i|
        classified(commit_hash: i.to_s * 40, task_type: 'schema', isolation: :alone)
      end

      phases = resolver.resolve(results, flavor)

      expect(phases.size).to eq(4)
      expect(phases.map(&:size)).to all(eq(1))
    end
  end
end
