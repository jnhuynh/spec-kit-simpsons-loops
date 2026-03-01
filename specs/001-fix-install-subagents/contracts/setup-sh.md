# Contract: setup.sh Install Script

**Type**: CLI command (bash script)
**Interface**: Filesystem operations with stdout reporting

## Invocation

```bash
# From target project root
bash <path-to-simpsons-loops>/setup.sh
```

## Preconditions

| Condition | Error Behavior |
|-----------|---------------|
| `.claude/` directory exists in `$PWD` | Exit 1 with: `ERROR: .claude/ directory not found in $PWD` |
| `.specify/` directory exists in `$PWD` | Exit 1 with: `ERROR: .specify/ directory not found in $PWD` |
| Script is NOT run from inside the simpsons-loops repo | Exit 1 with: `ERROR: You are running setup.sh from inside the simpsons-loops repo itself.` |

## Postconditions (on success, exit 0)

1. **13 files copied** to correct destinations (see Distribution File Manifest in spec)
2. **4 bash scripts** are executable (`chmod +x`)
3. **`.gitignore`** contains the `# Simpsons loops` marker block (appended if missing, skipped if present)
4. **`.claude/settings.local.json`** contains 4 permission entries (created/merged if jq available, manual instructions printed if jq missing)

## Idempotency Contract

Running `setup.sh` N times on the same target produces the same result as running it once:
- File copies: overwrite (idempotent by nature)
- `.gitignore`: marker check prevents duplicate blocks
- `settings.local.json`: `jq unique` prevents duplicate permission entries

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success (all files installed) |
| 1 | Preflight check failed (missing directory or self-install detected) |

## Output Format

```
Installing Simpsons Loops into: <PROJECT_DIR>

  Copied files:
    .specify/scripts/bash/ralph-loop.sh
    .specify/scripts/bash/lisa-loop.sh
    .specify/scripts/bash/homer-loop.sh
    .specify/scripts/bash/pipeline.sh
    .claude/agents/homer.md
    .claude/agents/lisa.md
    .claude/agents/ralph.md
    .claude/agents/plan.md
    .claude/agents/tasks.md
    .claude/commands/speckit.ralph.implement.md
    .claude/commands/speckit.lisa.analyze.md
    .claude/commands/speckit.homer.clarify.md
    .claude/commands/speckit.pipeline.md
  Made scripts executable
  Appended entries to .gitignore  (or: .gitignore already contains ... — skipped)
  Updated .claude/settings.local.json  (or: ... already has ... — skipped)

Done! Run /speckit.pipeline for the full end-to-end workflow, or use individual loops:
  /speckit.ralph.implement  /speckit.lisa.analyze  /speckit.homer.clarify
```
