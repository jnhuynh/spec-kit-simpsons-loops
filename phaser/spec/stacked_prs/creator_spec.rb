# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'json'
require 'stringio'
require 'tmpdir'
require 'yaml'
require 'phaser'

# Specs for Phaser::StackedPrs::Creator — the orchestrator that walks
# the phase manifest, queries `gh` for each phase's branch and PR, and
# either skips, creates, or halts with an idempotent resume point
# (feature 007-multi-phase-pipeline; T068/T075, FR-026, FR-027,
# FR-028, FR-029, FR-039, FR-040, FR-046, FR-047, SC-010, SC-013,
# plan.md "Pattern: Idempotent Stacked-PR Creator" / D-012).
#
# The Creator is the single load-bearing surface for two contracts:
#
#   1. **Idempotent resume (SC-010, FR-040).** When stacked-branch or
#      stacked-PR creation fails partway through phase K of an N-phase
#      manifest, the Creator MUST:
#        (a) leave phases 1..K-1 (the successfully created ones) and
#            phase K's partial state alone — never delete or modify a
#            branch or PR that already exists on the host;
#        (b) write `<feature_dir>/phase-creation-status.yaml` with
#            `stage: stacked-pr-creation`, the classified `failure_class`,
#            and `first_uncreated_phase: K`;
#        (c) exit non-zero so the pipeline halts.
#      A subsequent re-run MUST:
#        (d) read the manifest fresh (the manifest is the source of
#            truth, not the status file);
#        (e) for each phase, query `gh` for the branch and PR, skip
#            phases whose branch+PR already exist with the manifest's
#            expected base branch, and resume creation at the first
#            phase whose branch is missing;
#        (f) on full success, delete the status file (FR-040).
#
#   2. **Phase-by-phase creation (FR-026, FR-027).** For each
#      uncreated phase, the Creator:
#        (a) creates the phase branch via `gh api` from the previous
#            phase's branch (or the default integration branch for
#            phase 1);
#        (b) creates the phase PR via `gh pr create` with the
#            manifest's rationale and rollback note in the body, and a
#            link to the previous phase's PR for phases 2..N;
#        (c) emits one `phase-branch-created` and one
#            `phase-pr-created` INFO event per phase.
#
# The system-under-test (Phaser::StackedPrs::Creator) is implementation-
# not-yet-written (T075 lands after this spec). Each example below
# stubs the GitHostCli wrapper with `allow(...).to receive(...)` so the
# tests observe the Creator's behaviour without binding to the
# wrapper's internals (that is git_host_cli_spec.rb's job).
RSpec.describe 'Phaser::StackedPrs::Creator' do # rubocop:disable RSpec/MultipleMemoizedHelpers
  # The system-under-test is constructed per-example with collaborators
  # replaced by lightweight test doubles. The doubles let the spec
  # observe the exact arguments the Creator passes to each collaborator
  # without depending on the (still-to-be-implemented) GitHostCli
  # production class.
  subject(:creator) do
    Phaser::StackedPrs::Creator.new(
      git_host_cli: git_host_cli,
      failure_classifier: failure_classifier,
      status_writer: status_writer,
      observability: observability
    )
  end

  # A scratch feature directory per example so the manifest-read and
  # status-file-write cycles are isolated; mirrors the idiom used by
  # auth_probe_spec.rb.
  attr_reader :feature_dir

  around do |example|
    Dir.mktmpdir('phaser-creator-spec') do |tmp|
      @feature_dir = tmp
      example.run
    end
  end

  let(:manifest_path) { File.join(feature_dir, 'phase-manifest.yaml') }
  let(:status_path) { File.join(feature_dir, 'phase-creation-status.yaml') }

  # Test double for the gh subprocess wrapper. Production wraps every
  # gh invocation through a single Open3.capture3 facade; here we stub
  # the `#run` surface so each example can simulate one gh outcome at
  # a time. A plain `double` is used (rather than `instance_double`)
  # because the production GitHostCli class is implemented in T072 and
  # the spec deliberately stays decoupled from its constant identity
  # to keep the contract narrow.
  let(:git_host_cli) { double('GitHostCli') } # rubocop:disable RSpec/VerifiedDoubles

  # Test double for the failure classifier (T073). The Creator
  # delegates the exit-code → failure_class mapping so the policy
  # lives in one place and the Creator never inspects gh's exit-code
  # semantics directly.
  let(:failure_classifier) { double('FailureClassifier') } # rubocop:disable RSpec/VerifiedDoubles

  # Real status writer with a pinned clock so the on-disk YAML is
  # reproducible across runs. The Creator MUST persist failures via
  # this collaborator, not write YAML directly.
  let(:fixed_timestamp) { '2026-04-25T12:00:00.000Z' }
  let(:status_writer) { Phaser::StatusWriter.new(now: -> { fixed_timestamp }) }

  # Captured stderr stream so observability events can be asserted on.
  let(:stderr_buffer) { StringIO.new }
  let(:observability) { Phaser::Observability.new(stderr: stderr_buffer, now: -> { fixed_timestamp }) }

  # Default feature/integration branch names used by every fixture
  # below so the helper signatures stay short enough to satisfy the
  # community-default parameter-list and line-length cops while still
  # making the per-phase contract observable. Declared as `let` rather
  # than constants so the values stay scoped to the spec block (the
  # rubocop-rspec LeakyConstantDeclaration cop forbids constant
  # declarations inside RSpec blocks).
  let(:feature_branch) { 'feat-007-multi-phase-pipeline' }
  let(:default_branch) { 'main' }

  # Default stderr for a network-class failure used by the SC-010
  # canonical fixture. Pulled out of the helper signature so the cop's
  # parameter-list and line-length limits stay quiet without sacrificing
  # readability at the call site.
  let(:default_network_stderr) { 'dial tcp: lookup api.github.com: no such host' }

  # Helper: parse the captured stderr buffer into one Hash per
  # newline-terminated JSON record.
  def captured_events
    stderr_buffer.string.each_line.map { |line| JSON.parse(line.chomp) }
  end

  # Helper: build a (stdout, stderr, status)-shaped result that the
  # GitHostCli wrapper's #run method returns. Built inline with
  # Struct.new so the spec stays free of leaky top-level constants.
  def gh_result(stdout: '', stderr: '', exitstatus: 0)
    status_double = instance_double(Process::Status, exitstatus: exitstatus, success?: exitstatus.zero?)
    Struct.new(:stdout, :stderr, :status, keyword_init: true).new(
      stdout: stdout,
      stderr: stderr,
      status: status_double
    )
  end

  # Helper: write a synthetic N-phase manifest to disk so the Creator
  # has something to read. The manifest follows the exact schema from
  # contracts/phase-manifest.schema.yaml so we exercise the
  # production read path, not a stripped-down stub.
  def write_manifest(phase_count:)
    phases = (1..phase_count).map { |n| build_phase_hash(n) }
    File.write(manifest_path, YAML.dump(build_manifest_hash(phases)))
  end

  def build_phase_hash(number)
    {
      'number' => number,
      'name' => "Phase #{number}: example task",
      'branch_name' => "#{feature_branch}-phase-#{number}",
      'base_branch' => number == 1 ? default_branch : "#{feature_branch}-phase-#{number - 1}",
      'tasks' => [build_task_hash(number)],
      'ci_gates' => [],
      'rollback_note' => "Rollback guidance for phase #{number}."
    }
  end

  def build_task_hash(number)
    {
      'id' => "phase-#{number}-task-1",
      'task_type' => 'example task',
      'commit_hash' => format('%040x', number),
      'commit_subject' => "Example commit for phase #{number}"
    }
  end

  def build_manifest_hash(phases)
    {
      'flavor_name' => 'example-minimal',
      'flavor_version' => '0.1.0',
      'feature_branch' => feature_branch,
      'generated_at' => fixed_timestamp,
      'phases' => phases
    }
  end

  # Helper: stub gh queries that ask whether a branch exists. The
  # Creator's "is this phase already created?" check goes through gh
  # rather than poking the local git tree so the host's view of the
  # world is authoritative. Production uses
  # `gh api repos/:owner/:repo/branches/<branch>` which returns a JSON
  # body on success or exits non-zero on 404.
  def stub_branch_query(branch_name:, exists:)
    args = ['api', "repos/:owner/:repo/branches/#{branch_name}"]
    if exists
      allow(git_host_cli).to receive(:run).with(args).and_return(
        gh_result(stdout: %({"name":"#{branch_name}"}), exitstatus: 0)
      )
    else
      allow(git_host_cli).to receive(:run).with(args).and_return(
        gh_result(stderr: 'gh: Not Found (HTTP 404)', exitstatus: 1)
      )
    end
  end

  # Helper: stub gh queries that ask whether a PR exists for a head
  # branch. Production uses `gh pr list --head <branch> --json
  # number,baseRefName --limit 1`.
  def stub_pr_query(branch_name:, exists:, pr_number: nil, base_branch: nil)
    args = ['pr', 'list', '--head', branch_name, '--json', 'number,baseRefName', '--limit', '1']
    if exists
      json = JSON.generate([{ 'number' => pr_number, 'baseRefName' => base_branch }])
      allow(git_host_cli).to receive(:run).with(args).and_return(
        gh_result(stdout: json, exitstatus: 0)
      )
    else
      allow(git_host_cli).to receive(:run).with(args).and_return(
        gh_result(stdout: '[]', exitstatus: 0)
      )
    end
  end

  # Helper: stub branch creation succeeding for a phase. The Creator's
  # branch-creation contract is stable on the call SHAPE but the exact
  # arg vector is implementation-defined. We accept any args whose
  # first elements match the expected API endpoint so the spec doesn't
  # over-constrain the wrapper's encoding choices. The unused
  # `base_branch:` keyword is accepted for call-site symmetry with the
  # other stub helpers.
  def stub_branch_create(branch_name:, base_branch: nil)
    _ = base_branch
    allow(git_host_cli).to receive(:run).with(satisfy { |a|
      a[0] == 'api' && a.include?('--method') && a.include?('POST') &&
        a.any? { |s| s.include?("ref=refs/heads/#{branch_name}") }
    }).and_return(gh_result(stdout: %({"ref":"refs/heads/#{branch_name}"}), exitstatus: 0))
  end

  # Helper: stub PR creation succeeding for a phase.
  def stub_pr_create(branch_name:, base_branch:, pr_number:)
    pr_url = "https://github.com/owner/repo/pull/#{pr_number}"
    allow(git_host_cli).to receive(:run).with(satisfy { |a|
      a[0] == 'pr' && a[1] == 'create' &&
        a.include?('--head') && a.include?(branch_name) &&
        a.include?('--base') && a.include?(base_branch)
    }).and_return(gh_result(stdout: "#{pr_url}\n", exitstatus: 0))
  end

  # Helper: derive the canonical branch + base-branch names for phase N.
  def phase_branch_for(number)
    "#{feature_branch}-phase-#{number}"
  end

  def base_branch_for(number)
    number == 1 ? default_branch : phase_branch_for(number - 1)
  end

  # Helper: stub the per-phase happy-path sequence (branch missing →
  # PR missing → branch create → PR create) for one phase.
  def stub_phase_creation_succeeds(phase_number:, base_pr: 100)
    branch_name = phase_branch_for(phase_number)
    base_branch = base_branch_for(phase_number)

    stub_branch_query(branch_name: branch_name, exists: false)
    stub_pr_query(branch_name: branch_name, exists: false)
    stub_branch_create(branch_name: branch_name, base_branch: base_branch)
    stub_pr_create(branch_name: branch_name, base_branch: base_branch, pr_number: base_pr + phase_number)
  end

  # Helper: stub the per-phase already-exists sequence so the Creator
  # short-circuits and emits a `phase-skipped-existing` event.
  def stub_phase_already_exists(phase_number:, base_pr: 100)
    branch_name = phase_branch_for(phase_number)
    base_branch = base_branch_for(phase_number)

    stub_branch_query(branch_name: branch_name, exists: true)
    stub_pr_query(
      branch_name: branch_name,
      exists: true,
      pr_number: base_pr + phase_number,
      base_branch: base_branch
    )
  end

  # Helper: stub a phase's branch-create returning a network-class
  # failure so the Creator records the failure_class and bails.
  def stub_phase_branch_create_fails(phase_number:, stderr: nil,
                                     exitstatus: 1, failure_class: :network)
    stderr ||= default_network_stderr
    branch_name = phase_branch_for(phase_number)
    stub_branch_query(branch_name: branch_name, exists: false)
    stub_pr_query(branch_name: branch_name, exists: false)
    stub_branch_create_failure(branch_name: branch_name, stderr: stderr, exitstatus: exitstatus)
    allow(failure_classifier).to receive(:classify).with(
      exit_code: exitstatus, stderr: a_string_including(stderr.split.first)
    ).and_return(failure_class)
  end

  def stub_branch_create_failure(branch_name:, stderr:, exitstatus:)
    allow(git_host_cli).to receive(:run).with(satisfy { |a|
      a[0] == 'api' && a.include?('--method') && a.include?('POST') &&
        a.any? { |s| s.include?("ref=refs/heads/#{branch_name}") }
    }).and_return(gh_result(stderr: stderr, exitstatus: exitstatus))
  end

  describe 'happy path — N-phase manifest with no prior state' do # rubocop:disable RSpec/MultipleMemoizedHelpers
    let(:phase_count) { 3 }

    before do
      write_manifest(phase_count: phase_count)
      (1..phase_count).each { |n| stub_phase_creation_succeeds(phase_number: n) }
    end

    it 'returns a successful result' do
      result = creator.create(feature_dir: feature_dir)

      expect(result.success?).to be(true)
    end

    it 'reports every phase as created in result.phases_created' do
      result = creator.create(feature_dir: feature_dir)

      expect(result.phases_created).to eq([1, 2, 3])
    end

    it 'reports an empty phases_skipped_existing on a fresh run' do
      result = creator.create(feature_dir: feature_dir)

      expect(result.phases_skipped_existing).to eq([])
    end

    it 'emits one phase-branch-created INFO event per phase' do
      creator.create(feature_dir: feature_dir)

      events = captured_events.select { |e| e['event'] == 'phase-branch-created' }
      expect(events.length).to eq(phase_count)
    end

    it 'emits one phase-pr-created INFO event per phase' do
      creator.create(feature_dir: feature_dir)

      events = captured_events.select { |e| e['event'] == 'phase-pr-created' }
      expect(events.length).to eq(phase_count)
    end

    it 'records linked_to_previous_pr=false on phase 1 and =true on phases 2..N (FR-027)' do
      creator.create(feature_dir: feature_dir)

      events = captured_events.select { |e| e['event'] == 'phase-pr-created' }
                              .sort_by { |e| e['phase_number'] }
      expect(events.first['linked_to_previous_pr']).to be(false)
      expect(events.drop(1).map { |e| e['linked_to_previous_pr'] }).to all(be(true))
    end

    it 'does not write phase-creation-status.yaml on success' do
      creator.create(feature_dir: feature_dir)

      expect(File.exist?(status_path)).to be(false)
    end

    it 'deletes any pre-existing phase-creation-status.yaml on success (FR-040)' do
      File.write(status_path, "stage: stacked-pr-creation\nfailure_class: other\nfirst_uncreated_phase: 2\n")

      creator.create(feature_dir: feature_dir)

      expect(File.exist?(status_path)).to be(false)
    end
  end

  describe 'failure injected between phase K and phase K+1 of an N-phase manifest (SC-010)' do # rubocop:disable RSpec/MultipleMemoizedHelpers
    # The canonical SC-010 fixture: 5 phases, failure injected between
    # phase 2 (succeeds) and phase 3 (branch-create fails). Phases 1..2
    # MUST be untouched; phases 3..5 MUST not be created; the status
    # file MUST record first_uncreated_phase=3.
    let(:phase_count) { 5 }
    let(:failed_phase) { 3 }

    before do
      write_manifest(phase_count: phase_count)
      (1...failed_phase).each { |n| stub_phase_creation_succeeds(phase_number: n) }
      stub_phase_branch_create_fails(phase_number: failed_phase)
      # Phases failed_phase+1..N MUST NOT be queried — but to make the
      # test robust against subtle pipeline ordering bugs that touch
      # later phases, stub them as never-touched and assert below.
    end

    it 'returns a failure result' do
      result = creator.create(feature_dir: feature_dir)

      expect(result.success?).to be(false)
    end

    it 'reports phases 1..K-1 in phases_created (only the successfully completed ones)' do
      result = creator.create(feature_dir: feature_dir)

      expect(result.phases_created).to eq([1, 2])
    end

    it 'writes phase-creation-status.yaml at the feature dir (FR-039)' do
      creator.create(feature_dir: feature_dir)

      expect(File.exist?(status_path)).to be(true)
    end

    it 'writes stage=stacked-pr-creation in the status file (FR-039)' do
      creator.create(feature_dir: feature_dir)

      parsed = YAML.safe_load_file(status_path)
      expect(parsed['stage']).to eq('stacked-pr-creation')
    end

    it 'writes the classified failure_class in the status file (FR-046)' do
      creator.create(feature_dir: feature_dir)

      parsed = YAML.safe_load_file(status_path)
      expect(parsed['failure_class']).to eq('network')
    end

    it 'writes first_uncreated_phase=K in the status file (FR-039, SC-010)' do
      creator.create(feature_dir: feature_dir)

      parsed = YAML.safe_load_file(status_path)
      expect(parsed['first_uncreated_phase']).to eq(failed_phase)
    end

    it 'never queries gh for phases K+1..N (the run halts on the failed phase)' do
      creator.create(feature_dir: feature_dir)

      ((failed_phase + 1)..phase_count).each do |n|
        expect(git_host_cli).not_to have_received(:run).with(
          ['api', "repos/:owner/:repo/branches/#{phase_branch_for(n)}"]
        )
      end
    end

    it 'never deletes or modifies phases 1..K-1 (FR-039)' do
      creator.create(feature_dir: feature_dir)

      # The Creator's gh call surface MUST NOT include any DELETE
      # method invocation for any branch or PR. The contract is "phases
      # already created in this run are left intact" — verify that no
      # DELETE-style API calls were issued at all.
      delete_calls = RSpec::Mocks.space.proxy_for(git_host_cli).messages_arg_list.select do |args|
        args.first.is_a?(Array) && args.first.include?('--method') &&
          args.first.include?('DELETE')
      end
      expect(delete_calls).to be_empty
    rescue NoMethodError
      # Older RSpec internals don't expose proxy messages_arg_list.
      # Fall back to asserting the wrapper was never called with a
      # gh subcommand that mutates existing branches/PRs.
      expect(git_host_cli).not_to have_received(:run).with(satisfy { |a|
        a.include?('--method') && a.include?('DELETE')
      })
    end

    it 'emits exactly one phase-creation-failed ERROR event for phase K' do
      creator.create(feature_dir: feature_dir)

      events = captured_events.select { |e| e['event'] == 'phase-creation-failed' }
      expect(events.length).to eq(1)
      expect(events.first).to include(
        'level' => 'ERROR',
        'phase_number' => failed_phase,
        'failure_class' => 'network'
      )
    end
  end

  describe 'idempotent re-run after partial failure (SC-010, FR-040)' do # rubocop:disable RSpec/MultipleMemoizedHelpers
    # Same canonical fixture: 5 phases, prior run failed at phase 3.
    # The re-run sees phases 1..2 already exist on the host, queries
    # them, skips them, and proceeds to create phases 3..5.
    let(:phase_count) { 5 }
    let(:resume_at) { 3 }

    before do
      write_manifest(phase_count: phase_count)
      # Pre-existing status file from the prior failed run.
      File.write(status_path, <<~YAML)
        stage: stacked-pr-creation
        timestamp: '#{fixed_timestamp}'
        failure_class: network
        first_uncreated_phase: #{resume_at}
      YAML
      # Phases 1..K-1 already exist on the host (the prior run created
      # them).
      (1...resume_at).each { |n| stub_phase_already_exists(phase_number: n) }
      # Phases K..N do not exist; the re-run creates them.
      (resume_at..phase_count).each { |n| stub_phase_creation_succeeds(phase_number: n) }
    end

    it 'returns a successful result on the re-run' do
      result = creator.create(feature_dir: feature_dir)

      expect(result.success?).to be(true)
    end

    it 'reports phases K..N in phases_created (only the new ones)' do
      result = creator.create(feature_dir: feature_dir)

      expect(result.phases_created).to eq([3, 4, 5])
    end

    it 'reports phases 1..K-1 in phases_skipped_existing' do
      result = creator.create(feature_dir: feature_dir)

      expect(result.phases_skipped_existing).to eq([1, 2])
    end

    it 'emits one phase-skipped-existing INFO event per pre-existing phase' do
      creator.create(feature_dir: feature_dir)

      events = captured_events.select { |e| e['event'] == 'phase-skipped-existing' }
      expect(events.map { |e| e['phase_number'] }).to eq([1, 2])
    end

    it 'emits one phase-branch-created INFO event for each newly-created phase' do
      creator.create(feature_dir: feature_dir)

      events = captured_events.select { |e| e['event'] == 'phase-branch-created' }
      expect(events.map { |e| e['phase_number'] }).to eq([3, 4, 5])
    end

    it 'never re-creates phases 1..K-1 (FR-040, FR-039)' do
      creator.create(feature_dir: feature_dir)

      (1...resume_at).each do |n|
        branch_name = phase_branch_for(n)
        expect(git_host_cli).not_to have_received(:run).with(satisfy { |a|
          a[0] == 'api' && a.include?('--method') && a.include?('POST') &&
            a.any? { |s| s.include?("ref=refs/heads/#{branch_name}") }
        })
      end
    end

    it 'deletes phase-creation-status.yaml on full success of the re-run (FR-040)' do
      creator.create(feature_dir: feature_dir)

      expect(File.exist?(status_path)).to be(false)
    end

    it 'reads the manifest fresh on each invocation (the manifest is the source of truth)' do
      # The prior status file recorded first_uncreated_phase=3; if the
      # Creator trusted the status file blindly, it would skip
      # querying phases 1..2. Verify it actually queried phases 1..2
      # for branch existence — that is the "manifest is authoritative"
      # contract. See contracts/stacked-pr-creator-cli.md
      # "Idempotency".
      creator.create(feature_dir: feature_dir)

      expect(git_host_cli).to have_received(:run).with(
        ['api', "repos/:owner/:repo/branches/#{phase_branch_for(1)}"]
      ).at_least(:once)
      expect(git_host_cli).to have_received(:run).with(
        ['api', "repos/:owner/:repo/branches/#{phase_branch_for(2)}"]
      ).at_least(:once)
    end
  end

  describe 'phase-existence detection — branch present but PR missing (FR-040)' do # rubocop:disable RSpec/MultipleMemoizedHelpers
    # Edge case: a prior run created the branch but failed before
    # creating the PR. The Creator MUST treat the phase as
    # uncreated and proceed to create the PR (without re-creating the
    # branch). Per contracts/stacked-pr-creator-cli.md "Idempotency":
    # "The first phase whose branch is missing (or whose PR is missing
    # or has the wrong base) becomes the resume point."
    before do
      write_manifest(phase_count: 2)
      # Phase 1 fully created (branch + PR exist).
      stub_phase_already_exists(phase_number: 1)
      # Phase 2: branch exists but PR is missing.
      stub_branch_query(branch_name: phase_branch_for(2), exists: true)
      stub_pr_query(branch_name: phase_branch_for(2), exists: false)
      stub_pr_create(
        branch_name: phase_branch_for(2),
        base_branch: phase_branch_for(1),
        pr_number: 102
      )
    end

    it 'creates the missing PR for the partially-completed phase' do
      result = creator.create(feature_dir: feature_dir)

      expect(result.success?).to be(true)
      events = captured_events.select { |e| e['event'] == 'phase-pr-created' }
      expect(events.map { |e| e['phase_number'] }).to include(2)
    end

    it 'does not re-create the existing branch' do
      creator.create(feature_dir: feature_dir)

      branch_name = phase_branch_for(2)
      expect(git_host_cli).not_to have_received(:run).with(satisfy { |a|
        a[0] == 'api' && a.include?('--method') && a.include?('POST') &&
          a.any? { |s| s.include?("ref=refs/heads/#{branch_name}") }
      })
    end
  end

  describe 'phase-existence detection — PR exists with wrong base branch (FR-040)' do # rubocop:disable RSpec/MultipleMemoizedHelpers
    # Edge case: a prior run (or an operator manually) created the PR
    # against the wrong base. The Creator MUST treat the phase as
    # uncreated rather than blindly skipping. Per
    # contracts/stacked-pr-creator-cli.md: "If both exist with the
    # manifest's expected base branch, skips; otherwise creates the
    # branch and PR." Verify the wrong-base case classifies as
    # uncreated.
    before do
      write_manifest(phase_count: 2)
      stub_phase_already_exists(phase_number: 1)
      # Phase 2: branch exists, PR exists but with the WRONG base
      # (pointing at `main` instead of phase-1's branch).
      stub_branch_query(branch_name: phase_branch_for(2), exists: true)
      stub_pr_query(
        branch_name: phase_branch_for(2),
        exists: true,
        pr_number: 999,
        base_branch: default_branch
      )
    end

    it 'does not skip phase 2 (the base mismatch invalidates the existing PR)' do
      # The phase MUST NOT be reported as skipped-existing because the
      # PR's base branch does not match the manifest's expected base.
      # Instead the Creator emits a failure (since we don't stub
      # branch creation here — the test focuses on the detection,
      # not the recovery path). This pins the existence-check contract.
      allow(git_host_cli).to receive(:run).with(satisfy { |a|
        a[0] == 'api' && a.include?('--method') && a.include?('POST')
      }).and_return(gh_result(stderr: 'simulated failure', exitstatus: 1))
      allow(failure_classifier).to receive(:classify).and_return(:other)

      creator.create(feature_dir: feature_dir)

      events = captured_events.select { |e| e['event'] == 'phase-skipped-existing' }
      skipped_phases = events.map { |e| e['phase_number'] }
      expect(skipped_phases).not_to include(2)
    end
  end

  describe 'failure-class persistence (FR-046)' do # rubocop:disable RSpec/MultipleMemoizedHelpers
    # The Creator MUST persist whichever of the five FR-046 classes
    # the FailureClassifier returns. Cycle through every value to pin
    # the wiring.
    %w[auth-missing auth-insufficient-scope rate-limit network other].each do |klass|
      it "writes failure_class=#{klass} when the classifier returns :#{klass}" do
        write_manifest(phase_count: 2)
        stub_phase_creation_succeeds(phase_number: 1)
        stub_phase_branch_create_fails(
          phase_number: 2,
          stderr: "simulated #{klass} failure",
          failure_class: klass.to_sym
        )

        creator.create(feature_dir: feature_dir)

        parsed = YAML.safe_load_file(status_path)
        expect(parsed['failure_class']).to eq(klass)
        expect(parsed['first_uncreated_phase']).to eq(2)
      end
    end
  end

  describe 'credential-leak guard (FR-047, SC-013)' do # rubocop:disable RSpec/MultipleMemoizedHelpers
    # Even when gh's stderr contains a token-shaped substring, the
    # status file and observability stream MUST NOT serialize it.
    # The Creator delegates to StatusWriter and Observability for the
    # actual scrubbing; this spec pins the integration end-to-end so a
    # future regression where the Creator bypasses one of those
    # surfaces is caught immediately.
    let(:token) { 'ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789' }

    before do
      write_manifest(phase_count: 2)
      stub_phase_creation_succeeds(phase_number: 1)
      stub_phase_branch_create_fails(
        phase_number: 2,
        stderr: "Authorization: Bearer #{token}",
        failure_class: :other
      )
    end

    it 'never writes the token to the status file' do
      creator.create(feature_dir: feature_dir)

      bytes = File.binread(status_path)
      expect(bytes).not_to include(token)
      expect(bytes).not_to match(/Bearer\s+\S/)
    end

    it 'never writes the token to the observability stream' do
      creator.create(feature_dir: feature_dir)

      expect(stderr_buffer.string).not_to include(token)
    end
  end

  describe 'manifest-missing precondition (FR-039 cousin)' do # rubocop:disable RSpec/MultipleMemoizedHelpers
    # If the manifest is absent, the Creator has nothing to do. Per
    # contracts/stacked-pr-creator-cli.md exit-code table, this is an
    # "operational error" (manifest missing), not a stacked-pr-creation
    # failure. The Creator surfaces this distinctly from the
    # phase-creation failure modes so the CLI can map it to exit 3
    # rather than exit 1.
    it 'returns a failure result without writing phase-creation-status.yaml' do
      result = creator.create(feature_dir: feature_dir)

      expect(result.success?).to be(false)
      expect(File.exist?(status_path)).to be(false)
    end

    it 'never invokes gh when the manifest is missing' do
      allow(git_host_cli).to receive(:run)

      creator.create(feature_dir: feature_dir)

      expect(git_host_cli).not_to have_received(:run)
    end
  end
end
