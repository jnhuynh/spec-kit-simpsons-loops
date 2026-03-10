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
**Prefix Pattern Note**: `pipeline.sh:resolve_feature_dir()` uses a 4-char alphanumeric regex `^([a-z0-9]{4})-` while `common.sh:find_feature_dir_by_prefix()` (used by `check-prerequisites.sh`) uses a 3-digit numeric regex `^([0-9]{3})-`. Both resolve feature directories but via different patterns. Since `check-prerequisites.sh` is out of scope, only `pipeline.sh` is modified. When constructing a prospective path during bootstrap (no existing directory), the implementation MUST use the full branch name (`specs/$branch`) rather than prefix glob matching, because the directory does not exist yet for glob expansion to find.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Readability First | PASS | Changes are minimal, clear variable names, well-commented |
| II. Functional Design | PASS | `resolve_feature_dir()` already depends on global variables (`SPEC_DIR_ARG`, `REPO_ROOT`) and filesystem state (pre-existing pattern). The bootstrap fallback adds `FROM_STEP` and `DESCRIPTION` as additional inputs — consistent with the existing pattern, not a new violation. The function remains deterministic given the same global state and filesystem. |
| III. Maintainability Over Cleverness | PASS | Using existing `--paths-only` flag rather than inventing new mechanisms |
| IV. Best Practices | PASS | Following existing codebase patterns for flag usage and error handling |
| V. Simplicity (KISS & YAGNI) | PASS | Fixing callers to use existing capability; no new abstractions |
| Test-First Development | PASS | Lightweight Bash assertion scripts (T002a, T002b) are written before implementation to define expected behavior and verify they FAIL against unfixed code. After implementation, T007 re-runs these scripts to confirm they PASS. No external test framework is required — plain Bash scripts with assertions suffice for the constitution's test-first mandate. |
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
