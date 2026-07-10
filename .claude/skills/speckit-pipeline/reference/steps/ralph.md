# Ralph (loop step)

Run the Ralph loop exactly as its standalone skill defines it: read and follow `.claude/skills/speckit-ralph-implement/SKILL.md`, passing `<FEATURE_DIR>` through as the skill's spec-dir argument. The skill owns quality-gate validation, task counting, dynamic MAX_ITERATIONS (incomplete tasks + 10), the end-of-loop full quality gate, and tasks verification.

**Pipeline deltas**:

- Skip the loop orchestrator's Pre-Flight and Agent File checks (already done in pipeline pre-flight). Start from the orchestrator's Step 1 (Parse Arguments) using the already-resolved `FEATURE_DIR`.
- If the skill STOPs on missing/empty quality gates, abort the pipeline with that error.
- If the skill reports **failure** (loop abort, or its end-of-loop full quality gate failed), abort the pipeline with completion status **failure** and the skill's reason, suggest resuming with `--from ralph`, and skip the simplify, security-review, and marge steps.

**Post-step stop check**: After the ralph step completes, check if `STOP_AFTER_STEP` is set and equals `ralph`. If it does, output: `Pipeline stopped after ralph per --stop-after parameter. Skipping: marge.` and **skip all remaining steps** — do NOT spawn any further sub-agents. Proceed directly to Step 6 (Report Results). If `STOP_AFTER_STEP` is empty/unset, this check is a no-op — continue to the next step.
