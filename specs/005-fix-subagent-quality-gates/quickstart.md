# Quickstart: Fix Subagent Delegation and Quality Gate Consolidation

## Overview

This feature makes two changes: (1) removes CLI/env quality gate override mechanisms so `.specify/quality-gates.sh` is the sole source, and (2) adds quality gate file validation to command files. No structural changes to subagent spawning are needed — command files already describe Agent tool spawning correctly.

## Implementation Order

### Phase 1: Quality Gate Consolidation in Bash Scripts

**Files**: `pipeline.sh` (+ `.specify/scripts/bash/pipeline.sh`), `ralph-loop.sh` (+ `.specify/scripts/bash/ralph-loop.sh`)

1. **`pipeline.sh`**: Remove `--quality-gates` from help text, remove `QUALITY_GATES_CLI_ARG` variable, remove `QUALITY_GATES_ENV` variable, remove the CLI arg case in argument parsing, simplify `resolve_quality_gates()` to check only the file, remove source-dependent ralph command construction
2. **`ralph-loop.sh`**: Remove `QUALITY_GATES_CLI_ARG="${3:-}"`, simplify `resolve_quality_gates()` to check only the file, remove source-dependent prompt formatting
3. Apply identical changes to both root-level and `.specify/scripts/bash/` copies

### Phase 2: Quality Gate Text in Command Files

**Files**: `speckit.pipeline.md` (+ `.claude/commands/speckit.pipeline.md`), `speckit.ralph.implement.md` (+ `.claude/commands/speckit.ralph.implement.md`)

1. **`speckit.pipeline.md`**: Update Ralph IMPORTANT note to remove CLI/env override text, add quality gate file validation instruction
2. **`speckit.ralph.implement.md`**: Add quality gate file validation step before execution
3. Apply identical changes to both root-level and `.claude/commands/` copies

## Key Patterns

### Simplified resolve_quality_gates() pattern (bash)

```bash
resolve_quality_gates() {
    local qg_file=".specify/quality-gates.sh"

    if [[ ! -f "$qg_file" ]]; then
        echo "Error: Quality gates file not found: $qg_file" >&2
        echo "Create .specify/quality-gates.sh with your project's quality gate commands." >&2
        exit 1
    fi

    local effective_content
    effective_content=$(grep -v '^\s*#' "$qg_file" | grep -v '^\s*$' || true)
    if [[ -z "$effective_content" ]]; then
        echo "Error: Quality gate file exists but contains no executable commands." >&2
        echo "Edit .specify/quality-gates.sh and add your project's quality gate commands." >&2
        exit 1
    fi

    QUALITY_GATES="$qg_file"
}
```

### Quality gate validation in command files

```markdown
Validate quality gates file exists and contains executable content:
bash: test -f .specify/quality-gates.sh && grep -v '^\s*#' .specify/quality-gates.sh | grep -v '^\s*$' | head -1
If the file is missing or the check returns empty, abort with: "Quality gates file missing or empty. Create/edit .specify/quality-gates.sh with your project's quality gate commands."
```

## Verification Checklist

- [ ] `grep -r 'quality-gates' pipeline.sh` shows no `--quality-gates` flag references
- [ ] `grep -r 'QUALITY_GATES_ENV\|QUALITY_GATES_CLI' pipeline.sh ralph-loop.sh` returns empty
- [ ] `grep -r 'QUALITY_GATES_SOURCE' pipeline.sh ralph-loop.sh` returns empty
- [ ] `speckit.pipeline.md` Ralph section mentions only `.specify/quality-gates.sh`
- [ ] `speckit.ralph.implement.md` includes file validation step
- [ ] All root-level files match their `.specify/scripts/bash/` or `.claude/commands/` counterparts
