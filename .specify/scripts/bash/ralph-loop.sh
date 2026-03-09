#!/usr/bin/env bash
# Ralph Loop - Task-by-task implementation with fresh context per iteration
# Usage: ./ralph-loop.sh <spec-dir> [max-iterations] [quality-gates]
#
# Arg 1: A spec directory path (e.g. specs/a1b2-feat-foo)
# Arg 2: Max iterations (default: 5)
# Arg 3: Quality gates command (default: placeholder)

set -uo pipefail

FEATURE_DIR="${1:-}"
MAX_ITERATIONS="${2:-5}"
QUALITY_GATES_CLI_ARG="${3:-}"
MODEL="${CLAUDE_MODEL:-opus}"
ITERATION=0
LOG_DIR=".specify/logs"
LOG_FILE="$LOG_DIR/ralph-$(date '+%Y%m%d-%H%M%S').log"
LATEST_LOG="$LOG_DIR/ralph-latest.log"
STATE_FILE=".specify/.ralph-state"
CONSECUTIVE_FAILURES=0
MAX_CONSECUTIVE_FAILURES=3

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

# Resolve quality gates using precedence: CLI arg > env var > file > error
# Sets QUALITY_GATES (value) and QUALITY_GATES_SOURCE ("cli", "env", or "file")
resolve_quality_gates() {
    local cli_arg="${1:-}"
    local qg_file=".specify/quality-gates.sh"

    # Priority 1: CLI argument
    if [[ -n "$cli_arg" ]]; then
        QUALITY_GATES="$cli_arg"
        QUALITY_GATES_SOURCE="cli"
        return 0
    fi

    # Priority 2: Environment variable (QUALITY_GATES may already be set)
    if [[ -n "${QUALITY_GATES:-}" ]]; then
        QUALITY_GATES_SOURCE="env"
        return 0
    fi

    # Priority 3: Quality gate file
    if [[ -f "$qg_file" ]]; then
        # Validate file is non-empty after stripping comments and whitespace
        local effective_content
        effective_content=$(grep -v '^\s*#' "$qg_file" | grep -v '^\s*$' || true)
        if [[ -z "$effective_content" ]]; then
            echo -e "${RED}Error: Quality gate file exists but contains no executable commands.${NC}" >&2
            echo "Edit .specify/quality-gates.sh and add your project's quality gate commands." >&2
            exit 1
        fi
        QUALITY_GATES="$qg_file"
        QUALITY_GATES_SOURCE="file"
        return 0
    fi

    # Priority 4: Error — nothing configured
    echo -e "${RED}Error: No quality gates configured.${NC}" >&2
    echo "Create .specify/quality-gates.sh or pass quality gates as argument 3 or set QUALITY_GATES env var." >&2
    exit 1
}

# Resolve quality gates
resolve_quality_gates "$QUALITY_GATES_CLI_ARG"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Validate feature directory
if [[ -z "$FEATURE_DIR" ]]; then
    echo -e "${RED}Error: Feature directory required${NC}"
    echo "Usage: ./ralph-loop.sh <spec-dir> [max-iterations] [quality-gates]"
    exit 1
fi

if [[ ! -d "$FEATURE_DIR" ]]; then
    echo -e "${RED}Error: Directory not found: $FEATURE_DIR${NC}"
    exit 1
fi

TASKS_FILE="$FEATURE_DIR/tasks.md"

if [[ ! -f "$TASKS_FILE" ]]; then
    echo -e "${RED}Error: tasks.md not found in $FEATURE_DIR${NC}"
    echo "Run /speckit.tasks first"
    exit 1
fi

# Logging functions
log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

log_section() {
    {
        echo ""
        echo "═══════════════════════════════════════════════════════════════"
        echo "$1"
        echo "═══════════════════════════════════════════════════════════════"
    } >> "$LOG_FILE"
}

# Get current task from tasks.md
get_current_task() {
    if [[ -f "$TASKS_FILE" ]]; then
        grep -m1 '^\s*- \[ \]' "$TASKS_FILE" 2>/dev/null | sed 's/^\s*- \[ \] //' | head -c 60
    fi
}

# Get last git commit info
get_last_commit() {
    git log -1 --format='%h %s' 2>/dev/null | head -c 70
}

# Calculate progress bar
progress_bar() {
    local complete=$1
    local total=$2
    local width=30
    if [[ $total -eq 0 ]]; then
        printf "[%${width}s]" ""
        return
    fi
    local filled=$((complete * width / total))
    local empty=$((width - filled))
    printf "[%s%s]" "$(printf '█%.0s' $(seq 1 $filled 2>/dev/null) || echo "")" "$(printf '░%.0s' $(seq 1 $empty 2>/dev/null) || echo "")"
}

# Graceful exit on Ctrl+C
# shellcheck disable=SC2329
cleanup() {
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - START_TIME))

    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}  Loop interrupted after $ITERATION iterations${NC}"
    echo -e "${YELLOW}  Duration: $((duration / 60))m $((duration % 60))s${NC}"
    echo -e "${YELLOW}  Work is safely committed - rerun to continue${NC}"
    echo -e "${YELLOW}  Log: $LOG_FILE${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    log "INFO" "Interrupted after $ITERATION iterations (duration: ${duration}s)"
    rm -f ".specify/.ralph-prev-output" "$STATE_FILE"
    exit 130
}
trap cleanup SIGINT SIGTERM

# Start time tracking
START_TIME=$(date +%s)

# Header
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC}  ${BOLD}Ralph Loop${NC} - Fresh Context Per Iteration                  ${BLUE}║${NC}"
echo -e "${BLUE}╠════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BLUE}║${NC}  Feature dir: ${DIM}${FEATURE_DIR}${NC}"
echo -e "${BLUE}║${NC}  Max iterations: ${MAX_ITERATIONS}"
echo -e "${BLUE}║${NC}  Model: ${DIM}${MODEL}${NC}"
echo -e "${BLUE}║${NC}  Tasks: ${DIM}${TASKS_FILE}${NC}"
echo -e "${BLUE}║${NC}  Log: ${DIM}${LOG_FILE}${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"

# Initialize log
log_section "RALPH LOOP STARTED"
log "INFO" "Feature dir: $FEATURE_DIR"
log "INFO" "Max iterations: $MAX_ITERATIONS"
log "INFO" "Tasks file: $TASKS_FILE"

# Create symlink to latest log
ln -sf "$(basename "$LOG_FILE")" "$LATEST_LOG"

# Initial task count
INITIAL_INCOMPLETE=$(grep -c '^\s*- \[ \]' "$TASKS_FILE" 2>/dev/null) || INITIAL_INCOMPLETE=0
INITIAL_COMPLETE=$(grep -c '^\s*- \[[Xx]\]' "$TASKS_FILE" 2>/dev/null) || INITIAL_COMPLETE=0
TOTAL_TASKS=$((INITIAL_INCOMPLETE + INITIAL_COMPLETE))
log "INFO" "Initial state: $INITIAL_COMPLETE/$TOTAL_TASKS complete"

while [ $ITERATION -lt "$MAX_ITERATIONS" ]; do
    ITERATION=$((ITERATION + 1))
    ITER_START=$(date +%s)

    # Get current state
    CURRENT_TASK=$(get_current_task)
    INCOMPLETE=$(grep -c '^\s*- \[ \]' "$TASKS_FILE" 2>/dev/null) || INCOMPLETE=0
    COMPLETE=$(grep -c '^\s*- \[[Xx]\]' "$TASKS_FILE" 2>/dev/null) || COMPLETE=0
    TOTAL=$((INCOMPLETE + COMPLETE))

    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  ITERATION ${BOLD}$ITERATION${NC}${CYAN} / $MAX_ITERATIONS  ${DIM}$(date '+%H:%M:%S')${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    # Show progress
    PROGRESS_BAR=$(progress_bar "$COMPLETE" "$TOTAL")
    echo -e "  ${BLUE}Progress:${NC} $PROGRESS_BAR ${GREEN}$COMPLETE${NC}/${TOTAL} tasks"

    # Show current task
    if [[ -n "$CURRENT_TASK" ]]; then
        echo -e "  ${MAGENTA}Next task:${NC} ${CURRENT_TASK}..."
    fi

    echo ""

    # Log iteration start
    log_section "ITERATION $ITERATION"
    log "INFO" "Starting iteration $ITERATION"
    log "INFO" "Current task: ${CURRENT_TASK:-unknown}"
    log "INFO" "Progress: $COMPLETE/$TOTAL tasks complete"

    # Save state for resumption
    echo "ITERATION=$ITERATION" > "$STATE_FILE"
    echo "TASK=$CURRENT_TASK" >> "$STATE_FILE"

    # Run Claude with fresh context (new process each time)
    echo -e "  ${DIM}Running claude --agent ralph ...${NC}"

    # Build the quality gates prompt based on source type:
    # - File source: tell the agent to execute the file directly
    # - CLI/env source: pass the command string for shell evaluation
    if [[ "$QUALITY_GATES_SOURCE" == "file" ]]; then
        QG_PROMPT="Quality gates: $QUALITY_GATES (execute this file directly)"
    else
        QG_PROMPT="Quality gates: $QUALITY_GATES"
    fi

    CLAUDE_EXIT=0
    ITER_OUTPUT=$(claude --agent ralph \
        -p "Feature directory: $FEATURE_DIR. $QG_PROMPT" \
        --dangerously-skip-permissions \
        --model "$MODEL" \
        2>&1) || CLAUDE_EXIT=$?

    if [[ $CLAUDE_EXIT -ne 0 ]]; then
        echo -e "  ${RED}Claude exited with status $CLAUDE_EXIT${NC}"
        log "ERROR" "Claude exited with status $CLAUDE_EXIT"
        CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
        if [[ $CONSECUTIVE_FAILURES -ge $MAX_CONSECUTIVE_FAILURES ]]; then
            echo -e "  ${RED}Aborting after $MAX_CONSECUTIVE_FAILURES consecutive failures${NC}"
            log "ERROR" "Aborting: $MAX_CONSECUTIVE_FAILURES consecutive failures"
            rm -f ".specify/.ralph-prev-output" "$STATE_FILE"
            exit 2
        fi
        echo -e "  ${YELLOW}Retrying... (${CONSECUTIVE_FAILURES}/${MAX_CONSECUTIVE_FAILURES})${NC}"
        continue
    fi

    ITER_END=$(date +%s)
    ITER_DURATION=$((ITER_END - ITER_START))

    # Log full output
    log "OUTPUT" "--- BEGIN CLAUDE OUTPUT ---"
    echo "$ITER_OUTPUT" >> "$LOG_FILE"
    log "OUTPUT" "--- END CLAUDE OUTPUT ---"

    # Display output
    echo "$ITER_OUTPUT"

    # Show iteration stats
    echo ""
    echo -e "  ${DIM}────────────────────────────────────────────────────────${NC}"
    echo -e "  ${DIM}Iteration completed in ${ITER_DURATION}s${NC}"

    # Check for git commit
    LAST_COMMIT=$(get_last_commit)
    if [[ -n "$LAST_COMMIT" ]]; then
        echo -e "  ${GREEN}Latest commit:${NC} ${DIM}$LAST_COMMIT${NC}"
        log "INFO" "Latest commit: $LAST_COMMIT"
    fi

    # Stuck detection: warn if output identical to previous
    STUCK=false
    if [[ -f ".specify/.ralph-prev-output" ]]; then
        if diff -q ".specify/.ralph-prev-output" <(echo "$ITER_OUTPUT") > /dev/null 2>&1; then
            # shellcheck disable=SC2034
            STUCK=true
            CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
            echo -e "  ${YELLOW}  Output identical to previous iteration (${CONSECUTIVE_FAILURES}/${MAX_CONSECUTIVE_FAILURES})${NC}"
            log "WARN" "Stuck detection: output identical to previous (consecutive: $CONSECUTIVE_FAILURES)"

            if [[ $CONSECUTIVE_FAILURES -ge $MAX_CONSECUTIVE_FAILURES ]]; then
                echo -e "  ${RED}  Stuck after $MAX_CONSECUTIVE_FAILURES identical outputs${NC}"
                echo -e "  ${YELLOW}   Suggestion: Ctrl+C and run /speckit.tasks to regenerate${NC}"
                log "ERROR" "Aborting: stuck after $MAX_CONSECUTIVE_FAILURES consecutive identical outputs"
                rm -f ".specify/.ralph-prev-output" "$STATE_FILE"
                exit 2
            fi
        else
            CONSECUTIVE_FAILURES=0
        fi
    fi
    echo "$ITER_OUTPUT" > ".specify/.ralph-prev-output"

    # Check for completion promise in output
    if echo "$ITER_OUTPUT" | grep -q "<promise>ALL_TASKS_COMPLETE</promise>"; then
        END_TIME=$(date +%s)
        TOTAL_DURATION=$((END_TIME - START_TIME))

        echo ""
        echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║  ALL TASKS COMPLETE                                        ║${NC}"
        echo -e "${GREEN}╠════════════════════════════════════════════════════════════╣${NC}"
        echo -e "${GREEN}║${NC}  Iterations: $ITERATION"
        echo -e "${GREEN}║${NC}  Duration: $((TOTAL_DURATION / 60))m $((TOTAL_DURATION % 60))s"
        echo -e "${GREEN}║${NC}  Log: ${DIM}$LOG_FILE${NC}"
        echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"

        log_section "COMPLETE"
        log "INFO" "All tasks complete after $ITERATION iterations"
        log "INFO" "Total duration: ${TOTAL_DURATION}s"

        rm -f ".specify/.ralph-prev-output" "$STATE_FILE"
        exit 0
    fi

    # Also check tasks.md directly
    INCOMPLETE=$(grep -c '^\s*- \[ \]' "$TASKS_FILE" 2>/dev/null) || INCOMPLETE=0
    COMPLETE=$(grep -c '^\s*- \[[Xx]\]' "$TASKS_FILE" 2>/dev/null) || COMPLETE=0

    if [[ "$INCOMPLETE" -eq 0 ]] && [[ "$COMPLETE" -gt 0 ]]; then
        END_TIME=$(date +%s)
        TOTAL_DURATION=$((END_TIME - START_TIME))

        echo ""
        echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║  ALL TASKS COMPLETE (verified in tasks.md)                ║${NC}"
        echo -e "${GREEN}╠════════════════════════════════════════════════════════════╣${NC}"
        echo -e "${GREEN}║${NC}  Iterations: $ITERATION"
        echo -e "${GREEN}║${NC}  Duration: $((TOTAL_DURATION / 60))m $((TOTAL_DURATION % 60))s"
        echo -e "${GREEN}║${NC}  Log: ${DIM}$LOG_FILE${NC}"
        echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"

        log_section "COMPLETE"
        log "INFO" "All tasks complete (verified via tasks.md) after $ITERATION iterations"
        log "INFO" "Total duration: ${TOTAL_DURATION}s"

        rm -f ".specify/.ralph-prev-output" "$STATE_FILE"
        exit 0
    fi

    log "INFO" "Iteration $ITERATION completed in ${ITER_DURATION}s"
done

end_time=$(date +%s)
total_duration=$((end_time - START_TIME))

echo ""
echo -e "${YELLOW}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║  Max iterations ($MAX_ITERATIONS) reached                            ║${NC}"
echo -e "${YELLOW}╠════════════════════════════════════════════════════════════╣${NC}"
echo -e "${YELLOW}║${NC}  Duration: $((total_duration / 60))m $((total_duration % 60))s"
echo -e "${YELLOW}║${NC}  Rerun to continue"
echo -e "${YELLOW}║${NC}  Log: ${DIM}$LOG_FILE${NC}"
echo -e "${YELLOW}╚════════════════════════════════════════════════════════════╝${NC}"

log_section "MAX ITERATIONS REACHED"
log "WARN" "Max iterations ($MAX_ITERATIONS) reached"
log "INFO" "Total duration: ${total_duration}s"

rm -f ".specify/.ralph-prev-output" "$STATE_FILE"
exit 1
