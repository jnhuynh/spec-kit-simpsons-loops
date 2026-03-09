# Contract: `setup.sh` Rerun Behavior

## Invocation

```bash
# Run from the root of a target project
bash <path-to-simpsons-loops>/setup.sh
```

## Idempotency Guarantee

Running `setup.sh` N times produces the same result as running it once:

- All overwritable files are identical after each run
- The quality gate file is created exactly once (first run or migration)
- `.gitignore` entries are appended exactly once (marker-based dedup)
- Permissions are set identically on each run

## File Handling Rules

### Always Overwrite (update to latest)

These files are unconditionally overwritten on every run:

```
.specify/scripts/bash/ralph-loop.sh
.specify/scripts/bash/lisa-loop.sh
.specify/scripts/bash/homer-loop.sh
.specify/scripts/bash/pipeline.sh
.claude/agents/homer.md
.claude/agents/lisa.md
.claude/agents/ralph.md
.claude/agents/plan.md
.claude/agents/tasks.md
.claude/agents/specify.md
.claude/commands/speckit.ralph.implement.md
.claude/commands/speckit.lisa.analyze.md
.claude/commands/speckit.homer.clarify.md
.claude/commands/speckit.pipeline.md
```

### Never Overwrite (preserve user configuration)

```
.specify/quality-gates.sh
```

**Creation logic**:

```
IF .specify/quality-gates.sh exists:
    SKIP (log "quality gate file already exists")
ELSE IF .claude/commands/speckit.ralph.implement.md exists in TARGET:
    IF file contains "# SPECKIT_DEFAULT_QUALITY_GATE":
        CREATE placeholder quality-gates.sh
    ELSE:
        EXTRACT quality gate code block from Ralph command
        WRITE extracted content to quality-gates.sh
    ENDIF
ELSE:
    CREATE placeholder quality-gates.sh
ENDIF
chmod +x .specify/quality-gates.sh
```

### Atomic Write

Quality gate file creation uses atomic write:

```bash
tmp=$(mktemp)
# Write content to $tmp
chmod +x "$tmp"
mv "$tmp" "$PROJECT_DIR/.specify/quality-gates.sh"
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Preflight check failure (missing `.claude/`, `.specify/`, or running from wrong directory) |

## Output

Setup.sh MUST print status for each action taken, including:
- Files copied
- Quality gate file status (created / extracted / skipped)
- Permissions set
- `.gitignore` status
- Settings file status
