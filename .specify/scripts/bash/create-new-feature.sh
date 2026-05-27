#!/usr/bin/env bash

set -e

JSON_MODE=false
SHORT_NAME=""
FEATURE_ID=""
FEATURE_TYPE="feat"
ARGS=()
i=1
while [ $i -le $# ]; do
    arg="${!i}"
    case "$arg" in
        --json)
            JSON_MODE=true
            ;;
        --short-name)
            if [ $((i + 1)) -gt $# ]; then
                echo 'Error: --short-name requires a value' >&2
                exit 1
            fi
            i=$((i + 1))
            next_arg="${!i}"
            if [[ "$next_arg" == --* ]]; then
                echo 'Error: --short-name requires a value' >&2
                exit 1
            fi
            SHORT_NAME="$next_arg"
            ;;
        --id)
            if [ $((i + 1)) -gt $# ]; then
                echo 'Error: --id requires a value' >&2
                exit 1
            fi
            i=$((i + 1))
            next_arg="${!i}"
            if [[ "$next_arg" == --* ]]; then
                echo 'Error: --id requires a value' >&2
                exit 1
            fi
            FEATURE_ID="$next_arg"
            ;;
        --type)
            if [ $((i + 1)) -gt $# ]; then
                echo 'Error: --type requires a value' >&2
                exit 1
            fi
            i=$((i + 1))
            next_arg="${!i}"
            if [[ "$next_arg" == --* ]]; then
                echo 'Error: --type requires a value' >&2
                exit 1
            fi
            case "$next_arg" in
                feat|fix|chore) FEATURE_TYPE="$next_arg" ;;
                *) echo "Error: --type must be feat, fix, or chore (got '$next_arg')" >&2; exit 1 ;;
            esac
            ;;
        --help|-h)
            echo "Usage: $0 [--json] [--short-name <name>] [--id XXXX] [--type feat|fix|chore] <feature_description>"
            echo ""
            echo "Options:"
            echo "  --json              Output in JSON format"
            echo "  --short-name <name> Provide a custom short name (2-4 words) for the branch"
            echo "  --id XXXX           Specify 4-char alphanumeric feature ID (overrides auto-generation)"
            echo "  --type TYPE         Branch type: feat, fix, or chore (default: feat)"
            echo "  --help, -h          Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 'Add user authentication system' --short-name 'user-auth'"
            echo "  $0 'Fix login timeout bug' --type fix"
            echo "  $0 'Add OAuth2' --id a1b2"
            exit 0
            ;;
        *)
            ARGS+=("$arg")
            ;;
    esac
    i=$((i + 1))
done

FEATURE_DESCRIPTION="${ARGS[*]}"
if [ -z "$FEATURE_DESCRIPTION" ]; then
    echo "Usage: $0 [--json] [--short-name <name>] [--number N] <feature_description>" >&2
    exit 1
fi

# Trim whitespace and validate description is not empty (e.g., user passed only whitespace)
FEATURE_DESCRIPTION=$(echo "$FEATURE_DESCRIPTION" | xargs)
if [ -z "$FEATURE_DESCRIPTION" ]; then
    echo "Error: Feature description cannot be empty or contain only whitespace" >&2
    exit 1
fi

# Function to find the repository root by searching for existing project markers
find_repo_root() {
    local dir="$1"
    while [ "$dir" != "/" ]; do
        if [ -d "$dir/.git" ] || [ -d "$dir/.specify" ]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

# Generate a 4-character alphanumeric ID from the last 4 chars of a UUID
generate_feature_id() {
    local uuid
    if command -v uuidgen >/dev/null 2>&1; then
        uuid=$(uuidgen | tr '[:upper:]' '[:lower:]' | tr -d '-')
    elif [ -f /proc/sys/kernel/random/uuid ]; then
        uuid=$(cat /proc/sys/kernel/random/uuid | tr -d '-')
    elif command -v python3 >/dev/null 2>&1; then
        uuid=$(python3 -c "import uuid; print(uuid.uuid4().hex)")
    else
        echo "Error: Cannot generate UUID. Install uuidgen or python3." >&2
        exit 1
    fi
    echo "${uuid: -4}"
}

# Check if a feature ID already exists in branches or specs
id_exists() {
    local id="$1"
    local specs_dir="$2"

    if [ -d "$specs_dir" ]; then
        for dir in "$specs_dir"/*; do
            [ -d "$dir" ] || continue
            local dirname
            dirname=$(basename "$dir")
            if [[ "$dirname" == "$id"-* ]]; then
                return 0
            fi
        done
    fi

    if [ "$HAS_GIT" = true ]; then
        local branches
        branches=$(git branch -a 2>/dev/null || echo "")
        if [ -n "$branches" ]; then
            while IFS= read -r branch; do
                local clean_branch
                clean_branch=$(echo "$branch" | sed 's/^[* ]*//; s|^remotes/[^/]*/||')
                if [[ "$clean_branch" == "$id"-* ]]; then
                    return 0
                fi
            done <<< "$branches"
        fi
    fi

    return 1
}

# Generate a unique feature ID (retries on collision)
generate_unique_feature_id() {
    local specs_dir="$1"
    local max_attempts=10
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        local id
        id=$(generate_feature_id)
        if ! id_exists "$id" "$specs_dir"; then
            echo "$id"
            return 0
        fi
        attempt=$((attempt + 1))
    done

    echo "Error: Could not generate a unique feature ID after $max_attempts attempts." >&2
    exit 1
}

# Function to clean and format a branch name
clean_branch_name() {
    local name="$1"
    echo "$name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/-\+/-/g' | sed 's/^-//' | sed 's/-$//'
}

# Resolve repository root. Prefer git information when available, but fall back
# to searching for repository markers so the workflow still functions in repositories that
# were initialised with --no-git.
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

if git rev-parse --show-toplevel >/dev/null 2>&1; then
    REPO_ROOT=$(git rev-parse --show-toplevel)
    HAS_GIT=true
else
    REPO_ROOT="$(find_repo_root "$SCRIPT_DIR")"
    if [ -z "$REPO_ROOT" ]; then
        echo "Error: Could not determine repository root. Please run this script from within the repository." >&2
        exit 1
    fi
    HAS_GIT=false
fi

cd "$REPO_ROOT"

SPECS_DIR="$REPO_ROOT/specs"
mkdir -p "$SPECS_DIR"

# Function to generate branch name with stop word filtering and length filtering
generate_branch_name() {
    local description="$1"
    
    # Common stop words to filter out
    local stop_words="^(i|a|an|the|to|for|of|in|on|at|by|with|from|is|are|was|were|be|been|being|have|has|had|do|does|did|will|would|should|could|can|may|might|must|shall|this|that|these|those|my|your|our|their|want|need|add|get|set)$"
    
    # Convert to lowercase and split into words
    local clean_name
    clean_name=$(echo "$description" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/ /g')
    
    # Filter words: remove stop words and words shorter than 3 chars (unless they're uppercase acronyms in original)
    local meaningful_words=()
    for word in $clean_name; do
        # Skip empty words
        [ -z "$word" ] && continue
        
        # Keep words that are NOT stop words AND (length >= 3 OR are potential acronyms)
        if ! echo "$word" | grep -qiE "$stop_words"; then
            if [ ${#word} -ge 3 ]; then
                meaningful_words+=("$word")
            elif echo "$description" | grep -q "\b${word^^}\b"; then
                # Keep short words if they appear as uppercase in original (likely acronyms)
                meaningful_words+=("$word")
            fi
        fi
    done
    
    # If we have meaningful words, use first 3-4 of them
    if [ ${#meaningful_words[@]} -gt 0 ]; then
        local max_words=3
        if [ ${#meaningful_words[@]} -eq 4 ]; then max_words=4; fi
        
        local result=""
        local count=0
        for word in "${meaningful_words[@]}"; do
            if [ $count -ge $max_words ]; then break; fi
            if [ -n "$result" ]; then result="$result-"; fi
            result="$result$word"
            count=$((count + 1))
        done
        echo "$result"
    else
        # Fallback to original logic if no meaningful words found
        local cleaned
        cleaned=$(clean_branch_name "$description")
        echo "$cleaned" | tr '-' '\n' | grep -v '^$' | head -3 | tr '\n' '-' | sed 's/-$//'
    fi
}

# Generate branch description suffix
if [ -n "$SHORT_NAME" ]; then
    BRANCH_SUFFIX=$(clean_branch_name "$SHORT_NAME")
else
    BRANCH_SUFFIX=$(generate_branch_name "$FEATURE_DESCRIPTION")
fi

# Fetch all remotes to get latest branch info (suppress errors if no remotes)
if [ "$HAS_GIT" = true ]; then
    git fetch --all --prune 2>/dev/null || true
fi

# Generate or use provided 4-char alphanumeric feature ID
if [ -n "$FEATURE_ID" ]; then
    if ! echo "$FEATURE_ID" | grep -qE '^[a-z0-9]{4}$'; then
        echo "Error: --id must be exactly 4 lowercase alphanumeric characters (got '$FEATURE_ID')" >&2
        exit 1
    fi
    if id_exists "$FEATURE_ID" "$SPECS_DIR"; then
        echo "Error: Feature ID '$FEATURE_ID' already exists in branches or specs" >&2
        exit 1
    fi
    FEATURE_NUM="$FEATURE_ID"
else
    FEATURE_NUM=$(generate_unique_feature_id "$SPECS_DIR")
fi

# Build branch name: XXXX-[type]-description
BRANCH_NAME="${FEATURE_NUM}-${FEATURE_TYPE}-${BRANCH_SUFFIX}"

# GitHub enforces a 244-byte limit on branch names
MAX_BRANCH_LENGTH=244
if [ ${#BRANCH_NAME} -gt $MAX_BRANCH_LENGTH ]; then
    PREFIX_LENGTH=$(( ${#FEATURE_NUM} + 1 + ${#FEATURE_TYPE} + 1 ))
    MAX_SUFFIX_LENGTH=$((MAX_BRANCH_LENGTH - PREFIX_LENGTH))

    TRUNCATED_SUFFIX=$(echo "$BRANCH_SUFFIX" | cut -c1-$MAX_SUFFIX_LENGTH)
    TRUNCATED_SUFFIX=$(echo "$TRUNCATED_SUFFIX" | sed 's/-$//')

    ORIGINAL_BRANCH_NAME="$BRANCH_NAME"
    BRANCH_NAME="${FEATURE_NUM}-${FEATURE_TYPE}-${TRUNCATED_SUFFIX}"

    >&2 echo "[specify] Warning: Branch name exceeded GitHub's 244-byte limit"
    >&2 echo "[specify] Original: $ORIGINAL_BRANCH_NAME (${#ORIGINAL_BRANCH_NAME} bytes)"
    >&2 echo "[specify] Truncated to: $BRANCH_NAME (${#BRANCH_NAME} bytes)"
fi

if [ "$HAS_GIT" = true ]; then
    git checkout -b "$BRANCH_NAME"
else
    >&2 echo "[specify] Warning: Git repository not detected; skipped branch creation for $BRANCH_NAME"
fi

FEATURE_DIR="$SPECS_DIR/$BRANCH_NAME"
mkdir -p "$FEATURE_DIR"

TEMPLATE="$REPO_ROOT/.specify/templates/spec-template.md"
SPEC_FILE="$FEATURE_DIR/spec.md"
if [ -f "$TEMPLATE" ]; then cp "$TEMPLATE" "$SPEC_FILE"; else touch "$SPEC_FILE"; fi

export SPECIFY_FEATURE="$BRANCH_NAME"

if $JSON_MODE; then
    if has_jq; then
        jq -cn \
            --arg branch_name "$BRANCH_NAME" \
            --arg spec_file "$SPEC_FILE" \
            --arg feature_num "$FEATURE_NUM" \
            '{BRANCH_NAME:$branch_name,SPEC_FILE:$spec_file,FEATURE_NUM:$feature_num}'
    else
        printf '{"BRANCH_NAME":"%s","SPEC_FILE":"%s","FEATURE_NUM":"%s"}\n' \
            "$(json_escape "$BRANCH_NAME")" "$(json_escape "$SPEC_FILE")" "$(json_escape "$FEATURE_NUM")"
    fi
else
    echo "BRANCH_NAME: $BRANCH_NAME"
    echo "SPEC_FILE: $SPEC_FILE"
    echo "FEATURE_NUM: $FEATURE_NUM"
    echo "SPECIFY_FEATURE environment variable set to: $BRANCH_NAME"
fi
