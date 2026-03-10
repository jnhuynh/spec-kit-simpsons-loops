# Implementation Plan: Fix Subagent Delegation and Quality Gate Consolidation

**Branch**: `005-fix-subagent-quality-gates` | **Date**: 2026-03-10 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/005-fix-subagent-quality-gates/spec.md`

## Summary

Consolidate the project to a single invocation path (Claude Code command files) by deleting bash script fallbacks, reorganizing source directories (`agents/` → `claude-agents/`, root `speckit.*.md` → `speckit-commands/`), making `.specify/quality-gates.sh` the sole quality gate source (no CLI/env overrides), standardizing iteration defaults to 30 for homer/lisa, fixing homer to work without `plan.md`, and updating the README with architecture diagrams.

## Technical Context

**Language/Version**: Bash 4+ (shell scripts), Markdown (Claude Code command/agent files)
**Primary Dependencies**: Claude CLI (`claude` command), Claude Code Agent tool, standard Unix utilities (`grep`, `sed`, `test`, `jq`)
**Storage**: Filesystem only — `.md` command files, `.sh` scripts, `.specify/` configuration
**Testing**: shellcheck for shell scripts (quality gates); no unit test framework
**Target Platform**: macOS/Linux developer workstations
**Project Type**: CLI toolkit / developer tooling
**Performance Goals**: N/A
**Constraints**: Must work within Claude Code Agent tool invocation model
**Scale/Scope**: ~15 source files across commands, agents, and scripts

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Readability First | **PASS** | Command files use clear markdown sections with explicit numbered steps |
| II. Functional Design | **PASS** | Each command is self-contained with deterministic flow — inputs (feature dir, quality gates file) produce predictable outputs |
| III. Maintainability | **PASS** | Removing bash scripts eliminates 8 duplicate file pairs; single invocation path simplifies future changes |
| IV. Best Practices | **PASS** | Following Claude Code conventions for commands/agents; `jq` for JSON manipulation in setup script |
| V. Simplicity (KISS & YAGNI) | **PASS** | Consolidating from 2 invocation paths to 1; removing 66K+ of redundant bash code |
| Test-First Development | **N/A** | Changes are to markdown command files and shell scripts with no testable application logic; shellcheck serves as the quality gate |
| Dev Server Verification | **N/A** | No web UI or API |
| Process Cleanup | **N/A** | No long-running processes involved |

**Post-Phase 1 re-check**: All principles still PASS. No violations introduced by the design.

## Project Structure

### Documentation (this feature)

```text
specs/005-fix-subagent-quality-gates/
├── spec.md              # Feature specification
├── plan.md              # This file
├── research.md          # Phase 0 output — all decisions documented
├── data-model.md        # Phase 1 output — entity definitions
└── tasks.md             # Phase 2 output (created by /speckit.tasks)
```

### Source Code (repository root)

```text
# Post-implementation layout
claude-agents/                          # Renamed from agents/ (FR-006)
├── homer.md                            # Homer single-iteration agent
├── lisa.md                             # Lisa single-iteration agent
├── ralph.md                            # Ralph single-iteration agent
├── plan.md                             # Plan agent
├── specify.md                          # Specify agent
└── tasks.md                            # Tasks agent

speckit-commands/                       # New directory (FR-006)
├── speckit.pipeline.md                 # Pipeline orchestrator command
├── speckit.homer.clarify.md            # Homer loop command
├── speckit.lisa.analyze.md             # Lisa loop command
└── speckit.ralph.implement.md          # Ralph loop command

setup.sh                                # Installer — updated for new source dirs and cleanup
README.md                               # Documentation — updated per FR-014–FR-018
.specify/
├── quality-gates.sh                    # Single source of quality gates (unchanged)
└── scripts/bash/
    ├── check-prerequisites.sh          # Unchanged
    ├── common.sh                       # Unchanged
    ├── create-new-feature.sh           # Unchanged
    ├── setup-plan.sh                   # Unchanged
    └── update-agent-context.sh         # Unchanged

# DELETED files (FR-005)
# pipeline.sh (root)           — deleted
# homer-loop.sh (root)         — deleted
# lisa-loop.sh (root)          — deleted
# ralph-loop.sh (root)         — deleted
```

**Structure Decision**: This is a flat CLI toolkit with no `src/` or `tests/` hierarchy. Source files are organized by type: `claude-agents/` for agent definitions, `speckit-commands/` for loop/pipeline orchestrator commands. The `setup.sh` script copies source files to their installed locations (`.claude/agents/`, `.claude/commands/`).

## Design Decisions

### D-001: Source Directory Reorganization Strategy

The reorganization uses `git mv` for `agents/` → `claude-agents/` to preserve history. Root-level `speckit.*.md` files are moved via `git mv` into the new `speckit-commands/` directory. Only the 4 loop/pipeline command files move — the other SpecKit commands (`speckit.clarify.md`, `speckit.analyze.md`, etc.) are installed copies from SpecKit core and live only in `.claude/commands/`.

### D-002: setup.sh Cleanup Logic

The cleanup runs **before** the file copy step to ensure stale artifacts are removed even if the copy fails. The cleanup:
1. Removes `pipeline.sh`, `homer-loop.sh`, `lisa-loop.sh`, `ralph-loop.sh` from `.specify/scripts/bash/`
2. Uses `jq` to filter `.claude/settings.local.json` permissions array, removing entries matching `Bash(.specify/scripts/bash/{pipeline,homer-loop,lisa-loop,ralph-loop}.sh*)`
3. Both cleanup steps are idempotent — safe to run on fresh installations

### D-003: Homer Prerequisite Change

Homer switches from `check-prerequisites.sh --json` (validates `plan.md` exists) to `check-prerequisites.sh --json --paths-only` (returns paths without validation). Homer then validates only `spec.md` existence using a Bash tool `test -f` check. This enables homer to run immediately after `/speckit.specify` without `plan.md`.

### D-004: Quality Gate Validation Pattern

Ralph command and pipeline's ralph phase validate quality gates before execution:
```bash
# Check file exists
test -f .specify/quality-gates.sh

# Check file has executable content (not just comments/whitespace)
grep -v '^\s*#' .specify/quality-gates.sh | grep -v '^\s*$' | head -1
```
If either check fails, abort with a clear error message. Homer and lisa do not reference quality gates at all.

### D-005: Pipeline Ralph Iteration Default

The pipeline currently hardcodes ralph max iterations to 20 (Step 4). Post-change, it uses `incomplete_tasks + 10` (matching the standalone ralph command), calculated by counting `- [ ]` lines in `tasks.md` at the start of the ralph step.

## Complexity Tracking

No constitution violations to justify — all principles pass.
