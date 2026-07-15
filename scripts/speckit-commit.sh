#!/usr/bin/env bash
# Commit and push using the branch-derived conventional-commit format:
#   <type>(<scope>): [<ticket>] <description>
# Branch format: <ticket>-<type>-<scope...>, e.g. c31c-feat-billing-overhaul
# Usage: speckit-commit.sh "<description>" [type-override]
set -euo pipefail

description="${1:?usage: speckit-commit.sh \"<description>\" [type-override]}"
branch=$(git branch --show-current)

# Refuse anything that is not a <ticket>-<type>-<scope> branch: an empty name
# (detached HEAD) or a name with fewer than three dash-separated segments would
# produce a malformed commit subject and, on branches like main, push straight
# to the default branch.
if ! printf '%s' "$branch" | grep -Eq '^[^-]+-[^-]+-.+$'; then
  echo "speckit-commit: refusing to commit on branch '${branch:-<detached HEAD>}'" >&2
  echo "speckit-commit: expected branch format <ticket>-<type>-<scope>, e.g. c31c-feat-billing-overhaul" >&2
  exit 1
fi

ticket=$(printf '%s' "$branch" | cut -f 1 -d '-')
type="${2:-$(printf '%s' "$branch" | cut -f 2 -d '-')}"
scope=$(printf '%s' "$branch" | cut -f 3- -d '-')

git add -A
if git diff --cached --quiet; then
  echo "speckit-commit: nothing to commit"
else
  git commit -m "$type($scope): [$ticket] $description"
fi

# Push even when there was nothing new to commit — a prior iteration's commit
# may still be sitting unpushed (e.g. its push failed transiently).
git push origin "$branch"
