# Plan (single-shot step)

Skip if `plan.md` already exists. Otherwise, spawn a sub agent:
- **subagent_type**: `general-purpose`
- **agent file**: `.claude/agents/single-shot.md`
- **prompt**: `Read and follow .claude/agents/single-shot.md with SINGLE_SHOT_CONFIG — STEP_COMMAND: /speckit-plan; COMMIT_DESCRIPTION: generate implementation plan; FEATURE_DIR: <FEATURE_DIR>; EXTRA_INSTRUCTIONS: <PARENT_RESOLUTION>.`

**`<PARENT_RESOLUTION>`**: when FEATURE_DIR matches the `--p{N}-` child pattern, substitute the paragraph below (resolving `<PARENT_DIR>` by stripping `--p{N}-{slug}`); otherwise substitute `(none)`.

> This spec is a phase view, not a standalone spec — it references its parent by ID and holds no copy of the user stories, requirements, key entities, or success criteria. Before planning anything, read the parent spec at `<PARENT_DIR>/spec.md` and resolve every ID listed under the child's `## Inherited Scope`; the parent's text is authoritative. Treat the child's `## Phase Boundary` and its `FR-P{N}-###` / `SC-P{N}-###` entries as additive requirements layered on the inherited ones. Plan for the inherited IDs plus the phase-local ones and nothing else — anything the child lists under "Deferred elsewhere" belongs to another phase. Cite IDs in plan.md; do not copy parent prose into it.

**Post-step stop check**: After the plan step completes (whether it was executed or skipped because `plan.md` already exists), check if `STOP_AFTER_STEP` is set and equals `plan`. If it does, output: `Pipeline stopped after plan per --stop-after parameter. Skipping: tasks, lisa, split, ralph, marge.` and **skip all remaining steps** — do NOT spawn any further sub-agents. Proceed directly to Step 6 (Report Results). If `STOP_AFTER_STEP` is empty/unset, this check is a no-op — continue to the next step.

