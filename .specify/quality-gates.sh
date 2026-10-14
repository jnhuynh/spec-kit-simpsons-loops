#!/usr/bin/env bash
set -euo pipefail

# Collect shell files that actually exist
files=()
for pattern in *.sh scripts/*.sh scripts/tests/*.sh specify-marge/*.sh specify-marge/baseline/*.sh .specify/scripts/bash/*.sh .specify/marge/*.sh .specify/marge/project/*.sh; do
  for f in $pattern; do
    [ -f "$f" ] && files+=("$f")
  done
done

if [ ${#files[@]} -eq 0 ]; then
  echo "No shell files found to check"
  exit 0
fi

shellcheck --severity=warning "${files[@]}"

for t in scripts/tests/test-*.sh; do
  [ -f "$t" ] || continue
  bash "$t" >/dev/null || { echo "FAIL: $t"; bash "$t" | grep '^FAIL'; exit 1; }
done
