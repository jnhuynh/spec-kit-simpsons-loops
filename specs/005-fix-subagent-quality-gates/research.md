# Research: Fix Subagent Delegation and Quality Gate Consolidation

**Branch**: `005-fix-subagent-quality-gates` | **Date**: 2026-03-10

## R-001: Subagent Delegation Mechanism

**Decision**: Command files already contain correct Agent tool spawning instructions with `subagent_type: general-purpose`, fresh context per iteration, specific agent file references, and feature directory in prompts. No structural changes needed to the spawning mechanism.

**Rationale**: All four command files (`speckit.pipeline.md`, `speckit.homer.clarify.md`, `speckit.lisa.analyze.md`, `speckit.ralph.implement.md`) explicitly instruct Agent tool usage. The real issues are: (1) the pipeline mentions CLI/env quality gate overrides that confuse the LLM, (2) iteration defaults are too low, and (3) bash scripts create a competing invocation path.

**Alternatives considered**: Adding more explicit Agent tool invocation syntax — rejected because the current instruction format is what Claude Code interprets.

## R-002: Quality Gate Simplification

**Decision**: Strip all CLI argument (`--quality-gates`) and environment variable (`QUALITY_GATES`) override references from command files and README. Use `.specify/quality-gates.sh` as the sole source. Delete bash scripts entirely (FR-005), so their `resolve_quality_gates()` functions cease to exist.

**Rationale**: The pipeline command (`speckit.pipeline.md` line 195) mentions CLI/env overrides. Post-change, `.specify/quality-gates.sh` is the single source of truth. The `setup.sh` quality gate creation logic (lines 36-98) remains valid — it creates the file if absent.

**Alternatives considered**: Keeping env var override for CI/CD flexibility — rejected per spec clarification that single-file-only simplifies configuration.

## R-003: Quality Gate Validation (FR-010)

**Decision**: Add validation step to `speckit.ralph.implement.md` and pipeline's ralph phase. Use Bash tool check: `test -f .specify/quality-gates.sh && grep -v '^\s*#' .specify/quality-gates.sh | grep -v '^\s*$' | head -1`. Abort with clear error if file is missing or contains only comments/whitespace. Homer and lisa skip quality gate validation entirely.

**Rationale**: FR-010 requires command files to validate the quality gates file, catching the empty-file edge case. Since bash scripts are deleted, command files are the only invocation path.

**Alternatives considered**: Creating a shared validation script — over-engineering for a single check.

## R-004: Bash Script Deletion and Cleanup

**Decision**: Delete root-level `pipeline.sh`, `homer-loop.sh`, `lisa-loop.sh`, `ralph-loop.sh`. Update `setup.sh` to: (1) stop installing them to `.specify/scripts/bash/`, (2) actively remove previously-installed copies from `.specify/scripts/bash/`, (3) remove their `Bash(.specify/scripts/bash/...)` permission entries from `.claude/settings.local.json` using `jq`.

**Rationale**: 66K+ of bash code that duplicates command file functionality. Creates maintenance drift across 8 file pairs. Cleanup ensures existing installations don't retain orphaned artifacts.

**Alternatives considered**: Freezing scripts and marking deprecated — rejected per spec clarification.

## R-005: Source Directory Reorganization

**Decision**: Rename `agents/` → `claude-agents/`, move root-level `speckit.*.md` → `speckit-commands/`. Update `setup.sh` to install from new locations (`claude-agents/` → `.claude/agents/`, `speckit-commands/` → `.claude/commands/`).

**Rationale**: Current layout has ambiguous `agents/` naming and `speckit.*.md` scattered at root. New layout explicitly names source directories.

**Note**: Only the 4 loop/pipeline command files move to `speckit-commands/`. The other command files already live in `.claude/commands/` as installed copies from the SpecKit core.

## R-006: Homer Prerequisite Flow (FR-019)

**Decision**: Homer command switches to `check-prerequisites.sh --json --paths-only` and validates `spec.md` existence itself.

**Rationale**: The current `check-prerequisites.sh --json` (without `--paths-only`) validates that `plan.md` exists (line 110-114 of the script). When homer runs right after `/speckit.specify` (no `plan.md` yet), full validation fails. Using `--paths-only` gets the feature directory path without artifact validation.

**Alternatives considered**: Modifying `check-prerequisites.sh` to make `plan.md` optional — rejected per spec clarification that the prerequisite script stays unchanged.

## R-007: Iteration Default Standardization

**Decision**: Homer and Lisa defaults → 30 for both standalone commands and pipeline. Ralph standalone stays `incomplete_tasks + 10`. Pipeline ralph changes from hardcoded 20 to `incomplete_tasks + 10`.

**Rationale**: Current defaults are 10 (standalone) / 20 (pipeline) for homer/lisa. The spec requires 30 uniformly. Ralph's dynamic calculation is more useful than a static default.

## R-008: Stuck Detection Threshold

**Decision**: Already at 2 in all command files. Only the README needs correction (currently says "three consecutive iterations").

**Rationale**: Two consecutive iterations with no changes is sufficient stuck signal.

## Files Requiring Changes

### Delete (FR-005)

| File | Action |
|---|---|
| `pipeline.sh` (root) | Delete source |
| `homer-loop.sh` (root) | Delete source |
| `lisa-loop.sh` (root) | Delete source |
| `ralph-loop.sh` (root) | Delete source |

### Reorganize (FR-006)

| Current | Target |
|---|---|
| `agents/` | `claude-agents/` |
| `speckit.pipeline.md` (root) | `speckit-commands/speckit.pipeline.md` |
| `speckit.homer.clarify.md` (root) | `speckit-commands/speckit.homer.clarify.md` |
| `speckit.lisa.analyze.md` (root) | `speckit-commands/speckit.lisa.analyze.md` |
| `speckit.ralph.implement.md` (root) | `speckit-commands/speckit.ralph.implement.md` |

### Modify

| File (post-reorganization) | Changes | FRs |
|---|---|---|
| `speckit-commands/speckit.pipeline.md` | Remove CLI/env override text, add QG validation, update defaults to 30, ralph to `incomplete_tasks + 10`, verify subagent spawning with Agent tool, verify sequential execution, verify feature dir in prompts, verify stuck detection threshold is 2 | FR-001, FR-003, FR-004, FR-007, FR-008, FR-009, FR-010, FR-011, FR-012, FR-013 |
| `speckit-commands/speckit.homer.clarify.md` | Update default to 30, use `--json --paths-only`, validate only `spec.md` | FR-011, FR-019, FR-020 |
| `speckit-commands/speckit.lisa.analyze.md` | Update default to 30 | FR-011 |
| `speckit-commands/speckit.ralph.implement.md` | Add QG file validation | FR-010 |
| `setup.sh` | Install from new source dirs, cleanup stale bash scripts and permissions | FR-005, FR-006 |
| `README.md` | Remove bash/override refs, update defaults, add Architecture section | FR-014–FR-018 |

### No Changes Needed

| File | Reason |
|---|---|
| `claude-agents/*.md` | Agent files define single-iteration behavior; no content changes |
| `.specify/quality-gates.sh` | Content unchanged |
| `.specify/scripts/bash/check-prerequisites.sh` | Script stays unchanged per spec |
| `.specify/scripts/bash/common.sh` | No changes needed |
