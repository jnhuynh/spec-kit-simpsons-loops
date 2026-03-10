# Research: Fix Subagent Delegation and Quality Gate Consolidation

## Decision 1: File Duplication Strategy

**Decision**: All edits to command files and bash scripts must be applied to both locations (root-level copies and nested copies under `.claude/commands/` and `.specify/scripts/bash/`). The files are identical regular files (not symlinks).

**Rationale**: Both locations are tracked in git. Root-level files are used by the SpecKit CLI tooling (e.g., `claude --agent homer` resolves from root). Nested copies are used by Claude Code's command system (`.claude/commands/`) and the bash pipeline (`.specify/scripts/bash/`).

**Alternatives considered**:
- Symlinks: Would reduce duplication but may break cross-platform compatibility
- Single location: Would break existing invocation paths that reference the other location

**Duplicate pairs**:
| Root-level | Nested location |
|---|---|
| `pipeline.sh` | `.specify/scripts/bash/pipeline.sh` |
| `ralph-loop.sh` | `.specify/scripts/bash/ralph-loop.sh` |
| `homer-loop.sh` | `.specify/scripts/bash/homer-loop.sh` |
| `lisa-loop.sh` | `.specify/scripts/bash/lisa-loop.sh` |
| `speckit.pipeline.md` | `.claude/commands/speckit.pipeline.md` |
| `speckit.homer.clarify.md` | `.claude/commands/speckit.homer.clarify.md` |
| `speckit.lisa.analyze.md` | `.claude/commands/speckit.lisa.analyze.md` |
| `speckit.ralph.implement.md` | `.claude/commands/speckit.ralph.implement.md` |

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

**Decision**: Replace the 3-tier `resolve_quality_gates()` function in both `pipeline.sh` and `ralph-loop.sh` with a simple function that reads only from `.specify/quality-gates.sh`. Remove all CLI argument parsing (`--quality-gates`) and environment variable (`QUALITY_GATES`) resolution.

**Rationale**: The spec (FR-004 through FR-008) explicitly requires a single source of truth. The 3-tier precedence adds complexity, configuration confusion, and inconsistency between invocation methods.

**Alternatives considered**:
- Keep env var as fallback for CI environments: Rejected — spec explicitly removes it (FR-006)
- Move `resolve_quality_gates()` to `common.sh`: Not needed — the function becomes trivially simple (check file exists + non-empty)

## Decision 4: Pipeline Quality Gate Text Update

**Decision**: Update `speckit.pipeline.md` Ralph section to remove the text "CLI arguments (`--quality-gates`) and environment variables (`QUALITY_GATES`) override the file when provided." Replace with text stating the file is the sole source.

**Rationale**: FR-004 states "All quality gate references MUST be resolved exclusively from `.specify/quality-gates.sh`" and FR-008 states "without any override mechanism." The existing text in the command file directly contradicts these requirements.

## Decision 5: FR-011 Validation in Command Files

**Decision**: Add a validation step to `speckit.pipeline.md` and `speckit.ralph.implement.md` that instructs the LLM to check `.specify/quality-gates.sh` exists and contains non-empty executable content before proceeding with quality gate execution. Use a Bash tool check: `test -f .specify/quality-gates.sh && grep -v '^\s*#' .specify/quality-gates.sh | grep -v '^\s*$' | head -1`.

**Rationale**: FR-011 requires command files to validate the quality gates file, catching the empty-file edge case on both command file and bash script invocation paths. The bash tool approach mirrors what the bash scripts already do in `resolve_quality_gates()`.

**Alternatives considered**:
- Instruct the LLM to read the file and check manually: Less reliable than a deterministic bash check
- Create a shared validation script: Over-engineering for a single `test + grep` command

## Files Requiring Changes

### Must Modify (implementation required)

| File | Change | FR |
|---|---|---|
| `pipeline.sh` + `.specify/scripts/bash/pipeline.sh` | Remove `--quality-gates` CLI arg parsing, remove env var resolution, simplify `resolve_quality_gates()` to file-only | FR-004, FR-005, FR-006, FR-007 |
| `ralph-loop.sh` + `.specify/scripts/bash/ralph-loop.sh` | Remove CLI arg `$3` parsing, remove env var resolution, simplify `resolve_quality_gates()` to file-only | FR-004, FR-006, FR-007 |
| `speckit.pipeline.md` + `.claude/commands/speckit.pipeline.md` | Remove CLI/env override text in Ralph section, add quality gate file validation | FR-004, FR-008, FR-011 |
| `speckit.ralph.implement.md` + `.claude/commands/speckit.ralph.implement.md` | Add quality gate file validation step | FR-011 |

### Read-Only (no changes needed)

| File | Reason |
|---|---|
| `speckit.homer.clarify.md` / `.claude/commands/speckit.homer.clarify.md` | Already uses Agent tool correctly; no quality gate references |
| `speckit.lisa.analyze.md` / `.claude/commands/speckit.lisa.analyze.md` | Already uses Agent tool correctly; no quality gate references |
| `.claude/agents/homer.md`, `lisa.md`, `ralph.md` | Agent files define single-iteration behavior; no changes needed |
| `homer-loop.sh`, `lisa-loop.sh` | Already use `claude --agent`; no quality gate references |
