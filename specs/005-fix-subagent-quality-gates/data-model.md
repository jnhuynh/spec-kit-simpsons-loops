# Data Model: Fix Subagent Delegation and Quality Gate Consolidation

## Entities

### Quality Gates File

| Attribute | Type | Description |
|---|---|---|
| Path | String (constant) | `.specify/quality-gates.sh` — always at this fixed location |
| Content | Bash script | Shell commands that exit 0 on success, non-zero on failure |
| Executable content | Derived | Lines that are not comments (`#`) and not whitespace — must have at least one |

**Validation rules**:
- File MUST exist at `.specify/quality-gates.sh`
- File MUST contain at least one line of executable content (not comments/whitespace)
- File is executed via `bash .specify/quality-gates.sh` (execute bit not required)

**State**: Static configuration file. No lifecycle transitions.

### Command File (Orchestrator)

| Attribute | Type | Description |
|---|---|---|
| Source path | String | `speckit-commands/speckit.{name}.md` (source file, edited here) |
| Installed path | String | `.claude/commands/speckit.{name}.md` (installed by `setup.sh`) |
| Type | Enum | `pipeline` (multi-step) or `loop` (iterative: homer, lisa, ralph) |
| Agent spawning | Instruction block | Describes Agent tool invocation with `subagent_type`, agent file path, and prompt |
| Quality gate reference | Instruction block | (Ralph-related only) References `.specify/quality-gates.sh` as sole source |

**Orchestrator types**:
| Command | Type | Spawns agents for | Quality gates |
|---|---|---|---|
| `speckit.pipeline.md` | pipeline | specify, homer iterations, plan, tasks, lisa iterations, ralph iterations | Yes (Ralph step) |
| `speckit.homer.clarify.md` | loop | homer iterations | No |
| `speckit.lisa.analyze.md` | loop | lisa iterations | No |
| `speckit.ralph.implement.md` | loop | ralph iterations | Yes |

### Bash Script (Orchestrator) — DELETED per FR-005

All bash script orchestrators (`pipeline.sh`, `homer-loop.sh`, `lisa-loop.sh`, `ralph-loop.sh`) are deleted from both root level and `.specify/scripts/bash/`. The sole invocation path is Claude Code command files. This entity is documented here only for historical context of the migration.

### Agent File

| Attribute | Type | Description |
|---|---|---|
| Path | String | `.claude/agents/{name}.md` |
| Scope | Single iteration | Defines behavior for ONE iteration of a loop step |
| Quality gate reference | Text | Only `ralph.md` references quality gates (from prompt, not from file) |

**Read-only** — agent files are not modified by this feature.

## Relationships

```text
Command File (orchestrator)
  ├── spawns → Agent (via Agent tool, one per iteration)
  │             └── reads → Agent File (.claude/agents/{name}.md)
  └── references → Quality Gates File (Ralph-related only)

Quality Gates File
  └── single source of truth — no CLI args, no env vars

Setup Script (setup.sh)
  ├── copies → claude-agents/*.md → .claude/agents/*.md
  └── copies → speckit-commands/speckit.*.md → .claude/commands/speckit.*.md
```

**Note**: Bash script orchestrators are deleted per FR-005. No bash-based invocation path exists post-implementation.

### Loop Configuration Defaults

| Parameter | Homer | Lisa | Ralph |
|---|---|---|---|
| Max iterations | 30 | 30 | `incomplete_tasks + 10` |
| Stuck detection threshold | 2 consecutive | 2 consecutive | 2 consecutive |
| Completion promise | `ALL_FINDINGS_RESOLVED` | `ALL_FINDINGS_RESOLVED` | `ALL_TASKS_COMPLETE` |

**Note**: Only command file invocation paths exist (bash scripts deleted per FR-005).

**Validation rules**:
- Stuck detection compares consecutive iterations for no file changes and no completion signal
- Max iterations is a hard ceiling — loop exits with "max iterations reached" message
- Completion promise in subagent output triggers immediate clean exit

## Change Impact

### Before (current state)

```text
Quality gate resolution:
  CLI arg (--quality-gates) → env var (QUALITY_GATES) → file (.specify/quality-gates.sh) → error

3 entry points, 2 scripts with resolve_quality_gates(), source-dependent prompt formatting
```

### After (target state)

```text
Quality gate resolution:
  file (.specify/quality-gates.sh) → error

Single invocation path (command files only — bash scripts deleted per FR-005).
Quality gate validation in ralph command file and pipeline's ralph phase only.
```
