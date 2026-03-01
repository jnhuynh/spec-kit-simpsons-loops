# Implementation Plan: Fix Install Script, Sub Agent Consistency, and README

**Branch**: `001-fix-install-subagents` | **Date**: 2026-03-01 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `specs/001-fix-install-subagents/spec.md`

## Summary

Fix the install script (`setup.sh`) to work reliably with test directories, update all four loop command files to use the canonical "Agent tool" terminology instead of deprecated "Task tool", enforce consistent behavior (sequential execution, autonomous operation, 10-iteration limit, error handling), and rewrite the README to accurately reflect current behavior. This is primarily a consistency and correctness pass across shell scripts, Markdown command files, and documentation.

## Technical Context

**Language/Version**: Bash (POSIX-compatible, tested with bash 4+); Markdown for Claude Code commands and agent definitions
**Primary Dependencies**: Claude Code CLI (`claude --agent`), `jq` (optional, for JSON manipulation in setup.sh), `git`
**Storage**: N/A (file-based artifacts only: Markdown specs, shell scripts)
**Testing**: Manual testing via test directory scaffolding; bash script validation via `shellcheck`; idempotency verification by running `setup.sh` twice
**Target Platform**: macOS and Linux (developer workstations with Claude Code CLI installed)
**Project Type**: Developer tooling distribution (shell scripts + Claude Code command/agent definitions)
**Performance Goals**: N/A (human-initiated, not latency-sensitive)
**Constraints**: Must not require any dependencies beyond bash, git, and optionally jq; must be idempotent; must not prompt for user input during autonomous execution
**Scale/Scope**: 13 distribution files, 4 loop command files, 5 agent definitions, 4 bash scripts, 1 README, 1 install script

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

The constitution file (`.specify/memory/constitution.md`) contains only placeholder template content with no project-specific principles defined. Since no concrete constitutional rules have been ratified, there are no gates to evaluate or violate. This gate passes by default.

**Pre-Phase 0 assessment**: PASS (no constitution rules defined)
**Post-Phase 1 assessment**: PASS (no constitution rules defined)

## Project Structure

### Documentation (this feature)

```text
specs/001-fix-install-subagents/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (repository root)

```text
.
├── setup.sh                         # Install script (FR-001, FR-002, FR-003)
├── README.md                        # Project documentation (FR-007, FR-008, FR-009)
├── gitignore                        # Template .gitignore entries for target projects
├── agents/                          # Agent definitions (distribution source)
│   ├── homer.md
│   ├── lisa.md
│   ├── ralph.md
│   ├── plan.md
│   └── tasks.md
├── speckit.homer.clarify.md         # Loop command files (distribution source)
├── speckit.lisa.analyze.md
├── speckit.ralph.implement.md
├── speckit.pipeline.md
├── homer-loop.sh                    # Bash loop scripts (distribution source)
├── lisa-loop.sh
├── ralph-loop.sh
└── pipeline.sh
```

**Structure Decision**: This is a flat distribution repository. All source files live at the root level. The `agents/` subdirectory holds agent definitions. There is no `src/` or `tests/` directory because the project consists entirely of shell scripts and Markdown files that are copied into target projects via `setup.sh`.

## Complexity Tracking

> No constitution violations to justify. The constitution contains only placeholder content.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| N/A | N/A | N/A |
