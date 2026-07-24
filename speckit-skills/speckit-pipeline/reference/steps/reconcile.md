# Reconcile (conditional single-shot step — child specs only)
Detect if the current spec is a child spec by checking FEATURE_DIR for the `--p{N}-` pattern (e.g., `specs/c31c-feat-billing--p2-integration`).

- **If not a child spec** (parent or standalone): skip, continue to specify.
- **If child spec with N = 1** (first phase): skip, no earlier siblings to reconcile with.
- **If child spec with N > 1**: resolve the parent directory `<PARENT_DIR>` by stripping `--p{N}-{slug}` from the child directory name (e.g., `specs/c31c-feat-billing--p2-integration` -> `specs/c31c-feat-billing`). Spawn a sub agent:
  - **subagent_type**: `general-purpose`
  - **agent file**: `.claude/agents/single-shot.md`
  - **prompt**: `Read and follow .claude/agents/single-shot.md with SINGLE_SHOT_CONFIG — STEP_COMMAND: /speckit-split <PARENT_DIR>; COMMIT_DESCRIPTION: reconcile child spec with earlier phases; FEATURE_DIR: <FEATURE_DIR>; EXTRA_INSTRUCTIONS: Target the parent directory <PARENT_DIR> (already resolved), not the child feature directory — this reconciles all child specs with what earlier phases actually built.`

**Post-step stop check**: After the reconcile step completes (whether executed or skipped), check STOP_AFTER_STEP. If equals `reconcile`, output: `Pipeline stopped after reconcile per --stop-after parameter. Skipping: specify, homer, premortem, phase, plan, tasks, lisa, split, ralph, marge.` and skip all remaining steps.

