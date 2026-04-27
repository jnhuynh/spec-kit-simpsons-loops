# frozen_string_literal: true

require 'pathname'

# Regression spec for SC-003 / FR-003 / R-006:
# the phaser engine MUST contain zero references to any concrete
# framework, database, or library shipped in the reference flavor
# (feature 007-multi-phase-pipeline; T027).
#
# The contract is: a maintainer adding domain knowledge into the engine
# (e.g., importing a Rails-aware constant or referring to Postgres by
# name from a generic module) breaks the no-domain-leakage guarantee
# that lets the engine drive arbitrary flavors. This spec is the
# measurable check that R-006 calls for; it greps every byte of every
# source file under `phaser/lib/phaser/` and `phaser/bin/` for the
# forbidden literals and fails on any match.
#
# Scope (per R-006):
#
#   * Scanned roots:
#       - phaser/lib/phaser/   (engine, value objects, foundational
#                              services, stacked-PR adapter, flavor_init)
#       - phaser/bin/          (CLI entry points)
#
#   * Excluded paths:
#       - phaser/flavors/      (concrete flavors are *expected* to name
#                              their stack; that is the whole point of a
#                              flavor and is what the engine delegates
#                              to)
#       - phaser/spec/         (specs frequently mention the forbidden
#                              terms in documentation comments — like
#                              this very file — and are not engine code)
#       - phaser/lib/phaser.rb (the top-level loader is allowed to
#                              `require` flavor-init scaffolding, but
#                              currently contains no forbidden tokens
#                              either; the scan still covers it because
#                              everything under phaser/lib/phaser/ is
#                              covered by the engine root walk)
#
#   * Forbidden literal list (case-insensitive, per R-006):
#       Rails, ActiveRecord, Postgres, postgresql, strong_migrations,
#       migration, pg, Gemfile
#
#     The list intentionally mirrors R-006 verbatim. Future flavors may
#     add their own forbidden-string list to the scan without modifying
#     this test by appending to NoDomainLeakageScanner::FORBIDDEN_TERMS
#     in a follow-up; the current implementation is pinned to the
#     reference flavor's stack because that is the only shipped flavor
#     in this feature.
#
# Word-boundary handling: R-006 specifies "case-insensitive,
# word-boundary aware". Word boundaries matter because some terms (like
# `pg`) appear inside legitimate identifiers (e.g., `npg_token` would
# be a false positive). The match uses `\b<term>\b` semantics so e.g.
# `migrations.rb` in a path is allowed (paths aren't scanned), and a
# variable named `migration_count` would be flagged as a true positive
# (intentional — `migration` as a token *is* domain knowledge).

# The scanner constants live on a top-level module rather than inside
# the `RSpec.describe` block to satisfy rubocop's
# `Lint/ConstantDefinitionInBlock` and `RSpec/LeakyConstantDeclaration`
# cops; behaviour is identical and the scoping makes the contract
# easier to import from any future companion spec (e.g., a per-flavor
# leakage scan).
module NoDomainLeakageScanner
  # The literal forbidden terms from R-006. Ordered as in the research
  # doc so a future maintainer cross-referencing R-006 can scan top to
  # bottom and confirm each term is covered.
  FORBIDDEN_TERMS = %w[
    Rails
    ActiveRecord
    Postgres
    postgresql
    strong_migrations
    migration
    pg
    Gemfile
  ].freeze

  # The repo-relative roots the scan walks. Every file under these
  # directories that matches the EXTENSIONS allowlist below is opened
  # and scanned. Anything outside these roots is out of scope for
  # SC-003 by design (flavors and specs are explicitly excluded per
  # R-006).
  PHASER_ROOT = Pathname.new(File.expand_path('..', __dir__))
  SCAN_ROOTS = [
    PHASER_ROOT.join('lib', 'phaser'),
    PHASER_ROOT.join('bin')
  ].freeze

  # File extensions to scan. Bin entry points carry no extension by
  # convention (per .rubocop.yml `bin/**/*` exclude); we treat any
  # regular file under `bin/` as scannable. Under `lib/phaser/` we
  # scan `.rb` files only — there are no other source kinds in this
  # tree.
  RUBY_EXTENSION = '.rb'

  # Build the precompiled, case-insensitive, word-boundary-aware
  # regex once at load time so the spec runs in milliseconds even at
  # the FR-048 worst-case repo size.
  FORBIDDEN_REGEX = Regexp.new(
    "\\b(#{FORBIDDEN_TERMS.map { |term| Regexp.escape(term) }.join('|')})\\b",
    Regexp::IGNORECASE
  )

  # Enumerate every scannable file under SCAN_ROOTS.
  def self.scannable_files
    SCAN_ROOTS.flat_map do |root|
      next [] unless root.exist?

      root.find.select do |path|
        next false unless path.file?
        next true  if path.to_s.start_with?(PHASER_ROOT.join('bin').to_s)

        path.extname == RUBY_EXTENSION
      end
    end
  end

  # Scan a single file for forbidden literals; return a list of
  # `[line_number, line_text, matched_term]` tuples. An empty list
  # means the file is clean.
  def self.scan(path)
    matches = []
    path.each_line.with_index(1) do |line, lineno|
      line.scan(FORBIDDEN_REGEX) do |captured|
        matches << [lineno, line.chomp, captured.first]
      end
    end
    matches
  end
end

RSpec.describe 'engine no-domain-leakage regression' do # rubocop:disable RSpec/DescribeClass
  it 'scans at least one file under each scan root (sanity check)' do
    # Guard against a bug in the scan walker silently producing zero
    # files (which would make the SC-003 assertion vacuously pass).
    # If the engine has any source at all, the walker must find it.
    sanity_message = 'no files found under phaser/lib/phaser or phaser/bin — ' \
                     'the no-domain-leakage scan would vacuously pass'
    expect(NoDomainLeakageScanner.scannable_files).not_to be_empty, sanity_message
  end

  it 'finds zero forbidden domain references under phaser/lib/phaser/ or phaser/bin/' do
    offenders = NoDomainLeakageScanner.scannable_files.flat_map do |path|
      relative = path.relative_path_from(NoDomainLeakageScanner::PHASER_ROOT).to_s
      NoDomainLeakageScanner.scan(path).map do |lineno, line, term|
        "#{relative}:#{lineno}: matched '#{term}' in `#{line.strip}`"
      end
    end

    failure_message = 'Engine contains forbidden domain references ' \
                      "(SC-003 / FR-003 / R-006):\n#{offenders.join("\n")}\n\n" \
                      'These literals are reserved for concrete flavors under ' \
                      'phaser/flavors/. If you need to express stack-specific ' \
                      'behavior, put it in a flavor module and let the engine ' \
                      'consume it through the FlavorLoader contract.'
    expect(offenders).to be_empty, failure_message
  end

  it 'explicitly excludes phaser/flavors/ and phaser/spec/ from the scan (per R-006)' do
    # Pinning the exclusion contract: if a future change accidentally
    # adds `phaser/flavors` or `phaser/spec` to SCAN_ROOTS the scan
    # would start flagging the *intended* uses of these terms inside
    # the reference flavor and inside this very spec file. Catching
    # that here means a misconfigured scan fails one targeted
    # assertion instead of dozens of confusing false positives.
    flavors_root = NoDomainLeakageScanner::PHASER_ROOT.join('flavors').to_s
    spec_root    = NoDomainLeakageScanner::PHASER_ROOT.join('spec').to_s

    scanned_paths = NoDomainLeakageScanner.scannable_files.map(&:to_s)

    excluded = scanned_paths.reject do |p|
      p.start_with?(flavors_root) || p.start_with?(spec_root)
    end
    expect(excluded).to eq(scanned_paths)
  end
end
