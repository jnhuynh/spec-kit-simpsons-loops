#!/usr/bin/env bash
set -euo pipefail

# Collect shell files that actually exist
files=()
for pattern in *.sh .specify/scripts/bash/*.sh openclaw/*.sh openclaw/claude-runner/*.sh; do
  for f in $pattern; do
    [ -f "$f" ] && files+=("$f")
  done
done

if [ ${#files[@]} -eq 0 ]; then
  echo "No shell files found to check"
  exit 0
fi

shellcheck "${files[@]}"
