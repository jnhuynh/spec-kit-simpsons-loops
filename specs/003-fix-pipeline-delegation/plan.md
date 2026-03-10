# Implementation Plan: Fix Pipeline and Loop Command Delegation

**Branch**: `003-fix-pipeline-delegation` | **Date**: 2026-03-09 | **Spec**: `specs/003-fix-pipeline-delegation/spec.md`
**Input**: Feature specification from `specs/003-fix-pipeline-delegation/spec.md`

## Summary

Rewrite the 4 orchestrator slash commands (`/speckit.pipeline`, `/speckit.homer.clarify`, `/speckit.lisa.analyze`, `/speckit.ralph.implement`) to delegate execution to their corresponding bash scripts instead of reimplementing orchestration logic in Claude instructions. The current commands (64-146 lines) contain loop iteration, stuck detection, and agent-spawning logic that duplicates what already exists in the bash scripts, causing failures when the Claude session loses context or uses weaker models. The fix replaces this with thin delegation layers (30-60 lines) that check for script existence, pass through arguments, and report results.

## Technical Context

**Language/Version**: Bash 4+ (shell scripts), Markdown (Claude Code command files)
**Primary Dependencies**: Claude CLI (`claude` command), Claude Code Agent tool, Bash tool
**Storage**: Filesystem only — `.md` command files, `.sh` scripts
**Testing**: Manual invocation of slash commands; `diff` across file copies for sync verification; `wc -l` for line count validation
**Target Platform**: Any platform running Claude Code CLI (Linux, macOS)
**Project Type**: CLI tooling / developer workflow automation
**Performance Goals**: N/A (interactive developer tool)
**Constraints**: Standalone loop commands must not exceed 40 lines; pipeline command must not exceed 60 lines
**Scale/Scope**: 4 command files, each existing in 3 locations (12 files total)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Readability First | PASS | Rewritten commands will be dramatically simpler — thin delegation instead of complex orchestration logic |
| II. Functional Design | PASS | Each command takes user arguments, delegates to a script, returns the result. No hidden side effects |
| III. Maintainability Over Cleverness | PASS | Removing 100+ lines of duplicated orchestration logic per file. One implementation path instead of two |
| IV. Best Practices | PASS | Shell delegation is the standard pattern for CLI wrappers |
| V. Simplicity (KISS & YAGNI) | PASS | Core fix: remove duplicate logic, delegate to existing scripts |
| Test-First Development | N/A | No new business logic functions — this is a configuration/command file rewrite. Manual verification via invocation |
| Spec & Branch Naming | PASS | Branch `003-fix-pipeline-delegation` matches spec directory |

No violations. All gates pass.

## Project Structure

### Documentation (this feature)

```text
specs/003-fix-pipeline-delegation/
├── spec.md              # Feature specification
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── checklists/
│   └── requirements.md  # Requirements checklist
└── tasks.md             # Phase 2 output (created by /speckit.tasks)
```

### Source Code (repository root)

```text
# Upstream source files (repo root) — to be rewritten
speckit.pipeline.md
speckit.homer.clarify.md
speckit.lisa.analyze.md
speckit.ralph.implement.md

# Local project copies — must be synced after rewrite
.claude/commands/speckit.pipeline.md
.claude/commands/speckit.homer.clarify.md
.claude/commands/speckit.lisa.analyze.md
.claude/commands/speckit.ralph.implement.md

# Global installed copies — must be synced after rewrite
~/.openclaw/.claude/commands/speckit.pipeline.md
~/.openclaw/.claude/commands/speckit.homer.clarify.md
~/.openclaw/.claude/commands/speckit.lisa.analyze.md
~/.openclaw/.claude/commands/speckit.ralph.implement.md

# Bash scripts (NOT modified — out of scope)
.specify/scripts/bash/pipeline.sh
.specify/scripts/bash/homer-loop.sh
.specify/scripts/bash/lisa-loop.sh
.specify/scripts/bash/ralph-loop.sh
```

**Structure Decision**: No new directories or files are created. This is a rewrite of 4 existing command files (each in 3 locations = 12 file writes). The bash scripts remain untouched.

## Complexity Tracking

No constitution violations to justify. All principles are satisfied.
