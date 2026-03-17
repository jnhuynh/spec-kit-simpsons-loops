# Implementation Plan: Stop-After Pipeline Parameter

**Branch**: `006-stop-after-param` | **Date**: 2026-03-16 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/006-stop-after-param/spec.md`

## Summary

Add a `--stop-after <step>` parameter to the SpecKit pipeline command that halts execution after a specified step completes. This enables partial pipeline runs (e.g., `--stop-after plan` to generate only the spec and plan), combinable with the existing `--from` parameter to define a precise range of steps. The implementation modifies only the pipeline command file (`speckit.pipeline.md`) -- no sub-agent files, utility scripts, or other command files change.

## Technical Context

**Language/Version**: Bash 4+ (shell scripts), Markdown (command/agent files) + Claude CLI (`claude` command)
**Primary Dependencies**: Claude CLI (`claude` command), Agent tool, standard Unix utilities (`grep`, `sed`, `test`)
**Storage**: Filesystem only -- `.md` command files, `.sh` scripts
**Testing**: shellcheck for shell scripts (quality gates); manual pipeline invocation for integration verification
**Target Platform**: macOS/Linux developer workstations
**Project Type**: CLI toolkit / developer tooling
**Performance Goals**: N/A
**Constraints**: Must work within Claude Code Agent tool invocation model; single file change only
**Scale/Scope**: 1 file modified (~255 lines currently), ~50-80 lines of additions/modifications

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Readability First | **PASS** | New argument and validation logic follows existing patterns; clear variable names (`stop_after_step`, `stop_after_index`) |
| II. Functional Design | **PASS** | Stop logic is a deterministic check after each step: if current step matches stop-after, halt. No side effects. |
| III. Maintainability | **PASS** | Single-file change; follows the exact same patterns already used for `--from` |
| IV. Best Practices | **PASS** | Reuses the position-independent argument parsing pattern; same validation approach as `--from` |
| V. Simplicity (KISS & YAGNI) | **PASS** | Only adds what's needed: one new flag, validation, stop check, and enhanced report. No new files, scripts, or abstractions. |
| Test-First Development | **N/A** | The implementation medium (markdown command files interpreted by Claude CLI) does not support automated unit tests. Verification is achieved through alternative means: (1) the quickstart.md verification checklist (`specs/006-stop-after-param/quickstart.md`), which defines 13 concrete acceptance checks covering argument parsing, validation, execution, reporting, and default behavior; (2) manual integration test invocations documented in Phase 3-5 independent test descriptions in tasks.md; (3) T015 explicitly runs the full verification checklist against the implementation. |
| Dev Server Verification | **N/A** | No web UI or API |
| Process Cleanup | **N/A** | No long-running processes involved |

**Post-Phase 1 re-check**: All applicable principles PASS. Test-First Development is N/A for this medium (markdown command files). No violations introduced by the design.

## Project Structure

### Documentation (this feature)

```text
specs/006-stop-after-param/
├── spec.md              # Feature specification
├── plan.md              # This file
├── research.md          # Phase 0 output -- all decisions documented
├── data-model.md        # Phase 1 output -- entity definitions
└── tasks.md             # Phase 2 output (created by /speckit.tasks)
```

### Source Code (repository root)

```text
.claude/commands/
└── speckit.pipeline.md          # Pipeline orchestrator command (MODIFIED)

.claude/agents/                  # Agent files (UNCHANGED)
├── specify.md
├── homer.md
├── plan.md
├── tasks.md
├── lisa.md
└── ralph.md

.specify/
├── quality-gates.sh             # Quality gates (UNCHANGED)
└── scripts/bash/
    ├── check-prerequisites.sh   # Prerequisite checking (UNCHANGED)
    ├── common.sh                # Common functions (UNCHANGED)
    ├── create-new-feature.sh    # Feature creation (UNCHANGED)
    ├── setup-plan.sh            # Plan setup (UNCHANGED)
    └── update-agent-context.sh  # Agent context updater (UNCHANGED)
```

**Structure Decision**: This is a single-file change to the existing pipeline command. No new files or directories are created. The change adds argument parsing, validation, and execution control logic to `speckit.pipeline.md`.

## Design Decisions

### D-001: Argument Parsing Approach

Parse `--stop-after <step>` alongside existing `--from`, `--description`, and `spec-dir` in Step 1. The same position-independent parsing logic applies. The stop-after value is stored in a variable (`STOP_AFTER_STEP`) and validated immediately after all arguments are parsed.

### D-002: Validation Timing

All validation (invalid step name, range conflict with `--from`) happens before any pipeline steps execute. This satisfies FR-005 and FR-006 which require errors to be raised "before any steps execute." Validation is performed right after Step 3 (auto-detect starting step) so that both the start step and stop-after step are known.

### D-003: Step Index Mapping

A fixed mapping of step names to indices (specify=0, homer=1, plan=2, tasks=3, lisa=4, ralph=5) is used for range validation. This avoids complex string comparison chains and enables a simple numeric comparison: `stop_after_index >= start_index`.

### D-004: Post-Step Stop Check

After each step completes in Step 5, the pipeline checks: `if current_step == STOP_AFTER_STEP, then output stop message and skip remaining steps`. This is a simple equality check inserted into the existing sequential execution flow. No changes to how individual steps are executed.

### D-005: Execution Plan Announcement

Before Step 5 begins, the pipeline outputs a single line listing the planned steps and the stop point. This satisfies FR-011. Format: `Execution plan: specify -> homer -> plan. Stopping after: plan.` When `--stop-after` is not provided, the line omits the "Stopping after" clause.

### D-006: Enhanced Completion Report

Step 6 is expanded from listing "steps executed" to listing all six steps with per-step status (`executed`, `skipped`, `stopped-by-param`). Steps before `--from` are shown as `skipped` (they were not executed because they fall outside the execution range). Steps whose artifacts already exist are also shown as `skipped`. Steps after `--stop-after` are shown as `stopped-by-param`. This satisfies FR-008.

### D-007: No New Files

The entire feature is implemented by modifying one existing file. No new command files, agent files, scripts, or test files are created. This aligns with the spec's out-of-scope declaration that no sub-agent files are modified and keeps the change footprint minimal.

## Complexity Tracking

No constitution violations to justify -- all principles pass.
