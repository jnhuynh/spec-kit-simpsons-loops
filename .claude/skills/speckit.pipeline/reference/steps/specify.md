# Specify (single-shot step)
Skip if `spec.md` already exists. Otherwise, spawn a sub agent:
- **subagent_type**: `general-purpose`
- **agent file**: `.claude/agents/specify.md`
- **prompt**: `Feature directory: <FEATURE_DIR>. Feature description: <DESCRIPTION>. Run non-interactively: auto-resolve all clarifications with best guesses, do not present questions to the user.`

**Failure handling**: If the sub agent fails (crash, timeout, or error), abort the pipeline immediately. Log failure context: agent type (specify) and error message. Do NOT retry — sub agent failures in loop commands are treated as deterministic. Print: "Specify step failed. Fix the issue and re-invoke with --from specify". Suggest manual review and resuming with `--from specify`.

**Post-specify re-resolution**: After the specify step completes successfully, if `FEATURE_DIR` is empty or the directory does not exist, re-resolve by running `bash .specify/scripts/bash/check-prerequisites.sh --json --paths-only` from repo root via Bash tool and parsing the JSON output for `FEATURE_DIR`. This is required because the specify step (via `create-new-feature.sh`) creates the feature branch and directory. If re-resolution fails, abort the pipeline with: "Specify step completed but feature directory could not be resolved." The re-resolved `FEATURE_DIR` MUST be used for all subsequent steps.

**Post-step stop check**: After the specify step completes (whether it was executed or skipped because `spec.md` already exists), check if `STOP_AFTER_STEP` is set and equals `specify`. If it does, output: `Pipeline stopped after specify per --stop-after parameter. Skipping: homer, phase, plan, tasks, lisa, split, ralph, marge.` and **skip all remaining steps** — do NOT spawn any further sub-agents. Proceed directly to Step 6 (Report Results). If `STOP_AFTER_STEP` is empty/unset, this check is a no-op — continue to the next step.

