# Quickstart: Fix Pipeline and Loop Command Delegation

## What This Fix Does

Rewrites 4 slash command files to delegate to bash scripts instead of reimplementing orchestration logic in Claude instructions. The current commands fail because they contain 64-146 lines of loop iteration, stuck detection, and agent-spawning logic that breaks on weaker models or when context is lost. The fix replaces this with thin delegation wrappers (30-60 lines).

## Files Modified

4 command files, each in 3 locations (12 file writes total):

| Command | Repo Root | Local Copy | Global Copy |
|---------|-----------|------------|-------------|
| pipeline | `speckit.pipeline.md` | `.claude/commands/speckit.pipeline.md` | `~/.openclaw/.claude/commands/speckit.pipeline.md` |
| homer | `speckit.homer.clarify.md` | `.claude/commands/speckit.homer.clarify.md` | `~/.openclaw/.claude/commands/speckit.homer.clarify.md` |
| lisa | `speckit.lisa.analyze.md` | `.claude/commands/speckit.lisa.analyze.md` | `~/.openclaw/.claude/commands/speckit.lisa.analyze.md` |
| ralph | `speckit.ralph.implement.md` | `.claude/commands/speckit.ralph.implement.md` | `~/.openclaw/.claude/commands/speckit.ralph.implement.md` |

## Implementation Pattern

Each command follows the same pattern:

1. **Frontmatter**: Keep existing `description` field
2. **Script existence check**: Verify `.specify/scripts/bash/<script>.sh` exists
3. **Error message**: If missing, display remediation instructions
4. **Delegation**: Run `bash .specify/scripts/bash/<script>.sh $ARGUMENTS`
5. **Result reporting**: Report success or failure based on exit code

## Verification

After implementation:

```bash
# Line count check (homer/lisa/ralph <= 40, pipeline <= 60)
wc -l speckit.pipeline.md speckit.homer.clarify.md speckit.lisa.analyze.md speckit.ralph.implement.md

# Sync check (all 3 copies identical for each command)
diff speckit.pipeline.md .claude/commands/speckit.pipeline.md
diff speckit.pipeline.md ~/.openclaw/.claude/commands/speckit.pipeline.md
# Repeat for homer, lisa, ralph

# Functional test
/speckit.pipeline --dry-run
/speckit.homer.clarify specs/003-fix-pipeline-delegation
```
