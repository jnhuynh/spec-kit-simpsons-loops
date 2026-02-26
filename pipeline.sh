#!/usr/bin/env bash
# pipeline.sh — End-to-end SpecKit pipeline orchestrator
#
# Runs the SpecKit workflow from spec clarification to implementation.
# Prerequisite: Run /speckit.specify interactively first to create the spec.
#
# Steps:
#   1. homer    — Iterative spec clarification & remediation
#   2. plan     — Generate technical implementation plan
#   3. tasks    — Generate dependency-ordered task list
#   4. lisa     — Cross-artifact consistency analysis
#   5. ralph    — Task-by-task implementation with quality gates
#
# Usage:
#   pipeline.sh [spec-dir]
#   pipeline.sh [options] [spec-dir]
#
# Options:
#   --from <step>          Start from a specific step: homer, plan, tasks, lisa, ralph
#   --homer-max <n>        Max homer loop iterations (default: 10)
#   --lisa-max <n>         Max lisa loop iterations (default: 10)
#   --ralph-max <n>        Max ralph loop iterations (default: 20)
#   --model <model>        Claude model to use (default: opus)
#   --dry-run              Show what would be run without executing
#   --help                 Show this help message

set -uo pipefail

# ─── Configuration ──────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Defaults
FROM_STEP=""
MODEL="opus"
DRY_RUN=false
HOMER_MAX=10
LISA_MAX=10
RALPH_MAX=20

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

# Logging
LOG_DIR="$REPO_ROOT/.specify/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/pipeline-$(date '+%Y%m%d-%H%M%S').log"
LATEST_LOG="$LOG_DIR/pipeline-latest.log"
ln -sf "$(basename "$LOG_FILE")" "$LATEST_LOG"

# ─── Argument Parsing ───────────────────────────────────────────────────────

show_help() {
    cat <<'HELPEOF'
pipeline.sh — End-to-end SpecKit pipeline orchestrator

Runs the SpecKit workflow from spec clarification to implementation.
Prerequisite: Run /speckit.specify interactively first to create the spec.

Steps:
  1. homer    — Iterative spec clarification & remediation
  2. plan     — Generate technical implementation plan
  3. tasks    — Generate dependency-ordered task list
  4. lisa     — Cross-artifact consistency analysis
  5. ralph    — Task-by-task implementation with quality gates

Usage:
  pipeline.sh [spec-dir]
  pipeline.sh [options] [spec-dir]

Options:
  --from <step>          Start from a specific step: homer, plan, tasks, lisa, ralph
  --homer-max <n>        Max homer loop iterations (default: 10)
  --lisa-max <n>         Max lisa loop iterations (default: 10)
  --ralph-max <n>        Max ralph loop iterations (default: 20)
  --model <model>        Claude model to use (default: opus)
  --dry-run              Show what would be run without executing
  --help                 Show this help message

Examples:
  pipeline.sh                                        # Auto-detect from current branch
  pipeline.sh specs/a1b2-feat-user-auth              # Explicit spec directory
  pipeline.sh --from homer                           # Start from homer step
  pipeline.sh --from ralph specs/a1b2-feat-user-auth
HELPEOF
    exit 0
}

SPEC_DIR_ARG=""

i=1
while [ $i -le $# ]; do
    arg="${!i}"
    case "$arg" in
        --help|-h) show_help ;;
        --from)
            i=$((i + 1)); FROM_STEP="${!i}"
            if [[ ! "$FROM_STEP" =~ ^(homer|plan|tasks|lisa|ralph)$ ]]; then
                echo -e "${RED}Error: --from must be one of: homer, plan, tasks, lisa, ralph${NC}" >&2
                exit 1
            fi ;;
        --model)
            i=$((i + 1)); MODEL="${!i}" ;;
        --homer-max)
            i=$((i + 1)); HOMER_MAX="${!i}" ;;
        --lisa-max)
            i=$((i + 1)); LISA_MAX="${!i}" ;;
        --ralph-max)
            i=$((i + 1)); RALPH_MAX="${!i}" ;;
        --dry-run)
            DRY_RUN=true ;;
        *)
            SPEC_DIR_ARG="$arg" ;;
    esac
    i=$((i + 1))
done

# ─── Logging ────────────────────────────────────────────────────────────────

log() {
    local level="$1" message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" >> "$LOG_FILE"
}

log_section() {
    echo "" >> "$LOG_FILE"
    echo "═══════════════════════════════════════════════════════════════" >> "$LOG_FILE"
    echo "$1" >> "$LOG_FILE"
    echo "═══════════════════════════════════════════════════════════════" >> "$LOG_FILE"
}

# ─── Step Tracking ──────────────────────────────────────────────────────────

STEPS=("homer" "plan" "tasks" "lisa" "ralph")

should_skip_step() {
    local step="$1"
    if [[ -n "$FROM_STEP" ]]; then
        for s in "${STEPS[@]}"; do
            if [[ "$s" == "$FROM_STEP" ]]; then return 1; fi
            if [[ "$s" == "$step" ]]; then return 0; fi
        done
    fi
    return 1
}

print_step_header() {
    local step_num="$1" step_name="$2" total="${#STEPS[@]}"
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}  ${BOLD}Step ${step_num}/${total}${NC} — ${step_name}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_step_complete() {
    local step_name="$1" duration="$2"
    echo ""
    echo -e "  ${GREEN}Step complete:${NC} ${step_name} ${DIM}(${duration}s)${NC}"
}

print_step_skip() {
    local step_name="$1" reason="$2"
    echo -e "  ${DIM}Skipping: ${step_name} — ${reason}${NC}"
}

# ─── Graceful Exit ──────────────────────────────────────────────────────────

cleanup() {
    local end_time=$(date +%s)
    local duration=$((end_time - PIPELINE_START))

    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}  Pipeline interrupted${NC}"
    echo -e "${YELLOW}  Duration: $((duration / 60))m $((duration % 60))s${NC}"
    if [[ -n "${FEATURE_DIR:-}" ]]; then
        echo -e "${YELLOW}  Resume with: pipeline.sh ${FEATURE_DIR}${NC}"
    fi
    echo -e "${YELLOW}  Log: $LOG_FILE${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    log "INFO" "Pipeline interrupted after $((duration))s"
    exit 130
}
trap cleanup SIGINT SIGTERM

# ─── Run claude -p ──────────────────────────────────────────────────────────

run_claude() {
    local prompt="$1"
    local description="$2"

    log "INFO" "Running claude -p: $description"
    echo -e "  ${DIM}Running claude -p --model $MODEL ...${NC}"

    if $DRY_RUN; then
        echo -e "  ${CYAN}[dry-run] Would run: echo '...' | claude -p --dangerously-skip-permissions --model $MODEL${NC}"
        return 0
    fi

    local exit_code=0
    local output
    output=$(echo "$prompt" | claude -p \
        --dangerously-skip-permissions \
        --model "$MODEL" \
        2>&1) || exit_code=$?

    # Log output
    log "OUTPUT" "--- BEGIN CLAUDE OUTPUT ($description) ---"
    echo "$output" >> "$LOG_FILE"
    log "OUTPUT" "--- END CLAUDE OUTPUT ---"

    # Display output
    echo "$output"

    if [[ $exit_code -ne 0 ]]; then
        echo -e "  ${RED}Claude exited with status $exit_code${NC}"
        log "ERROR" "Claude exited with status $exit_code for: $description"
        return $exit_code
    fi

    return 0
}

# ─── Resolve Feature Directory ──────────────────────────────────────────────

resolve_feature_dir() {
    if [[ -n "$SPEC_DIR_ARG" ]]; then
        # Explicit spec directory
        if [[ -d "$REPO_ROOT/$SPEC_DIR_ARG" ]]; then
            echo "$SPEC_DIR_ARG"
        elif [[ -d "$SPEC_DIR_ARG" ]]; then
            # Absolute path — make relative to repo root
            echo "${SPEC_DIR_ARG#$REPO_ROOT/}"
        else
            echo -e "${RED}Error: Spec directory not found: $SPEC_DIR_ARG${NC}" >&2
            return 1
        fi
        return
    fi

    # Auto-detect from current branch
    local branch
    branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

    if [[ -z "$branch" || "$branch" == "main" || "$branch" == "HEAD" ]]; then
        echo -e "${RED}Error: Cannot auto-detect feature directory. Pass spec-dir as argument.${NC}" >&2
        return 1
    fi

    # Extract UUID prefix and find matching spec dir
    if [[ "$branch" =~ ^([a-z0-9]{4})- ]]; then
        local prefix="${BASH_REMATCH[1]}"
        for dir in "$REPO_ROOT/specs/$prefix"-*; do
            if [[ -d "$dir" ]]; then
                echo "specs/$(basename "$dir")"
                return
            fi
        done
    fi

    # Exact match
    if [[ -d "$REPO_ROOT/specs/$branch" ]]; then
        echo "specs/$branch"
        return
    fi

    echo -e "${RED}Error: No spec directory found for branch '$branch'${NC}" >&2
    return 1
}

detect_from_step() {
    local feature_dir="$1"
    local full_dir="$REPO_ROOT/$feature_dir"

    # Walk backwards through artifacts to find the right starting step:
    # Pipeline order: homer → plan → tasks → lisa → ralph
    #
    # tasks.md with some complete → ralph
    # tasks.md with none complete → lisa
    # plan.md exists → tasks
    # spec.md exists → homer (first step after specify)

    if [[ -f "$full_dir/tasks.md" ]]; then
        local incomplete
        incomplete=$(grep -c '^\s*- \[ \]' "$full_dir/tasks.md" 2>/dev/null) || incomplete=0
        local complete
        complete=$(grep -c '^\s*- \[[Xx]\]' "$full_dir/tasks.md" 2>/dev/null) || complete=0

        if [[ $incomplete -gt 0 && $complete -gt 0 ]]; then
            # Some tasks done, some remaining — go straight to ralph
            echo "ralph"
        elif [[ $incomplete -gt 0 ]]; then
            # Tasks exist but none started — run lisa first
            echo "lisa"
        else
            # All tasks complete
            echo -e "${GREEN}All tasks already complete!${NC}" >&2
            return 1
        fi
    elif [[ -f "$full_dir/plan.md" ]]; then
        echo "tasks"
    elif [[ -f "$full_dir/spec.md" ]]; then
        echo "homer"
    else
        echo -e "${RED}Error: No spec.md found in $feature_dir. Run /speckit.specify interactively first.${NC}" >&2
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════

cd "$REPO_ROOT"

PIPELINE_START=$(date +%s)
FEATURE_DIR=""

# ─── Resolve Feature Directory ────────────────────────────────────────────

FEATURE_DIR=$(resolve_feature_dir) || exit 1

# Validate that spec.md exists (must be created interactively first)
if [[ ! -f "$REPO_ROOT/$FEATURE_DIR/spec.md" ]]; then
    echo -e "${RED}Error: No spec.md found in $FEATURE_DIR${NC}" >&2
    echo -e "${RED}Run /speckit.specify interactively first to create the spec.${NC}" >&2
    exit 1
fi

# Auto-detect starting step if not specified
if [[ -z "$FROM_STEP" ]]; then
    FROM_STEP=$(detect_from_step "$FEATURE_DIR") || exit 0
fi

# ─── Header ─────────────────────────────────────────────────────────────────

echo -e "${MAGENTA}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${MAGENTA}║${NC}  ${BOLD}SpecKit Pipeline${NC} — Plan to Implementation                  ${MAGENTA}║${NC}"
echo -e "${MAGENTA}╠════════════════════════════════════════════════════════════╣${NC}"
echo -e "${MAGENTA}║${NC}  Feature: ${CYAN}${FEATURE_DIR}${NC}"
echo -e "${MAGENTA}║${NC}  Starting from: ${CYAN}${FROM_STEP}${NC}"
echo -e "${MAGENTA}║${NC}  Model: ${DIM}${MODEL}${NC}  Max: ${DIM}homer=${HOMER_MAX} lisa=${LISA_MAX} ralph=${RALPH_MAX}${NC}"
echo -e "${MAGENTA}║${NC}  Log: ${DIM}${LOG_FILE}${NC}"
echo -e "${MAGENTA}╚════════════════════════════════════════════════════════════╝${NC}"

log_section "PIPELINE STARTED"
log "INFO" "Feature dir: $FEATURE_DIR, starting from: $FROM_STEP"
log "INFO" "Model: $MODEL"

# ─── Step 1: Homer Loop ───────────────────────────────────────────────────

if ! should_skip_step "homer"; then
    STEP_START=$(date +%s)
    print_step_header 1 "Homer: Spec Clarification"

    HOMER_CMD="$REPO_ROOT/.specify/scripts/bash/homer-loop.sh $FEATURE_DIR $HOMER_MAX"
    log "INFO" "Running: $HOMER_CMD"
    echo -e "  ${DIM}Running: $HOMER_CMD${NC}"

    if $DRY_RUN; then
        echo -e "  ${CYAN}[dry-run] Would run: $HOMER_CMD${NC}"
        HOMER_EXIT=0
    else
        CLAUDE_MODEL="$MODEL" $HOMER_CMD
        HOMER_EXIT=$?
    fi

    if [[ $HOMER_EXIT -eq 0 ]]; then
        echo -e "  ${GREEN}Homer: All findings resolved${NC}"
    elif [[ $HOMER_EXIT -eq 1 ]]; then
        echo -e "  ${YELLOW}Homer: Max iterations reached — continuing pipeline${NC}"
    else
        echo -e "  ${RED}Homer: Failed with exit code $HOMER_EXIT${NC}"
        log "ERROR" "Homer loop failed: exit $HOMER_EXIT"
        exit $HOMER_EXIT
    fi

    STEP_END=$(date +%s)
    print_step_complete "Homer" "$((STEP_END - STEP_START))"
fi

# ─── Step 2: Plan ──────────────────────────────────────────────────────────

if ! should_skip_step "plan"; then
    STEP_START=$(date +%s)
    print_step_header 2 "Generate Plan (plan)"

    if [[ -f "$REPO_ROOT/$FEATURE_DIR/plan.md" ]]; then
        print_step_skip "plan" "plan.md already exists"
    else
        run_claude "/speckit.plan" "Generate implementation plan" || {
            echo -e "${RED}Failed to generate plan${NC}"
            exit 1
        }
    fi

    STEP_END=$(date +%s)
    print_step_complete "Plan" "$((STEP_END - STEP_START))"
fi

# ─── Step 3: Tasks ─────────────────────────────────────────────────────────

if ! should_skip_step "tasks"; then
    STEP_START=$(date +%s)
    print_step_header 3 "Generate Tasks (tasks)"

    if [[ -f "$REPO_ROOT/$FEATURE_DIR/tasks.md" ]]; then
        print_step_skip "tasks" "tasks.md already exists"
    else
        run_claude "/speckit.tasks" "Generate task list" || {
            echo -e "${RED}Failed to generate tasks${NC}"
            exit 1
        }
    fi

    STEP_END=$(date +%s)
    print_step_complete "Tasks" "$((STEP_END - STEP_START))"
fi

# ─── Step 4: Lisa Loop ─────────────────────────────────────────────────────

if ! should_skip_step "lisa"; then
    STEP_START=$(date +%s)
    print_step_header 4 "Lisa: Cross-Artifact Analysis"

    LISA_CMD="$REPO_ROOT/.specify/scripts/bash/lisa-loop.sh $FEATURE_DIR $LISA_MAX"
    log "INFO" "Running: $LISA_CMD"
    echo -e "  ${DIM}Running: $LISA_CMD${NC}"

    if $DRY_RUN; then
        echo -e "  ${CYAN}[dry-run] Would run: $LISA_CMD${NC}"
        LISA_EXIT=0
    else
        CLAUDE_MODEL="$MODEL" $LISA_CMD
        LISA_EXIT=$?
    fi

    if [[ $LISA_EXIT -eq 0 ]]; then
        echo -e "  ${GREEN}Lisa: All findings resolved${NC}"
    elif [[ $LISA_EXIT -eq 1 ]]; then
        echo -e "  ${YELLOW}Lisa: Max iterations reached — continuing pipeline${NC}"
    else
        echo -e "  ${RED}Lisa: Failed with exit code $LISA_EXIT${NC}"
        log "ERROR" "Lisa loop failed: exit $LISA_EXIT"
        exit $LISA_EXIT
    fi

    STEP_END=$(date +%s)
    print_step_complete "Lisa" "$((STEP_END - STEP_START))"
fi

# ─── Step 5: Ralph Loop ────────────────────────────────────────────────────

if ! should_skip_step "ralph"; then
    STEP_START=$(date +%s)
    print_step_header 5 "Ralph: Implementation"

    RALPH_CMD="$REPO_ROOT/.specify/scripts/bash/ralph-loop.sh $FEATURE_DIR $RALPH_MAX $REPO_ROOT/$FEATURE_DIR/tasks.md"
    log "INFO" "Running: $RALPH_CMD"
    echo -e "  ${DIM}Running: $RALPH_CMD${NC}"

    if $DRY_RUN; then
        echo -e "  ${CYAN}[dry-run] Would run: $RALPH_CMD${NC}"
        RALPH_EXIT=0
    else
        CLAUDE_MODEL="$MODEL" $RALPH_CMD
        RALPH_EXIT=$?
    fi

    if [[ $RALPH_EXIT -eq 0 ]]; then
        echo -e "  ${GREEN}Ralph: All tasks complete${NC}"
    elif [[ $RALPH_EXIT -eq 1 ]]; then
        echo -e "  ${YELLOW}Ralph: Max iterations reached${NC}"
        echo -e "  ${YELLOW}Resume with: pipeline.sh --from ralph $FEATURE_DIR${NC}"
    else
        echo -e "  ${RED}Ralph: Failed with exit code $RALPH_EXIT${NC}"
        log "ERROR" "Ralph loop failed: exit $RALPH_EXIT"
        exit $RALPH_EXIT
    fi

    STEP_END=$(date +%s)
    print_step_complete "Ralph" "$((STEP_END - STEP_START))"
fi

# ─── Summary ────────────────────────────────────────────────────────────────

PIPELINE_END=$(date +%s)
PIPELINE_DURATION=$((PIPELINE_END - PIPELINE_START))

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║${NC}  ${BOLD}Pipeline Complete${NC}                                         ${GREEN}║${NC}"
echo -e "${GREEN}╠════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║${NC}  Feature: ${DIM}${FEATURE_DIR}${NC}"
echo -e "${GREEN}║${NC}  Duration: $((PIPELINE_DURATION / 60))m $((PIPELINE_DURATION % 60))s"
echo -e "${GREEN}║${NC}  Log: ${DIM}$LOG_FILE${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"

log_section "PIPELINE COMPLETE"
log "INFO" "Total duration: ${PIPELINE_DURATION}s"
