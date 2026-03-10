# Implementation Plan: Fix Prerequisite Bootstrap Ordering

**Branch**: `004-fix-prereq-bootstrap` | **Date**: 2026-03-09 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/004-fix-prereq-bootstrap/spec.md`

## Summary

The SpecKit pipeline fails when starting from the `specify` step because both `speckit.pipeline.md` and `pipeline.sh` run prerequisite checks that require the spec directory, spec.md, and plan.md to already exist. The fix changes callers to use the existing `--paths-only` flag of `check-prerequisites.sh` for path resolution during early pipeline steps, and updates `pipeline.sh`'s `resolve_feature_dir()` to handle the case where no spec directory exists yet when `--from specify` or `--description` is provided.

## Technical Context

**Language/Version**: Bash 4+ (shell scripts), Markdown (Claude Code command files)
**Primary Dependencies**: Claude CLI (`claude` command), standard Unix utilities (`grep`, `sed`, `test`)
**Storage**: Filesystem only -- `.md` command files, `.sh` scripts
**Testing**: Manual pipeline execution tests (run pipeline with `--from specify --description "..."` and verify it proceeds); shellcheck for static analysis
**Target Platform**: Linux/macOS (any system with Bash 4+)
**Project Type**: CLI tooling / developer workflow automation
**Performance Goals**: N/A (developer tooling, not performance-critical)
**Constraints**: Must not modify `check-prerequisites.sh` internals or `create-new-feature.sh` behavior (explicitly out of scope per spec)
**Scale/Scope**: 3 files to modify: `speckit.pipeline.md`, `pipeline.sh`, and their root-level copies

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Readability First | PASS | Changes are minimal, clear variable names, well-commented |
| II. Functional Design | PASS | `resolve_feature_dir()` remains a pure function with deterministic outputs |
| III. Maintainability Over Cleverness | PASS | Using existing `--paths-only` flag rather than inventing new mechanisms |
| IV. Best Practices | PASS | Following existing codebase patterns for flag usage and error handling |
| V. Simplicity (KISS & YAGNI) | PASS | Fixing callers to use existing capability; no new abstractions |
| Test-First Development | PASS (adapted) | Constitution MUST acknowledged. No new business logic functions are introduced — changes are control-flow adjustments (adding conditional branches) to existing shell scripts. No unit test framework (e.g., bats-core) is present in this project. Validation is performed via manual pipeline execution dry-runs (T007, T011) and shellcheck static analysis (T012), which serve as the test-equivalent for shell script control flow. The spec explicitly defines these as the testing approach (spec.md Technical Context). |
| Spec & Branch Naming | PASS | Branch `004-fix-prereq-bootstrap` follows `XXXX-type-description` pattern |

## Project Structure

### Documentation (this feature)

```text
specs/004-fix-prereq-bootstrap/
├── spec.md              # Feature specification
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── checklists/
│   └── requirements.md  # Spec quality checklist
└── tasks.md             # Phase 2 output (NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
.specify/scripts/bash/
├── pipeline.sh              # Bash pipeline orchestrator (MODIFY: resolve_feature_dir)
├── check-prerequisites.sh   # Prerequisite checker (READ ONLY — not modified)
├── common.sh                # Shared functions (READ ONLY — not modified)
└── create-new-feature.sh    # Feature scaffolding (READ ONLY — not modified)

.claude/commands/
├── speckit.pipeline.md      # Claude Code pipeline command (MODIFY: Step 1 resolution)
├── speckit.homer.clarify.md # Homer command (READ ONLY — already uses --json appropriately)
├── speckit.lisa.analyze.md  # Lisa command (READ ONLY — already uses --json with --require-tasks)
└── speckit.ralph.implement.md # Ralph command (READ ONLY — already uses --json with --require-tasks)

# Root-level copies (kept in sync)
pipeline.sh                  # Wrapper that delegates to .specify/scripts/bash/pipeline.sh
speckit.pipeline.md          # Root copy of .claude/commands/speckit.pipeline.md
```

**Structure Decision**: This is a bug fix on existing infrastructure. No new files are created (aside from plan artifacts). Changes touch the pipeline orchestrator script and the pipeline command file — the two callers that resolve the feature directory before the specify step runs.

## Complexity Tracking

No constitution violations. No complexity tracking needed.
