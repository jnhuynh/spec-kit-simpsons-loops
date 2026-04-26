# frozen_string_literal: true

require 'phaser'

# Specs for Phaser::SizeGuard — the FR-048 hard-bound enforcement that
# rejects any feature whose post-classification commit count exceeds 200
# or whose worst-case projected phase count exceeds 50, BEFORE any
# manifest is written (feature 007-multi-phase-pipeline; T025/T034,
# FR-009, FR-041, FR-042, FR-048, SC-014, data-model.md "Error
# Conditions" table row "Feature branch exceeds 200 non-empty commits or
# projected 50 phases").
#
# Position in the engine pipeline (per quickstart.md "Pattern:
# Pre-Classification Gate Discipline" and T035 in tasks.md):
#
#   empty-diff filter (FR-009)
#     → forbidden-operations gate (FR-049)
#     → classifier (FR-004)
#     → precedent validator (FR-006)
#     → SIZE GUARD (FR-048)                       <-- this module
#     → isolation resolver (FR-005)
#     → manifest writer (FR-002, FR-038)
#
# The guard runs AFTER classification (so each input is a
# `Phaser::ClassificationResult` carrying a normalized `isolation`
# value the worst-case phase projection can read directly) and BEFORE
# the isolation resolver and manifest writer (so a too-large feature
# never produces a partial manifest on disk). FR-048 explicitly states
# that empty-diff commits skipped under FR-009 do NOT count toward the
# 200-commit bound; the guard sees only the post-FR-009 list, so this
# is enforced by construction — the spec includes a marker example
# (the 200-commit boundary check) that pins this contract.
#
# Surface (T034 / data-model.md "Error Conditions"):
#
#   * `Phaser::SizeGuard.new` — stateless; constructed once per engine
#     run with no arguments. The two bounds (200 commits, 50 phases)
#     are encoded as constants on the class so the bounds are visible
#     at the call site and assertable from the spec without
#     introspecting the implementation. No constructor knob exists to
#     change the bounds; mirroring `ForbiddenOperationsGate`'s D-016
#     stance, the guard's bypass surface is empty by construction
#     (FR-048 is a deploy-safety guarantee, not a tunable preference).
#
#   * `#enforce(classification_results, flavor)` — given the
#     post-precedent-validation list of `Phaser::ClassificationResult`s
#     in commit-emission order and the active `Phaser::Flavor`, returns
#     the input list unchanged on success (so the engine can chain the
#     call site directly into the next pipeline stage). On violation
#     the guard raises `Phaser::SizeBoundError` carrying
#     `commit_count` (== `classification_results.length`),
#     `phase_count` (== the worst-case projected phase count), and the
#     canonical `decomposition_message` instructing the operator to
#     split the feature into smaller specs (FR-048).
#
#   * `Phaser::SizeBoundError` — exception raised by the guard.
#     Descends from `Phaser::ValidationError` so the engine's outer
#     `rescue` clause handles it uniformly with the other validation
#     failure modes (forbidden-operation, precedent, backfill-safety,
#     unknown-type-tag). Exposes `commit_count`, `phase_count`,
#     `failing_rule` (the canonical literal `"feature-too-large"` per
#     FR-041 / FR-048 / contracts/observability-events.md), and
#     `decomposition_message`. The error MUST NOT carry a
#     `commit_hash` — the failure is feature-attributable, not
#     commit-attributable, per the `validation-failed` schema's
#     "Not set for `feature-too-large`" note in
#     contracts/observability-events.md.
#
# Worst-case phase projection contract (FR-048):
#
#   * The guard simulates the smallest grouping the IsolationResolver
#     could produce GIVEN the classification results: every
#     `:alone`-isolation result occupies its own phase (so each
#     contributes exactly 1 phase); every contiguous run of
#     `:groups`-isolation results coalesces into a single phase (so a
#     run of K `:groups` results contributes 1 phase, regardless of K).
#     The worst-case count IS the count actually projected by the
#     resolver under FR-005's greedy-coalesce default — there is no
#     "worse" case to consider because precedent rules (FR-006) only
#     ever increase the phase count by forcing additional boundaries
#     that the projection already accounts for via the precedent rule's
#     subject being placed in a strictly later phase than its
#     predecessor. Because the size guard runs BEFORE the isolation
#     resolver, a 51-phase projection IS a 51-phase rejection: the
#     guard's count is computed by walking the classification result
#     list once and counting boundaries.
#
#   * The projection MUST NOT inspect the diff, the filesystem, or any
#     non-input source; it is a pure function of `(classification_result
#     isolation values, ordering)`.
#
# Determinism / no-bypass contract (FR-002, SC-002, FR-048):
#
#   * The two bounds are class constants (not constructor arguments,
#     not flavor-configurable, not environment-variable-controlled).
#   * No flag, environment variable, or commit-message trailer can
#     suppress the guard. The constructor's keyword surface is empty.
#   * The same input list ALWAYS produces the same projection, so two
#     operators running the same flavor on the same commits see the
#     same `commit_count` / `phase_count` payload.
#
# Logging / status-file contract (FR-041, FR-042, data-model.md
# "PhaseCreationStatus"):
#
#   * The engine relays `error.to_validation_failed_payload` to
#     `Observability#log_validation_failed` and `StatusWriter#write`.
#     The payload carries exactly `{failing_rule, commit_count,
#     phase_count, decomposition_message}` — NO `commit_hash`, NO
#     `missing_precedent`, NO `forbidden_operation`. The schema's
#     cross-field rule "On feature-too-large: commit_count and
#     phase_count MUST both be present" is enforced by the payload
#     shape (both fields are unconditionally populated).
#   * The guard does NOT write to stderr or to the status file
#     directly; emission is the engine's responsibility (FR-041
#     mandates exactly one `validation-failed` ERROR record per
#     failure).
RSpec.describe Phaser::SizeGuard do # rubocop:disable RSpec/SpecFilePathFormat
  subject(:guard) { described_class.new }

  # Build a minimal flavor matching the shape produced by
  # `Phaser::FlavorLoader` (T019). The size guard does not consume any
  # flavor-side rules directly — it operates purely on the
  # `ClassificationResult.isolation` values — but the engine passes the
  # flavor for symmetry with the other validators, and the spec passes
  # one too so the guard's signature stays uniform with
  # `PrecedentValidator#validate(results, flavor)` and
  # `IsolationResolver#resolve(results, flavor)`.
  def build_flavor
    Phaser::Flavor.new(
      name: 'size-guard-spec',
      version: '0.1.0',
      default_type: 'misc',
      task_types: [
        Phaser::FlavorTaskType.new(name: 'misc', isolation: :groups, description: 'misc'),
        Phaser::FlavorTaskType.new(name: 'schema', isolation: :alone, description: 'schema')
      ],
      precedent_rules: [],
      inference_rules: [],
      forbidden_operations: [],
      stack_detection: Phaser::FlavorStackDetection.new(signals: [])
    )
  end

  # Build a ClassificationResult value object directly. The guard
  # consumes the post-precedent-validation output, so each spec
  # composes the exact list of results it wants to test against
  # without going through the upstream validators.
  def classified(commit_hash:, isolation: :groups, task_type: 'misc')
    Phaser::ClassificationResult.new(
      commit_hash: commit_hash,
      task_type: task_type,
      source: :inference,
      isolation: isolation
    )
  end

  # Helper: build N classification results, each isolation-tagged
  # `:alone` so the worst-case phase projection equals N. Each commit
  # gets a unique 40-char hex hash so the value object's contract is
  # honored.
  def alone_results(count)
    (1..count).map do |index|
      classified(
        commit_hash: format('%040x', index),
        isolation: :alone,
        task_type: 'schema'
      )
    end
  end

  # Helper: build N classification results, each isolation-tagged
  # `:groups`. Under FR-005's greedy-coalesce default, all N collapse
  # into a single projected phase regardless of N.
  def groups_results(count)
    (1..count).map do |index|
      classified(
        commit_hash: format('%040x', index),
        isolation: :groups,
        task_type: 'misc'
      )
    end
  end

  describe 'class-level bound constants (FR-048)' do
    it 'pins MAX_COMMITS to 200' do
      # The bound is documented as 200 in spec.md FR-048 and in the
      # data-model.md error-conditions table. We assert the constant
      # is exposed (rather than buried inside the implementation) so
      # operators reading the source see the threshold at a glance and
      # so the spec catches any future drift.
      expect(described_class::MAX_COMMITS).to eq(200)
    end

    it 'pins MAX_PHASES to 50' do
      expect(described_class::MAX_PHASES).to eq(50)
    end

    it 'pins FAILING_RULE to the canonical "feature-too-large" literal' do
      # FR-041 / contracts/observability-events.md: the literal
      # `failing_rule` value for the FR-048 size-bound rejection is
      # exactly "feature-too-large". Pinning the constant keeps the
      # ERROR record's wire shape stable across implementations.
      expect(described_class::FAILING_RULE).to eq('feature-too-large')
    end
  end

  describe 'constructor surface (no-bypass contract per FR-048)' do
    it 'accepts no constructor arguments' do
      # The bypass surface that matters most is the constructor: if a
      # `max_commits:` / `max_phases:` / `disable:` keyword existed an
      # operator could plausibly find a way to set it from the engine.
      # We assert the parameter list is empty, matching the
      # ForbiddenOperationsGate's D-016 stance for the size-bound
      # guard's adjacent deploy-safety contract.
      keyword_params = described_class.instance_method(:initialize).parameters

      expect(keyword_params).to eq([])
    end

    it 'does not consult environment variables to decide whether to evaluate' do
      # Environment-variable bypasses are out-of-band by definition; we
      # set a constellation of plausible names with permissive values
      # and confirm the guard's decision is unchanged.
      bypass_env = {
        'PHASER_SKIP_SIZE_GUARD' => '1',
        'PHASER_DISABLE_SIZE_BOUNDS' => '1',
        'PHASER_MAX_COMMITS' => '99999',
        'PHASER_MAX_PHASES' => '99999',
        'SKIP_SIZE_GUARD' => '1'
      }

      with_env(bypass_env) do
        expect { guard.enforce(alone_results(201), build_flavor) }
          .to raise_error(Phaser::SizeBoundError)
      end
    end
  end

  # Set the given env vars for the duration of the block, restoring the
  # prior state (including absence) on return. Extracted as a helper to
  # keep the bypass-env example body within rubocop's example-length
  # budget.
  def with_env(overrides)
    original = overrides.keys.to_h { |k| [k, ENV.fetch(k, nil)] }
    overrides.each { |k, v| ENV[k] = v }
    yield
  ensure
    original.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  describe '#enforce — happy paths (within bounds)' do
    let(:flavor) { build_flavor }

    it 'returns the input list unchanged when given an empty list' do
      expect(guard.enforce([], flavor)).to eq([])
    end

    it 'returns the input list unchanged at the 200-commit boundary' do
      # FR-048 phrases the bound as "more than 200 non-empty commits"
      # (spec.md edge-cases) and "200 non-empty commits and 50 emitted
      # phases" as accepted (FR-048). 200 is therefore the MAXIMUM
      # accepted count — 201 is the first rejected count. We pin both
      # ends of the boundary in adjacent examples.
      results = groups_results(200)

      expect(guard.enforce(results, flavor)).to eq(results)
    end

    it 'returns the input list unchanged at the 50-phase boundary' do
      results = alone_results(50)

      expect(guard.enforce(results, flavor)).to eq(results)
    end

    it 'returns the input list unchanged for a mixed groups+alone projection within bounds' do
      # Mixed example: 5 :alone results + a contiguous run of 100
      # :groups results (which collapses into 1 projected phase) +
      # 4 more :alone results = 5 + 1 + 4 = 10 projected phases, well
      # within MAX_PHASES. The point is to exercise the projection's
      # boundary-counting logic on a realistic input.
      head = alone_results(5)
      # Renumber the middle/tail hashes so they don't collide with head.
      middle = (1..100).map do |i|
        classified(commit_hash: format('%040x', 1000 + i), isolation: :groups, task_type: 'misc')
      end
      tail = (1..4).map do |i|
        classified(commit_hash: format('%040x', 2000 + i), isolation: :alone, task_type: 'schema')
      end
      results = head + middle + tail

      expect(guard.enforce(results, flavor)).to eq(results)
    end
  end

  describe '#enforce — commit-count bound (FR-048; SC-014 first half)' do
    let(:flavor) { build_flavor }

    it 'raises Phaser::SizeBoundError when commit count exceeds 200' do
      # SC-014 explicitly constructs a "201 non-empty commits" feature
      # to verify this rejection path. We use the smallest possible
      # over-bound input (201 :groups results, which projects to
      # exactly 1 phase) so the example isolates the COMMIT-bound
      # rejection from the phase-bound rejection that follows below.
      results = groups_results(201)

      expect { guard.enforce(results, flavor) }
        .to raise_error(Phaser::SizeBoundError)
    end

    it 'reports commit_count == 201 on the error for the SC-014 boundary input' do
      results = groups_results(201)

      guard.enforce(results, flavor)
    rescue Phaser::SizeBoundError => e
      expect(e.commit_count).to eq(201)
    end

    it 'reports phase_count even when the rejection was triggered by the commit bound' do
      # FR-048 requires BOTH `commit_count` and `phase_count` on the
      # payload regardless of which bound was tripped — the operator
      # sees both numbers and understands the feature's full size
      # profile (the data-model.md error-conditions table lists both
      # fields unconditionally).
      results = groups_results(201)

      guard.enforce(results, flavor)
    rescue Phaser::SizeBoundError => e
      expect(e.phase_count).to eq(1) # 201 :groups → 1 coalesced phase
    end

    it 'sets failing_rule to the canonical "feature-too-large" literal (FR-041)' do
      results = groups_results(201)

      guard.enforce(results, flavor)
    rescue Phaser::SizeBoundError => e
      expect(e.failing_rule).to eq('feature-too-large')
    end

    it 'instructs the operator to split the feature in the decomposition_message (FR-048)' do
      # FR-048: "decomposition_message that instructs the operator to
      # split the feature into multiple smaller specs". SC-008
      # (precise error messages) requires the maintainer can diagnose
      # the failure from the message alone — the most actionable next
      # step IS "split the feature", so the message's content is
      # contractual.
      results = groups_results(201)

      guard.enforce(results, flavor)
    rescue Phaser::SizeBoundError => e
      expect(e.decomposition_message).to match(/split/i)
    end
  end

  describe '#enforce — phase-count bound (FR-048; SC-014 second half)' do
    let(:flavor) { build_flavor }

    it 'raises Phaser::SizeBoundError when projected phase count exceeds 50' do
      # SC-014 explicitly constructs a "51 phases" projection to
      # verify this rejection path. 51 :alone results project to 51
      # phases (one per result under FR-005's :alone isolation rule)
      # while keeping the commit count well below 200 — so this
      # example isolates the PHASE-bound rejection from the
      # commit-bound rejection above.
      results = alone_results(51)

      expect { guard.enforce(results, flavor) }
        .to raise_error(Phaser::SizeBoundError)
    end

    it 'reports phase_count == 51 on the error for the SC-014 boundary input' do
      results = alone_results(51)

      guard.enforce(results, flavor)
    rescue Phaser::SizeBoundError => e
      expect(e.phase_count).to eq(51)
    end

    it 'reports commit_count even when the rejection was triggered by the phase bound' do
      results = alone_results(51)

      guard.enforce(results, flavor)
    rescue Phaser::SizeBoundError => e
      expect(e.commit_count).to eq(51)
    end

    it 'sets failing_rule to the canonical "feature-too-large" literal (FR-041)' do
      results = alone_results(51)

      guard.enforce(results, flavor)
    rescue Phaser::SizeBoundError => e
      expect(e.failing_rule).to eq('feature-too-large')
    end
  end

  describe '#enforce — worst-case phase projection (FR-005 + FR-048)' do
    let(:flavor) { build_flavor }

    it 'projects each :alone result as its own phase' do
      # 51 :alone → 51 phases. Pinned in the rejection example above;
      # this example is here for completeness so the projection
      # contract is documented end-to-end.
      results = alone_results(50)

      # 50 :alone is exactly at the boundary, so this MUST NOT raise.
      expect { guard.enforce(results, flavor) }.not_to raise_error
    end

    it 'projects a contiguous :groups run as a single phase regardless of length' do
      # 199 :groups (well under MAX_COMMITS) projects to 1 phase. We
      # assert the run does not raise — if the projection were
      # incorrectly counting one-phase-per-:groups-result, this would
      # raise on the phase bound.
      results = groups_results(199)

      expect { guard.enforce(results, flavor) }.not_to raise_error
    end

    it 'projects an :alone-separated :groups run as multiple phases' do
      # Construct a "comb" of 25 alternating singletons:
      #   alone, groups, alone, groups, ...
      # Each :alone is 1 phase. Each contiguous :groups run between
      # two :alones is also 1 phase (a singleton run). 50 alternating
      # singletons project to 50 phases — at the boundary. We pin
      # both at-the-boundary acceptance and just-over-the-boundary
      # rejection in adjacent examples.
      results = (1..50).map do |i|
        classified(
          commit_hash: format('%040x', i),
          isolation: i.odd? ? :alone : :groups,
          task_type: i.odd? ? 'schema' : 'misc'
        )
      end

      expect { guard.enforce(results, flavor) }.not_to raise_error
    end

    it 'rejects 51 alternating :alone/:groups singletons as 51 projected phases' do
      results = (1..51).map do |i|
        classified(
          commit_hash: format('%040x', i),
          isolation: i.odd? ? :alone : :groups,
          task_type: i.odd? ? 'schema' : 'misc'
        )
      end

      guard.enforce(results, flavor)
    rescue Phaser::SizeBoundError => e
      expect(e.phase_count).to eq(51)
      expect(e.commit_count).to eq(51)
    end
  end

  describe '#enforce — input not mutated (immutability per Data.define convention)' do
    let(:flavor) { build_flavor }

    it 'does not mutate the input list on a successful pass' do
      results = groups_results(10)
      original = results.dup

      guard.enforce(results, flavor)

      expect(results).to eq(original)
    end

    it 'returns the SAME object reference on a successful pass' do
      # The guard is a pure check — if the bounds hold, it returns the
      # input unchanged. Returning the same array reference (not a
      # defensive copy) keeps the engine's call-site allocation profile
      # flat and signals the guard does not produce a "new" view of
      # the data.
      results = groups_results(10)

      expect(guard.enforce(results, flavor)).to be(results)
    end
  end

  describe 'Phaser::SizeBoundError — payload contract (FR-041, FR-042)' do
    it 'descends from Phaser::ValidationError so the engine can rescue uniformly' do
      expect(Phaser::SizeBoundError).to be < Phaser::ValidationError
    end

    it 'is raisable with explicit commit_count and phase_count' do
      error = Phaser::SizeBoundError.new(commit_count: 201, phase_count: 1)

      expect(error).to be_a(Phaser::SizeBoundError)
      expect(error.commit_count).to eq(201)
      expect(error.phase_count).to eq(1)
    end

    it 'exposes failing_rule as the canonical "feature-too-large" literal regardless of which bound tripped' do
      commit_bound_error = Phaser::SizeBoundError.new(commit_count: 201, phase_count: 1)
      phase_bound_error = Phaser::SizeBoundError.new(commit_count: 51, phase_count: 51)

      expect(commit_bound_error.failing_rule).to eq('feature-too-large')
      expect(phase_bound_error.failing_rule).to eq('feature-too-large')
    end

    it 'exposes a non-empty decomposition_message that mentions splitting the feature' do
      error = Phaser::SizeBoundError.new(commit_count: 201, phase_count: 1)

      expect(error.decomposition_message).to be_a(String)
      expect(error.decomposition_message).not_to be_empty
      expect(error.decomposition_message).to match(/split/i)
    end

    it 'serializes to the validation-failed ERROR payload shape per FR-041' do
      # The engine relays the four payload fields to
      # `Observability#log_validation_failed` (FR-041) and to
      # `StatusWriter#write` (FR-042). The error object exposes
      # `to_validation_failed_payload` so the engine does not have to
      # know the bound's internal computation.
      error = Phaser::SizeBoundError.new(commit_count: 201, phase_count: 1)

      payload = error.to_validation_failed_payload

      expect(payload).to eq(
        failing_rule: 'feature-too-large',
        commit_count: 201,
        phase_count: 1,
        decomposition_message: error.decomposition_message
      )
    end

    it 'omits commit_hash from the payload (failure is feature-attributable, not commit-attributable)' do
      # contracts/observability-events.md `validation-failed`:
      # "commit_hash ... Not set for `feature-too-large`." The
      # phase-creation-status.schema.yaml's commit_hash field is
      # likewise scoped to commit-attributable failures. We assert the
      # payload does NOT carry the key so the resulting YAML / JSON
      # records remain schema-valid for the feature-too-large mode.
      error = Phaser::SizeBoundError.new(commit_count: 201, phase_count: 1)
      payload = error.to_validation_failed_payload

      expect(payload).not_to include(:commit_hash)
    end

    it 'omits fields the feature-too-large mode does not populate (missing_precedent etc.)' do
      # The validation-failed schema permits these keys for OTHER
      # failure modes (`precedent` populates missing_precedent;
      # `forbidden-operation` populates forbidden_operation). The
      # feature-too-large rejection path MUST NOT emit them so the
      # operator-facing record is precise about which rule fired.
      error = Phaser::SizeBoundError.new(commit_count: 201, phase_count: 1)
      payload = error.to_validation_failed_payload

      expect(payload).not_to include(:missing_precedent, :forbidden_operation)
    end

    it 'puts both bounds in the human-readable message (SC-008 precise error messages)' do
      # SC-008: a maintainer can diagnose the failure from the
      # message alone, without reading the engine source. The two
      # numbers that uniquely identify the failure mode are
      # commit_count and phase_count; both belong in the message.
      error = Phaser::SizeBoundError.new(commit_count: 201, phase_count: 1)

      expect(error.message).to include('201')
      expect(error.message).to include('1')
    end
  end
end
