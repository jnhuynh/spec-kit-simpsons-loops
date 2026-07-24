# Homer (loop step)

Run the Homer loop exactly as its standalone skill defines it: read and follow `.claude/skills/speckit-homer-clarify/SKILL.md`, passing `<FEATURE_DIR>` through as the skill's spec-dir argument. The skill's own LOOP_CONFIG (including MAX_ITERATIONS) applies.

**Pipeline delta**: Skip the loop orchestrator's Pre-Flight and Agent File checks (already done in pipeline pre-flight). Start from the orchestrator's Step 1 (Parse Arguments) using the already-resolved `FEATURE_DIR`.

**Post-step stop check**: After the homer step completes, check if `STOP_AFTER_STEP` is set and equals `homer`. If it does, output: `Pipeline stopped after homer per --stop-after parameter. Skipping: premortem, phase, plan, tasks, lisa, split, ralph, marge.` and **skip all remaining steps** — do NOT spawn any further sub-agents. Proceed directly to Step 6 (Report Results). If `STOP_AFTER_STEP` is empty/unset, this check is a no-op — continue to the next step.
