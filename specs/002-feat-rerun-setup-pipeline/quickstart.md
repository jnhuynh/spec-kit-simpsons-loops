# Quickstart: Rerunnable Setup & End-to-End Pipeline

## Implementation Overview

This feature touches 6 existing files and creates 1 new source file (`agents/specify.md`). The quality gate file is created per-project by `setup.sh`, not in this repo. Changes are organized into three workstreams:

1. **Quality Gate File** — Create, extract, and read `.specify/quality-gates.sh`
2. **Setup.sh Rerun Safety** — Never overwrite the quality gate file
3. **Pipeline Specify Step** — Add optional step 0 for spec creation

## Key Files to Modify

| File | Change | Priority |
|------|--------|----------|
| `setup.sh` | Add quality gate file creation/extraction logic (Section 1 addition after existing copies) | P1 |
| `ralph-loop.sh` | Add quality gate file reading as fallback source | P1 |
| `pipeline.sh` | Add quality gate file reading + specify step | P1/P2 |
| `speckit.ralph.implement.md` | Replace inline quality gate placeholder with file reference + sentinel | P1 |
| `agents/specify.md` | New agent wrapper for `/speckit.specify` (non-interactive mode for pipeline use) | P2 |
| `speckit.pipeline.md` | Add specify step documentation + quality gate file reference | P2 |

## Implementation Sequence

### Phase 1: Quality Gate File Infrastructure (P1)

**Step 1**: Update `speckit.ralph.implement.md` — Add `# SPECKIT_DEFAULT_QUALITY_GATE` sentinel to the existing placeholder code block. Replace the instruction text to reference `.specify/quality-gates.sh`.

**Step 2**: Update `setup.sh` — **BEFORE** existing file copies (Section 1), add a new Section 0 that:
- Checks if `.specify/quality-gates.sh` exists in the target project
- If not, checks the target's Ralph command file for the sentinel
- Creates or extracts the quality gate file accordingly
- Sets executable permissions
- **CRITICAL**: This MUST run before the `cp` commands that overwrite the Ralph command file, otherwise the newly-copied template (which always contains the sentinel) will mask any custom quality gates the user previously configured.

**Step 3**: Update `ralph-loop.sh` — Modify the quality gate resolution at the top of the script to check the file as a fallback after CLI arg and env var.

**Step 4**: Update `pipeline.sh` — Same quality gate resolution change as ralph-loop.sh, applied before the Ralph step.

### Phase 2: Pipeline Specify Step (P2)

**Step 5**: Update `pipeline.sh` — Add `specify` to the `STEPS` array, update `--from` validation, add the specify step execution block before the homer step.

**Step 6**: Update `speckit.pipeline.md` — Document the new specify step, update the steps list, add usage examples.

## Quality Gate Resolution Pattern

This pattern is shared between `ralph-loop.sh` and `pipeline.sh`:

```bash
resolve_quality_gates() {
    local repo_root="$1"
    local cli_arg="${2:-}"
    local qg_file="$repo_root/.specify/quality-gates.sh"

    if [[ -n "$cli_arg" ]]; then
        echo "$cli_arg"
    elif [[ -n "${QUALITY_GATES:-}" ]]; then
        echo "$QUALITY_GATES"
    elif [[ -x "$qg_file" ]]; then
        # Validate file has executable content (not just comments/whitespace)
        local content
        content=$(grep -v '^\s*#' "$qg_file" | grep -v '^\s*$' || true)
        if [[ -z "$content" ]]; then
            echo "ERROR: Quality gate file exists but contains no executable commands." >&2
            echo "Edit .specify/quality-gates.sh and add your project's quality gate commands." >&2
            return 1
        fi
        echo "$qg_file"
    else
        echo "ERROR: No quality gates configured." >&2
        echo "Create .specify/quality-gates.sh or pass --quality-gates or set QUALITY_GATES env var." >&2
        return 1
    fi
}
```

## Setup.sh Quality Gate Logic

```bash
# BEFORE existing file copies (must read original Ralph command file before it's overwritten)
QG_FILE="$PROJECT_DIR/.specify/quality-gates.sh"
RALPH_CMD_FILE="$PROJECT_DIR/.claude/commands/speckit.ralph.implement.md"

if [[ -f "$QG_FILE" ]]; then
    echo "  Quality gate file already exists — skipped"
else
    if [[ -f "$RALPH_CMD_FILE" ]] && ! grep -q "# SPECKIT_DEFAULT_QUALITY_GATE" "$RALPH_CMD_FILE"; then
        # Custom quality gates found — extract them
        # (extract code block from "Extract Quality Gates" section)
        echo "  Extracted existing quality gates to .specify/quality-gates.sh"
    else
        # Create placeholder
        # (write placeholder content with sentinel)
        echo "  Created quality gate placeholder at .specify/quality-gates.sh"
    fi
    chmod +x "$QG_FILE"
fi
```

## Testing Checklist

- [ ] Fresh install: `setup.sh` creates `.specify/quality-gates.sh` with placeholder
- [ ] Rerun: `setup.sh` does not overwrite existing `.specify/quality-gates.sh`
- [ ] Migration: `setup.sh` extracts custom quality gates from Ralph command file
- [ ] Migration (placeholder): `setup.sh` creates placeholder when Ralph has sentinel
- [ ] Ralph loop reads quality gates from file when no CLI/env override
- [ ] Pipeline reads quality gates from file when no CLI/env override
- [ ] CLI `--quality-gates` overrides file
- [ ] `QUALITY_GATES` env var overrides file
- [ ] Error when no quality gates configured (no file, no env, no CLI)
- [ ] Pipeline `--from specify` creates spec and continues
- [ ] Pipeline skips specify when spec.md exists
- [ ] Pipeline halts with error when specify step fails
- [ ] `shellcheck` passes on all modified scripts
