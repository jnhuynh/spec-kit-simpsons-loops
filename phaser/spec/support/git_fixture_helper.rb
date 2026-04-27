# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require 'open3'

# Test helper that builds throwaway Git fixture repositories on disk for
# Phaser engine specs (feature 007-multi-phase-pipeline).
#
# Why a helper module instead of literal repos checked into the tree:
#
#   * Synthetic Git repositories can carry committer identity, author
#     timestamps, and trailers that vary per machine. Building them at
#     test time with a fixed identity and frozen clock keeps the
#     fixtures byte-stable across developer workstations and CI.
#
#   * The phaser engine reads commits via `git log` (T036), so the
#     fixtures must be real Git histories, not flat YAML stubs. The
#     helper's `make_fixture_repo` returns a path the engine can be
#     pointed at directly.
#
#   * Per CLAUDE.md "Process Hygiene", every test that creates a
#     temporary directory must clean it up. The helper exposes
#     `make_fixture_repo` and `cleanup_fixture_repos` so individual
#     specs can opt into per-example teardown via `after(:each)` and
#     the suite-wide `after(:suite)` hook in `spec_helper.rb` can sweep
#     anything left behind.
#
# Usage from a spec:
#
#   RSpec.describe "Phaser::Engine" do
#     let(:repo_path) do
#       make_fixture_repo("example-minimal") do |repo|
#         repo.commit(
#           subject: "Add nullable column",
#           files: { "db/migrate/001_add_email.rb" => "# add email\n" }
#         )
#         repo.commit(
#           subject: "Backfill email",
#           files: { "lib/tasks/backfill.rake" => "# backfill\n" },
#           trailers: { "Phase-Type" => "data backfill" }
#         )
#       end
#     end
#
#     after { cleanup_fixture_repos }
#   end
#
# The `repo` block argument is a `GitFixtureHelper::Builder` (defined
# below) that exposes a small commit-authoring DSL. The DSL writes the
# requested files, stages them, and commits with a fixed identity and a
# deterministic author/committer timestamp so repeated runs produce
# byte-identical commit hashes (R-005, FR-002, SC-002).
module GitFixtureHelper
  # Fixed identity used for every fixture commit. Held constant so
  # commit hashes are reproducible across machines.
  FIXTURE_AUTHOR_NAME  = 'Phaser Fixture'
  FIXTURE_AUTHOR_EMAIL = 'fixture@phaser.test'

  # First fixture timestamp. Each subsequent commit advances by 60s so
  # author timestamps remain monotonic without colliding.
  FIXTURE_EPOCH = '2026-04-25T00:00:00Z'

  # Per-thread registry of fixture repo paths created during a single
  # spec example. `cleanup_fixture_repos` reads this list and removes
  # each path in turn, then clears the list. Thread-local so parallel
  # RSpec runs (when introduced later) cannot interfere.
  def fixture_repo_paths
    Thread.current[:phaser_fixture_repo_paths] ||= []
  end

  # Build a throwaway Git repository under a fresh temporary directory
  # and return its absolute path. The block (required) yields a
  # `Builder` that exposes the commit-authoring DSL described above.
  #
  # The `name` argument is used only as a human-readable suffix in the
  # temp directory name to make `ls /tmp` debugging less painful.
  def make_fixture_repo(name = 'phaser-fixture')
    raise ArgumentError, 'make_fixture_repo requires a block' unless block_given?

    repo_path = Dir.mktmpdir(["phaser-#{name}-", ''])
    fixture_repo_paths << repo_path

    builder = Builder.new(repo_path)
    builder.init_repo
    yield builder
    repo_path
  end

  # Remove every fixture repo created by the current example. Safe to
  # call when no repos were created. Designed for `after { ... }`
  # blocks at the example level and an `after(:suite)` sweep.
  def cleanup_fixture_repos
    while (path = fixture_repo_paths.pop)
      FileUtils.rm_rf(path)
    end
  end

  # Internal builder that wraps a single fixture repository directory.
  # Exposed only via the block argument to `make_fixture_repo` so spec
  # files never instantiate it directly.
  class Builder
    attr_reader :path

    def initialize(path)
      @path = path
      @commit_index = 0
    end

    # Initialize an empty repository on the default branch `main` with a
    # committer identity scoped to the repo (no global git config
    # mutation per CLAUDE.md "Git Discipline").
    def init_repo
      run_git('init', '--quiet', '--initial-branch=main')
      run_git('config', 'user.name',  FIXTURE_AUTHOR_NAME)
      run_git('config', 'user.email', FIXTURE_AUTHOR_EMAIL)
      run_git('config', 'commit.gpgsign', 'false')
    end

    # Author one commit on the current branch.
    #
    # Arguments:
    #
    #   * `subject:`  the commit subject line.
    #   * `body:`     optional commit body (string).
    #   * `files:`    map of relative path => content. Pass an empty
    #                 hash for a `--allow-empty` commit (used by tests
    #                 that exercise the FR-009 empty-diff filter).
    #   * `trailers:` map of trailer key => value. Each entry becomes a
    #                 trailing `Key: value` line in the commit message.
    def commit(subject:, body: nil, files: {}, trailers: {})
      write_files(files)
      stage_files(files)
      message = build_message(subject, body, trailers)
      author_date = next_author_date
      run_git_with_env(
        { 'GIT_AUTHOR_DATE' => author_date, 'GIT_COMMITTER_DATE' => author_date },
        'commit',
        commit_args(files),
        '-m', message
      )
      head_sha
    end

    # Switch to a branch (creating it if needed) so multi-branch
    # fixtures can be assembled.
    def checkout(branch, create: false)
      args = ['checkout', '--quiet']
      args << '-b' if create
      args << branch
      run_git(*args)
    end

    # Return the SHA of the current HEAD.
    def head_sha
      stdout, = run_git('rev-parse', 'HEAD')
      stdout.strip
    end

    private

    # Build the commit message, appending trailers as `Key: Value` lines
    # separated from the body by a blank line so `git interpret-trailers`
    # reads them.
    def build_message(subject, body, trailers)
      parts = [subject]
      parts << '' << body if body
      unless trailers.empty?
        parts << ''
        trailers.each { |key, value| parts << "#{key}: #{value}" }
      end
      parts.join("\n")
    end

    def write_files(files)
      files.each do |relative_path, content|
        absolute_path = File.join(@path, relative_path)
        FileUtils.mkdir_p(File.dirname(absolute_path))
        File.write(absolute_path, content)
      end
    end

    def stage_files(files)
      return if files.empty?

      run_git('add', '--', *files.keys)
    end

    def commit_args(files)
      files.empty? ? ['--allow-empty'] : []
    end

    def next_author_date
      base = Time.parse(FIXTURE_EPOCH)
      offset_seconds = @commit_index * 60
      @commit_index += 1
      (base + offset_seconds).utc.strftime('%Y-%m-%dT%H:%M:%S+00:00')
    end

    # Invoke `git` against the fixture repo, capturing stdout/stderr so
    # failures surface as RSpec assertion errors instead of silent
    # exits. Raises on non-zero status because every fixture step is
    # expected to succeed.
    def run_git(*)
      run_git_with_env({}, *)
    end

    def run_git_with_env(env, *args)
      stdout, stderr, status = Open3.capture3(
        env,
        'git', '-C', @path, *args.flatten
      )
      raise "git #{args.flatten.join(' ')} failed (exit #{status.exitstatus}): #{stderr}" unless status.success?

      [stdout, stderr]
    end
  end
end

# Pull in `Time.parse` for the fixture-date helper above. Loaded after
# the module so the require sits next to the only call site.
require 'time'
