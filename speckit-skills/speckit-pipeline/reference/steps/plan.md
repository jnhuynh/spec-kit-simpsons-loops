# Plan (single-shot step)

Skip if `plan.md` already exists. Otherwise, spawn a sub agent:
- **subagent_type**: `general-purpose`
- **agent file**: `.claude/agents/single-shot.md`
- **prompt**: `Read and follow .claude/agents/single-shot.md with SINGLE_SHOT_CONFIG — STEP_COMMAND: /speckit-plan; COMMIT_DESCRIPTION: generate implementation plan; FEATURE_DIR: <FEATURE_DIR>; EXTRA_INSTRUCTIONS: <PARENT_RESOLUTION>.`

**`<PARENT_RESOLUTION>`**: when FEATURE_DIR matches the `--p{N}-` child pattern, substitute the paragraph below (resolving `<PARENT_DIR>` by stripping `--p{N}-{slug}`); otherwise substitute `(none)`.

> This spec is a phase view, not a standalone spec — it references its parent by ID and holds no copy of the user stories, requirements, key entities, or success criteria. Before planning anything, read the parent spec at `<PARENT_DIR>/spec.md` and resolve every ID listed under the child's `## Inherited Scope`; the parent's text is authoritative. Treat the child's `## Phase Boundary` and its `FR-P{N}-###` / `SC-P{N}-###` entries as additive requirements layered on the inherited ones. Plan for the inherited IDs plus the phase-local ones and nothing else — anything the child lists under "Deferred elsewhere" belongs to another phase. Cite IDs in plan.md; do not copy parent prose into it.

**Stop check**: apply the pipeline skill's post-step stop check (its Step 5) with the step name `plan`.
