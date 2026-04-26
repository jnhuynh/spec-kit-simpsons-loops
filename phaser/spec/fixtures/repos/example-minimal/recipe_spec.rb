# frozen_string_literal: true

require 'open3'

# Pull in the spec_helper so the GitFixtureHelper mixin (and the
# fixture-recipe loader at `spec/support/fixture_recipes.rb`) are wired
# into every example group. RSpec adds `./spec` to `$LOAD_PATH` by
# default, so `require 'spec_helper'` resolves without further
# configuration. Calling it explicitly here keeps this spec runnable
# in isolation (`bundle exec rspec spec/fixtures/repos/example-minimal/recipe_spec.rb`)
# regardless of whether a future `.rspec` file auto-requires it.
require 'spec_helper'

# Smoke spec for the example-minimal fixture recipe (feature
# 007-multi-phase-pipeline; T029 sanity check).
#
# T029 ships a five-commit synthetic Git history that downstream specs
# (the engine integration test, the CLI contract test, the
# no-domain-leakage scan, and the SC-002 determinism check) consume to
# exercise the engine end-to-end. Those downstream specs depend on the
# recipe producing the exact commit count, branch layout, paths,
# subjects, and trailers documented in `recipe.rb`. This spec pins the
# recipe's externally observable shape so a future edit to the recipe
# that breaks a downstream spec fails here first with an explanation,
# not later with a confusing classification mismatch in the engine
# spec.
#
# The recipe is loaded automatically by `spec/support/fixture_recipes.rb`
# (which `spec_helper.rb` auto-requires from `spec/support/`); the spec
# only needs to call `ExampleMinimalFixture.build(self)`.
RSpec.describe 'example-minimal fixture recipe' do # rubocop:disable RSpec/DescribeClass
  subject(:repo_path) { ExampleMinimalFixture.build(self) }

  after { cleanup_fixture_repos }

  # Helper: run a `git` command inside the fixture repo and return the
  # captured stdout (chomped). Raises on non-zero exit so a broken
  # fixture surfaces as a hard failure with the underlying git error
  # rather than as a confusing assertion mismatch downstream.
  def git_in_repo(*args)
    stdout, stderr, status = Open3.capture3('git', '-C', repo_path, *args)
    raise "git #{args.join(' ')} failed: #{stderr}" unless status.success?

    stdout.chomp
  end

  # Helper: list every commit on the feature branch (oldest-first) as
  # an array of `{ sha:, subject:, trailers: }` Hashes. Built from
  # `git log` so the spec asserts properties of the actual fixture, not
  # of the recipe's in-memory data structures.
  #
  # Format: each commit emits `<sha>\x00<subject>\x00<trailers-block>\x1e`
  # where the trailers block (from `%(trailers:only,unfold)`) is itself
  # multi-line. The `\x1e` (ASCII record separator) is the safest way to
  # split entries because it cannot legally appear inside any of the
  # captured fields, while a plain `\n` would collide with the trailer
  # block's own newlines.
  def feature_commits
    range = "#{ExampleMinimalFixture::DEFAULT_BRANCH}..#{ExampleMinimalFixture::FEATURE_BRANCH}"
    log = git_in_repo('log', '--reverse',
                      '--format=%H%x00%s%x00%(trailers:only,unfold)%x1e', range)
    log.split("\x1e").map(&:strip).reject(&:empty?).map { |entry| build_commit_hash(entry) }
  end

  def build_commit_hash(log_entry)
    sha, subject, trailers_block = log_entry.split("\x00", 3)
    trailers = (trailers_block || '').each_line.with_object({}) do |line, acc|
      key, value = line.chomp.split(': ', 2)
      acc[key] = value if key && value
    end
    { sha: sha, subject: subject, trailers: trailers }
  end

  describe 'repository layout' do
    it 'creates a real Git repository at the returned path' do
      expect(File.directory?(File.join(repo_path, '.git'))).to be(true)
    end

    it 'sets the integration branch to ExampleMinimalFixture::DEFAULT_BRANCH' do
      branches = git_in_repo('branch', '--format=%(refname:short)').split("\n")
      expect(branches).to include(ExampleMinimalFixture::DEFAULT_BRANCH)
    end

    it 'creates the feature branch named ExampleMinimalFixture::FEATURE_BRANCH' do
      branches = git_in_repo('branch', '--format=%(refname:short)').split("\n")
      expect(branches).to include(ExampleMinimalFixture::FEATURE_BRANCH)
    end

    it 'leaves HEAD on the feature branch after building' do
      head_branch = git_in_repo('rev-parse', '--abbrev-ref', 'HEAD')
      expect(head_branch).to eq(ExampleMinimalFixture::FEATURE_BRANCH)
    end
  end

  describe 'feature-branch commit history' do
    it 'records exactly five commits on the feature branch ahead of main' do
      expect(feature_commits.length).to eq(5)
    end

    it 'orders the commit subjects per ExampleMinimalFixture::FEATURE_COMMIT_SUBJECTS' do
      subjects = feature_commits.map { |c| c[:subject] }
      expect(subjects).to eq(ExampleMinimalFixture::FEATURE_COMMIT_SUBJECTS)
    end

    it 'tags commit 2 with Phase-Type: schema (operator-tag exercise)' do
      expect(feature_commits[1][:trailers]).to include('Phase-Type' => 'schema')
    end

    it 'tags commit 3 with Phase-Type: misc (operator-tag exercise)' do
      expect(feature_commits[2][:trailers]).to include('Phase-Type' => 'misc')
    end

    it 'leaves commits 1, 4, 5 untagged so the cascade falls through to inference / default' do
      [0, 3, 4].each do |idx|
        expect(feature_commits[idx][:trailers]).not_to have_key('Phase-Type'),
                                                       "expected commit #{idx + 1} to have no Phase-Type trailer"
      end
    end
  end

  describe 'feature-branch file changes' do
    it 'introduces each documented path exactly once across the feature commits' do
      range = "#{ExampleMinimalFixture::DEFAULT_BRANCH}..#{ExampleMinimalFixture::FEATURE_BRANCH}"
      changed_paths = git_in_repo('log', '--name-only', '--pretty=format:', range)
                      .split("\n").reject(&:empty?).sort
      expect(changed_paths).to eq(ExampleMinimalFixture::FEATURE_COMMIT_PATHS.sort)
    end

    it 'places exactly two migrations under db/migrate/ to exercise the schema-by-path rule' do
      migrations = ExampleMinimalFixture::FEATURE_COMMIT_PATHS.grep(%r{\Adb/migrate/})
      expect(migrations.length).to eq(2)
    end

    it 'places at least one path outside any inference glob to exercise the default cascade' do
      non_migration = ExampleMinimalFixture::FEATURE_COMMIT_PATHS.reject { |p| p.start_with?('db/migrate/') }
      expect(non_migration).not_to be_empty
    end
  end

  describe 'expected classification metadata (drives downstream engine specs)' do
    it 'declares one source per commit in cascade-precedence order' do
      sources = ExampleMinimalFixture::FEATURE_COMMIT_SOURCES
      expect(sources.length).to eq(ExampleMinimalFixture::FEATURE_COMMIT_SUBJECTS.length)
    end

    it 'covers all three cascade sources (inference, operator_tag, default)' do
      expect(ExampleMinimalFixture::FEATURE_COMMIT_SOURCES.uniq.sort)
        .to eq(%i[default inference operator_tag])
    end

    it 'declares one task type per commit, exercising both schema and misc' do
      types = ExampleMinimalFixture::FEATURE_COMMIT_TASK_TYPES
      expect(types.length).to eq(ExampleMinimalFixture::FEATURE_COMMIT_SUBJECTS.length)
      expect(types.uniq.sort).to eq(%w[misc schema])
    end

    it 'orders misc commits AFTER all schema commits so the misc-after-schema precedent rule is satisfied' do
      types = ExampleMinimalFixture::FEATURE_COMMIT_TASK_TYPES
      first_misc = types.index('misc')
      last_schema = types.rindex('schema')
      expect(first_misc).to be > last_schema
    end
  end

  describe 'determinism (FR-002, SC-002 — fixture must be byte-stable)' do
    # Helper: capture the feature-branch commit hashes from a fresh fixture
    # build, then immediately tear it down so each call is hermetic.
    # Returns the hashes as an Array of Strings in oldest-first order.
    def capture_feature_hashes
      path = ExampleMinimalFixture.build(self)
      range = "#{ExampleMinimalFixture::DEFAULT_BRANCH}..#{ExampleMinimalFixture::FEATURE_BRANCH}"
      stdout, _stderr, status = Open3.capture3('git', '-C', path, 'log', '--reverse',
                                               '--format=%H', range)
      raise 'git log failed' unless status.success?

      stdout.split("\n")
    ensure
      cleanup_fixture_repos
    end

    it 'produces the same feature-branch commit hashes across two consecutive builds' do
      first_hashes = capture_feature_hashes
      second_hashes = capture_feature_hashes

      expect(second_hashes).to eq(first_hashes)
    end
  end
end
