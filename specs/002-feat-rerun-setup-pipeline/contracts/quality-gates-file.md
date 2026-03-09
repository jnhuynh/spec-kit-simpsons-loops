# Contract: Quality Gates File (`.specify/quality-gates.sh`)

## File Format

- **Type**: Executable bash script
- **Path**: `.specify/quality-gates.sh` (relative to project root)
- **Permissions**: `0755` (owner rwx, group rx, other rx)
- **Encoding**: UTF-8

## Content Contract

The file MUST be a valid bash script that:

1. Exits with code `0` if all quality gates pass
2. Exits with a non-zero code if any quality gate fails
3. Can be executed directly (`./quality-gates.sh`) or sourced (`. quality-gates.sh`)

## Sentinel Comment

The placeholder file contains the sentinel comment on a dedicated line:

```
# SPECKIT_DEFAULT_QUALITY_GATE
```

**Rules**:
- Sentinel MUST appear as a standalone comment line (no leading whitespace beyond `#`)
- Presence of sentinel = file is the unconfigured placeholder
- Absence of sentinel = file has been customized by the user
- User MUST remove the sentinel when configuring their quality gates (the placeholder instructions guide them to replace the entire file content)

## Consumer Contract

Scripts that consume the quality gate file MUST follow this resolution order:

```bash
# Pseudocode for quality gate resolution
if [[ -n "${quality_gates_cli_arg:-}" ]]; then
    # Use CLI argument (highest priority)
    QUALITY_GATES="$quality_gates_cli_arg"
elif [[ -n "${QUALITY_GATES:-}" ]]; then
    # Use environment variable (medium priority)
    QUALITY_GATES="$QUALITY_GATES"
elif [[ -f "$REPO_ROOT/.specify/quality-gates.sh" ]]; then
    # Use file (lowest priority)
    QUALITY_GATES="$REPO_ROOT/.specify/quality-gates.sh"
else
    # Error: no quality gates configured
    echo "Error: No quality gates configured." >&2
    echo "Create .specify/quality-gates.sh or pass --quality-gates" >&2
    exit 1
fi
```

When the source is the file, the script executes it directly (not as a string eval). When the source is CLI or env var, the value is evaluated as a shell command string.

## Setup.sh Contract

| Condition | Action |
|-----------|--------|
| File does not exist + Ralph command has sentinel | Create placeholder file |
| File does not exist + Ralph command lacks sentinel | Extract custom gates from Ralph command, write to file |
| File does not exist + Ralph command not found | Create placeholder file |
| File already exists | Skip (never overwrite) |
