# frozen_string_literal: true

require 'open3'
require 'phaser'

# Specs for Phaser::StackedPrs::GitHostCli — the single, narrow
# subprocess wrapper that invokes the `gh` CLI on behalf of every
# stacked-PR-creator surface (feature 007-multi-phase-pipeline; T067/T072,
# FR-044, FR-045, FR-046, FR-047, SC-012, SC-013, plan.md "Pattern: gh
# Subprocess Wrapper" / D-009).
#
# The wrapper exists for one reason: to be the SOLE in-process surface
# that ever shells out to `gh`. Everything downstream — AuthProbe,
# FailureClassifier callers, Creator — talks to `gh` exclusively
# through this wrapper. That gives us four properties for free that we
# would otherwise have to re-prove at every call site:
#
#   1. **One subprocess invocation path.** All `gh` calls go through
#      `Open3.capture3('gh', *args)`. T071's grep-based regression test
#      asserts no `system('gh ...')` or backtick-`gh` exists anywhere
#      under `phaser/lib/`; this spec asserts the wrapper itself uses
#      `Open3.capture3` (and only that).
#
#   2. **No environment-variable token reads.** The wrapper neither
#      adds nor removes anything from the subprocess environment under
#      its own control (per `contracts/stacked-pr-creator-cli.md`
#      "Authentication Surface"). It also MUST NOT consult any
#      `*TOKEN*` / `*KEY*` / `*SECRET*` / `*PASSWORD*` env var to
#      decide whether or how to invoke `gh`. The same pattern is
#      pinned for the FailureClassifier in failure_classifier_spec.rb;
#      here we pin it for the wrapper too.
#
#   3. **Stderr-credential sanitization.** The wrapper captures
#      stderr in full but only forwards the FIRST LINE to callers,
#      and that first line is scanned against the FR-047 credential
#      patterns. On any match, the offending substring is replaced
#      with the redaction marker before the result reaches the caller
#      (so a downstream JSON-serialized observability event can never
#      embed a token, regardless of which call site emits it).
#
#   4. **Result-shape stability.** The wrapper returns a value that
#      responds to `#stdout`, `#stderr`, and `#status` (a
#      `Process::Status`-shaped object). AuthProbe (T065) and Creator
#      (T068) consume exactly that surface, so changing the shape
#      breaks every downstream test in lockstep.
#
# The system-under-test is implementation-not-yet-written (T072 lands
# after this spec). Each example below stubs `Open3.capture3` with
# `allow(Open3).to receive(...)`, observes the wrapper's behaviour,
# and asserts a single property. The tests deliberately avoid binding
# to the wrapper's internal collaborator names so future refactors
# inside `git_host_cli.rb` (e.g., extracting the credential scan into a
# helper) do not cascade into churn here.
RSpec.describe 'Phaser::StackedPrs::GitHostCli' do
  subject(:cli) { Phaser::StackedPrs::GitHostCli.new }

  # A fresh `Process::Status`-shaped double per example. The real
  # `Open3.capture3` returns a `Process::Status`; the wrapper passes
  # that object through to callers under the `#status` reader.
  let(:exit_status_zero) { instance_double(Process::Status, exitstatus: 0, success?: true) }
  let(:exit_status_one)  { instance_double(Process::Status, exitstatus: 1, success?: false) }

  # Convenience helper: stub `Open3.capture3('gh', *args)` to return
  # the given (stdout, stderr, status) triple. The wrapper's only
  # subprocess invocation path is `Open3.capture3` so every example
  # below stubs through this single seam.
  def stub_capture3(args, stdout: '', stderr: '', status: exit_status_zero)
    allow(Open3).to receive(:capture3).with('gh', *args).and_return(
      [stdout, stderr, status]
    )
  end

  describe 'subprocess invocation surface (FR-044, plan.md D-009)' do
    it 'invokes Open3.capture3 with the literal "gh" binary name and the given args' do
      stub_capture3(%w[auth status])

      cli.run(%w[auth status])

      expect(Open3).to have_received(:capture3).with('gh', 'auth', 'status')
    end

    it 'splats array args one-per-positional so spaces are never re-joined into one token' do
      # Splatting the args (rather than passing the array as a single
      # argument) is what keeps each `gh` argument its own argv entry.
      # Re-joining would silently break commands like
      # `gh pr create --title "long title with spaces"` by passing the
      # whole quoted string as one token. This test pins the splat.
      stub_capture3(['pr', 'create', '--title', 'long title with spaces'])

      cli.run(['pr', 'create', '--title', 'long title with spaces'])

      expect(Open3).to have_received(:capture3).with(
        'gh', 'pr', 'create', '--title', 'long title with spaces'
      )
    end

    it 'invokes Open3.capture3 exactly once per #run call (no retries inside the wrapper)' do
      # Retry policy belongs in the caller (Creator), not the wrapper.
      # The wrapper is a thin facade.
      stub_capture3(%w[auth status])

      cli.run(%w[auth status])

      expect(Open3).to have_received(:capture3).exactly(1).time
    end

    it 'never invokes a subprocess via Kernel#system' do
      allow(Kernel).to receive(:system)
      stub_capture3(%w[auth status])

      cli.run(%w[auth status])

      expect(Kernel).not_to have_received(:system)
    end

    it 'never invokes a subprocess via Kernel#`' do
      # Backtick subshell is the other "easy mistake" path. Pin that
      # the wrapper does not reach for it. (`Kernel#` is the literal
      # backtick method name in Ruby.)
      allow(Kernel).to receive(:`)
      stub_capture3(%w[auth status])

      cli.run(%w[auth status])

      expect(Kernel).not_to have_received(:`)
    end
  end

  describe 'no environment-variable token reads (FR-047, contracts/stacked-pr-creator-cli.md)' do
    it 'does not pass an explicit env hash as Open3.capture3 first positional' do
      # `Open3.capture3(env_hash, 'gh', ...)` is the API for adding env
      # vars under the wrapper's control. The contract forbids that:
      # the subprocess inherits the operator's environment unchanged.
      # Stubbing with the explicit-env signature would not match this
      # call, so the wrapper MUST NOT use it.
      stub_capture3(%w[auth status])

      cli.run(%w[auth status])

      # If the wrapper were passing an env hash, the stub above would
      # not match and the test would fail with "received :capture3
      # with unexpected arguments". The successful match here pins the
      # absence of the env-hash form.
      expect(Open3).to have_received(:capture3).with('gh', 'auth', 'status')
    end

    it 'never reads ENV["GITHUB_TOKEN"] during a #run call' do
      # The wrapper has no business inspecting credential env vars —
      # `gh` itself owns that decision. Pin the prohibition by
      # spying on ENV#[] for the duration of the call.
      stub_capture3(%w[auth status])
      allow(ENV).to receive(:[]).and_call_original

      cli.run(%w[auth status])

      expect(ENV).not_to have_received(:[]).with('GITHUB_TOKEN')
    end

    it 'never reads ENV["GH_TOKEN"] during a #run call' do
      stub_capture3(%w[auth status])
      allow(ENV).to receive(:[]).and_call_original

      cli.run(%w[auth status])

      expect(ENV).not_to have_received(:[]).with('GH_TOKEN')
    end

    it 'never fetches a token-shaped key via ENV.fetch during a #run call' do
      # `ENV.fetch('GITHUB_TOKEN', nil)` is the other common idiom for
      # cautious env reads. Pin that the wrapper does not reach for it.
      stub_capture3(%w[auth status])
      allow(ENV).to receive(:fetch).and_call_original

      cli.run(%w[auth status])

      expect(ENV).not_to have_received(:fetch).with(/TOKEN|KEY|SECRET|PASSWORD/i, anything)
      expect(ENV).not_to have_received(:fetch).with(/TOKEN|KEY|SECRET|PASSWORD/i)
    end
  end

  describe 'result shape — responds to #stdout, #stderr, #status' do
    it 'returns an object that responds to #stdout' do
      stub_capture3(%w[auth status], stdout: 'logged in')

      result = cli.run(%w[auth status])

      expect(result).to respond_to(:stdout)
    end

    it 'returns an object that responds to #stderr' do
      stub_capture3(%w[auth status], stderr: 'some message')

      result = cli.run(%w[auth status])

      expect(result).to respond_to(:stderr)
    end

    it 'returns an object that responds to #status' do
      stub_capture3(%w[auth status])

      result = cli.run(%w[auth status])

      expect(result).to respond_to(:status)
    end

    it 'forwards stdout from the subprocess unchanged' do
      stub_capture3(%w[auth status], stdout: "raw stdout from gh\n")

      result = cli.run(%w[auth status])

      expect(result.stdout).to eq("raw stdout from gh\n")
    end

    it 'forwards the Process::Status object from the subprocess unchanged' do
      stub_capture3(%w[auth status], status: exit_status_one)

      result = cli.run(%w[auth status])

      expect(result.status).to be(exit_status_one)
      expect(result.status.exitstatus).to eq(1)
    end

    it 'returns a value that exposes the gh exit code via result.status.exitstatus' do
      # AuthProbe (T065) reads `result.status.exitstatus` directly.
      # Pin that the wrapper preserves that surface.
      stub_capture3(%w[auth status], status: exit_status_zero)

      result = cli.run(%w[auth status])

      expect(result.status.exitstatus).to eq(0)
    end
  end

  describe 'stderr first-line forwarding (plan.md "Pattern: gh Subprocess Wrapper")' do
    it 'forwards only the first line of stderr (drops subsequent lines)' do
      # The contract is explicit: "Captures stdout, stderr, and status.
      # Scans stderr's first line for credential patterns before
      # returning it to callers. Never logs or persists the raw stderr
      # beyond that first sanitized line." So multi-line stderr from
      # `gh` is collapsed to its first line before the caller sees it.
      multi_line_stderr = "first line of message\nsecond line\nthird line\n"
      stub_capture3(%w[auth status], stderr: multi_line_stderr)

      result = cli.run(%w[auth status])

      expect(result.stderr).not_to include('second line')
      expect(result.stderr).not_to include('third line')
    end

    it 'preserves the first line content (sans trailing newline) when no credential patterns match' do
      stub_capture3(
        %w[auth status],
        stderr: "You are not logged into any GitHub hosts.\nTo log in, run: gh auth login\n"
      )

      result = cli.run(%w[auth status])

      expect(result.stderr).to include('You are not logged into any GitHub hosts.')
    end

    it 'returns an empty string when the subprocess emitted no stderr' do
      stub_capture3(%w[auth status], stderr: '')

      result = cli.run(%w[auth status])

      expect(result.stderr).to eq('')
    end

    it 'tolerates stderr that has no trailing newline (single-line case)' do
      stub_capture3(%w[auth status], stderr: 'no newline at end')

      result = cli.run(%w[auth status])

      expect(result.stderr).to include('no newline at end')
    end
  end

  describe 'credential-leak sanitization (FR-047, SC-013)' do
    # The wrapper is the LAST chance to scrub a token before it
    # reaches a downstream caller that might serialize it into a JSON
    # observability event or a YAML status file. The redaction marker
    # mirrors the one used by Phaser::Observability and
    # Phaser::StatusWriter so the three surfaces stay in lockstep.
    let(:redaction_marker) { '[REDACTED:credential-pattern-match]' }

    it "redacts a ghp_-prefixed token from stderr's first line" do
      stub_capture3(
        %w[auth status],
        stderr: "Authorization: Bearer ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789\n"
      )

      result = cli.run(%w[auth status])

      expect(result.stderr).not_to include('ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789')
    end

    it "redacts a gho_-prefixed token from stderr's first line" do
      stub_capture3(
        %w[auth status],
        stderr: "leaked token gho_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 in error\n"
      )

      result = cli.run(%w[auth status])

      expect(result.stderr).not_to include('gho_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789')
    end

    it "redacts a ghu_, ghs_, and ghr_ prefixed tokens from stderr's first line" do
      %w[ghu_ABCDEFGHIJKLMNOP ghs_ABCDEFGHIJKLMNOP ghr_ABCDEFGHIJKLMNOP].each do |token|
        stub_capture3(%w[auth status], stderr: "leak: #{token}\n")

        result = cli.run(%w[auth status])

        expect(result.stderr).not_to include(token)
      end
    end

    it "redacts a Bearer-token header from stderr's first line" do
      stub_capture3(
        %w[auth status],
        stderr: "Authorization: Bearer some-opaque-token-value\n"
      )

      result = cli.run(%w[auth status])

      expect(result.stderr).not_to match(/Bearer\s+\S/)
    end

    it 'replaces the credential substring with the documented redaction marker' do
      stub_capture3(
        %w[auth status],
        stderr: "auth failed: ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789\n"
      )

      result = cli.run(%w[auth status])

      expect(result.stderr).to include(redaction_marker)
    end

    it 'preserves the surrounding context when redacting (only the credential substring is replaced)' do
      # The contract sanitizes the FIRST LINE — it does not throw the
      # whole line away. The non-credential context remains so the
      # caller still has actionable text.
      stub_capture3(
        %w[auth status],
        stderr: "auth failed reason ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 here\n"
      )

      result = cli.run(%w[auth status])

      expect(result.stderr).to include('auth failed reason')
      expect(result.stderr).to include('here')
      expect(result.stderr).not_to include('ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789')
    end

    it 'never lets a credential reach the caller even when the second line carried it' do
      # Defense-in-depth: even though the wrapper drops lines 2..N
      # before returning, a future regression that accidentally kept
      # multi-line stderr would still need the credential scan to
      # catch the leak. Verify the leak is impossible regardless of
      # which line carried the token.
      stub_capture3(
        %w[auth status],
        stderr: "first line\nghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789\n"
      )

      result = cli.run(%w[auth status])

      expect(result.stderr).not_to include('ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789')
    end
  end

  describe 'failure-mode passthrough (FR-046 prerequisite)' do
    # The wrapper does not classify failures — that is FailureClassifier's
    # job (T073). The wrapper's only failure-mode contract is that it
    # surfaces the raw exit code and the sanitized first stderr line so
    # the classifier has the inputs it needs.
    it 'returns a result with status.exitstatus=1 when gh exits non-zero' do
      stub_capture3(
        %w[auth status],
        stderr: "You are not logged into any GitHub hosts.\n",
        status: exit_status_one
      )

      result = cli.run(%w[auth status])

      expect(result.status.exitstatus).to eq(1)
    end

    it 'still sanitizes stderr on a failed exit (the credential guard is unconditional)' do
      stub_capture3(
        %w[auth status],
        stderr: "auth failed: ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789\n",
        status: exit_status_one
      )

      result = cli.run(%w[auth status])

      expect(result.stderr).not_to include('ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789')
    end

    it 'does not raise when gh exits non-zero (raising is the caller\'s policy)' do
      stub_capture3(
        %w[auth status],
        stderr: 'transient failure',
        status: exit_status_one
      )

      expect { cli.run(%w[auth status]) }.not_to raise_error
    end
  end
end
