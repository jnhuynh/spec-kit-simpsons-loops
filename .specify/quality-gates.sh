#!/usr/bin/env bash
set -euo pipefail

# Collect shell files that actually exist
files=()
for pattern in *.sh .specify/scripts/bash/*.sh; do
  for f in $pattern; do
    [ -f "$f" ] && files+=("$f")
  done
done

if [ ${#files[@]} -eq 0 ]; then
  echo "No shell files found to check"
else
  shellcheck "${files[@]}"
fi

# Ruby quality gates for the phaser engine (R-018).
# Gated on phaser/ directory existence so existing repositories without the
# phaser feature are unaffected.
if [ -d phaser ]; then
  ( cd phaser && bundle exec rspec )
  ( cd phaser && bundle exec rubocop )
fi
