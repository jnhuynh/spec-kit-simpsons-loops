# Quickstart: Fix Subagent Delegation and Quality Gate Consolidation

## Overview

This feature makes four changes:
1. Removes CLI/env quality gate override mechanisms so `.specify/quality-gates.sh` is the sole source
2. Adds quality gate file validation to command files (empty-file edge case)
3. Standardizes iteration defaults to 30 and stuck detection to 2 across all invocation paths
4. Updates README with architecture diagrams and corrected configuration tables

No structural changes to subagent spawning are needed — command files already describe Agent tool spawning correctly.

## Implementation Order

### Phase 1: Quality Gate Consolidation in Bash Scripts

**Files**: `pipeline.sh` (+ `.specify/scripts/bash/pipeline.sh`), `ralph-loop.sh` (+ `.specify/scripts/bash/ralph-loop.sh`)

1. **`pipeline.sh`**: Remove `--quality-gates` from help text, remove `QUALITY_GATES_CLI_ARG` variable, remove `QUALITY_GATES_ENV` variable, remove the CLI arg case in argument parsing, simplify `resolve_quality_gates()` to check only the file, remove source-dependent ralph command construction
2. **`ralph-loop.sh`**: Remove `QUALITY_GATES_CLI_ARG="${3:-}"`, simplify `resolve_quality_gates()` to check only the file, remove source-dependent prompt formatting
3. Apply identical changes to both root-level and `.specify/scripts/bash/` copies

### Phase 2: Iteration Defaults and Stuck Detection in Bash Scripts

**Files**: `homer-loop.sh`, `lisa-loop.sh`, `ralph-loop.sh`, `pipeline.sh` (all + `.specify/scripts/bash/` copies)

1. **`homer-loop.sh`**: Change `MAX_ITERATIONS="${2:-20}"` to `MAX_ITERATIONS="${2:-30}"`, change `MAX_CONSECUTIVE_FAILURES=3` to `MAX_CONSECUTIVE_FAILURES=2`
2. **`lisa-loop.sh`**: Same changes as homer
3. **`ralph-loop.sh`**: Change `MAX_ITERATIONS="${2:-5}"` to `MAX_ITERATIONS="${2:-30}"`, change stuck threshold to 2
4. **`pipeline.sh`**: Update any hardcoded iteration defaults and stuck detection thresholds to match

### Phase 3: Quality Gate Text and Defaults in Command Files

**Files**: `speckit.pipeline.md`, `speckit.homer.clarify.md`, `speckit.lisa.analyze.md`, `speckit.ralph.implement.md` (all + `.claude/commands/` copies)

1. **`speckit.pipeline.md`**: Update Ralph IMPORTANT note to remove CLI/env override text, add quality gate file validation instruction, update iteration defaults to 30, stuck detection to 2
2. **`speckit.homer.clarify.md`**: Update default iterations to 30, stuck detection to 2
3. **`speckit.lisa.analyze.md`**: Update default iterations to 30, stuck detection to 2
4. **`speckit.ralph.implement.md`**: Add quality gate file validation step, update stuck detection to 2

### Phase 4: README Updates

**File**: `README.md`

1. Remove all references to `--quality-gates` CLI flag and `QUALITY_GATES` environment variable
2. Update iteration defaults: homer/lisa → 30, ralph bash → 30
3. Update stuck detection: "two consecutive iterations" (not three)
4. Add new "Architecture" section with two mermaid diagrams
5. Consolidate "Quality gates" section to document file-only source

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
- [ ] Homer/lisa bash scripts default to 30 iterations
- [ ] Ralph bash script defaults to 30 iterations
- [ ] Homer/lisa command files default to 30 iterations
- [ ] All stuck detection thresholds are 2
- [ ] README has no `--quality-gates` or `QUALITY_GATES` references
- [ ] README shows 30 for homer/lisa defaults
- [ ] README shows "two consecutive iterations" for stuck detection
- [ ] README has "Architecture" section with two mermaid diagrams
- [ ] All root-level files match their `.specify/scripts/bash/` or `.claude/commands/` counterparts
