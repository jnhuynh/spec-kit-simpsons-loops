# frozen_string_literal: true

require 'pathname'

# Regression spec for FR-044 / FR-047 / SC-013 / quickstart.md
# "Pattern: gh Subprocess Wrapper" / plan.md D-009:
# the `gh` CLI MUST be invoked from exactly ONE place in the production
# code — the `Phaser::StackedPrs::GitHostCli` wrapper at
# `phaser/lib/phaser/stacked_prs/git_host_cli.rb` — and nowhere else
# (feature 007-multi-phase-pipeline; T071).
#
# The contract this spec pins is structural, not behavioural: behaviour
# tests for the wrapper itself live in `git_host_cli_spec.rb` (T067).
# What this spec catches is a maintainer accidentally re-introducing a
# direct `gh` invocation from a downstream module — typically through
# the convenient-but-forbidden `system('gh ...')` or `\`gh ...\``
# (backtick subshell) idioms.
#
# Why a structural test, not a behavioural one:
#
#   * The wrapper exists so the credential-leak guard (FR-047) and the
#     stderr first-line-only forwarding rule (plan.md "Pattern: gh
#     Subprocess Wrapper") run unconditionally on every `gh` outcome.
#     Any direct `gh` call from another module bypasses both guards and
#     is therefore a SC-013 regression risk regardless of whether the
#     specific call happens to leak in any one fixture.
#
#   * Catching the regression at the source-text level lets the suite
#     stay fast (this is a millisecond-scale grep) and lets the failure
#     point at the offending line directly so a reviewer does not have
#     to chase a credential-leak failure in some unrelated downstream
#     spec.
#
# Scope of the scan:
#
#   * Scanned root: `phaser/lib/` (everything under `lib/phaser/` plus
#     the top-level `lib/phaser.rb` loader).
#
#   * Excluded path: `phaser/lib/phaser/stacked_prs/git_host_cli.rb` —
#     this is the wrapper itself; it is the SOLE legitimate caller of
#     the `gh` binary. The exclusion list is intentionally a single
#     file so that adding a second exclusion requires deliberate review.
#
#   * Forbidden idioms (case-insensitive on the binary token; the
#     surrounding syntax is matched literally):
#
#       1. `system('gh', ...)`        — the explicit-args form.
#       2. `system("gh ...")`         — the shell-string form.
#       3. `system('gh ...')`         — single-quoted shell-string form.
#       4. `Kernel.system('gh ...')`  — the qualified form.
#       5. `\`gh ...\``               — backtick subshell.
#       6. `%x{gh ...}` / `%x[gh ...]` / `%x(gh ...)` — `%x` subshell.
#       7. `IO.popen('gh ...')` / `Open3.popen3('gh', ...)` — every
#          other Process-spawning idiom that names `gh` directly.
#
#   * The wrapper's own canonical idiom is `Open3.capture3('gh', *args)`
#     (per `git_host_cli_spec.rb`'s subprocess-invocation-surface
#     describe block). Any new module that needs to talk to `gh` MUST
#     route through `Phaser::StackedPrs::GitHostCli` rather than
#     re-introducing one of the idioms above.

# The scanner constants live on a top-level module rather than inside
# the `RSpec.describe` block to satisfy rubocop's
# `Lint/ConstantDefinitionInBlock` and `RSpec/LeakyConstantDeclaration`
# cops. The pattern mirrors `engine_no_domain_leakage_spec.rb` (T027),
# which is the structural-grep precedent in this codebase.
module GhInvocationIsolationScanner
  PHASER_ROOT = Pathname.new(File.expand_path('../..', __dir__))
  LIB_ROOT = PHASER_ROOT.join('lib')

  # The wrapper itself. This is the SOLE file in `phaser/lib/` that is
  # permitted to mention the `gh` binary as a subprocess target. Every
  # other file MUST go through `Phaser::StackedPrs::GitHostCli#run`.
  WRAPPER_PATH = LIB_ROOT.join('phaser', 'stacked_prs', 'git_host_cli.rb')

  RUBY_EXTENSION = '.rb'

  # The forbidden-idiom regexes. Each one matches a Ruby idiom that
  # spawns a subprocess naming `gh` directly. The patterns are written
  # to be as narrow as possible so they do not flag legitimate prose
  # references to `gh` inside comments — only actual subprocess-spawning
  # syntax matches.
  #
  # Why each pattern is shaped the way it is:
  #
  #   * `Kernel.system` and bare `system` both spawn subprocesses, so
  #     both forms are matched. The qualifying `Kernel.` prefix is
  #     optional in the regex.
  #
  #   * The backtick form (`\`gh ...\``) is matched by looking for a
  #     literal backtick followed by `gh ` (with the trailing space) so
  #     identifiers like `pgh_token` inside backticks would not match —
  #     only an actual `gh` command invocation does.
  #
  #   * The `%x` form supports three bracket pairs (`{}`, `[]`, `()`),
  #     mirroring Ruby's literal-string syntax.
  #
  #   * `IO.popen` and `Open3.popen3` are caught alongside their
  #     `system`/backtick cousins because the contract is that the
  #     wrapper is the SOLE process-spawn surface — even a non-blocking
  #     popen would bypass the credential-leak guard.
  #
  #   * `Open3.capture3('gh'` is the wrapper's own canonical idiom.
  #     This pattern is intentionally NOT in the forbidden list; the
  #     wrapper file is excluded from the scan above, so its presence
  #     there is fine, and any other file that names `Open3.capture3`
  #     with a `gh` literal is forbidden too. We catch the latter via
  #     a dedicated regex below.
  # Each pattern accepts both the positional-args form
  # (`Open3.capture3('gh', 'auth', 'status')`) and the array-args form
  # (`Open3.capture3(['gh', 'auth', 'status'])`) because Ruby allows
  # both at every Process-spawning entry point. The leading `(` may be
  # immediately followed by a `[` (array-args form) or by a quote
  # (positional form); the literal `gh` token then follows in either
  # case. Anchoring on `\bgh\b` after the opening quote pins the binary
  # name so identifiers like `ghost_record` cannot match.
  FORBIDDEN_PATTERNS = [
    {
      name: "system('gh' ...) / system(\"gh ...\")",
      regex: /(?:Kernel\.)?system\s*\(\s*\[?\s*['"]gh\b/
    },
    {
      name: '`gh ...` (backtick subshell)',
      regex: /`gh[\s`]/
    },
    {
      name: '%x{gh ...} / %x[gh ...] / %x(gh ...)',
      regex: /%x\s*[{\[(]\s*gh\b/
    },
    {
      name: "IO.popen('gh' ...)",
      regex: /IO\.popen\s*\(\s*\[?\s*['"]gh\b/
    },
    {
      name: "Open3.popen3('gh' ...) / Open3.popen2('gh' ...) / Open3.popen2e('gh' ...)",
      regex: /Open3\.popen[23]e?\s*\(\s*\[?\s*['"]gh\b/
    },
    {
      name: "Open3.capture3('gh' ...) / Open3.capture2('gh' ...) / Open3.capture2e('gh' ...)",
      regex: /Open3\.capture[23]e?\s*\(\s*\[?\s*['"]gh\b/
    }
  ].freeze

  # Walk every `.rb` file under `phaser/lib/` except the wrapper itself.
  def self.scannable_files
    return [] unless LIB_ROOT.exist?

    LIB_ROOT.find.select do |path|
      next false unless path.file?
      next false unless path.extname == RUBY_EXTENSION
      next false if path == WRAPPER_PATH

      true
    end
  end

  # Scan a single file for any forbidden idiom; return a list of
  # `[line_number, line_text, pattern_name]` tuples. An empty list
  # means the file is clean.
  def self.scan(path)
    matches = []
    path.each_line.with_index(1) do |line, lineno|
      FORBIDDEN_PATTERNS.each do |pattern|
        next unless line.match?(pattern[:regex])

        matches << [lineno, line.chomp, pattern[:name]]
      end
    end
    matches
  end

  # Walk every scannable file and return a list of human-readable
  # offender strings, one per match. Empty list means the codebase is
  # clean. Helper exists so the corresponding spec example stays well
  # under rubocop's RSpec/ExampleLength ceiling.
  def self.collect_offenders
    scannable_files.flat_map do |path|
      relative = path.relative_path_from(PHASER_ROOT).to_s
      scan(path).map do |lineno, line, pattern_name|
        "#{relative}:#{lineno}: matched [#{pattern_name}] in `#{line.strip}`"
      end
    end
  end

  # The fixed remediation text appended to the failure message when a
  # forbidden idiom is found. Keeping it as a constant rather than an
  # inline string in the spec keeps the failing-example output stable
  # and prevents the example block from exceeding rubocop's length
  # ceiling.
  OFFENDER_REMEDIATION = <<~MSG.chomp
    The `gh` CLI MUST be invoked from exactly one place: `Phaser::StackedPrs::GitHostCli#run`
    at phaser/lib/phaser/stacked_prs/git_host_cli.rb. Every other caller MUST route through
    that wrapper so the credential-leak guard (FR-047) and the stderr first-line-only
    forwarding rule (plan.md "Pattern: gh Subprocess Wrapper") run unconditionally on every
    subprocess outcome.
  MSG
end

RSpec.describe 'gh invocation isolation regression' do # rubocop:disable RSpec/DescribeClass
  it 'finds at least one file under phaser/lib/ to scan (sanity check)' do
    # Guard against a bug in the scan walker silently producing zero
    # files (which would make the FR-044 assertion vacuously pass).
    # If the engine has any source at all, the walker must find it.
    sanity_message = 'no files found under phaser/lib/ — the gh-invocation-isolation ' \
                     'scan would vacuously pass'
    expect(GhInvocationIsolationScanner.scannable_files).not_to be_empty, sanity_message
  end

  it 'excludes the wrapper file itself from the scan (the wrapper is the SOLE legitimate caller)' do
    # The wrapper IS allowed to invoke `gh` (that is its whole purpose);
    # every other file is not. Pinning the exclusion contract here means
    # a misconfigured scan that accidentally scanned the wrapper would
    # fail this targeted assertion instead of the (correctly-empty)
    # main assertion below.
    scanned_paths = GhInvocationIsolationScanner.scannable_files.map(&:to_s)

    expect(scanned_paths).not_to include(GhInvocationIsolationScanner::WRAPPER_PATH.to_s)
  end

  it 'finds zero direct gh invocations under phaser/lib/ outside the wrapper' do
    offenders = GhInvocationIsolationScanner.collect_offenders
    failure_message = 'phaser/lib/ contains a direct gh invocation outside the wrapper ' \
                      "(FR-044 / FR-047 / SC-013):\n#{offenders.join("\n")}\n\n" \
                      "#{GhInvocationIsolationScanner::OFFENDER_REMEDIATION}"
    expect(offenders).to be_empty, failure_message
  end

  describe 'forbidden-idiom coverage (each pattern catches its own canonical example)' do
    # These examples synthesise the exact source strings the regex
    # bank is designed to catch and assert each pattern matches its
    # canonical example. This pins the regex contract so a future
    # refactor that "simplifies" a pattern into something narrower
    # would fail one of these assertions before it could let a real
    # regression slip through unnoticed.

    let(:patterns_by_name) do
      GhInvocationIsolationScanner::FORBIDDEN_PATTERNS.to_h { |pat| [pat[:name], pat[:regex]] }
    end

    # `expect(regex).to match(string)` is the rubocop-rspec-friendly
    # spelling of "this regex catches this synthetic source line": the
    # `match` matcher accepts either order, but putting the regex on
    # the left makes the SUT (the regex) the explicit subject of the
    # assertion (RSpec/ExpectActual).

    it "catches the bare system('gh', ...) form" do
      regex = patterns_by_name["system('gh' ...) / system(\"gh ...\")"]
      expect(regex).to match("system('gh', 'auth', 'status')")
    end

    it 'catches the system("gh ...") shell-string form' do
      regex = patterns_by_name["system('gh' ...) / system(\"gh ...\")"]
      expect(regex).to match('system("gh auth status")')
    end

    it "catches the Kernel.system('gh' ...) qualified form" do
      regex = patterns_by_name["system('gh' ...) / system(\"gh ...\")"]
      expect(regex).to match("Kernel.system('gh', 'auth', 'status')")
    end

    it 'catches the backtick subshell form' do
      regex = patterns_by_name['`gh ...` (backtick subshell)']
      expect(regex).to match('result = `gh auth status`')
    end

    it 'catches the %x{gh ...} brace form' do
      regex = patterns_by_name['%x{gh ...} / %x[gh ...] / %x(gh ...)']
      expect(regex).to match('result = %x{gh auth status}')
    end

    it 'catches the %x[gh ...] bracket form' do
      regex = patterns_by_name['%x{gh ...} / %x[gh ...] / %x(gh ...)']
      expect(regex).to match('result = %x[gh auth status]')
    end

    it 'catches the %x(gh ...) paren form' do
      regex = patterns_by_name['%x{gh ...} / %x[gh ...] / %x(gh ...)']
      expect(regex).to match('result = %x(gh auth status)')
    end

    it "catches the IO.popen('gh' ...) form (both positional and array-args)" do
      regex = patterns_by_name["IO.popen('gh' ...)"]
      expect(regex).to match("IO.popen('gh auth status')")
      expect(regex).to match("IO.popen(['gh', 'auth', 'status'])")
    end

    it "catches the Open3.popen3('gh' ...) form (both positional and array-args)" do
      regex = patterns_by_name[
        "Open3.popen3('gh' ...) / Open3.popen2('gh' ...) / Open3.popen2e('gh' ...)"
      ]
      expect(regex).to match("Open3.popen3('gh', 'auth', 'status')")
      expect(regex).to match("Open3.popen2('gh', 'auth', 'status')")
      expect(regex).to match("Open3.popen2e('gh', 'auth', 'status')")
      expect(regex).to match("Open3.popen3(['gh', 'auth', 'status'])")
    end

    it "catches the Open3.capture3('gh' ...) form when used outside the wrapper" do
      # The wrapper file is excluded from the scan, so its own use of
      # `Open3.capture3('gh', ...)` is allowed. But ANY other file
      # using the same idiom must be flagged — the wrapper is the SOLE
      # legitimate caller per plan.md D-009.
      regex = patterns_by_name[
        "Open3.capture3('gh' ...) / Open3.capture2('gh' ...) / Open3.capture2e('gh' ...)"
      ]
      expect(regex).to match("Open3.capture3('gh', 'auth', 'status')")
      expect(regex).to match("Open3.capture2('gh', 'auth', 'status')")
      expect(regex).to match("Open3.capture2e('gh', 'auth', 'status')")
      expect(regex).to match("Open3.capture3(['gh', 'auth', 'status'])")
    end

    it 'does not match prose mentions of "gh" inside a comment' do
      # Negative-control: a doc comment that mentions "gh" as English
      # text must NOT trip any pattern. This protects the heavy
      # documentation comments throughout the codebase from triggering
      # false positives.
      docstring = '# This wrapper invokes the gh CLI as the sole subprocess path.'
      GhInvocationIsolationScanner::FORBIDDEN_PATTERNS.each do |pattern|
        expect(pattern[:regex]).not_to match(docstring),
                                       "comment-form prose tripped pattern [#{pattern[:name]}]"
      end
    end

    it 'does not match identifiers that happen to contain "gh" as a substring' do
      # Negative-control: a variable named `length` or `weight` or
      # `ghost_record` MUST NOT trigger any pattern. The patterns are
      # anchored on subprocess-spawning syntax + the literal `gh`
      # binary token, never on bare identifier substrings.
      benign_lines = [
        'length = commits.length',
        'weight = phase.weight',
        'ghost_record = repo.lookup(:ghost)',
        '# pgh_token is a fictional credential-shaped substring'
      ]
      benign_lines.each do |line|
        GhInvocationIsolationScanner::FORBIDDEN_PATTERNS.each do |pattern|
          expect(pattern[:regex]).not_to match(line),
                                         "benign line `#{line}` tripped pattern [#{pattern[:name]}]"
        end
      end
    end
  end
end
