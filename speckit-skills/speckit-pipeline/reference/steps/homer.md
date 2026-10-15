# Homer (loop step)

**Child-spec skip**: If FEATURE_DIR matches the `--p{N}-` child pattern, **skip this step** and log `Homer skipped — child spec (clarifications belong in the parent).` A child spec owns no user stories or requirements; it references the parent by ID under `## Inherited Scope`. The parent already cleared Homer before phase and split ran. Ambiguity discovered while working a phase is resolved once, at the source: run `/speckit-homer-clarify <PARENT_DIR>`, then `/speckit-split <PARENT_DIR>` if the phase's scope changed.

Run the Homer loop exactly as its standalone skill defines it: read and follow `.claude/skills/speckit-homer-clarify/SKILL.md`, passing `<FEATURE_DIR>` through as the skill's spec-dir argument. The skill's own LOOP_CONFIG (including MAX_ITERATIONS) applies.

**Pipeline delta**: Skip the loop orchestrator's Pre-Flight and Agent File checks (already done in pipeline pre-flight). Start from the orchestrator's Step 1 (Parse Arguments) using the already-resolved `FEATURE_DIR`.

**Stop check**: apply the pipeline skill's post-step stop check (its Step 5) with the step name `homer`.
