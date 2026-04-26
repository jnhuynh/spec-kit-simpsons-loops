# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'json'
require 'stringio'
require 'tmpdir'
require 'yaml'
require 'phaser'

# The seven-commit fixture recipe is shipped by T048
# (`spec/fixtures/repos/users-email-rename/recipe.rb`). Until that
# task lands the recipe file does not exist; deferring the require to
# a `begin/rescue LoadError` (rather than a top-of-file
# `require_relative`) keeps THIS spec failing inside its examples
# (the contract surface CLAUDE.md "Test-First Development" wants)
# without breaking the load of the broader phaser test suite. Once
# T048 ships the recipe and T050..T055 ship the flavor + validators,
# the require succeeds and the examples below assert against the
# real engine output.
begin
  require_relative '../../fixtures/repos/users-email-rename/recipe'
  USERS_EMAIL_RENAME_FIXTURE_LOADED = true
rescue LoadError
  USERS_EMAIL_RENAME_FIXTURE_LOADED = false
end

# Specs for the rails-postgres-strong-migrations flavor's column-rename
# worked example end-to-end through `Phaser::Engine#process` (feature
# 007-multi-phase-pipeline; T046, FR-017, R-016, SC-001, spec.md User
# Story 2 Acceptance Scenario 6).
#
# FR-017 pins the externally observable contract:
#
#   "The reference flavor MUST ship a fixture for the worked example
#    'rename `users.email` to `users.email_address`' and the phaser
#    MUST produce exactly seven ordered phases from this fixture
#    without any operator intervention."
#
# SC-001 pins the headline measurable outcome:
#
#   "A team running the canonical column-rename worked example
#    end-to-end with the reference flavor configured produces exactly
#    seven phases, seven stacked pull requests, and zero operator
#    interventions during phasing."
#
# R-016 (research.md) pins the seven canonical commits the fixture
# replays:
#
#   1. Add `email_address` column as nullable (no default).
#   2. Add ignored-columns directive for `email`.
#   3. Dual-write to both `email` and `email_address`.
#   4. Backfill `email_address` from `email` (batched, throttled,
#      outside transaction).
#   5. Switch reads to `email_address`.
#   6. Remove all references to `email`.
#   7. Remove the ignored-columns directive AND drop the `email`
#      column.
#
# How this spec realises that contract:
#
#   * It builds the seven-commit fixture via
#     `UsersEmailRenameFixture.build(self)` (T048,
#     `spec/fixtures/repos/users-email-rename/recipe.rb`). The recipe
#     constructs a real Git repository under `Dir.mktmpdir` so the
#     fixture exercises the full `Phaser::Commit` shape — file paths,
#     diff hunks, and commit-message trailers — exactly as production
#     `bin/phaser` would read them via `git log` (T036).
#
#   * It loads the production reference flavor through
#     `Phaser::FlavorLoader#load('rails-postgres-strong-migrations')`
#     (T050 ships `flavor.yaml`; T051..T054b ship the inference,
#     forbidden-operations, backfill-safety, column-drop precedent, and
#     safety-assertion validators wired through T055's `flavor_loader.rb`
#     extension). No operator `Phase-Type:` trailer is set on any of
#     the seven commits — FR-017 demands "no operator intervention," so
#     the cascade in FR-004 collapses to "inference rule wins, or
#     default type if no rule matches" for each commit.
#
#   * It runs the production `Phaser::Engine#process` against the
#     fixture's seven commits in order, then asserts:
#       a. The engine returns the manifest path (no error raised), so
#          every gate (forbidden-ops, classifier, precedent validator,
#          backfill-safety, safety-assertion, size guard) accepts
#          every commit (the worked example is by construction
#          deploy-safe).
#       b. The manifest contains exactly seven phases (FR-017, SC-001).
#       c. The seven phases appear in the canonical R-016 order, each
#          carrying the matching task type.
#       d. The phases are 1-indexed with no gaps and the
#          stacked-PR `branch_name` / `base_branch` chain matches FR-026
#          (phase 1 based on `main`, phases 2..7 stacked on the prior
#          phase's branch).
#       e. The manifest pins the active flavor name and version
#          (FR-021, FR-035) and is byte-stable on a second run with the
#          same clock (FR-002, SC-002 — the column-rename example is
#          the canonical end-to-end determinism witness).
#
# Why a fixture-driven integration test rather than a stubbed
# `Phaser::Commit` array:
#
#   * The reference flavor's inference layer (T051) and forbidden-
#     operations gate (T052) read commit diffs via `Phaser::FileChange`
#     hunks — the same shape `bin/phaser`'s `GitCommitReader` produces.
#     Building the fixture as a real Git repo proves the inference
#     rules and the forbidden-operations detectors agree on the diff
#     shape across the read path.
#   * The backfill-safety validator (T053) inspects the rake task's
#     hunks for `find_each` / `in_batches`, sleep-throttling, and
#     `disable_ddl_transaction!`. A real diff exercises the AST-aware
#     and content-regex paths the validator uses; a stubbed diff
#     hash-literal would silently bypass them.
#   * The safety-assertion validator (T054b, FR-018) reads the commit
#     message trailer/fenced block on the column-drop commit and
#     joins against earlier commit hashes. Real Git commits give the
#     validator the actual SHAs to verify against.
#
# This spec MUST observe failure (red) before T048 ships
# `spec/fixtures/repos/users-email-rename/recipe.rb`, T050 ships the
# reference flavor's `flavor.yaml`, T051..T054b ship the validator
# modules, and T055 wires them through `flavor_loader.rb` (the
# test-first requirement in CLAUDE.md "Test-First Development"). Until
# then `require_relative` of the recipe raises `LoadError`; once the
# recipe lands, `FlavorLoader#load` raises `FlavorNotFoundError`; once
# the flavor lands, the engine's classifier or one of the validators
# raises until every collaborator agrees on every commit.
#
# Position in the test surface (per tasks.md Phase 4 dependencies):
#
#   T040 catalog_spec.rb              — flavor.yaml ships every FR-010 type
#   T041 inference_spec.rb            — inference layer hits ≥ 90 % (SC-004)
#   T042 backfill_validator_spec.rb   — backfill-safety rejects unsafe scripts
#   T043 precedent_validator_spec.rb  — column-drop requires both precedents
#   T044 forbidden_operations_spec.rb — registry rejects every entry
#   T045 operator_tag_cannot_bypass_gate_spec.rb — SC-015
#   T046 column_rename_worked_example_spec.rb (THIS SPEC) — SC-001 / FR-017
#   T046b safety_assertion_validator_spec.rb — FR-018 / D-017
#
# This spec is the convergence point: every per-validator unit test
# above asserts a single rule in isolation; this spec asserts that all
# of them together produce the seven-phase manifest the spec promises.
RSpec.describe 'rails-postgres-strong-migrations column-rename worked example' do # rubocop:disable RSpec/DescribeClass,RSpec/MultipleMemoizedHelpers
  # Surface a single, loud failure when the fixture recipe (T048) has
  # not shipped yet. Without this guard the examples below would
  # raise `NameError: uninitialized constant UsersEmailRenameFixture`
  # at the per-example level, scattering the same root cause across
  # every example. Failing once at the top of the describe block
  # points the operator at the missing dependency in a single line.
  before do
    unless USERS_EMAIL_RENAME_FIXTURE_LOADED
      raise 'spec/fixtures/repos/users-email-rename/recipe.rb is missing — ' \
            'T048 ships the seven-commit fixture recipe; this spec (T046) ' \
            'must observe failure (red) until then per CLAUDE.md ' \
            '"Test-First Development".'
    end
  end

  # Per-example feature-spec directory. The engine writes
  # `phase-manifest.yaml` here (and on validation failure
  # `phase-creation-status.yaml`). A scratch directory keeps writes
  # isolated and lets the suite assert byte-level properties of the
  # produced manifest. Mirrors the harness used by `engine_spec.rb`
  # (T026) so the integration assertions stay readable next to the
  # engine unit assertions they aggregate.
  attr_reader :feature_dir

  around do |example|
    Dir.mktmpdir('phaser-column-rename-spec') do |tmp|
      @feature_dir = tmp
      example.run
    end
  end

  # Tear down the throwaway Git fixture repo created by
  # `UsersEmailRenameFixture.build` (T048). Required by
  # `GitFixtureHelper`'s "every test that creates a temporary
  # directory must clean it up" contract per CLAUDE.md
  # "Process Hygiene".
  after { cleanup_fixture_repos }

  # Pinned clock so `generated_at` is reproducible for the byte-level
  # determinism assertion below (SC-002, FR-002). The clock is a
  # zero-arg callable mirroring the convention used by
  # `Phaser::Observability` and `Phaser::StatusWriter` and exercised by
  # `engine_spec.rb`.
  let(:fixed_clock) { -> { '2026-04-25T12:00:00.000Z' } }
  # Capture every JSON-line record the engine emits to stderr so
  # examples can assert on observability emissions when needed
  # (SC-011). Most examples below assert manifest contents, but the
  # determinism assertion uses this stream to verify the engine's
  # ERROR surface stays clean (the worked example is by construction
  # deploy-safe — every gate accepts).
  let(:stderr_io) { StringIO.new }
  # The seven `Phaser::Commit` value objects the recipe writes onto
  # the feature branch, in author order. Read via the same `git log`
  # path `bin/phaser`'s GitCommitReader uses (T036). Pinning the
  # path-translation in a single `let` keeps individual examples
  # focused on assertions about engine output, not on subprocess
  # mechanics.
  let(:fixture_commits) { read_commits_from_fixture(fixture_repo) }
  # The seven canonical phases from R-016. The names are
  # sentence-case operator-facing strings so reviewers reading the
  # manifest in code review see what each phase does. The task_type
  # values are the canonical FR-010 catalog names from
  # `catalog_spec.rb`'s `required_task_types`. The order is the safe
  # deploy sequence — reordering any pair would either break
  # deploy-safety or violate a precedent rule the reference flavor
  # enforces.
  let(:expected_phases) do
    [
      { name: /add.*nullable.*column/i,
        task_type: 'schema add-nullable-column' },
      { name: /ignor.*column/i,
        task_type: 'code ignore-column-for-pending-drop' },
      { name: /dual.?write/i,
        task_type: 'code dual-write-old-and-new-column' },
      { name: /backfill/i,
        task_type: 'data backfill-batched' },
      { name: /switch.*read/i,
        task_type: 'code switch-reads-to-new-column' },
      { name: /remove.*reference/i,
        task_type: 'code remove-references-to-pending-drop-column' },
      { name: /(remove.*ignor|drop.*column)/i,
        task_type: 'schema drop-column-with-cleanup-precedent' }
    ]
  end

  # The production reference flavor loaded via the production
  # `FlavorLoader`. The loader resolves
  # `phaser/flavors/rails-postgres-strong-migrations/flavor.yaml`,
  # validates against `contracts/flavor.schema.yaml`, and requires the
  # five Ruby validator modules (T051..T054b) wired through T055. Until
  # T050 lands this raises `Phaser::FlavorNotFoundError`.
  let(:flavor) do
    Phaser::FlavorLoader.new.load('rails-postgres-strong-migrations')
  end

  # The seven-commit Git fixture repo built at test time by
  # `UsersEmailRenameFixture.build` (T048,
  # `spec/fixtures/repos/users-email-rename/recipe.rb`). Exposed as a
  # `let!` so the repo is built before the engine runs even when the
  # example body short-circuits on an early assertion failure.
  let!(:fixture_repo) { UsersEmailRenameFixture.build(self) }

  # Build a Phaser::Engine pointed at the per-example feature_dir with
  # a fresh observability/status_writer/manifest_writer wired in. The
  # feature_branch and default_branch values mirror the recipe's
  # branch constants so manifest assertions about phase branch names
  # (FR-026: `<feature>-phase-<N>`) are reproducible.
  def build_engine(stderr: stderr_io)
    Phaser::Engine.new(
      feature_dir: feature_dir,
      feature_branch: UsersEmailRenameFixture::FEATURE_BRANCH,
      default_branch: UsersEmailRenameFixture::DEFAULT_BRANCH,
      observability: Phaser::Observability.new(stderr: stderr, now: fixed_clock),
      status_writer: Phaser::StatusWriter.new(now: fixed_clock),
      manifest_writer: Phaser::ManifestWriter.new,
      clock: fixed_clock
    )
  end

  # Read commits from the fixture repository via `git log` and
  # convert each one into a `Phaser::Commit` value object. This
  # mirrors the production CLI's reading path exactly so the
  # integration test exercises the same Commit shape the engine sees
  # in production (file paths, diff hunks via raw diff-tree output,
  # parsed trailers). The implementation deliberately matches
  # `bin/phaser`'s `GitCommitReader` so a future refactor of the
  # reader's surface is mirrored here in one place.
  def read_commits_from_fixture(repo_path)
    Dir.chdir(repo_path) do
      shas = `git log --reverse --format=%H \
        #{UsersEmailRenameFixture::DEFAULT_BRANCH}..HEAD`.each_line.map(&:strip).reject(&:empty?)
      shas.map { |sha| build_commit_from_sha(sha) }
    end
  end

  # Build a single `Phaser::Commit` from a SHA in the current Git
  # working directory. Reads the commit header (subject, ISO author
  # timestamp, trailer block) and the per-file diff via
  # `git diff-tree --no-commit-id --raw -r --root <sha>`. Helpers
  # below handle the trailer and diff parsing so this method stays
  # readable.
  def build_commit_from_sha(sha)
    subject, author_iso, trailer_block = read_commit_header(sha)
    Phaser::Commit.new(
      hash: sha,
      subject: subject,
      message_trailers: parse_trailers(trailer_block),
      diff: build_diff_for_sha(sha),
      author_timestamp: author_iso
    )
  end

  def read_commit_header(sha)
    raw = `git show --no-patch --format=%s%x1f%aI%x1f%(trailers:only,unfold) #{sha}`.chomp
    raw.split("\x1f", 3)
  end

  def parse_trailers(block)
    return {} if block.nil? || block.empty?

    trailers = {}
    block.each_line do |line|
      stripped = line.strip
      next if stripped.empty?

      key, value = stripped.split(':', 2)
      trailers[key.strip] = value.strip if value
    end
    trailers
  end

  # Build a `Phaser::Diff` for one commit by enumerating the changed
  # files via `git diff-tree --raw` and reading each file's hunks via
  # `git show <sha> -- <path>`. Mirrors `bin/phaser`'s GitCommitReader
  # surface; kept here so the integration test does not depend on the
  # CLI binary being executable.
  def build_diff_for_sha(sha)
    raw = `git diff-tree --no-commit-id --raw -r --root #{sha}`
    files = raw.each_line.map do |line|
      parts = line.strip.split(/\s+/)
      status_letter = parts[4]
      path = parts[5]
      Phaser::FileChange.new(
        path: path,
        change_kind: change_kind_for(status_letter),
        hunks: read_hunks_for(sha, path)
      )
    end
    Phaser::Diff.new(files: files)
  end

  def change_kind_for(status_letter)
    case status_letter
    when 'A' then :added
    when 'D' then :deleted
    else :modified
    end
  end

  def read_hunks_for(sha, path)
    raw = `git show --format= #{sha} -- #{path}`
    [raw]
  end

  # Path the engine writes the manifest to. Used by every example
  # below that asserts on manifest contents.
  def manifest_path
    File.join(feature_dir, 'phase-manifest.yaml')
  end

  describe '#process — produces a manifest from the seven-commit fixture' do # rubocop:disable RSpec/MultipleMemoizedHelpers
    it 'returns the absolute manifest path (no error raised — the worked example is deploy-safe)' do
      result = build_engine.process(fixture_commits, flavor)

      expect(result).to eq(manifest_path)
    end

    it 'writes phase-manifest.yaml at <feature_dir>/phase-manifest.yaml' do
      build_engine.process(fixture_commits, flavor)

      expect(File.file?(manifest_path)).to be(true)
    end

    it 'pins the active flavor name on the manifest (FR-021)' do
      build_engine.process(fixture_commits, flavor)

      expect(YAML.load_file(manifest_path)['flavor_name'])
        .to eq('rails-postgres-strong-migrations')
    end

    it 'pins the active flavor version on the manifest (FR-021, FR-035)' do
      build_engine.process(fixture_commits, flavor)

      expect(YAML.load_file(manifest_path)['flavor_version']).to match(/\A\d+\.\d+\.\d+\z/)
    end

    it 'records the fixture feature branch on the manifest (FR-021)' do
      build_engine.process(fixture_commits, flavor)

      expect(YAML.load_file(manifest_path)['feature_branch'])
        .to eq(UsersEmailRenameFixture::FEATURE_BRANCH)
    end
  end

  describe 'phase count — exactly seven phases (FR-017, SC-001)' do # rubocop:disable RSpec/MultipleMemoizedHelpers
    it 'emits exactly seven phases for the seven-commit fixture' do
      build_engine.process(fixture_commits, flavor)

      manifest = YAML.load_file(manifest_path)

      expect(manifest['phases'].length).to eq(7)
    end

    it 'numbers the seven phases 1..7 with no gaps (data-model.md Phase #number)' do
      build_engine.process(fixture_commits, flavor)

      numbers = YAML.load_file(manifest_path)['phases'].map { |p| p['number'] }

      expect(numbers).to eq([1, 2, 3, 4, 5, 6, 7])
    end

    it 'requires zero operator-supplied Phase-Type trailers (FR-017 "no operator intervention")' do
      # Every fixture commit's trailers map MUST be empty (or at least
      # contain no Phase-Type key). FR-017 demands the seven phases
      # emerge from the inference layer alone — operator tags would
      # bypass the SC-004 inference contract and silently mask
      # inference-layer regressions.
      operator_tagged = fixture_commits.select { |c| c.message_trailers.key?('Phase-Type') }

      expect(operator_tagged).to be_empty
    end
  end

  describe 'phase ordering — seven canonical R-016 phases in the canonical order' do # rubocop:disable RSpec/MultipleMemoizedHelpers
    it 'classifies each phase\'s single task with the canonical FR-010 task type' do
      build_engine.process(fixture_commits, flavor)

      manifest = YAML.load_file(manifest_path)
      actual_task_types = manifest['phases'].map do |phase|
        phase['tasks'].first['task_type']
      end
      expected_task_types = expected_phases.map { |p| p[:task_type] }

      expect(actual_task_types).to eq(expected_task_types)
    end

    it 'gives each phase a single task (every R-016 step is its own phase)' do
      build_engine.process(fixture_commits, flavor)

      manifest = YAML.load_file(manifest_path)
      task_counts = manifest['phases'].map { |p| p['tasks'].length }

      expect(task_counts).to eq([1, 1, 1, 1, 1, 1, 1])
    end

    it 'names each phase to match the canonical R-016 step (sentence-case operator-facing)' do
      build_engine.process(fixture_commits, flavor)

      manifest = YAML.load_file(manifest_path)
      manifest['phases'].each_with_index do |phase, index|
        expected = expected_phases[index]
        message = "expected phase #{index + 1} name to match " \
                  "#{expected[:name].inspect}, got #{phase['name'].inspect}"
        expect(phase['name']).to match(expected[:name]), message
      end
    end
  end

  describe 'stacked-PR chain — branch_name and base_branch follow FR-026' do # rubocop:disable RSpec/MultipleMemoizedHelpers
    it 'derives every phase\'s branch_name from the feature branch and phase number' do
      build_engine.process(fixture_commits, flavor)

      manifest = YAML.load_file(manifest_path)
      branch_names = manifest['phases'].map { |p| p['branch_name'] }
      expected = (1..7).map do |n|
        "#{UsersEmailRenameFixture::FEATURE_BRANCH}-phase-#{n}"
      end

      expect(branch_names).to eq(expected)
    end

    it 'bases phase 1 on the project default integration branch (FR-026)' do
      build_engine.process(fixture_commits, flavor)

      manifest = YAML.load_file(manifest_path)

      expect(manifest['phases'].first['base_branch'])
        .to eq(UsersEmailRenameFixture::DEFAULT_BRANCH)
    end

    it 'bases each subsequent phase on the previous phase\'s branch_name (FR-026)' do
      build_engine.process(fixture_commits, flavor)

      manifest = YAML.load_file(manifest_path)
      bases_after_first = manifest['phases'].drop(1).map { |p| p['base_branch'] }
      expected_bases = manifest['phases'].take(6).map { |p| p['branch_name'] }

      expect(bases_after_first).to eq(expected_bases)
    end
  end

  describe 'task->commit mapping — every task references its source commit hash' do # rubocop:disable RSpec/MultipleMemoizedHelpers
    it 'attaches every fixture commit\'s SHA to exactly one manifest task' do
      build_engine.process(fixture_commits, flavor)

      manifest = YAML.load_file(manifest_path)
      task_hashes = manifest['phases'].flat_map { |p| p['tasks'].map { |t| t['commit_hash'] } }
      fixture_hashes = fixture_commits.map(&:hash)

      expect(task_hashes.sort).to eq(fixture_hashes.sort)
    end

    it 'preserves fixture commit order across the seven phases (R-016 deploy sequence)' do
      build_engine.process(fixture_commits, flavor)

      manifest = YAML.load_file(manifest_path)
      task_hashes = manifest['phases'].flat_map { |p| p['tasks'].map { |t| t['commit_hash'] } }
      fixture_hashes = fixture_commits.map(&:hash)

      expect(task_hashes).to eq(fixture_hashes)
    end
  end

  describe 'determinism — byte-identical manifest across re-runs (FR-002, SC-002)' do # rubocop:disable RSpec/MultipleMemoizedHelpers
    it 'produces a byte-identical manifest when re-run with the same inputs and clock' do
      build_engine.process(fixture_commits, flavor)
      first_run = File.binread(manifest_path)

      FileUtils.rm_f(manifest_path)
      build_engine(stderr: StringIO.new).process(fixture_commits, flavor)
      second_run = File.binread(manifest_path)

      expect(second_run).to eq(first_run)
    end

    it 'emits no validation-failed ERROR records on the deploy-safe worked example' do
      build_engine.process(fixture_commits, flavor)

      records = stderr_io.string.each_line.map { |line| JSON.parse(line) }
      validation_errors = records.select { |r| r['event'] == 'validation-failed' }

      expect(validation_errors).to be_empty
    end
  end
end
