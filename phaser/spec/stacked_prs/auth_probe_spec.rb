# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'json'
require 'stringio'
require 'tmpdir'
require 'yaml'
require 'phaser'

# Specs for Phaser::StackedPrs::AuthProbe — the one-shot `gh auth status`
# probe that runs at the start of every `phaser-stacked-prs` invocation
# (feature 007-multi-phase-pipeline; T065/T074, FR-045, FR-046, FR-047,
# SC-012, SC-013, plan.md R-009 / D-012).
#
# The probe is the single load-bearing surface for the stacked-PR
# creator's "fail-fast before any branch is created" guarantee. Its
# contract is narrow but every line of it carries a Success Criterion,
# so the test suite below pins each one explicitly:
#
#   1. Exactly one `gh auth status` invocation per probe (FR-045) — the
#      probe MUST NOT retry, MUST NOT re-probe per phase, and MUST NOT
#      shell out to `gh` for any other purpose during the probe call.
#
#   2. Cached result reuse — calling `#probe` twice on the same instance
#      consults `gh` exactly once; the second call returns the cached
#      result. The creator (T075) relies on this so subsequent `gh`
#      calls do not accidentally re-probe.
#
#   3. Fail-fast on auth-missing (SC-012) — when `gh auth status`
#      reports no authenticated identity, the probe writes
#      `phase-creation-status.yaml` with `stage: stacked-pr-creation`,
#      `failure_class: auth-missing`, and `first_uncreated_phase: 1`,
#      then returns a failure result. No branch creation is attempted.
#
#   4. Fail-fast on auth-insufficient-scope — when the authenticated
#      identity lacks `repo` scope, the same status-file shape is
#      written with `failure_class: auth-insufficient-scope`.
#
#   5. Failure-class delegation — the probe asks
#      `Phaser::StackedPrs::FailureClassifier` to map the `gh` exit code
#      and stderr to one of the five FR-046 values; it never inspects
#      tokens or guesses.
#
#   6. Observability — every probe emits exactly one
#      `auth-probe-result` INFO event; on failure the probe additionally
#      emits one `phase-creation-failed` ERROR event with the matching
#      `failure_class`.
RSpec.describe 'Phaser::StackedPrs::AuthProbe' do # rubocop:disable RSpec/MultipleMemoizedHelpers
  # The system-under-test is constructed per-example with collaborators
  # replaced by lightweight test doubles. The doubles let the spec
  # observe the exact arguments the probe passes to each collaborator
  # without depending on the (still-to-be-implemented) GitHostCli or
  # FailureClassifier production classes.
  subject(:probe) do
    Phaser::StackedPrs::AuthProbe.new(
      git_host_cli: git_host_cli,
      failure_classifier: failure_classifier,
      status_writer: status_writer,
      observability: observability
    )
  end

  # A scratch feature directory per example so the status-file write is
  # isolated; mirrors the idiom used by status_writer_spec.rb.
  attr_reader :feature_dir

  around do |example|
    Dir.mktmpdir('phaser-auth-probe-spec') do |tmp|
      @feature_dir = tmp
      example.run
    end
  end

  let(:status_path) { File.join(feature_dir, 'phase-creation-status.yaml') }

  # Test double for the `gh` subprocess wrapper. The real wrapper
  # (T072) is a thin Open3.capture3 facade; here we configure it to
  # return a (stdout, stderr, status) triple per example so each test
  # can simulate one `gh auth status` outcome. A plain `double` is used
  # (rather than `instance_double`) because the production
  # `Phaser::StackedPrs::GitHostCli` class is not implemented yet (T072
  # follows this test). The same applies to the FailureClassifier
  # double below.
  let(:git_host_cli) { double('GitHostCli') } # rubocop:disable RSpec/VerifiedDoubles

  # Test double for the failure classifier (T073). The probe delegates
  # the exit-code → failure_class mapping to this collaborator so the
  # probe itself never touches gh's exit-code semantics.
  let(:failure_classifier) { double('FailureClassifier') } # rubocop:disable RSpec/VerifiedDoubles

  # Real status writer with a pinned clock so the on-disk YAML is
  # reproducible across runs. The probe MUST persist failures via this
  # collaborator, not write YAML directly.
  let(:fixed_timestamp) { '2026-04-25T12:00:00.000Z' }
  let(:status_writer) { Phaser::StatusWriter.new(now: -> { fixed_timestamp }) }

  # Captured stderr stream so observability events can be asserted on.
  let(:stderr_buffer) { StringIO.new }
  let(:observability) { Phaser::Observability.new(stderr: stderr_buffer, now: -> { fixed_timestamp }) }

  # Helper: parse the captured stderr buffer into one Hash per
  # newline-terminated JSON record.
  def captured_events
    stderr_buffer.string.each_line.map { |line| JSON.parse(line.chomp) }
  end

  # Helper: stub git_host_cli.run to return an object exposing
  # `#stdout`, `#stderr`, `#status` so the probe's call site is
  # verifiable without binding to the wrapper's exact return-type
  # implementation. The result type is built with `Struct.new(...)`
  # inline (no top-level constant declaration) so the spec stays free
  # of leaky constants.
  def stub_gh_auth_status(stdout: '', stderr: '', exitstatus: 0)
    status_double = instance_double(Process::Status, exitstatus: exitstatus, success?: exitstatus.zero?)
    result = Struct.new(:stdout, :stderr, :status, keyword_init: true).new(
      stdout: stdout,
      stderr: stderr,
      status: status_double
    )
    allow(git_host_cli).to receive(:run).with(%w[auth status]).and_return(result)
  end

  describe 'exactly one `gh auth status` invocation per run (FR-045)' do # rubocop:disable RSpec/MultipleMemoizedHelpers
    before do
      stub_gh_auth_status(
        stdout: "github.com\n  Logged in to github.com as alice (oauth_token)\n  Token scopes: 'repo', 'workflow'\n",
        exitstatus: 0
      )
    end

    it 'invokes git_host_cli.run with exactly the auth-status arguments' do
      probe.probe(feature_dir: feature_dir)

      expect(git_host_cli).to have_received(:run).with(%w[auth status]).exactly(1).time
    end

    it 'does not invoke gh for any other purpose during the probe' do
      probe.probe(feature_dir: feature_dir)

      expect(git_host_cli).to have_received(:run).exactly(1).time
    end

    it 'caches the result so a second probe call does not re-invoke gh' do
      probe.probe(feature_dir: feature_dir)
      probe.probe(feature_dir: feature_dir)

      expect(git_host_cli).to have_received(:run).exactly(1).time
    end

    it 'returns the same result object on the second cached call' do
      first = probe.probe(feature_dir: feature_dir)
      second = probe.probe(feature_dir: feature_dir)

      expect(second).to equal(first)
    end
  end

  describe 'success path — authenticated with required scope' do # rubocop:disable RSpec/MultipleMemoizedHelpers
    before do
      stub_gh_auth_status(
        stdout: '',
        stderr: "github.com\n  Logged in to github.com as alice (oauth_token)\n  Token scopes: 'repo', 'workflow'\n",
        exitstatus: 0
      )
    end

    it 'returns a successful result' do
      result = probe.probe(feature_dir: feature_dir)

      expect(result.success?).to be(true)
    end

    it 'does not write phase-creation-status.yaml' do
      probe.probe(feature_dir: feature_dir)

      expect(File.exist?(status_path)).to be(false)
    end

    it 'does not consult the failure classifier' do
      allow(failure_classifier).to receive(:classify)

      probe.probe(feature_dir: feature_dir)

      expect(failure_classifier).not_to have_received(:classify)
    end

    it 'emits exactly one auth-probe-result INFO event' do
      probe.probe(feature_dir: feature_dir)

      events = captured_events.select { |e| e['event'] == 'auth-probe-result' }
      expect(events.length).to eq(1)
      expect(events.first['level']).to eq('INFO')
    end

    it 'records authenticated=true and the parsed scopes on the auth-probe-result event' do
      probe.probe(feature_dir: feature_dir)

      event = captured_events.find { |e| e['event'] == 'auth-probe-result' }
      expect(event).to include(
        'authenticated' => true,
        'scopes' => array_including('repo')
      )
    end

    it 'records the host on the auth-probe-result event' do
      probe.probe(feature_dir: feature_dir)

      event = captured_events.find { |e| e['event'] == 'auth-probe-result' }
      expect(event['host']).to eq('github.com')
    end

    it 'does not emit a phase-creation-failed event on success' do
      probe.probe(feature_dir: feature_dir)

      events = captured_events.select { |e| e['event'] == 'phase-creation-failed' }
      expect(events).to be_empty
    end
  end

  describe 'fail-fast on auth-missing (SC-012)' do # rubocop:disable RSpec/MultipleMemoizedHelpers
    before do
      stub_gh_auth_status(
        stdout: '',
        stderr: "You are not logged into any GitHub hosts. To log in, run: gh auth login\n",
        exitstatus: 1
      )
      allow(failure_classifier).to receive(:classify).and_return(:'auth-missing')
    end

    it 'returns a failure result with failure_class=auth-missing' do
      result = probe.probe(feature_dir: feature_dir)

      expect(result.success?).to be(false)
      expect(result.failure_class).to eq('auth-missing')
    end

    it 'writes phase-creation-status.yaml at the feature dir' do
      probe.probe(feature_dir: feature_dir)

      expect(File.exist?(status_path)).to be(true)
    end

    it 'writes stage=stacked-pr-creation in the status file' do
      probe.probe(feature_dir: feature_dir)

      parsed = YAML.safe_load_file(status_path)
      expect(parsed['stage']).to eq('stacked-pr-creation')
    end

    it 'writes failure_class=auth-missing in the status file' do
      probe.probe(feature_dir: feature_dir)

      parsed = YAML.safe_load_file(status_path)
      expect(parsed['failure_class']).to eq('auth-missing')
    end

    it 'writes first_uncreated_phase=1 in the status file (FR-045, SC-012)' do
      probe.probe(feature_dir: feature_dir)

      parsed = YAML.safe_load_file(status_path)
      expect(parsed['first_uncreated_phase']).to eq(1)
    end

    it 'consults the failure classifier with the gh exit code and stderr' do
      probe.probe(feature_dir: feature_dir)

      expect(failure_classifier).to have_received(:classify).with(
        exit_code: 1,
        stderr: a_string_including('not logged in')
      )
    end

    it 'emits a phase-creation-failed ERROR event for phase 1' do
      probe.probe(feature_dir: feature_dir)

      events = captured_events.select { |e| e['event'] == 'phase-creation-failed' }
      expect(events.length).to eq(1)
      expect(events.first).to include(
        'level' => 'ERROR',
        'phase_number' => 1,
        'failure_class' => 'auth-missing',
        'gh_exit_code' => 1
      )
    end

    it 'records authenticated=false on the auth-probe-result event' do
      probe.probe(feature_dir: feature_dir)

      event = captured_events.find { |e| e['event'] == 'auth-probe-result' }
      expect(event['authenticated']).to be(false)
    end
  end

  describe 'fail-fast on auth-insufficient-scope' do # rubocop:disable RSpec/MultipleMemoizedHelpers
    before do
      stub_gh_auth_status(
        stdout: '',
        stderr: "github.com\n  Logged in to github.com as alice (oauth_token)\n  Token scopes: 'gist', 'read:org'\n",
        exitstatus: 0
      )
      # Even with exit 0, a probe that detects missing `repo` scope MUST
      # treat the run as a failure. The probe asks the classifier to make
      # the scope-vs-required determination so the policy lives in one
      # place.
      allow(failure_classifier).to receive(:classify).and_return(:'auth-insufficient-scope')
    end

    it 'returns a failure result with failure_class=auth-insufficient-scope' do
      result = probe.probe(feature_dir: feature_dir)

      expect(result.success?).to be(false)
      expect(result.failure_class).to eq('auth-insufficient-scope')
    end

    it 'writes failure_class=auth-insufficient-scope and first_uncreated_phase=1' do
      probe.probe(feature_dir: feature_dir)

      parsed = YAML.safe_load_file(status_path)
      expect(parsed).to include(
        'stage' => 'stacked-pr-creation',
        'failure_class' => 'auth-insufficient-scope',
        'first_uncreated_phase' => 1
      )
    end

    it 'emits a phase-creation-failed ERROR event with the matching failure_class' do
      probe.probe(feature_dir: feature_dir)

      event = captured_events.find { |e| e['event'] == 'phase-creation-failed' }
      expect(event).to include(
        'level' => 'ERROR',
        'failure_class' => 'auth-insufficient-scope',
        'phase_number' => 1
      )
    end
  end

  describe 'never reaches branch creation on probe failure (SC-012)' do # rubocop:disable RSpec/MultipleMemoizedHelpers
    before do
      stub_gh_auth_status(stderr: 'not logged in', exitstatus: 1)
      allow(failure_classifier).to receive(:classify).and_return(:'auth-missing')
    end

    it 'invokes gh exactly once (the probe call) and never again' do
      probe.probe(feature_dir: feature_dir)

      expect(git_host_cli).to have_received(:run).exactly(1).time
    end
  end

  describe 'failure_class delegated to FailureClassifier (FR-046)' do # rubocop:disable RSpec/MultipleMemoizedHelpers
    %w[auth-missing auth-insufficient-scope rate-limit network other].each do |klass|
      it "records failure_class=#{klass} when the classifier returns :#{klass}" do
        stub_gh_auth_status(stderr: 'simulated failure', exitstatus: 4)
        allow(failure_classifier).to receive(:classify).and_return(klass.to_sym)

        result = probe.probe(feature_dir: feature_dir)

        expect(result.failure_class).to eq(klass)
        parsed = YAML.safe_load_file(status_path)
        expect(parsed['failure_class']).to eq(klass)
      end
    end
  end

  describe 'credential-leak guard (FR-047, SC-013)' do # rubocop:disable RSpec/MultipleMemoizedHelpers
    before do
      stub_gh_auth_status(
        stderr: "Authorization: Bearer ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789\n",
        exitstatus: 1
      )
      allow(failure_classifier).to receive(:classify).and_return(:other)
    end

    it 'never writes a credential-shaped substring to the status file' do
      probe.probe(feature_dir: feature_dir)

      bytes = File.binread(status_path)
      expect(bytes).not_to include('ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789')
      expect(bytes).not_to match(/Bearer\s+\S/)
    end

    it 'never writes a credential-shaped substring to stderr observability events' do
      probe.probe(feature_dir: feature_dir)

      expect(stderr_buffer.string).not_to include('ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789')
    end
  end
end
