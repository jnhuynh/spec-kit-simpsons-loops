#!/usr/bin/env bash
# Commit and push using the branch-derived conventional-commit format:
#   <type>(<scope>): [<ticket>] <description>
# Branch format: <ticket>-<type>-<scope...>, e.g. c31c-feat-billing-overhaul
# Usage: speckit-commit.sh "<description>" [type-override]
set -euo pipefail

description="${1:?usage: speckit-commit.sh \"<description>\" [type-override]}"
branch=$(git branch --show-current)
ticket=$(printf '%s' "$branch" | cut -f 1 -d '-')
type="${2:-$(printf '%s' "$branch" | cut -f 2 -d '-')}"
scope=$(printf '%s' "$branch" | cut -f 3- -d '-')

git add -A
if git diff --cached --quiet; then
  echo "speckit-commit: nothing to commit"
  exit 0
fi
git commit -m "$type($scope): [$ticket] $description"
git push origin "$branch"
