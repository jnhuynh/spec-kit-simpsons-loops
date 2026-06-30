# Reconcile (conditional single-shot step — child specs only)
Detect if the current spec is a child spec by checking FEATURE_DIR for the `--p{N}-` pattern (e.g., `specs/c31c-feat-billing--p2-integration`).

- **If not a child spec** (parent or standalone): skip, continue to specify.
- **If child spec with N = 1** (first phase): skip, no earlier siblings to reconcile with.
- **If child spec with N > 1**: resolve the parent directory by stripping `--p{N}-{slug}` from the child directory name. Spawn a sub agent:
  - **subagent_type**: `general-purpose`
  - **agent file**: `.claude/agents/reconcile.md`
  - **prompt**: `Feature directory: <FEATURE_DIR>. Run non-interactively.`

**Failure handling**: If the sub agent fails, abort the pipeline. Suggest resuming with `--from reconcile`.

**Post-step stop check**: After the reconcile step completes (whether executed or skipped), check STOP_AFTER_STEP. If equals `reconcile`, output: `Pipeline stopped after reconcile per --stop-after parameter. Skipping: specify, homer, phase, plan, tasks, lisa, split, ralph, marge.` and skip all remaining steps.

