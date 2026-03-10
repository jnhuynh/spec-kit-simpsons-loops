# Research: Fix Subagent Delegation and Quality Gate Consolidation

## Decision 1: File Duplication Strategy (Superseded by FR-005/FR-006)

**Decision**: Bash script fallbacks (`pipeline.sh`, `homer-loop.sh`, `lisa-loop.sh`, `ralph-loop.sh`) are deleted from both root level and `.specify/scripts/bash/` per FR-005. Command files are moved from root level into `speckit-commands/` per FR-006. Agent files are moved from `agents/` to `claude-agents/` per FR-006. All edits target source directories; `setup.sh` installs to `.claude/commands/` and `.claude/agents/`.

**Rationale**: The bash script invocation path is dead weight — this project uses Claude Code command files exclusively. Eliminating the duplicate bash scripts removes 8 file pairs and maintenance drift risk. Source directory reorganization (`claude-agents/`, `speckit-commands/`) provides clear naming for the remaining file flow.

**Source → Installed pairs (post-implementation)**:
| Source location | Installed location |
|---|---|
| `speckit-commands/speckit.pipeline.md` | `.claude/commands/speckit.pipeline.md` |
| `speckit-commands/speckit.homer.clarify.md` | `.claude/commands/speckit.homer.clarify.md` |
| `speckit-commands/speckit.lisa.analyze.md` | `.claude/commands/speckit.lisa.analyze.md` |
| `speckit-commands/speckit.ralph.implement.md` | `.claude/commands/speckit.ralph.implement.md` |
| `claude-agents/homer.md` | `.claude/agents/homer.md` |
| `claude-agents/lisa.md` | `.claude/agents/lisa.md` |
| `claude-agents/ralph.md` | `.claude/agents/ralph.md` |

**Deleted pairs (FR-005)**:
| Root-level (DELETE) | Installed location (DELETE) |
|---|---|
| `pipeline.sh` | `.specify/scripts/bash/pipeline.sh` |
| `ralph-loop.sh` | `.specify/scripts/bash/ralph-loop.sh` |
| `homer-loop.sh` | `.specify/scripts/bash/homer-loop.sh` |
| `lisa-loop.sh` | `.specify/scripts/bash/lisa-loop.sh` |

## Decision 2: Command Files Already Describe Agent Tool Spawning

**Decision**: The command files (`speckit.homer.clarify.md`, `speckit.lisa.analyze.md`, `speckit.ralph.implement.md`) already contain correct Agent tool spawning instructions. The pipeline command (`speckit.pipeline.md`) also describes Agent tool spawning. No structural changes needed to the spawning mechanism — the instructions are already correct.

**Rationale**: Investigation revealed that all four command files explicitly instruct:
- `subagent_type: general-purpose`
- Fresh context per iteration
- Specific agent file references (`.claude/agents/homer.md`, etc.)
- Feature directory passed in prompt

The "bug" was not that instructions were missing, but that the pipeline command file's quality gate text still mentions CLI/env overrides (contradicting FR-004/FR-008) and potentially confusing the LLM executing the instructions.

**Alternatives considered**: Adding more explicit Agent tool invocation syntax — rejected because the current instruction format is what Claude Code interprets.

## Decision 3: Quality Gate Simplification Approach

**Decision**: Delete the bash scripts entirely (FR-005) rather than simplifying their `resolve_quality_gates()` functions. Quality gate validation is implemented only in command files (`speckit.pipeline.md` and `speckit.ralph.implement.md`), which instruct the LLM to validate `.specify/quality-gates.sh` as the sole source (FR-004, FR-007, FR-010).

**Rationale**: The spec (FR-004 through FR-008) requires a single source of truth, and FR-005 requires deleting bash scripts entirely. Since bash scripts are deleted, there is no need to simplify their quality gate resolution — the function ceases to exist. Quality gate validation moves entirely to command files.

**Alternatives considered**:
- Keep env var as fallback for CI environments: Rejected — spec explicitly removes all override mechanisms (FR-004)
- Simplify bash `resolve_quality_gates()`: Rejected — bash scripts are deleted per FR-005, making this moot

## Decision 4: Pipeline Quality Gate Text Update

**Decision**: Update `speckit.pipeline.md` Ralph section to remove the text "CLI arguments (`--quality-gates`) and environment variables (`QUALITY_GATES`) override the file when provided." Replace with text stating the file is the sole source.

**Rationale**: FR-004 states "All quality gate references MUST be resolved exclusively from `.specify/quality-gates.sh`" and FR-008 states "without any override mechanism." The existing text in the command file directly contradicts these requirements.

## Decision 5: FR-010 Validation in Command Files

**Decision**: Add a validation step to `speckit.pipeline.md` (ralph phase) and `speckit.ralph.implement.md` that instructs the LLM to check `.specify/quality-gates.sh` exists and contains non-empty executable content before proceeding with quality gate execution. Use a Bash tool check: `test -f .specify/quality-gates.sh && grep -v '^\s*#' .specify/quality-gates.sh | grep -v '^\s*$' | head -1`.

**Rationale**: FR-010 requires command files to validate the quality gates file, catching the empty-file edge case. Since bash scripts are deleted (FR-005), command files are the only invocation path and the only place validation is needed. The bash tool approach provides a deterministic check.

**Alternatives considered**:
- Instruct the LLM to read the file and check manually: Less reliable than a deterministic bash check
- Create a shared validation script: Over-engineering for a single `test + grep` command

## Decision 6: Iteration Default Standardization

**Decision**: Standardize loop defaults in command files to 30 iterations for homer and lisa, and `incomplete_tasks + 10` for ralph. Bash scripts are deleted (FR-005), so only command file defaults remain.

**Rationale**: Current command file defaults are too low (10 for homer/lisa). The increase to 30 provides headroom for complex features with many findings. Premature termination loses work; extra iteration capacity costs nothing when the loop exits early on completion. Ralph keeps dynamic sizing (`incomplete_tasks + 10`) because task count is a more precise ceiling.

**Alternatives considered**:
- Keep 20 as standard: Rejected — spec explicitly requires 30 (FR-011)
- Make ralph commands also use 30: Rejected — dynamic sizing based on task count is more precise (FR-012)

## Decision 7: Stuck Detection Threshold Standardization

**Decision**: Standardize stuck detection at 2 consecutive iterations in command files (the sole invocation path after bash script deletion per FR-005).

**Rationale**: Two consecutive identical iterations (no file changes and no completion signal) is sufficient signal that the loop is stuck — a third rarely recovers. The threshold of 2 saves one wasted subagent invocation per stuck event compared to the previous bash script threshold of 3.

**Alternatives considered**:
- Use 1: Rejected — transient issues can cause false positives
- Use 3: Rejected — wastes an iteration; 2 is sufficient per FR-013

## Decision 8: README Architecture Updates

**Decision**: Add a new "Architecture" section to README with two mermaid diagrams, update all configuration tables, and remove references to `--quality-gates` and `QUALITY_GATES`.

**Rationale**: The README currently documents removed/changed features:
- References `--quality-gates` CLI flag (being removed)
- References `QUALITY_GATES` env var (being removed)
- Shows 20 as default iterations (changing to 30)
- Shows 3 as stuck detection threshold (changing to 2)

Two mermaid diagrams provide visual architecture documentation:
1. Pipeline flow: specify → homer loop → plan → tasks → lisa loop → ralph loop, each spawning subagents
2. Loop lifecycle: orchestrator → spawn subagent → check completion/stuck → next or exit

**Alternatives considered**:
- ASCII art → Rejected: harder to maintain, renders poorly on GitHub
- External diagram tool → Rejected: adds binary artifacts

## Files Requiring Changes

### Must Delete (FR-005)

| File | Action | FR |
|---|---|---|
| `pipeline.sh` (root) | Delete | FR-005 |
| `homer-loop.sh` (root) | Delete | FR-005 |
| `lisa-loop.sh` (root) | Delete | FR-005 |
| `ralph-loop.sh` (root) | Delete | FR-005 |
| `.specify/scripts/bash/pipeline.sh` | Delete (via `setup.sh` cleanup) | FR-005 |
| `.specify/scripts/bash/homer-loop.sh` | Delete (via `setup.sh` cleanup) | FR-005 |
| `.specify/scripts/bash/lisa-loop.sh` | Delete (via `setup.sh` cleanup) | FR-005 |
| `.specify/scripts/bash/ralph-loop.sh` | Delete (via `setup.sh` cleanup) | FR-005 |

### Must Modify (implementation required)

| File | Change | FR |
|---|---|---|
| `speckit-commands/speckit.pipeline.md` | Remove CLI/env override text, add QG file validation, update iteration defaults to 30, stuck detection to 2 | FR-004, FR-007, FR-010, FR-011, FR-013 |
| `speckit-commands/speckit.homer.clarify.md` | Update default iterations to 30, stuck detection to 2, use `--json --paths-only` for prereqs | FR-011, FR-013, FR-019 |
| `speckit-commands/speckit.lisa.analyze.md` | Update default iterations to 30, stuck detection to 2 | FR-011, FR-013 |
| `speckit-commands/speckit.ralph.implement.md` | Add QG file validation, stuck detection to 2 | FR-010, FR-013 |
| `setup.sh` | Install from `claude-agents/` and `speckit-commands/`, remove stale bash scripts and permissions, stop installing bash scripts | FR-005, FR-006 |
| `README.md` | Remove `--quality-gates`/`QUALITY_GATES` refs, remove bash script docs, update defaults to 30, stuck detection to 2, add Architecture section with mermaid diagrams | FR-014–FR-018 |

### Must Reorganize (FR-006)

| Source (current) | Source (target) | Action |
|---|---|---|
| `agents/` | `claude-agents/` | Rename directory |
| Root-level `speckit.*.md` files | `speckit-commands/` | Move into new directory |

### Read-Only (no changes needed)

| File | Reason |
|---|---|
| `claude-agents/homer.md`, `lisa.md`, `ralph.md` | Agent files define single-iteration behavior; no changes needed |
| `.specify/quality-gates.sh` | Quality gate content unchanged |
