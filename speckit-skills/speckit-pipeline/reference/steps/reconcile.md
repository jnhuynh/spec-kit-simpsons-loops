# Reconcile (conditional single-shot step — child specs only)
Detect if the current spec is a child spec by checking FEATURE_DIR for the `--p{N}-` pattern (e.g., `specs/c31c-feat-billing--p2-integration`).

- **If not a child spec** (parent or standalone): skip, continue to specify.
- **If child spec with N = 1** (first phase): skip, no earlier siblings have shipped yet.
- **If child spec with N > 1**: resolve the parent directory `<PARENT_DIR>` by stripping `--p{N}-{slug}` from the child directory name (e.g., `specs/c31c-feat-billing--p2-integration` -> `specs/c31c-feat-billing`). Spawn a sub agent:
  - **subagent_type**: `general-purpose`
  - **agent file**: `.claude/agents/single-shot.md`
  - **prompt**: `Read and follow .claude/agents/single-shot.md with SINGLE_SHOT_CONFIG — STEP_COMMAND: /speckit-reconcile <PARENT_DIR>; COMMIT_DESCRIPTION: reconcile parent spec with what completed phases shipped; FEATURE_DIR: <FEATURE_DIR>; EXTRA_INSTRUCTIONS: The parent spec is the single source of truth — child specs reference it by ID and hold no copy. Correct drift in <PARENT_DIR>/spec.md only; never edit a sibling child's authored content (## Phase Boundary, FR-P{N}-###, SC-P{N}-###). Report NEEDS_HUMAN drift without changing it.`

**Non-blocking**: `NEEDS_HUMAN` drift findings are reported, not fatal. Surface them in the pipeline report and continue — the developer decides whether to halt.

**Skill absent**: if `.claude/skills/speckit-reconcile/SKILL.md` does not exist, log `speckit-reconcile not installed — skipping reconcile` and continue. Run `setup.sh` to install it.

**Post-step stop check**: After the reconcile step completes (whether executed or skipped), check STOP_AFTER_STEP. If equals `reconcile`, output: `Pipeline stopped after reconcile per --stop-after parameter. Skipping: plan, tasks, lisa, ralph, marge.` and skip all remaining steps.
