# Data Model: Fix Install Script, Sub Agent Consistency, and README

**Branch**: `001-fix-install-subagents` | **Date**: 2026-03-01

## Entities

This feature does not introduce runtime data structures, databases, or persistent state. The "data model" consists of file artifacts that are distributed, read, and modified.

### Entity 1: Distribution File

**Description**: A source file in the simpsons-loops repository that gets copied to a target project by `setup.sh`.

| Field | Type | Description | Validation |
|-------|------|-------------|------------|
| source_path | string | Relative path from repo root (e.g., `homer-loop.sh`) | Must exist in repo |
| destination_path | string | Relative path in target project (e.g., `.specify/scripts/bash/homer-loop.sh`) | Parent directory must be created by setup.sh |
| category | enum | `bash-script`, `agent-definition`, `loop-command` | One of 3 categories |
| executable | boolean | Whether `chmod +x` is applied | true only for bash-scripts |

**Instances** (13 files per Distribution File Manifest in spec):

| # | Source | Destination | Category | Executable |
|---|--------|-------------|----------|------------|
| 1 | `homer-loop.sh` | `.specify/scripts/bash/homer-loop.sh` | bash-script | true |
| 2 | `lisa-loop.sh` | `.specify/scripts/bash/lisa-loop.sh` | bash-script | true |
| 3 | `ralph-loop.sh` | `.specify/scripts/bash/ralph-loop.sh` | bash-script | true |
| 4 | `pipeline.sh` | `.specify/scripts/bash/pipeline.sh` | bash-script | true |
| 5 | `agents/homer.md` | `.claude/agents/homer.md` | agent-definition | false |
| 6 | `agents/lisa.md` | `.claude/agents/lisa.md` | agent-definition | false |
| 7 | `agents/ralph.md` | `.claude/agents/ralph.md` | agent-definition | false |
| 8 | `agents/plan.md` | `.claude/agents/plan.md` | agent-definition | false |
| 9 | `agents/tasks.md` | `.claude/agents/tasks.md` | agent-definition | false |
| 10 | `speckit.homer.clarify.md` | `.claude/commands/speckit.homer.clarify.md` | loop-command | false |
| 11 | `speckit.lisa.analyze.md` | `.claude/commands/speckit.lisa.analyze.md` | loop-command | false |
| 12 | `speckit.ralph.implement.md` | `.claude/commands/speckit.ralph.implement.md` | loop-command | false |
| 13 | `speckit.pipeline.md` | `.claude/commands/speckit.pipeline.md` | loop-command | false |

### Entity 2: Loop Command Configuration

**Description**: The behavioral parameters embedded in each loop command file.

| Field | Type | Description | Validation |
|-------|------|-------------|------------|
| command_name | string | Slash command name (e.g., `speckit.homer.clarify`) | Must match filename |
| max_iterations | integer | Maximum loop iterations before abort | Homer/Lisa: 10; Ralph: incomplete_tasks + 10 |
| agent_tool_type | string | Sub agent type parameter | Must be `general-purpose` |
| completion_signal | string | Promise tag indicating loop success | Must be an XML promise tag |
| stuck_detection_threshold | integer | Consecutive identical outputs before abort | Must be 3 |
| failure_policy | enum | `abort-immediately` (loop commands), `retry-3` (bash scripts) | Per FR-011 |
| autonomous | boolean | Whether the loop runs without user prompts | Must be true |

**Instances**:

| Command | Max Iterations | Completion Signal | Failure Policy |
|---------|---------------|-------------------|----------------|
| `speckit.homer.clarify` | 10 | `<promise>ALL_FINDINGS_RESOLVED</promise>` | abort-immediately |
| `speckit.lisa.analyze` | 10 | `<promise>ALL_FINDINGS_RESOLVED</promise>` | abort-immediately |
| `speckit.ralph.implement` | incomplete_tasks + 10 | `<promise>ALL_TASKS_COMPLETE</promise>` | abort-immediately |
| `speckit.pipeline` | Per-step (see above) | Per-step (see above) | abort-immediately |

### Entity 3: Target Project Scaffolding

**Description**: The directory structure required in a target project for `setup.sh` to succeed.

| Field | Type | Description | Validation |
|-------|------|-------------|------------|
| claude_dir | directory | `.claude/` directory | Must exist before running setup.sh |
| specify_dir | directory | `.specify/` directory | Must exist before running setup.sh |
| gitignore | file | `.gitignore` | Created/appended by setup.sh |
| settings_local | file | `.claude/settings.local.json` | Created/updated by setup.sh (requires jq) |

**State Transitions for setup.sh**:
1. **Pre-install**: Target has `.claude/` and `.specify/` only
2. **Post-install**: Target has all 13 distribution files, updated `.gitignore`, updated `settings.local.json`
3. **Re-install** (idempotent): Same as post-install, no duplicate entries

### Entity 4: Terminology Map

**Description**: The canonical terminology that must be consistent across all files.

| Canonical Term | Deprecated Synonyms | Scope |
|---------------|---------------------|-------|
| Agent tool | Task tool | All .md files |
| sub agent | task, child agent | All .md files |
| loop command | loop script (reserved for bash) | All .md files |
| bash loop script | (none) | All .md files |
| promise tag | completion signal (acceptable) | All .md files |
| stuck detection | (none) | All .md files |

## Relationships

```
Distribution File --(copied by)--> setup.sh --(installs into)--> Target Project Scaffolding
Loop Command --(spawns)--> sub agent (via Agent tool)
Loop Command --(references)--> Agent Definition
Pipeline Command --(orchestrates)--> Loop Commands (homer, lisa, ralph) + Single-shot agents (plan, tasks)
```
