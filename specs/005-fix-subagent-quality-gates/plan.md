# Implementation Plan: Fix Subagent Delegation and Quality Gate Consolidation

**Branch**: `005-fix-subagent-quality-gates` | **Date**: 2026-03-10 | **Spec**: `specs/005-fix-subagent-quality-gates/spec.md`
**Input**: Feature specification from `specs/005-fix-subagent-quality-gates/spec.md`

## Summary

Fix two related issues: (1) pipeline and loop command files do not spawn fresh-context subagents via the Agent tool — they describe the behavior but execute inline, causing context accumulation and hallucination drift; (2) quality gate resolution uses a 3-tier precedence (CLI arg > env var > file) when the file should be the sole source. The fix updates 4 command files to use the Agent tool for subagent spawning, simplifies `resolve_quality_gates()` in 2 bash scripts to read only from `.specify/quality-gates.sh`, and removes CLI/env override mechanisms.

## Technical Context

**Language/Version**: Bash 4+ (shell scripts), Markdown (Claude Code command/agent files)
**Primary Dependencies**: Claude CLI (`claude` command), Claude Code Agent tool, standard Unix utilities (`grep`, `sed`, `test`, `bash`)
**Storage**: Filesystem only — `.md` command files, `.sh` scripts, `.specify/` configuration
**Testing**: Manual verification via pipeline/loop execution; no automated test framework for markdown command files; bash script changes verified by running the scripts
**Target Platform**: macOS/Linux (developer workstation with Claude Code CLI installed)
**Project Type**: CLI tooling / developer workflow automation
**Performance Goals**: N/A — developer tool, no latency or throughput requirements
**Constraints**: Command files are interpreted by Claude Code LLM, not executed directly; changes must preserve backward compatibility with existing feature specs
**Scale/Scope**: 4 command files, 2 bash scripts, ~15 targeted edits

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Readability First | PASS | Changes simplify code by removing override precedence logic; clearer intent |
| II. Functional Design | PASS | Orchestrators take inputs (feature dir) and produce deterministic outputs (subagent calls); no hidden side effects |
| III. Maintainability Over Cleverness | PASS | Removing complexity (3-tier resolution) improves maintainability |
| IV. Best Practices | PASS | Using Agent tool as designed; following established `claude --agent` pattern in bash |
| V. Simplicity (KISS & YAGNI) | PASS | Removing unused override mechanisms aligns directly with YAGNI |
| Test-First Development | JUSTIFIED | Markdown command files are LLM instruction documents, not executable code — traditional unit tests do not apply. Bash script changes are to configuration resolution logic verified by running the pipeline. See Complexity Tracking. |
| Quality Gates | PASS | No linting/type-checking applies to markdown/bash in this project |

## Project Structure

### Documentation (this feature)

```text
specs/005-fix-subagent-quality-gates/
├── spec.md              # Feature specification
├── plan.md              # This file
├── research.md          # Phase 0: codebase analysis and design decisions
├── data-model.md        # Phase 1: entity relationships and file contracts
├── quickstart.md        # Phase 1: implementation guide
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (repository root)

```text
.claude/
├── commands/
│   ├── speckit.pipeline.md          # Pipeline orchestrator (modify: add Agent tool spawning)
│   ├── speckit.homer.clarify.md     # Homer loop orchestrator (verify: already uses Agent tool)
│   ├── speckit.lisa.analyze.md      # Lisa loop orchestrator (verify: already uses Agent tool)
│   └── speckit.ralph.implement.md   # Ralph loop orchestrator (modify: add quality gate validation)
└── agents/
    ├── homer.md                     # Homer single-iteration agent (read-only reference)
    ├── lisa.md                       # Lisa single-iteration agent (read-only reference)
    └── ralph.md                      # Ralph single-iteration agent (read-only reference)

.specify/
├── scripts/bash/
│   ├── pipeline.sh                  # Bash pipeline orchestrator (modify: remove CLI/env quality gate resolution)
│   ├── ralph-loop.sh                # Ralph bash loop (modify: remove CLI/env quality gate resolution)
│   ├── homer-loop.sh                # Homer bash loop (read-only: already uses claude --agent)
│   ├── lisa-loop.sh                 # Lisa bash loop (read-only: already uses claude --agent)
│   └── common.sh                    # Shared utilities (may need resolve_quality_gates update)
└── quality-gates.sh                 # Single source of truth for quality gates
```

**Structure Decision**: No new files or directories created. All changes are edits to existing command files (`.claude/commands/`) and bash scripts (`.specify/scripts/bash/`). The project structure remains unchanged.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| Test-First for markdown command files | Command files are natural-language instructions interpreted by an LLM — they cannot be unit tested with a test framework | Verification is done by running the pipeline/loops and confirming subagent spawning behavior in the Claude Code UI |
