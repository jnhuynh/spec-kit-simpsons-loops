# Contract: `pipeline.sh` Specify Step & Quality Gate File Support

## New Step: Specify (Step 0)

### CLI Interface

```bash
pipeline.sh [options] [spec-dir]

# New option value for --from:
--from specify    # Start from the specify step

# New option for feature description:
--description "feature description text"
```

### Step Behavior

| Condition | Action |
|-----------|--------|
| `--from specify` + description provided | Run specify step, then continue pipeline |
| `--from specify` + no description | Exit with error: "Feature description required for specify step" |
| No `--from` + no `spec.md` exists + description provided | Auto-detect: run specify step |
| No `--from` + `spec.md` exists | Skip specify step (existing behavior) |
| `--from homer` (or later) | Skip specify step (existing behavior) |

### Specify Step Execution

The specify step invokes the specify agent non-interactively:

```bash
run_agent "specify" \
    "Feature directory: $FEATURE_DIR. Feature description: $DESCRIPTION. Run non-interactively: auto-resolve all clarifications with best guesses, do not present questions to the user." \
    "Create feature spec from description"
```

### Error Handling (FR-018)

If the specify step fails:
- Pipeline halts immediately
- Exit with non-zero code
- Print: "Specify step failed. Fix the issue and re-invoke with --from specify"

## Quality Gate File Integration

### Resolution Logic

Before running the Ralph step, pipeline.sh resolves quality gates:

```bash
# Priority: CLI arg > env var > file
if [[ -n "${QG_CLI_ARG:-}" ]]; then
    QUALITY_GATES="$QG_CLI_ARG"
elif [[ -n "${QUALITY_GATES:-}" ]]; then
    # Already set from environment
    :
elif [[ -x "$REPO_ROOT/.specify/quality-gates.sh" ]]; then
    QUALITY_GATES="$REPO_ROOT/.specify/quality-gates.sh"
else
    echo "Error: No quality gates configured." >&2
    exit 1
fi
```

### Updated Steps Array

```bash
STEPS=("specify" "homer" "plan" "tasks" "lisa" "ralph")
```

### Updated --from Validation

```bash
if [[ ! "$FROM_STEP" =~ ^(specify|homer|plan|tasks|lisa|ralph)$ ]]; then
    echo "Error: --from must be one of: specify, homer, plan, tasks, lisa, ralph" >&2
    exit 1
fi
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Pipeline completed successfully |
| 1 | Step failure or configuration error |
| 130 | User interrupt (SIGINT/SIGTERM) |

## Backward Compatibility

- Existing invocations without `--from specify` or `--description` behave identically to before
- The default quality gate placeholder behavior is preserved when no file, env var, or CLI arg is present
- `--quality-gates` CLI argument continues to work as the highest-priority override
