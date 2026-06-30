# Phase (single-shot step)
Skip if `spec.md` already contains a populated `## Phases` section (check for at least one `### Phase` subsection within it). Otherwise, spawn a sub agent:
- **subagent_type**: `general-purpose`
- **agent file**: `.claude/agents/phase.md`
- **prompt**: `Feature directory: <FEATURE_DIR>. Run non-interactively.`

**Failure handling**: If the sub agent fails (crash, timeout, or error), abort the pipeline immediately. Log failure context: agent type (phase) and error message. Do NOT retry — sub agent failures in loop commands are treated as deterministic. Print: "Phase step failed. Fix the issue and re-invoke with --from phase". Suggest manual review and resuming with `--from phase`.

**Post-step stop check**: After the phase step completes (whether it was executed or skipped because `## Phases` is already populated), check if `STOP_AFTER_STEP` is set and equals `phase`. If it does, output: `Pipeline stopped after phase per --stop-after parameter. Skipping: plan, tasks, lisa, split, ralph, marge.` and **skip all remaining steps** — do NOT spawn any further sub-agents. Proceed directly to Step 6 (Report Results). If `STOP_AFTER_STEP` is empty/unset, this check is a no-op — continue to the next step.

