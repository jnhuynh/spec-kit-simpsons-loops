# Phase (single-shot step)

**Child-spec skip**: If FEATURE_DIR matches the `--p{N}-` child pattern, **skip this step** and log `Phase skipped — child spec (already a phase of <PARENT_DIR>).` A child spec is itself one phase of an already-phased parent; re-phasing it would nest deployment boundaries inside a boundary. Its phase number, slug, and release strategy come from the parent's `## Phases` section.

Skip if `spec.md` already contains a populated `## Phases` section (check for at least one `### Phase` subsection within it). Otherwise, spawn a sub agent:
- **subagent_type**: `general-purpose`
- **agent file**: `.claude/agents/single-shot.md`
- **prompt**: `Read and follow .claude/agents/single-shot.md with SINGLE_SHOT_CONFIG — STEP_COMMAND: /speckit-phase; COMMIT_DESCRIPTION: detect deployment boundaries and generate phase annotations; FEATURE_DIR: <FEATURE_DIR>; EXTRA_INSTRUCTIONS: (none).`

**Post-step stop check**: After the phase step completes (whether it was executed or skipped because `## Phases` is already populated), check if `STOP_AFTER_STEP` is set and equals `phase`. If it does, output: `Pipeline stopped after phase per --stop-after parameter. Skipping: plan, tasks, lisa, split, ralph, marge.` and **skip all remaining steps** — do NOT spawn any further sub-agents. Proceed directly to Step 6 (Report Results). If `STOP_AFTER_STEP` is empty/unset, this check is a no-op — continue to the next step.

