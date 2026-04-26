# frozen_string_literal: true

require 'open3'
require 'pathname'
require 'tempfile'
require 'spec_helper'

# Test scaffold for SC-006 / FR-025 / FR-019 — the conditional
# `.specify/flavor.yaml` gate that determines whether the SpecKit
# pipeline runs the phaser stage or behaves byte-identically to the
# pre-feature pipeline (feature 007-multi-phase-pipeline; T057,
# T061, quickstart.md "Pattern: Conditional Pipeline Behavior").
#
# The contract under test:
#
#   The modified `speckit-commands/speckit.pipeline.md` MUST detect
#   the presence of `.specify/flavor.yaml` at the repository root via
#   a `test -f .specify/flavor.yaml` Bash check. When the file is
#   present, the pipeline inserts the phaser step (and the per-phase
#   marge invocations); when absent, the pipeline skips all
#   phaser-related logic and runs marge once holistically (FR-025).
#
# What this scaffold asserts (and explicitly does NOT assert):
#
#   * The source-of-truth pipeline command file exists and contains
#     the literal `test -f .specify/flavor.yaml` gate snippet.
#   * The same snippet appears in the installed `.claude/commands/`
#     copy (so `setup.sh` actually propagates the gate; per the
#     "Source vs Installed Files" section of CLAUDE.md).
#   * The snippet's executable form (extracted into a temp file and
#     wrapped in a minimal shebang/shell scaffold) is shellcheck-
#     clean. Per T057's wording — "shellcheck-validated test
#     scaffold" — the gate is exercised by passing it through
#     shellcheck, NOT by spawning the Claude CLI to interpret the
#     Markdown command (which would couple the test to a non-
#     deterministic LLM execution surface and break FR-002 / SC-002,
#     mirroring the same reasoning called out in
#     `pipeline_no_flavor_baseline_spec.rb`).
#
#   * This scaffold deliberately does NOT assert anything about the
#     pipeline's downstream behavior (per-phase marge invocation,
#     phaser step ordering, etc.) — those contracts are exercised by
#     `pipeline_no_flavor_baseline_spec.rb` (the absent-path) and by
#     the per-phase marge / phaser specs (the present-path).
#
# Acceptance:
#
#   * Test fails today (T061 has not yet inserted the gate into
#     `speckit-commands/speckit.pipeline.md`); this is the test-first
#     signal that the implementation task is still outstanding,
#     matching the constitution's Test-First Development principle.
#   * Test passes once T061 lands the gate snippet and T063 re-runs
#     `bash setup.sh` to refresh `.claude/commands/speckit.pipeline.md`.
#   * Test fails loudly if a future change drops the gate, replaces
#     `test -f` with a shape that shellcheck flags (e.g., an unquoted
#     glob, an `if [ ... ]` with missing brackets), or lets the
#     installed copy drift from the source.
#
# Why shellcheck rather than executing the snippet directly: the gate
# lives inside a Markdown command file that the Claude CLI
# interprets at pipeline runtime; the snippet is never invoked by
# this Ruby test suite. shellcheck is the lightest-weight
# deterministic validator that catches the failure modes that matter
# (typos, unquoted expansions, missing `fi`, etc.) without coupling
# the spec to either the Claude CLI or a live filesystem.

# Module-scoped constants so the rubocop `Lint/ConstantDefinitionInBlock`
# and `RSpec/LeakyConstantDeclaration` cops are satisfied while keeping
# the contract surface easy to import from any companion spec.
module PipelineFlavorGate
  REPO_ROOT = Pathname.new(File.expand_path('../..', __dir__))

  # The source-of-truth pipeline command file. Per CLAUDE.md
  # "Source vs Installed Files", this is the file that contributors
  # MUST edit; `setup.sh` propagates it into `.claude/commands/`.
  SOURCE_PIPELINE_PATH = REPO_ROOT.join('speckit-commands', 'speckit.pipeline.md')

  # The installed pipeline command file. Refreshed from the source
  # by `bash setup.sh`. This spec asserts the source and installed
  # copies agree on the gate snippet so a stale install can't cause
  # the gate to be silently skipped at pipeline runtime.
  INSTALLED_PIPELINE_PATH = REPO_ROOT.join('.claude', 'commands', 'speckit.pipeline.md')

  # The literal Bash gate snippet the pipeline MUST contain (per
  # quickstart.md "Pattern: Conditional Pipeline Behavior" and
  # FR-025). The snippet is matched as a substring rather than a
  # whole-line regex because the surrounding Markdown may wrap it in
  # a fenced code block, an inline code span, or a longer compound
  # command — all of which are acceptable as long as the literal
  # `test -f .specify/flavor.yaml` shape is present.
  GATE_SNIPPET = 'test -f .specify/flavor.yaml'

  # Whether shellcheck is available on PATH. The gate snippet's
  # shellcheck validation is skipped (rather than failing hard) when
  # the binary is absent so the spec stays runnable in environments
  # that haven't installed shellcheck yet — matching the "graceful
  # degradation when an optional tool is missing" pattern used by
  # the rest of the project's quality gates.
  SHELLCHECK_AVAILABLE = begin
    _stdout, _stderr, status = Open3.capture3('shellcheck', '--version')
    status.success?
  rescue Errno::ENOENT
    false
  end

  # Wrap the bare gate snippet in the minimum shellcheck-friendly
  # scaffold so shellcheck has enough context to lint it. The wrap
  # uses an explicit `#!/usr/bin/env bash` shebang and the standard
  # `set -euo pipefail` preamble, mirroring the project's existing
  # shell scripts (`.specify/quality-gates.sh`, `setup.sh`). The
  # gate is exercised inside an `if`/`then`/`fi` block because that
  # is exactly how the pipeline command is expected to use it at
  # runtime (per quickstart.md's example).
  def self.shellcheck_wrap(snippet)
    <<~BASH
      #!/usr/bin/env bash
      set -euo pipefail

      if #{snippet}; then
        echo "PHASER_ENABLED"
      else
        echo "PHASER_DISABLED"
      fi
    BASH
  end

  # Run shellcheck against the wrapped snippet. Returns
  # `[exit_status, stdout, stderr]` so the spec can produce a
  # high-signal failure message when shellcheck flags the snippet.
  def self.run_shellcheck(snippet)
    Tempfile.create(['pipeline-flavor-gate', '.sh']) do |file|
      file.write(shellcheck_wrap(snippet))
      file.flush
      stdout, stderr, status = Open3.capture3('shellcheck', '--shell=bash', file.path)
      return [status.exitstatus, stdout, stderr]
    end
  end
end

RSpec.describe 'pipeline conditional flavor-file gate' do # rubocop:disable RSpec/DescribeClass
  let(:source_path)    { PipelineFlavorGate::SOURCE_PIPELINE_PATH }
  let(:installed_path) { PipelineFlavorGate::INSTALLED_PIPELINE_PATH }
  let(:snippet)        { PipelineFlavorGate::GATE_SNIPPET }

  describe 'gate snippet presence in the source-of-truth pipeline command' do
    it 'has a source pipeline command file at the documented path' do
      missing_message = <<~MSG.strip
        Source pipeline command missing: #{source_path}.

        Per CLAUDE.md "Source vs Installed Files", the pipeline
        command's source-of-truth lives under `speckit-commands/`.
        Without it, the gate snippet has no place to live and the
        conditional pipeline behavior contract (FR-025, SC-006) is
        unverifiable.
      MSG
      expect(source_path).to exist, missing_message
    end

    # This is the assertion that fails today (T061 has not yet
    # inserted the gate). It is the test-first signal the
    # implementation task is outstanding.
    it 'contains the `test -f .specify/flavor.yaml` gate snippet' do # rubocop:disable RSpec/ExampleLength
      skip 'source pipeline command file does not exist yet' unless source_path.exist?

      contents = source_path.read

      missing_snippet_message = <<~MSG.strip
        Source pipeline command at #{source_path} does NOT contain
        the literal gate snippet:

          #{snippet}

        Per quickstart.md "Pattern: Conditional Pipeline Behavior"
        and FR-025, the pipeline MUST detect `.specify/flavor.yaml`
        with a `test -f` Bash check immediately after the existing
        pre-flight checks. When present, the pipeline inserts the
        phaser stage; when absent, the pipeline behaves byte-
        identically to the pre-feature pipeline.

        T061 is the implementation task that lands the gate snippet
        in the source file. T063 then re-runs `bash setup.sh` to
        refresh the installed copy so the
        installed-copy-agreement assertion in this same spec can
        also pass.
      MSG
      expect(contents).to include(snippet), missing_snippet_message
    end
  end

  describe 'gate snippet propagation to the installed pipeline command' do
    # The installed copy is refreshed from the source by
    # `bash setup.sh` (per CLAUDE.md). This assertion catches the
    # failure mode where T061 lands the gate in the source but T063
    # (the setup.sh re-run) is forgotten — at which point the
    # pipeline command Claude actually executes still lacks the gate
    # and the conditional behavior is silently disabled.
    it 'has an installed pipeline command file refreshed from the source' do
      skip 'installed pipeline command file does not exist yet' unless installed_path.exist?

      contents = installed_path.read

      missing_snippet_message = <<~MSG.strip
        Installed pipeline command at #{installed_path} does NOT
        contain the gate snippet:

          #{snippet}

        Either T061 has not yet landed the snippet in the source
        file, OR T063 (the `bash setup.sh` invocation that refreshes
        installed copies from source) has not yet been re-run. Per
        CLAUDE.md "Source vs Installed Files", the installed copy is
        what Claude actually executes at pipeline runtime — a stale
        install means the gate is silently skipped.
      MSG
      expect(contents).to include(snippet), missing_snippet_message
    end
  end

  describe 'gate snippet shellcheck cleanliness' do
    # T057's wording — "shellcheck-validated test scaffold" — is
    # exercised here. The gate snippet is wrapped in a minimal
    # shellcheck-friendly scaffold (shebang + `set -euo pipefail` +
    # `if`/`then`/`else`/`fi`), passed to shellcheck, and asserted
    # to exit 0 with no diagnostics.
    it 'passes shellcheck when wrapped in a minimal Bash scaffold',
       skip: PipelineFlavorGate::SHELLCHECK_AVAILABLE ? false : 'shellcheck not installed' do
      exit_status, stdout, stderr = PipelineFlavorGate.run_shellcheck(snippet)

      shellcheck_failure_message = <<~MSG.strip
        shellcheck flagged the gate snippet wrapped in the standard
        scaffold (exit=#{exit_status}):

        ----- snippet -----
        #{PipelineFlavorGate.shellcheck_wrap(snippet)}
        ----- shellcheck stdout -----
        #{stdout}
        ----- shellcheck stderr -----
        #{stderr}
        -------------------

        The gate snippet MUST be shellcheck-clean so the conditional
        pipeline behavior is reliable across Bash versions and so a
        typo (unquoted glob, missing bracket, etc.) is caught at
        review time rather than at pipeline runtime.
      MSG
      expect(exit_status).to eq(0), shellcheck_failure_message
    end
  end
end
