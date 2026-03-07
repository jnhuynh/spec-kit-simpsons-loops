#!/usr/bin/env bash
#
# claude-runner/runner.sh — Mechanical launch sequence for Claude Code tmux sessions.
#
# Creates a tmux session, generates a launcher script, auto-dismisses the
# directory trust prompt, and outputs key=value pairs for the caller.
#
# Usage:
#   runner.sh --prefix <prefix> --slug <slug> --workdir <dir> --task-file <path> [--on-success <script>]
#
# --on-success <script>  Optional. If provided, bash <script> is run when Claude
#                        exits with code 0. Use for Phase 2 chaining (e.g. Ghost
#                        upload in blog-drafter). The script must exist at launch time.
#
set -euo pipefail

# --- Argument parsing ---

PREFIX=""
SLUG=""
WORKDIR=""
TASK_FILE=""
ON_SUCCESS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)     PREFIX="$2";     shift 2 ;;
    --slug)       SLUG="$2";       shift 2 ;;
    --workdir)    WORKDIR="$2";    shift 2 ;;
    --task-file)  TASK_FILE="$2";  shift 2 ;;
    --on-success) ON_SUCCESS="$2"; shift 2 ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: runner.sh --prefix <prefix> --slug <slug> --workdir <dir> --task-file <path> [--on-success <script>]" >&2
      exit 1
      ;;
  esac
done

# --- Validation ---

if [[ -z "$PREFIX" || -z "$SLUG" || -z "$WORKDIR" || -z "$TASK_FILE" ]]; then
  echo "Error: Required arguments missing: --prefix, --slug, --workdir, --task-file" >&2
  exit 1
fi

if [[ -n "$ON_SUCCESS" && ! -f "$ON_SUCCESS" ]]; then
  echo "Error: --on-success script does not exist: $ON_SUCCESS" >&2
  exit 1
fi

if ! command -v tmux >/dev/null 2>&1; then
  echo "Error: tmux is not installed" >&2
  exit 1
fi

if ! command -v claude >/dev/null 2>&1; then
  echo "Error: claude CLI is not found" >&2
  exit 1
fi

if [[ ! -d "$WORKDIR" ]]; then
  echo "Error: workdir does not exist: $WORKDIR" >&2
  exit 1
fi

if [[ ! -f "$TASK_FILE" ]]; then
  echo "Error: task-file does not exist: $TASK_FILE" >&2
  exit 1
fi

if [[ ! -s "$TASK_FILE" ]]; then
  echo "Error: task-file is empty: $TASK_FILE" >&2
  exit 1
fi

# --- Sanitize inputs (LLM callers may pass trailing whitespace) ---

PREFIX=$(printf '%s' "$PREFIX" | tr -d '[:space:]')
SLUG=$(printf '%s' "$SLUG" | tr -d '[:space:]')

# --- Generate identifiers ---

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
TMUX_NAME="${PREFIX}-${SLUG}-${TIMESTAMP}"

if [[ "$TMUX_NAME" =~ [[:space:]] ]]; then
  echo "Error: TMUX_NAME contains whitespace: '${TMUX_NAME}'" >&2
  exit 1
fi
LOG="/tmp/claude-runner-${PREFIX}-${SLUG}-${TIMESTAMP}.log"
LAUNCHER="/tmp/claude-runner-launch-${PREFIX}-${SLUG}-${TIMESTAMP}.sh"
EXECUTOR="/tmp/claude-runner-exec-${TMUX_NAME}.sh"

# --- Idempotency check ---

if tmux has-session -t "$TMUX_NAME" 2>/dev/null; then
  echo "Error: tmux session already exists: $TMUX_NAME" >&2
  exit 1
fi

# --- Build the on-success chain line ---
# Empty string if no --on-success provided; otherwise a bash invocation.

if [[ -n "$ON_SUCCESS" ]]; then
  ON_SUCCESS_LINE="[ \$CLAUDE_EXIT -eq 0 ] && bash '${ON_SUCCESS}'"
else
  ON_SUCCESS_LINE=""
fi

# --- Write launcher script ---
#
# Two-script pattern to avoid shell metacharacter expansion on task content:
# - EXECUTOR reads the task file at runtime with set -f (noglob), runs claude
# - LAUNCHER writes the executor, then passes only its *path* to script -c
#   (safe: a file path contains no shell metacharacters)
# - Task content never appears as a literal string in any shell -c argument
# - ON_SUCCESS chain is embedded as a path reference, not inline content

cat > "$LAUNCHER" << LAUNCHER_EOF
#!/usr/bin/env bash
set -euo pipefail
cd ${WORKDIR}

# Write glob-safe executor: task content read at runtime, not expanded in -c string
cat > '${EXECUTOR}' << 'EXEC_INNER'
#!/usr/bin/env bash
set -f
TASK=\$(cat '${TASK_FILE}')
exec claude --dangerously-skip-permissions "\$TASK"
EXEC_INNER
chmod +x '${EXECUTOR}'

script -qf ${LOG} -c '${EXECUTOR}'
CLAUDE_EXIT=\$?
rm -f '${EXECUTOR}'
${ON_SUCCESS_LINE}
openclaw system event --text "claude-runner ${TMUX_NAME} finished (exit \$CLAUDE_EXIT). Log: ${LOG}" --mode now
LAUNCHER_EOF

chmod +x "$LAUNCHER"

# --- Create tmux session and launch ---

tmux new-session -d -s "$TMUX_NAME" -x 220 -y 50000
tmux send-keys -t "$TMUX_NAME" "bash $LAUNCHER" Enter

# --- Auto-dismiss trust prompt ---
# Polls tmux pane for up to 60s.
# Matches both known trust prompt variants:
#   - "Do you trust the files in this folder?"  (older Claude Code)
#   - "Is this a project you created or one you trust?" (newer Claude Code)
# Sends Enter (selects default "Yes") when detected.
# Also sends Enter if the menu item "Yes, I trust" is visible.
# Exits early if Claude Code task UI is already running.

for i in $(seq 1 60); do
  sleep 1
  PANE=$(tmux capture-pane -t "$TMUX_NAME" -p -S -15 2>/dev/null || true)
  if echo "$PANE" | grep -qiE "Do you trust|trust this folder|created or one you trust|Yes, I trust"; then
    tmux send-keys -t "$TMUX_NAME" "" Enter
    echo "Trust prompt dismissed (iteration $i)" >&2
    break
  fi
  if echo "$PANE" | grep -qE '[╭─]|Task:|Claude Code'; then
    echo "No trust prompt — Claude Code already running" >&2
    break
  fi
  if [[ $i -eq 60 ]]; then
    echo "Timeout waiting for trust prompt — sending Enter as fallback" >&2
    tmux send-keys -t "$TMUX_NAME" "" Enter
  fi
done

# --- Output key=value pairs (stdout only) ---

WATCHER_NAME="watch-${TMUX_NAME}"

printf "TMUX_NAME='%s'\n" "$TMUX_NAME"
printf "LOG='%s'\n" "$LOG"
printf "TIMESTAMP='%s'\n" "$TIMESTAMP"
printf "LAUNCHER='%s'\n" "$LAUNCHER"
printf "WATCHER_NAME='%s'\n" "$WATCHER_NAME"
printf "ATTACH='tmux attach -t %s'\n" "$TMUX_NAME"
