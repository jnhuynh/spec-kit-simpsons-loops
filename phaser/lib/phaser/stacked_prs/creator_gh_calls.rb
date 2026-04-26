# frozen_string_literal: true

module Phaser
  module StackedPrs
    # Pure builders for the argv-style argument vectors the Creator
    # passes to `Phaser::StackedPrs::GitHostCli#run` (feature
    # 007-multi-phase-pipeline; T075, FR-026, FR-027).
    #
    # Why this lives in its own module:
    #
    #   The Creator class has one job: walk the manifest and decide
    #   which gh calls to issue for each phase. The exact argv shape
    #   each call uses is mechanical — gh api with `--method POST`
    #   and `-f` field flags for branch creation, gh pr create with
    #   `--head`/`--base`/`--title`/`--body` for PR creation, and so
    #   on. Pulling the argv-build helpers out keeps the Creator under
    #   the community-default Metrics/ClassLength ceiling without
    #   sacrificing the per-call docstrings each gh shape deserves.
    #
    # Every method here is a pure function from manifest data to an
    # argv array. No subprocess invocation happens here — that lives
    # in `GitHostCli`. No observability emission happens here — that
    # lives in the Creator's success/failure callbacks.
    module CreatorGhCalls
      module_function

      # gh api repos/:owner/:repo/branches/<branch> — query whether a
      # branch exists. Exit zero means the branch exists; non-zero
      # (typically the gh "Not Found (HTTP 404)" surface) means it
      # does not.
      def branch_exists_args(branch_name)
        ['api', "repos/:owner/:repo/branches/#{branch_name}"]
      end

      # gh pr list --head <branch> --json number,baseRefName --limit 1
      # — query whether a PR has been opened against the given head
      # branch. The `--limit 1` keeps the response small; the `--json`
      # subselects only the fields the Creator's skip-detection check
      # consults (number, baseRefName).
      def lookup_pr_args(branch_name)
        ['pr', 'list', '--head', branch_name, '--json', 'number,baseRefName', '--limit', '1']
      end

      # gh api repos/:owner/:repo/git/refs --method POST -f ref=... -f sha=...
      # — create a new branch ref pointing at the head of the source
      # branch. Per gh's docs, `-f` encodes a string field into the
      # POST body; `--method POST` overrides the default GET so the
      # endpoint accepts the create request.
      def create_branch_args(branch_name:, base_branch:)
        [
          'api',
          'repos/:owner/:repo/git/refs',
          '--method', 'POST',
          '-f', "ref=refs/heads/#{branch_name}",
          '-f', "sha=#{base_branch}"
        ]
      end

      # gh pr create --head <branch> --base <base> --title ... --body ...
      # — open a PR. The `--title` and `--body` values are pinned by
      # the manifest so a regenerated manifest yields a regenerated PR
      # body without operator intervention (FR-027).
      def create_pr_args(branch_name:, base_branch:, title:, body:)
        [
          'pr', 'create',
          '--head', branch_name,
          '--base', base_branch,
          '--title', title,
          '--body', body
        ]
      end

      # Build the body markdown for a phase's PR. Phase 1 has no
      # predecessor PR; phases 2..N include a "Stacked on top of …"
      # line so the dependency graph is visible from the PR page.
      def build_pr_body(phase)
        lines = []
        lines << "Phase #{phase['number']}: #{phase['name']}" if phase['name']
        lines << ''
        if phase['rollback_note']
          lines << '## Rollback'
          lines << phase['rollback_note']
          lines << ''
        end
        lines << "Stacked on top of `#{phase['base_branch']}`." if phase['number'] > 1
        lines.join("\n")
      end

      # Pull the PR number off the trailing `/pull/<n>` segment of
      # the URL that gh pr create prints to stdout. Returns nil
      # when the URL does not match (defensive — the observability
      # event still fires with nil so the operator sees the URL alone).
      def extract_pr_number(pr_url)
        match = pr_url.match(%r{/pull/(\d+)\b})
        return nil unless match

        match[1].to_i
      end
    end
  end
end
