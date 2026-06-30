# Plan (single-shot step)

Skip if `plan.md` already exists. Otherwise, spawn a sub agent:
- **subagent_type**: `general-purpose`
- **agent file**: `.claude/agents/plan.md`

**Failure handling**: If the sub agent fails (crash, timeout, or error), abort the pipeline immediately. Log failure context: agent type (plan) and error message. Do NOT retry — sub agent failures in loop commands are treated as deterministic. Suggest manual review and resuming with `--from plan`.

**Post-step stop check**: After the plan step completes (whether it was executed or skipped because `plan.md` already exists), check if `STOP_AFTER_STEP` is set and equals `plan`. If it does, output: `Pipeline stopped after plan per --stop-after parameter. Skipping: tasks, lisa, split, ralph, marge.` and **skip all remaining steps** — do NOT spawn any further sub-agents. Proceed directly to Step 6 (Report Results). If `STOP_AFTER_STEP` is empty/unset, this check is a no-op — continue to the next step.

