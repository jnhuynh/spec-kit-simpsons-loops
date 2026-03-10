# Implementation Plan: Fix Subagent Delegation and Quality Gate Consolidation

**Branch**: `005-fix-subagent-quality-gates` | **Date**: 2026-03-10 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/005-fix-subagent-quality-gates/spec.md`

## Summary

Consolidate quality gate resolution to use `.specify/quality-gates.sh` exclusively (removing CLI arg and env var overrides), ensure all pipeline steps and loop iterations spawn fresh-context subagents via the Agent tool (command files only — bash script fallbacks are deleted), reorganize source directories (`agents/` → `claude-agents/`, root-level `speckit.*.md` → `speckit-commands/`), standardize iteration defaults to 30 and stuck detection to 2 consecutive iterations in command files, and update the README to reflect these changes with architecture diagrams.

## Technical Context

**Language/Version**: Bash 4+ (shell scripts), Markdown (Claude Code command/agent files)
**Primary Dependencies**: Claude CLI (`claude` command), Claude Code Agent tool, standard Unix utilities (`grep`, `sed`, `test`, `bash`)
**Storage**: Filesystem only — `.md` command files, `.sh` scripts, `.specify/` configuration
**Testing**: Manual verification (no test framework — shell scripts and markdown files validated by shellcheck and runtime behavior)
**Target Platform**: macOS / Linux (developer workstations)
**Project Type**: CLI tooling / developer workflow automation
**Performance Goals**: N/A (interactive developer tool, not latency-sensitive)
**Constraints**: Must work within Claude Code Agent tool capabilities; subagent prompts limited by Claude context window
**Scale/Scope**: ~15 files affected — 4 command files modified, 4 bash scripts deleted (root + `.specify/scripts/bash/`), source directories reorganized (`agents/` → `claude-agents/`, root-level `speckit.*.md` → `speckit-commands/`), `setup.sh` updated, 1 README updated

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Readability First | PASS | Removing bash script fallbacks and consolidating quality gate resolution (3-tier → 1-tier) simplifies the codebase |
| II. Functional Design | PASS | Quality gate validation in command files is a deterministic check. No hidden side effects from env vars or CLI args |
| III. Maintainability Over Cleverness | PASS | Deleting 8 duplicate bash script files eliminates maintenance drift risk entirely |
| IV. Best Practices | PASS | Source directory reorganization follows clear naming conventions (`claude-agents/`, `speckit-commands/`) |
| V. Simplicity (KISS & YAGNI) | PASS | Eliminating bash script fallback path — single invocation method (command files) reduces complexity |
| Test-First Development | N/A | No test framework in project; validation is shellcheck + manual runtime verification |
| Dev Server Verification | N/A | No web UI or API — CLI tooling only |
| Process Cleanup | PASS | No new processes introduced; subagent lifecycle managed by Claude Code |
| Quality Gates | PASS | shellcheck remains the quality gate via `.specify/quality-gates.sh` |

**Gate Result**: PASS — no violations requiring justification.

## Project Structure

### Documentation (this feature)

```text
specs/005-fix-subagent-quality-gates/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output (verification guide)
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code — Current State (before implementation)

```text
# Root-level source files (CURRENT)
agents/                              # Agent source files (rename to claude-agents/)
├── homer.md, lisa.md, ralph.md, plan.md, tasks.md, specify.md
speckit.pipeline.md                  # Command source files (move to speckit-commands/)
speckit.homer.clarify.md
speckit.lisa.analyze.md
speckit.ralph.implement.md
pipeline.sh                          # Bash script fallbacks (DELETE per FR-005)
homer-loop.sh                        # (DELETE per FR-005)
lisa-loop.sh                         # (DELETE per FR-005)
ralph-loop.sh                        # (DELETE per FR-005)
setup.sh                             # Installer (modify to use new source dirs)
README.md                            # Project documentation (modify)

# Installed locations (managed by setup.sh)
.claude/commands/                    # Installed command files (from speckit-commands/)
.claude/agents/                      # Installed agent files (from claude-agents/)
.specify/scripts/bash/               # Installed bash scripts (DELETE installed copies too)
```

### Source Code — Target State (after implementation)

```text
# Root-level source files (TARGET)
claude-agents/                       # Renamed from agents/ (FR-006)
├── homer.md, lisa.md, ralph.md, plan.md, tasks.md, specify.md
speckit-commands/                    # New directory for command source files (FR-006)
├── speckit.pipeline.md              # Pipeline orchestrator (modify)
├── speckit.homer.clarify.md         # Homer loop orchestrator (modify)
├── speckit.lisa.analyze.md          # Lisa loop orchestrator (modify)
├── speckit.ralph.implement.md       # Ralph loop orchestrator (modify)
setup.sh                             # Updated to install from new source dirs
README.md                            # Updated with architecture diagrams

# Installed locations (managed by setup.sh)
.claude/commands/                    # Installed from speckit-commands/
.claude/agents/                      # Installed from claude-agents/
.specify/quality-gates.sh            # Quality gate commands (no change)
```

**Structure Decision**: Source directories are reorganized per FR-006 (`agents/` → `claude-agents/`, root-level `speckit.*.md` → `speckit-commands/`). Bash script fallbacks are deleted per FR-005 (both root-level and `.specify/scripts/bash/` copies). `setup.sh` is updated to install from the new source locations. The sole invocation path is Claude Code command files.

**File flow** (source → installed):

| Source location | Installed location | Action |
|---|---|---|
| `claude-agents/*.md` | `.claude/agents/*.md` | `setup.sh` copies (renamed from `agents/`) |
| `speckit-commands/speckit.*.md` | `.claude/commands/speckit.*.md` | `setup.sh` copies (moved from root) |
| `pipeline.sh` (root) | `.specify/scripts/bash/pipeline.sh` | **DELETE both** (FR-005) |
| `homer-loop.sh` (root) | `.specify/scripts/bash/homer-loop.sh` | **DELETE both** (FR-005) |
| `lisa-loop.sh` (root) | `.specify/scripts/bash/lisa-loop.sh` | **DELETE both** (FR-005) |
| `ralph-loop.sh` (root) | `.specify/scripts/bash/ralph-loop.sh` | **DELETE both** (FR-005) |

## Post-Design Constitution Re-Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Readability First | PASS | Fewer files, clearer directory naming, single invocation path |
| II. Functional Design | PASS | Quality gate validation is a deterministic bash check with no external inputs |
| III. Maintainability Over Cleverness | PASS | Deleting bash scripts eliminates 8 duplicate files and maintenance drift risk |
| IV. Best Practices | PASS | Source directory names (`claude-agents/`, `speckit-commands/`) clearly describe their contents; mermaid for diagrams |
| V. Simplicity (KISS & YAGNI) | PASS | Net file reduction — deleting bash fallback path, consolidating source directories |

**Post-Design Gate Result**: PASS — design reduces complexity by removing dead-weight invocation paths.
