# Tasks (single-shot step)
Skip if `tasks.md` already exists. Otherwise, spawn a sub agent:
- **subagent_type**: `general-purpose`
- **agent file**: `.claude/agents/single-shot.md`
- **prompt**: `Read and follow .claude/agents/single-shot.md with SINGLE_SHOT_CONFIG — STEP_COMMAND: /speckit-tasks; COMMIT_DESCRIPTION: generate dependency-ordered task list; FEATURE_DIR: <FEATURE_DIR>; EXTRA_INSTRUCTIONS: (none).`

**Post-step stop check**: After the tasks step completes (whether it was executed or skipped because `tasks.md` already exists), check if `STOP_AFTER_STEP` is set and equals `tasks`. If it does, output: `Pipeline stopped after tasks per --stop-after parameter. Skipping: lisa, split, ralph, marge.` and **skip all remaining steps** — do NOT spawn any further sub-agents. Proceed directly to Step 6 (Report Results). If `STOP_AFTER_STEP` is empty/unset, this check is a no-op — continue to the next step.

