#!/usr/bin/env bash
# setup-readme-sync — a project continuity gate for THIS repo (dogfood).
#
# Invariant: every .claude/ file that setup.sh copies must also appear in the
# README "Option B: Manual" copy list, and vice versa. Those two lists drift
# easily whenever a command/agent is added. Emits PROJECT_GATE findings on
# drift. Contract: .specify/marge/README.md (review stage, diff-scoped).
set -euo pipefail

root="${SPECKIT_REPO_ROOT:-$(pwd)}"
setup="$root/setup.sh"
readme="$root/README.md"

# Only relevant when this diff touches setup.sh or README.md.
case "${SPECKIT_DIFF_FILES:-}" in
  *setup.sh*|*README.md*) ;;
  *) exit 0 ;;
esac
[ -f "$setup" ] && [ -f "$readme" ] || exit 0

# .claude/ destinations setup.sh copies: cp "$SCRIPT_DIR/..." "$PROJECT_DIR/.claude/...".
setup_targets=$(grep -E '^cp ' "$setup" \
  | grep -oE '\$PROJECT_DIR/\.claude/[^"]+' \
  | sed 's#\$PROJECT_DIR/##' | sort -u || true)

# .claude/ targets listed in the README Option B copy block.
readme_targets=$(grep -E 'cp <path-to-simpsons-loops>' "$readme" \
  | grep -oE '\.claude/[^ ]+' | sort -u || true)

emit() {  # $1=file  $2=issue
  cat <<YAML
- file: $1:0
  severity: MEDIUM
  confidence: 90
  pack: project/$(basename "$0")
  rule: setup-readme-sync
  issue: "$2"
  fix: "keep setup.sh's .claude/ copy list and README Option B in sync"
  tags: [PROJECT_GATE]
YAML
}

while IFS= read -r p; do
  [ -n "$p" ] || continue
  emit "README.md" "setup.sh copies $p but README Option B does not list it"
done < <(comm -23 <(printf '%s\n' "$setup_targets") <(printf '%s\n' "$readme_targets"))

while IFS= read -r p; do
  [ -n "$p" ] || continue
  emit "setup.sh" "README Option B lists $p but setup.sh no longer copies it"
done < <(comm -13 <(printf '%s\n' "$setup_targets") <(printf '%s\n' "$readme_targets"))

# Skills install as a whole tree (a loop in setup.sh; a `cp -R .../speckit-skills/*`
# glob in README) rather than per-file cp lines, so the comm checks above don't see
# them. Guard the pair at directory level: if one side installs skills, so must the other.
setup_has_skills=$(grep -q 'speckit-skills/' "$setup" && echo yes || echo no)
readme_has_skills=$(grep -q 'speckit-skills/' "$readme" && echo yes || echo no)
if [ "$setup_has_skills" != "$readme_has_skills" ]; then
  if [ "$setup_has_skills" = yes ]; then
    emit "README.md" "setup.sh installs the speckit-skills/ tree but README Option B does not mention speckit-skills/"
  else
    emit "setup.sh" "README Option B installs speckit-skills/ but setup.sh no longer does"
  fi
fi

exit 0
