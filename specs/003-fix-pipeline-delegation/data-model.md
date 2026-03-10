# Data Model: Fix Pipeline and Loop Command Delegation

## Entities

This feature does not introduce new data entities, databases, or persistent state. It rewrites existing Markdown command files. The "data model" here describes the structure of the files being modified.

### Slash Command File

A Claude Code command definition file in Markdown format.

| Field | Type | Description |
|-------|------|-------------|
| frontmatter.description | string | Help text shown in Claude Code command list |
| body | markdown | Instructions Claude follows when the command is invoked |
| $ARGUMENTS | template variable | Replaced with user-provided arguments at invocation time |

**Locations**: Each command file exists in 3 locations:
1. Repo root: `speckit.<name>.md` (upstream source)
2. Local project: `.claude/commands/speckit.<name>.md`
3. Global installed: `~/.openclaw/.claude/commands/speckit.<name>.md`

**Validation rules**:
- Standalone loop commands (homer, lisa, ralph) must not exceed 40 lines
- Pipeline command must not exceed 60 lines
- All 3 copies must be byte-identical after deployment

### Command-to-Script Mapping

| Command File | Bash Script | Script Path |
|-------------|-------------|-------------|
| `speckit.pipeline.md` | `pipeline.sh` | `.specify/scripts/bash/pipeline.sh` |
| `speckit.homer.clarify.md` | `homer-loop.sh` | `.specify/scripts/bash/homer-loop.sh` |
| `speckit.lisa.analyze.md` | `lisa-loop.sh` | `.specify/scripts/bash/lisa-loop.sh` |
| `speckit.ralph.implement.md` | `ralph-loop.sh` | `.specify/scripts/bash/ralph-loop.sh` |

### Bash Script Interfaces (read-only reference, not modified)

**homer-loop.sh**: `./homer-loop.sh <spec-dir> [max-iterations]`
**lisa-loop.sh**: `./lisa-loop.sh <spec-dir> [max-iterations]`
**ralph-loop.sh**: `./ralph-loop.sh <spec-dir> [max-iterations] [quality-gates]`
**pipeline.sh**: `./pipeline.sh [options] [spec-dir]`
  - Options: `--from <step>`, `--description <text>`, `--homer-max <n>`, `--lisa-max <n>`, `--ralph-max <n>`, `--quality-gates <cmd>`, `--model <model>`, `--dry-run`, `--help`

## State Transitions

No state machines. The command files are stateless — they check for script existence, invoke the script, and report the result. All stateful behavior (iteration tracking, stuck detection, completion conditions) lives in the bash scripts.
