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
| Path | String | `.claude/commands/speckit.{name}.md` (+ root-level copy `speckit.{name}.md`) |
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

### Bash Script (Orchestrator)

| Attribute | Type | Description |
|---|---|---|
| Path | String | `.specify/scripts/bash/{name}.sh` (+ root-level copy `{name}.sh`) |
| resolve_quality_gates() | Function | Validates and resolves quality gates from file |
| Agent invocation | Shell command | `claude --agent {name} -p "{prompt}"` |

**Script types**:
| Script | Quality gates | Agent invocation |
|---|---|---|
| `pipeline.sh` | Yes (resolve + pass to ralph) | `run_agent()` for specify/plan/tasks; delegates to loop scripts for homer/lisa/ralph |
| `ralph-loop.sh` | Yes (resolve + include in prompt) | `claude --agent ralph -p "..."` per iteration |
| `homer-loop.sh` | No | `claude --agent homer -p "..."` per iteration |
| `lisa-loop.sh` | No | `claude --agent lisa -p "..."` per iteration |

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

Bash Script (orchestrator)
  ├── spawns → Agent (via `claude --agent`, one per iteration)
  │             └── reads → Agent File (.claude/agents/{name}.md)
  └── resolves → Quality Gates File (Ralph-related only)

Quality Gates File
  └── single source of truth — no CLI args, no env vars
```

### Loop Configuration Defaults

| Parameter | Homer (all paths) | Lisa (all paths) | Ralph (commands) | Ralph (bash) |
|---|---|---|---|---|
| Max iterations | 30 | 30 | `incomplete_tasks + 10` | 30 |
| Stuck detection threshold | 2 consecutive | 2 consecutive | 2 consecutive | 2 consecutive |
| Completion promise | `ALL_FINDINGS_RESOLVED` | `ALL_FINDINGS_RESOLVED` | `ALL_TASKS_COMPLETE` | `ALL_TASKS_COMPLETE` |

**Validation rules**:
- Stuck detection compares consecutive iterations for identical output (bash) or no file changes (commands)
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

1 entry point, 2 scripts with simplified resolve_quality_gates(), uniform prompt formatting
```
