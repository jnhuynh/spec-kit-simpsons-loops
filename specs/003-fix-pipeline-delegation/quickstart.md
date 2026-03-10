# Quickstart: Fix Pipeline and Loop Command Delegation

## What This Fix Does

Updates 4 orchestrator slash command files to use a hybrid architecture: Agent tool sub-agents for loop orchestration (one per iteration) and Bash tool calls for deterministic operations (feature dir resolution via `check-prerequisites.sh`, stuck detection, quality gates). The fix also updates stuck detection from output-hash comparison (3-iteration threshold) to git diff-based detection (2-iteration threshold) per FR-007, adds utility script existence checks with actionable error messages (FR-002, FR-003), and syncs all file copies across 3 locations.

## Files Modified

4 command files, each in 3 locations (12 file writes total):

| Command | Repo Root | Local Copy | Global Copy |
|---------|-----------|------------|-------------|
| pipeline | `speckit.pipeline.md` | `.claude/commands/speckit.pipeline.md` | `~/.openclaw/.claude/commands/speckit.pipeline.md` |
| homer | `speckit.homer.clarify.md` | `.claude/commands/speckit.homer.clarify.md` | `~/.openclaw/.claude/commands/speckit.homer.clarify.md` |
| lisa | `speckit.lisa.analyze.md` | `.claude/commands/speckit.lisa.analyze.md` | `~/.openclaw/.claude/commands/speckit.lisa.analyze.md` |
| ralph | `speckit.ralph.implement.md` | `.claude/commands/speckit.ralph.implement.md` | `~/.openclaw/.claude/commands/speckit.ralph.implement.md` |

## Implementation Pattern

Each command follows the same hybrid orchestration pattern:

1. **Frontmatter**: Keep existing `description` field
2. **Utility script existence check**: Verify `.specify/scripts/bash/check-prerequisites.sh` exists
3. **Error message**: If missing, display actionable remediation instructions and exit
4. **Feature dir resolution**: Run `check-prerequisites.sh --json` via Bash tool to resolve the feature directory
5. **Loop orchestration**: Spawn Agent tool sub-agents (one per iteration), each reading the agent file, doing work, committing, and exiting
6. **Stuck detection**: After each sub-agent returns, check `git diff HEAD~1 --stat` for file changes and check output for completion promise tag. Abort after 2 consecutive stuck iterations (no git diff AND no promise tag)
7. **Result reporting**: Report success, completion, or failure to the user

## Verification

After implementation:

```bash
# Sync check (all 3 copies identical for each command)
diff speckit.pipeline.md .claude/commands/speckit.pipeline.md
diff speckit.pipeline.md ~/.openclaw/.claude/commands/speckit.pipeline.md
# Repeat for homer, lisa, ralph

# Functional test
/speckit.pipeline --from homer
/speckit.homer.clarify specs/003-fix-pipeline-delegation
```
