#!/bin/bash
# Ralph Loop - True fresh context per iteration
# Usage: ./ralph-loop.sh <prompt-file|spec-dir> [max-iterations] [tasks-file]
#
# Arg 1 can be either:
#   - A prompt file path (e.g. .specify/.ralph-prompt.md)
#   - A spec directory path (e.g. specs/a1b2-feat-foo) — generates prompt from template
#     with FEATURE_DIR set to the given path

set -uo pipefail

ARG1="${1:-}"
MAX_ITERATIONS="${2:-5}"
TASKS_FILE="${3:-}"
GENERATED_PROMPT=""
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

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Resolve PROMPT_FILE from arg: either use directly or generate from template
resolve_prompt_file() {
    if [[ -z "$ARG1" ]]; then
        PROMPT_FILE=".specify/.ralph-prompt.md"
        return
    fi

    if [[ -f "$ARG1" ]]; then
        PROMPT_FILE="$ARG1"
        return
    fi

    if [[ -d "$ARG1" ]]; then
        FEATURE_DIR="$ARG1"
        GENERATED_PROMPT=".specify/.ralph-prompt.md"
        local template=".specify/templates/ralph-prompt.template.md"
        if [[ ! -f "$template" ]]; then
            echo -e "${RED}Error: Template not found: $template${NC}"
            exit 1
        fi
        sed "s|{FEATURE_DIR}|$FEATURE_DIR|g" "$template" > "$GENERATED_PROMPT"
        PROMPT_FILE="$GENERATED_PROMPT"
        return
    fi

    echo -e "${RED}Error: '$ARG1' is neither an existing file nor directory${NC}"
    exit 1
}
resolve_prompt_file

# Logging functions
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

log_section() {
    echo "" >> "$LOG_FILE"
    echo "═══════════════════════════════════════════════════════════════" >> "$LOG_FILE"
    echo "$1" >> "$LOG_FILE"
    echo "═══════════════════════════════════════════════════════════════" >> "$LOG_FILE"
}

# Get current task from tasks.md
get_current_task() {
    if [[ -n "$TASKS_FILE" ]] && [[ -f "$TASKS_FILE" ]]; then
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
cleanup() {
    local end_time=$(date +%s)
    local duration=$((end_time - START_TIME))

    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}  Loop interrupted after $ITERATION iterations${NC}"
    echo -e "${YELLOW}  Duration: $((duration / 60))m $((duration % 60))s${NC}"
    echo -e "${YELLOW}  Work is safely committed - resume with /speckit.ralph.implement${NC}"
    echo -e "${YELLOW}  Log: $LOG_FILE${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    log "INFO" "Interrupted after $ITERATION iterations (duration: ${duration}s)"
    rm -f ".specify/.ralph-prev-output" "$STATE_FILE"
    [[ -n "$GENERATED_PROMPT" ]] && rm -f "$GENERATED_PROMPT"
    exit 130
}
trap cleanup SIGINT SIGTERM

# Start time tracking
START_TIME=$(date +%s)

# Header
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC}  ${BOLD}Ralph Loop${NC} - Fresh Context Per Iteration                  ${BLUE}║${NC}"
echo -e "${BLUE}╠════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BLUE}║${NC}  Prompt: ${DIM}${PROMPT_FILE}${NC}"
[[ -n "${FEATURE_DIR:-}" ]] && echo -e "${BLUE}║${NC}  Feature dir: ${DIM}${FEATURE_DIR}${NC}"
echo -e "${BLUE}║${NC}  Max iterations: ${MAX_ITERATIONS}"
if [[ -n "$TASKS_FILE" ]]; then
    echo -e "${BLUE}║${NC}  Tasks: ${DIM}${TASKS_FILE}${NC}"
fi
echo -e "${BLUE}║${NC}  Log: ${DIM}${LOG_FILE}${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"

# Verify prompt file exists
if [[ ! -f "$PROMPT_FILE" ]]; then
    echo -e "${RED}Error: Prompt file not found: $PROMPT_FILE${NC}"
    log "ERROR" "Prompt file not found: $PROMPT_FILE"
    exit 1
fi

# Initialize log
log_section "RALPH LOOP STARTED"
log "INFO" "Prompt: $PROMPT_FILE"
log "INFO" "Max iterations: $MAX_ITERATIONS"
log "INFO" "Tasks file: ${TASKS_FILE:-none}"

# Create symlink to latest log
ln -sf "$(basename "$LOG_FILE")" "$LATEST_LOG"

# Initial task count
if [[ -n "$TASKS_FILE" ]] && [[ -f "$TASKS_FILE" ]]; then
    INITIAL_INCOMPLETE=$(grep -c '^\s*- \[ \]' "$TASKS_FILE" 2>/dev/null) || INITIAL_INCOMPLETE=0
    INITIAL_COMPLETE=$(grep -c '^\s*- \[[Xx]\]' "$TASKS_FILE" 2>/dev/null) || INITIAL_COMPLETE=0
    TOTAL_TASKS=$((INITIAL_INCOMPLETE + INITIAL_COMPLETE))
    log "INFO" "Initial state: $INITIAL_COMPLETE/$TOTAL_TASKS complete"
fi

while [ $ITERATION -lt $MAX_ITERATIONS ]; do
    ITERATION=$((ITERATION + 1))
    ITER_START=$(date +%s)

    # Get current state
    CURRENT_TASK=$(get_current_task)
    if [[ -n "$TASKS_FILE" ]] && [[ -f "$TASKS_FILE" ]]; then
        INCOMPLETE=$(grep -c '^\s*- \[ \]' "$TASKS_FILE" 2>/dev/null) || INCOMPLETE=0
        COMPLETE=$(grep -c '^\s*- \[[Xx]\]' "$TASKS_FILE" 2>/dev/null) || COMPLETE=0
        TOTAL=$((INCOMPLETE + COMPLETE))
    fi

    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  ITERATION ${BOLD}$ITERATION${NC}${CYAN} / $MAX_ITERATIONS  ${DIM}$(date '+%H:%M:%S')${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    # Show progress
    if [[ -n "$TASKS_FILE" ]] && [[ -f "$TASKS_FILE" ]]; then
        PROGRESS_BAR=$(progress_bar "$COMPLETE" "$TOTAL")
        echo -e "  ${BLUE}Progress:${NC} $PROGRESS_BAR ${GREEN}$COMPLETE${NC}/${TOTAL} tasks"
    fi

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
    echo -e "  ${DIM}Running claude -p ...${NC}"

    CLAUDE_EXIT=0
    ITER_OUTPUT=$(claude -p \
        --dangerously-skip-permissions \
        --model opus \
        < "$PROMPT_FILE" \
        2>&1) || CLAUDE_EXIT=$?

    if [[ $CLAUDE_EXIT -ne 0 ]]; then
        echo -e "  ${RED}Claude exited with status $CLAUDE_EXIT${NC}"
        log "ERROR" "Claude exited with status $CLAUDE_EXIT"
        CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
        if [[ $CONSECUTIVE_FAILURES -ge $MAX_CONSECUTIVE_FAILURES ]]; then
            echo -e "  ${RED}Aborting after $MAX_CONSECUTIVE_FAILURES consecutive failures${NC}"
            log "ERROR" "Aborting: $MAX_CONSECUTIVE_FAILURES consecutive failures"
            rm -f ".specify/.ralph-prev-output" "$STATE_FILE"
            [[ -n "$GENERATED_PROMPT" ]] && rm -f "$GENERATED_PROMPT"
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
            STUCK=true
            CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
            echo -e "  ${YELLOW}⚠️  Output identical to previous iteration (${CONSECUTIVE_FAILURES}/${MAX_CONSECUTIVE_FAILURES})${NC}"
            log "WARN" "Stuck detection: output identical to previous (consecutive: $CONSECUTIVE_FAILURES)"

            if [[ $CONSECUTIVE_FAILURES -ge $MAX_CONSECUTIVE_FAILURES ]]; then
                echo -e "  ${RED}❌ Stuck after $MAX_CONSECUTIVE_FAILURES identical outputs${NC}"
                echo -e "  ${YELLOW}   Suggestion: Ctrl+C and run /speckit.tasks to regenerate${NC}"
                log "ERROR" "Aborting: stuck after $MAX_CONSECUTIVE_FAILURES consecutive identical outputs"
                rm -f ".specify/.ralph-prev-output" "$STATE_FILE"
                [[ -n "$GENERATED_PROMPT" ]] && rm -f "$GENERATED_PROMPT"
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
        echo -e "${GREEN}║  ✅ ALL TASKS COMPLETE                                     ║${NC}"
        echo -e "${GREEN}╠════════════════════════════════════════════════════════════╣${NC}"
        echo -e "${GREEN}║${NC}  Iterations: $ITERATION"
        echo -e "${GREEN}║${NC}  Duration: $((TOTAL_DURATION / 60))m $((TOTAL_DURATION % 60))s"
        echo -e "${GREEN}║${NC}  Log: ${DIM}$LOG_FILE${NC}"
        echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"

        log_section "COMPLETE"
        log "INFO" "All tasks complete after $ITERATION iterations"
        log "INFO" "Total duration: ${TOTAL_DURATION}s"

        rm -f ".specify/.ralph-prev-output" "$STATE_FILE"
        [[ -n "$GENERATED_PROMPT" ]] && rm -f "$GENERATED_PROMPT"
        exit 0
    fi

    # Also check tasks.md directly if provided
    if [[ -n "$TASKS_FILE" ]] && [[ -f "$TASKS_FILE" ]]; then
        INCOMPLETE=$(grep -c '^\s*- \[ \]' "$TASKS_FILE" 2>/dev/null) || INCOMPLETE=0
        COMPLETE=$(grep -c '^\s*- \[[Xx]\]' "$TASKS_FILE" 2>/dev/null) || COMPLETE=0

        if [[ "$INCOMPLETE" -eq 0 ]] && [[ "$COMPLETE" -gt 0 ]]; then
            END_TIME=$(date +%s)
            TOTAL_DURATION=$((END_TIME - START_TIME))

            echo ""
            echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
            echo -e "${GREEN}║  ✅ ALL TASKS COMPLETE (verified in tasks.md)             ║${NC}"
            echo -e "${GREEN}╠════════════════════════════════════════════════════════════╣${NC}"
            echo -e "${GREEN}║${NC}  Iterations: $ITERATION"
            echo -e "${GREEN}║${NC}  Duration: $((TOTAL_DURATION / 60))m $((TOTAL_DURATION % 60))s"
            echo -e "${GREEN}║${NC}  Log: ${DIM}$LOG_FILE${NC}"
            echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"

            log_section "COMPLETE"
            log "INFO" "All tasks complete (verified via tasks.md) after $ITERATION iterations"
            log "INFO" "Total duration: ${TOTAL_DURATION}s"

            rm -f ".specify/.ralph-prev-output" "$STATE_FILE"
            [[ -n "$GENERATED_PROMPT" ]] && rm -f "$GENERATED_PROMPT"
            exit 0
        fi
    fi

    log "INFO" "Iteration $ITERATION completed in ${ITER_DURATION}s"
done

end_time=$(date +%s)
total_duration=$((end_time - START_TIME))

echo ""
echo -e "${YELLOW}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║  ⚠️  Max iterations ($MAX_ITERATIONS) reached              ║${NC}"
echo -e "${YELLOW}╠════════════════════════════════════════════════════════════╣${NC}"
echo -e "${YELLOW}║${NC}  Duration: $((total_duration / 60))m $((total_duration % 60))s"
echo -e "${YELLOW}║${NC}  Run /speckit.ralph.implement to continue"
echo -e "${YELLOW}║${NC}  Log: ${DIM}$LOG_FILE${NC}"
echo -e "${YELLOW}╚════════════════════════════════════════════════════════════╝${NC}"

log_section "MAX ITERATIONS REACHED"
log "WARN" "Max iterations ($MAX_ITERATIONS) reached"
log "INFO" "Total duration: ${total_duration}s"

rm -f ".specify/.ralph-prev-output" "$STATE_FILE"
[[ -n "$GENERATED_PROMPT" ]] && rm -f "$GENERATED_PROMPT"
exit 1
