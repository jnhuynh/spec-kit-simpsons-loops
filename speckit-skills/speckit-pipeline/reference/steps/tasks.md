# Tasks (single-shot step)
Skip if `tasks.md` already exists. Otherwise, spawn a sub agent:
- **subagent_type**: `general-purpose`
- **agent file**: `.claude/agents/single-shot.md`
- **prompt**: `Read and follow .claude/agents/single-shot.md with SINGLE_SHOT_CONFIG — STEP_COMMAND: /speckit-tasks; COMMIT_DESCRIPTION: generate dependency-ordered task list; FEATURE_DIR: <FEATURE_DIR>; EXTRA_INSTRUCTIONS: <PARENT_RESOLUTION>.`

**`<PARENT_RESOLUTION>`**: when FEATURE_DIR matches the `--p{N}-` child pattern, substitute the paragraph below (resolving `<PARENT_DIR>` by stripping `--p{N}-{slug}`); otherwise substitute `(none)`.

> This spec is a phase view, not a standalone spec — it references its parent by ID and holds no copy of the user stories, requirements, key entities, or success criteria. `/speckit-tasks` organizes work by user story, so before generating tasks read the parent spec at `<PARENT_DIR>/spec.md` and resolve every ID listed under the child's `## Inherited Scope` — the story titles and priorities you need live there, and the parent's text is authoritative. Generate tasks for the inherited IDs plus the child's phase-local `FR-P{N}-###` / `SC-P{N}-###` entries, and for nothing the child lists under "Deferred elsewhere". Task story tags reference the parent's story numbering (`[US3]`, not a renumbered `[US1]`).

**Stop check**: apply the pipeline skill's post-step stop check (its Step 5) with the step name `tasks`.
