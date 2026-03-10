# Research: Fix Prerequisite Bootstrap Ordering

## Research Task 1: How `speckit.pipeline.md` resolves the feature directory

**Decision**: When no `spec-dir` argument is provided, `speckit.pipeline.md` (Step 1, line 89) instructs the agent to run `check-prerequisites.sh --json` to resolve `FEATURE_DIR`. This triggers full validation (requiring the feature directory, spec.md, and plan.md to exist), which fails when starting from the `specify` step. The fix is to use `--paths-only` (or `--json --paths-only`) instead, which returns computed paths without validation. When `--from specify` or `--description` is provided and no `spec-dir` is given, the command should use `--paths-only` mode or skip `check-prerequisites.sh` entirely and derive the feature directory from the current branch name.

**Rationale**: The `--paths-only` flag already exists in `check-prerequisites.sh` (lines 87-101) and provides exactly the behavior needed: path resolution without file-existence validation. The spec explicitly says to use this existing flag rather than modifying the script.

**Alternatives considered**: (1) Adding a new `--no-validate` flag to `check-prerequisites.sh` -- rejected because modifying the script's internals is explicitly out of scope. (2) Always using `--paths-only` for all steps -- rejected because later steps (homer, lisa, ralph) benefit from the validation that `--json` provides to catch genuinely missing prerequisites.

## Research Task 2: How `pipeline.sh` resolves the feature directory when it doesn't exist yet

**Decision**: `pipeline.sh`'s `resolve_feature_dir()` function (lines 302-345) requires either an explicit `spec-dir` argument pointing to an existing directory, or auto-detection from the current branch (which also requires the directory to exist in `specs/`). When `--from specify` or `--description` is provided without a `spec-dir` argument, and no spec directory exists yet, the function fails. The fix is to add a fallback in `resolve_feature_dir()` that, when no existing directory is found and `--from specify` or `--description` is set, constructs a prospective `FEATURE_DIR` path from the branch name (e.g., `specs/004-fix-prereq-bootstrap`) without requiring the directory to exist.

**Rationale**: The specify step's agent (via `create-new-feature.sh`) will create the feature branch, directory, and spec.md. The pipeline only needs a path to pass to the specify agent -- it does not need the directory to exist yet.

**Alternatives considered**: (1) Requiring users to always pass `spec-dir` when using `--from specify` -- rejected because the whole point of auto-detection is convenience, and the branch name already encodes the directory path. (2) Having the pipeline create the directory before calling the specify agent -- rejected because `create-new-feature.sh` handles all scaffolding and the spec says not to modify its behavior.

## Research Task 3: How `speckit.pipeline.md` handles the `--from specify` case in Step 2

**Decision**: `speckit.pipeline.md` Step 2 (lines 92-98) already has the correct logic: if spec.md doesn't exist and `--from specify` or `--description` is provided, allow the pipeline to continue. The problem is that Step 1's resolution via `check-prerequisites.sh --json` fails before Step 2 is reached. The fix in Step 1 must ensure feature directory resolution succeeds even when no artifacts exist.

**Rationale**: The validation logic in Step 2 is correct and does not need changes. Only the resolution mechanism in Step 1 needs the fix.

**Alternatives considered**: Merging Step 1 and Step 2 into a single resolution step -- rejected because the current separation of concerns (resolve path vs. validate artifacts) is clean and maintainable.

## Research Task 4: Identifying all callers that need changes

**Decision**: Only two callers need modification:

1. **`speckit.pipeline.md`** (and its root-level copy `speckit.pipeline.md`): Step 1 must use `--paths-only` instead of `--json` when the pipeline will start from `specify` or when `--description` is provided.
2. **`pipeline.sh`** (and its root-level copy `pipeline.sh`): `resolve_feature_dir()` must construct a prospective feature directory path from the branch name when no existing directory is found and the pipeline is bootstrapping.

Other callers (`speckit.homer.clarify.md`, `speckit.lisa.analyze.md`, `speckit.ralph.implement.md`, `speckit.tasks.md`, `speckit.checklist.md`) do NOT need changes because they are only invoked after the specify step has created the necessary artifacts.

**Rationale**: The spec's FR-002 says "Pipeline callers MUST use the existing `--paths-only` flag when running early pipeline steps that create artifacts." The only pipeline caller that runs before artifacts exist is the pipeline orchestrator itself (both the bash and command-file versions).

**Alternatives considered**: Changing all callers to use `--paths-only` uniformly -- rejected because downstream callers benefit from `--json` validation to catch genuinely missing prerequisites early.

## Research Task 5: Root-level file synchronization

**Decision**: The root-level copies (`pipeline.sh` and `speckit.pipeline.md`) are byte-identical to their counterparts in `.specify/scripts/bash/` and `.claude/commands/` respectively. Both copies must be updated in lockstep.

**Rationale**: The project maintains root-level copies for convenience (direct invocation without navigating into `.specify/` or `.claude/`). If only one copy is updated, the other becomes stale and the bug persists when the stale copy is invoked.

**Alternatives considered**: Replacing root copies with symlinks -- out of scope for this fix; would be a separate chore.
