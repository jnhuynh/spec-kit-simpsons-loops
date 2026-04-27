# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'tmpdir'

# T093 regression: `bash setup.sh` MUST be idempotent.
#
# Running `setup.sh` twice in a row from the same target project
# directory MUST leave the working tree unchanged after the second
# run — equivalent to running `git diff` and seeing nothing.
#
# This is the test-first reproducer for the trailing-newline
# stripping bug discovered while verifying T093: `templates/setup.sh`'s
# `update_file` function passed the project-specific section to
# `printf '\n%s'` (no trailing `\n`), and shell command substitution
# strips trailing newlines from `$(...)`. The first `init` wrote a
# file ending in `\n`; the second invocation re-wrote it without a
# trailing `\n`, producing a one-byte git diff on every subsequent
# run.
#
# The fix is to ensure the rewrite preserves the trailing newline so
# the file is byte-identical to the first init.
RSpec.describe 'setup.sh idempotency' do # rubocop:disable RSpec/DescribeClass
  let(:repo_root) { File.expand_path('../..', __dir__) }
  let(:setup_script) { File.join(repo_root, 'setup.sh') }

  it 'leaves the target project byte-identical after a second run' do
    Dir.mktmpdir('speckit-setup-idempotency-') do |target|
      bootstrap_target_project(target)
      run_setup(target)
      snapshot_target(target)
      run_setup(target)

      status, = Open3.capture2('git', '-C', target, 'status', '--porcelain')
      diff,   = Open3.capture2('git', '-C', target, 'diff')

      expect(status.strip).to(
        eq(''),
        "Second run of setup.sh modified the working tree:\n#{status}\n#{diff}"
      )
    end
  end

  def bootstrap_target_project(target)
    FileUtils.mkdir_p(File.join(target, '.claude'))
    FileUtils.mkdir_p(File.join(target, '.specify'))
    run_git(target, 'init', '-q', '-b', 'main')
    run_git(target, 'config', 'user.email', 'test@example.com')
    run_git(target, 'config', 'user.name',  'Test')
    run_git(target, 'config', 'commit.gpgsign', 'false')
  end

  def snapshot_target(target)
    run_git(target, 'add', '-A')
    run_git(target, 'commit', '-q', '-m', 'after first setup')
  end

  def run_setup(target)
    out, err, status = Open3.capture3('bash', setup_script, chdir: target)
    raise "setup.sh failed:\nstdout:\n#{out}\nstderr:\n#{err}" unless status.success?
  end

  def run_git(dir, *args)
    out, err, status = Open3.capture3('git', '-C', dir, *args)
    raise "git #{args.join(' ')} failed:\n#{out}\n#{err}" unless status.success?
  end
end
