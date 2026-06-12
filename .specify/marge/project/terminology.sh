#!/usr/bin/env bash
# terminology — a project continuity pack for THIS repo (dogfood).
#
# Guards the Marge pack taxonomy against vocabulary drift. Once the
# pack / PROJECT_GATE / quality-gate naming was settled (see
# .specify/marge/README.md), these retired terms must not creep back into the
# canonical docs. Emits a PROJECT_GATE finding per occurrence.
#
# "gate" legitimately survives only in the tag PROJECT_GATE, in "quality gate",
# and in the run-gates.sh filename — none of the patterns below match those.
# Contract: .specify/marge/README.md (review stage, diff-scoped).
set -euo pipefail

root="${SPECKIT_REPO_ROOT:-$(pwd)}"

# Canonical taxonomy docs this pack guards (relative to repo root).
docs=(
  specify-marge/README.md
  specify-marge/config/README.md
  speckit-commands/speckit.review.md
  speckit-commands/speckit.review.pr.md
  claude-agents/marge.md
  claude-agents/lisa.md
  README.md
  CLAUDE.md
  templates/CLAUDE.md
)

# Retired terms (ERE) and the message to emit for each. Parallel arrays.
patterns=(
  'script gate(s)?'
  'review gate(s)?'
  'gate-execution'
  'marge/checks/'
  'marge/gates/'
  'gates/README'
)
messages=(
  "retired term 'script gate' — use 'script pack'"
  "retired term 'review gate' — use 'review pack' / 'project pack'"
  "retired term 'gate-execution' — use 'pack-execution'"
  "retired path 'marge/checks/' — use 'marge/baseline/' (shipped) or 'marge/project/' (yours)"
  "retired path 'marge/gates/' — use 'marge/project/'; the runner is 'marge/run-gates.sh'"
  "retired path 'gates/README' — the contract now lives at '.specify/marge/README.md'"
)

diff_files="${SPECKIT_DIFF_FILES:-}"

emit() {  # $1=file:line  $2=issue message
  cat <<YAML
- file: $1
  severity: MEDIUM
  confidence: 95
  pack: project/$(basename "$0")
  rule: taxonomy-vocabulary
  issue: "$2"
  fix: "rename to the current taxonomy term (see .specify/marge/README.md glossary)"
  tags: [PROJECT_GATE]
YAML
}

for doc in "${docs[@]}"; do
  [ -f "$root/$doc" ] || continue
  # Scope to changed docs when a diff is supplied; scan all on a manual run.
  if [ -n "$diff_files" ]; then
    printf '%s\n' "$diff_files" | grep -qxF "$doc" || continue
  fi
  for i in "${!patterns[@]}"; do
    while IFS=: read -r lineno _rest; do
      [ -n "$lineno" ] || continue
      emit "$doc:$lineno" "${messages[$i]}"
    done < <(grep -niE "${patterns[$i]}" "$root/$doc" || true)
  done
done

exit 0
