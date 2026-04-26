#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEPARATOR="<!-- ====== PROJECT SPECIFIC ====== -->"

CLAUDE_SRC="$SCRIPT_DIR/CLAUDE.md"
CONSTITUTION_SRC="$SCRIPT_DIR/constitution.md"

FORCE=false

usage() {
  cat <<EOF
Usage: $(basename "$0") [--force] <command> [project-dir]

Commands:
  init <project-dir>     Copy global files into a new project
  update <project-dir>   Update global portion, preserve project-specific content
  update-all             Update all projects in ~/Projects/

Options:
  --force                Overwrite files entirely (discard project-specific content)

Files managed:
  CLAUDE.md                          → <project>/CLAUDE.md
  constitution.md                    → <project>/.specify/memory/constitution.md

Both files use a separator to split global vs project-specific content:
  $SEPARATOR
Everything above the separator is managed by this script.
Everything below is yours — it will never be touched by updates (unless --force).
EOF
  exit 1
}

# Write source file to destination with separator + hint (fresh copy, no merge).
force_file() {
  local src="$1"
  local dest="$2"
  local hint="$3"

  mkdir -p "$(dirname "$dest")"

  {
    cat "$src"
    printf '\n%s\n\n%s\n' "$SEPARATOR" "<!-- $hint -->"
  } > "$dest"

  echo "  ✅ Force-wrote $dest"
}

# Deploy a source file to a destination, adding the separator.
# If the file already exists with a separator, update the global portion instead.
init_file() {
  local src="$1"
  local dest="$2"
  local hint="$3"

  mkdir -p "$(dirname "$dest")"

  if [[ "$FORCE" == true ]]; then
    force_file "$src" "$dest" "$hint"
    return $?
  fi

  if [[ -f "$dest" ]]; then
    if grep -qF "$SEPARATOR" "$dest"; then
      update_file "$src" "$dest"
      return $?
    else
      echo "  ⚠️  $dest exists but has no separator — back it up and re-init manually, or use --force"
      return 1
    fi
  fi

  {
    cat "$src"
    printf '\n%s\n\n%s\n' "$SEPARATOR" "<!-- $hint -->"
  } > "$dest"

  echo "  ✅ Created $dest"
}

# Replace everything above the separator with latest global content
update_file() {
  local src="$1"
  local dest="$2"

  if [[ ! -f "$dest" ]]; then
    echo "  ⚠️  $dest not found — use 'init' first"
    return 1
  fi

  if ! grep -qF "$SEPARATOR" "$dest"; then
    echo "  ⚠️  $dest has no separator marker — add one manually or re-init"
    return 1
  fi

  # Extract project-specific content (separator line + everything below)
  local project_section
  project_section="$(sed -n "/${SEPARATOR}/,\$p" "$dest")"

  # NOTE: command substitution `$(...)` strips trailing newlines, so
  # `$project_section` has no trailing `\n`. The format string MUST
  # restore it so the rewritten file is byte-identical to the one
  # `init_file` produced — otherwise `setup.sh` is non-idempotent
  # (T093 regression; covered by spec/setup_idempotency_spec.rb).
  {
    cat "$src"
    printf '\n%s\n' "$project_section"
  } > "$dest"

  echo "  ✅ Updated $dest"
}

cmd_init() {
  local project_dir="$1"
  echo "Initializing $project_dir..."
  init_file "$CLAUDE_SRC" "$project_dir/CLAUDE.md" \
    "Add project-specific guidelines below (technologies, commands, structure, etc.)"
  init_file "$CONSTITUTION_SRC" "$project_dir/.specify/memory/constitution.md" \
    "Add project-specific standards below (language tooling, formatting, lint rules, etc.)"
  echo ""
  echo "Done. Edit the sections below the separator to add project-specific content."
}

cmd_update() {
  local project_dir="$1"
  local updated=0

  echo "Updating $project_dir..."

  if [[ "$FORCE" == true ]]; then
    force_file "$CLAUDE_SRC" "$project_dir/CLAUDE.md" \
      "Add project-specific guidelines below (technologies, commands, structure, etc.)" && ((updated++)) || true
    force_file "$CONSTITUTION_SRC" "$project_dir/.specify/memory/constitution.md" \
      "Add project-specific standards below (language tooling, formatting, lint rules, etc.)" && ((updated++)) || true
  else
    if [[ -f "$project_dir/CLAUDE.md" ]]; then
      update_file "$CLAUDE_SRC" "$project_dir/CLAUDE.md" && ((updated++)) || true
    fi

    if [[ -f "$project_dir/.specify/memory/constitution.md" ]]; then
      update_file "$CONSTITUTION_SRC" "$project_dir/.specify/memory/constitution.md" && ((updated++)) || true
    fi
  fi

  if [[ $updated -eq 0 ]]; then
    echo "  ⚠️  No managed files found in $project_dir (use --force or init to create)"
  fi
}

cmd_update_all() {
  local found=0

  for dir in ~/Projects/*/; do
    [[ -d "$dir" ]] || continue

    if [[ -f "$dir/CLAUDE.md" ]] || [[ -f "$dir/.specify/memory/constitution.md" ]]; then
      cmd_update "$dir"
      ((found++))
      echo ""
    fi
  done

  if [[ $found -eq 0 ]]; then
    echo "No projects with managed files found in ~/Projects/"
  else
    echo "Updated $found project(s)."
  fi
}

# --- Main ---

[[ $# -lt 1 ]] && usage

# Parse global flags
while [[ $# -gt 0 && "$1" == --* ]]; do
  case "$1" in
    --force) FORCE=true; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

[[ $# -lt 1 ]] && usage

case "$1" in
  init)
    [[ $# -lt 2 ]] && usage
    cmd_init "$(realpath "$2")"
    ;;
  update)
    [[ $# -lt 2 ]] && usage
    cmd_update "$(realpath "$2")"
    ;;
  update-all)
    cmd_update_all
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    echo "Unknown command: $1"
    usage
    ;;
esac
