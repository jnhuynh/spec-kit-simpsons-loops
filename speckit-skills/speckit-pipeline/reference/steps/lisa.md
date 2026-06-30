# Lisa (loop step)
Execute the Lisa loop using the shared loop orchestrator. Read and follow `.claude/agents/loop-orchestrator.md` with this LOOP_CONFIG:

- **AGENT_NAME**: lisa
- **AGENT_DISPLAY_NAME**: Lisa
- **AGENT_FILE**: .claude/agents/lisa.md
- **SLASH_COMMAND_REF**: /speckit-analyze
- **PROMISE_TAG**: ALL_FINDINGS_RESOLVED
- **PREREQ_FLAGS**: --json --require-tasks --include-tasks
- **REQUIRED_ARTIFACTS**: spec.md, plan.md, tasks.md
- **MAX_ITERATIONS**: 30 (or lisa max from Step 4)
- **EXTRA_PROMPT_SUFFIX**: (none)
- **REPORT_MODE**: standard

Skip the orchestrator's Pre-Flight and Agent File checks (already done in pipeline pre-flight). Start from Step 1 (Parse Arguments) using the already-resolved `FEATURE_DIR`.

**Failure handling**: If the loop aborts (stuck, stalled, oscillating, or sub agent failure), abort the pipeline immediately. Suggest manual review and resuming with `--from lisa`.

**Post-step stop check**: After the lisa step completes, check if `STOP_AFTER_STEP` is set and equals `lisa`. If it does, output: `Pipeline stopped after lisa per --stop-after parameter. Skipping: split, ralph, marge.` and **skip all remaining steps** — do NOT spawn any further sub-agents. Proceed directly to Step 6 (Report Results). If `STOP_AFTER_STEP` is empty/unset, this check is a no-op — continue to the next step.

