# Feature Specification: Fix Prerequisite Bootstrap Ordering

**Feature Branch**: `004-fix-prereq-bootstrap`
**Created**: 2026-03-09
**Status**: Draft
**Input**: The speckit pipeline from specify is failing because it runs prerequisite checks that expect a specs directory, feature git branch, and specs file to exist — but those don't exist until `/speckit.specify` completes.

## Clarifications

### Session 2026-03-09

- Q: Does FR-002 require building a new path-resolution mode in check-prerequisites.sh, or fixing callers to use the existing --paths-only flag? → A: Fix callers to use existing --paths-only flag.
- Q: What is explicitly out of scope for this fix? → A: Modifying check-prerequisites.sh internals or create-new-feature.sh behavior.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Run Full Pipeline from Description (Priority: P1)

A developer wants to start a brand-new feature from scratch by running the SpecKit pipeline with a feature description. They expect the pipeline to create the spec directory, branch, and spec file as part of the `specify` step, then continue through the remaining steps (homer, plan, tasks, lisa, ralph) without errors.

**Why this priority**: This is the core broken workflow. Without this fix, users cannot use the pipeline end-to-end from a fresh feature description — the most common new-feature workflow.

**Independent Test**: Can be fully tested by running the pipeline with `--from specify --description "some feature"` on the `main` branch and verifying it creates the spec structure and proceeds to the next step.

**Acceptance Scenarios**:

1. **Given** the user is on a branch without an existing specs directory for the feature, **When** they run the pipeline with `--from specify --description "Add widget support"`, **Then** the pipeline creates the feature branch, spec directory, and spec.md, and proceeds to the homer step without prerequisite errors.
2. **Given** the user provides a `--description` but no `--from` flag, **When** they run the pipeline, **Then** the pipeline auto-detects that no spec.md exists, starts from the `specify` step, and completes successfully.
3. **Given** the specify step has already completed (spec.md exists), **When** the user re-runs the pipeline, **Then** it skips the specify step and begins from homer as before.

---

### User Story 2 - Pipeline Prerequisite Checks Skip Validation for Early Steps (Priority: P2)

The prerequisite checking system currently validates that the feature directory, spec.md, and plan.md all exist before any pipeline step can run. When starting from an early step like `specify`, these validations must be relaxed or deferred so that the step responsible for creating those artifacts can execute.

**Why this priority**: This is the technical root cause. Fixing this unlocks the P1 user story and ensures the check system is stage-aware.

**Independent Test**: Can be tested by invoking the prerequisite check script with a mode that resolves paths without validating file existence, and verifying it returns path information without erroring.

**Acceptance Scenarios**:

1. **Given** the prerequisite check script is invoked with `--paths-only` during the `specify` step, **When** no spec directory or plan.md exists, **Then** it returns path information without exiting with an error (no validation is performed in `--paths-only` mode).
2. **Given** the prerequisite check script is invoked with `--paths-only` during the `homer` step (which runs before plan.md exists), **When** spec.md exists but plan.md does not, **Then** it returns path information without error because `--paths-only` skips all existence validation. The homer step's internal command (`speckit.clarify`) also uses `--paths-only` and validates spec.md existence separately.
3. **Given** the prerequisite check script is invoked with full validation (without `--paths-only`) during the `lisa` or `ralph` step, **When** plan.md and tasks.md are expected, **Then** it validates their existence as it does today.

---

### Edge Cases

- What happens when the user runs `--from specify` without providing `--description`? The pipeline should exit with a clear error requesting a feature description (this already works in pipeline.sh).
- What happens when the user is on the `main` branch and runs `--from specify --description "..."` without a spec-dir argument? The pipeline's `resolve_feature_dir()` cannot derive a path from the branch name because `main` has no feature prefix. In this case, the pipeline MUST skip directory resolution entirely and allow the `specify` step's agent (via `create-new-feature.sh`) to create the feature branch, directory, and spec.md. The `FEATURE_DIR` will be resolved after the specify step completes, before subsequent steps run. If `resolve_feature_dir()` fails and the pipeline is bootstrapping (`--from specify` or `--description` provided), the failure is non-fatal.
- What happens when the `create-new-feature.sh` script fails during the specify step (e.g., branch already exists, numbering conflict)? The pipeline should surface the error clearly and stop.
- What happens when `check-prerequisites.sh` is called with `--paths-only` but the spec directory doesn't exist? It should still return computed paths without validation errors.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The pipeline MUST be able to start from the `specify` step without requiring a pre-existing spec directory, spec.md, or plan.md.
- **FR-002**: Pipeline callers MUST use `check-prerequisites.sh --json --paths-only` (rather than `--json` alone, which triggers full validation) when running early pipeline steps that create artifacts on a feature branch, so that path resolution succeeds without requiring those artifacts to already exist. Note: `--paths-only` (with or without `--json`) only works on feature branches because `check-prerequisites.sh` validates the branch name (via `check_feature_branch()`) before reaching the `--paths-only` code path. On non-feature branches (e.g., `main`), callers MUST skip `check-prerequisites.sh` entirely and allow the specify step to proceed without a resolved feature directory.
- **FR-003**: The pipeline's feature-directory resolution MUST handle the case where no spec directory exists yet when `--from specify` or `--description` is provided.
- **FR-004**: The pipeline's `specify` step MUST create the feature branch, spec directory, and spec.md before subsequent steps run their prerequisite checks.
- **FR-005**: Existing prerequisite validation behavior MUST remain unchanged for steps that depend on prior artifacts (homer requires spec.md, plan requires spec.md, lisa/ralph require spec.md + plan.md + tasks.md).
- **FR-006**: The `speckit.pipeline.md` command file MUST defer full prerequisite validation when `--from specify` or `--description` is provided. On feature branches, it SHOULD use `check-prerequisites.sh --json --paths-only` (path resolution without existence checks) instead of `check-prerequisites.sh --json` (which triggers full validation). On non-feature branches (e.g., `main` or `HEAD`), it MUST skip `check-prerequisites.sh` entirely because the script's branch validation (`check_feature_branch()` in `common.sh`) rejects non-feature branches before the `--paths-only` code path is reached. In either case, if path resolution fails or is skipped, the failure MUST be treated as non-fatal when bootstrapping: `FEATURE_DIR` MUST be set to an empty string (not left unset), and the specify step proceeds without a resolved `FEATURE_DIR`. After the specify step completes, `FEATURE_DIR` MUST be re-resolved before subsequent steps execute.

### Out of Scope

- Modifying the internal logic of `check-prerequisites.sh` (e.g., adding new flags or validation modes). The existing `--paths-only` flag provides path resolution on feature branches. On non-feature branches, callers skip the script entirely rather than modifying it.
- Changing `create-new-feature.sh` behavior. This script is assumed to work correctly and is not part of this fix.
- Adding new pipeline steps or reordering existing steps beyond what is needed to defer prerequisite checks for the `specify` step.
- Non-functional improvements (performance, logging enhancements) to the prerequisite or pipeline scripts.

### Key Entities

- **Prerequisite Check Script** (`check-prerequisites.sh`): Resolves feature paths and validates artifact existence. Must support stage-appropriate validation.
- **Pipeline Orchestrator** (`pipeline.sh` and `speckit.pipeline.md`): Coordinates step execution. Must handle bootstrapping when starting from `specify`.
- **Feature Directory**: The `specs/###-feature-name/` directory containing all feature artifacts. Does not exist before the `specify` step completes.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can run the pipeline from `specify` with a feature description and reach the `homer` step without any prerequisite-related errors, 100% of the time.
- **SC-002**: Existing pipeline runs (starting from homer, plan, tasks, lisa, or ralph with pre-existing artifacts) continue to work identically — zero regressions.
- **SC-003**: The prerequisite check script returns path information without errors when invoked in a path-resolution-only mode, even when the spec directory does not exist.
- **SC-004**: Error messages for genuinely missing prerequisites (e.g., running homer without spec.md) remain clear and actionable.

## Assumptions

- The `create-new-feature.sh` script reliably creates the branch, directory, and initial spec.md. This fix does not change that script's behavior.
- The `--paths-only` flag in `check-prerequisites.sh` already provides path resolution without validation, but may not be used correctly by all callers.
- The `speckit.pipeline.md` command file currently always runs `check-prerequisites.sh --json` for directory resolution, which triggers full validation prematurely.
