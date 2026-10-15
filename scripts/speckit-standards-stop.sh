#!/usr/bin/env bash
# Claude Code Stop hook. When an interactive session tries to finish with a
# blocking standards finding in its uncommitted work, this sends it back once
# with the reason. setup.sh installs it to .claude/hooks/ and registers it under
# "Stop" in .claude/settings.json; delete that entry to opt out.
#
# Fails open: every exit is 0, and anything unexpected means no opinion, never a
# stuck session. Only the last step prints.
set -u

input=$(cat 2>/dev/null) || exit 0
[ -n "$input" ] || exit 0

# The two keys this hook reads: jq when it is installed (input it cannot parse
# is no opinion), else sed on each key.
if command -v jq >/dev/null 2>&1; then
  parsed=$(printf '%s' "$input" | jq -r '[(.cwd // ""), (.stop_hook_active // false | tostring)] | join("\n")' 2>/dev/null) || exit 0
  cwd=${parsed%%$'\n'*}
  active=${parsed#*$'\n'}
else
  cwd=$(printf '%s' "$input" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
  active=$(printf '%s' "$input" | sed -n 's/.*"stop_hook_active"[[:space:]]*:[[:space:]]*\([a-z]*\).*/\1/p' | head -n 1)
fi

# Claude is already continuing because of this hook. Never loop.
[ "$active" != true ] || exit 0

for dir in "$cwd" "${CLAUDE_PROJECT_DIR:-}" .; do
  [ -n "$dir" ] || continue
  if cd "$dir" 2>/dev/null; then break; fi
done
root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$root" 2>/dev/null || exit 0

engine=.specify/scripts/bash/speckit-standards.sh
[ -x "$engine" ] || exit 0
[ -n "$(git status --porcelain --untracked-files=all 2>/dev/null)" ] || exit 0

# plain-language is advice and the slow group; the blocking rules live in
# lexicon and pr-shape.
out=$(bash "$engine" --working-tree --blocking-only --only lexicon,pr-shape --format hook 2>/dev/null)
rc=$?
if [ "$rc" -eq 1 ] && [ -n "$out" ]; then
  printf '%s\n' "$out"
fi
exit 0
