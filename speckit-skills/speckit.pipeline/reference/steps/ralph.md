# Ralph (loop step)

**Quality gate validation**: Before starting the ralph loop, validate that `.specify/quality-gates.sh` (full gate, required) exists and contains executable content, and check for `.specify/quality-gates-fast.sh` (fast gate, optional). Run the following via Bash tool:

```bash
test -f .specify/quality-gates.sh && grep -v '^\s*#' .specify/quality-gates.sh | grep -v '^\s*$' | head -1
test -f .specify/quality-gates-fast.sh && echo "FAST_GATE_EXISTS" || echo "FAST_GATE_MISSING"
```

If the full gate file does not exist or contains only comments/whitespace (the first command produces no output), **STOP** the pipeline with this error:

```
ERROR: Quality gates file is missing or empty.

Expected: .specify/quality-gates.sh with executable commands.

Create the file with your project's quality gate commands, e.g.:
  echo 'npm test && npm run lint' > .specify/quality-gates.sh

The ralph and marge phases require quality gates to validate implementation work.

Optionally, also create .specify/quality-gates-fast.sh with scoped commands
that check only changed files for faster per-iteration feedback.
```

Determine the per-iteration gate command: if `.specify/quality-gates-fast.sh` exists and is non-empty, use `bash .specify/quality-gates-fast.sh`; otherwise fall back to `bash .specify/quality-gates.sh`.

**Calculate ralph max iterations**: Count incomplete tasks in tasks.md and add 10:

```bash
incomplete_count=$(grep -c '^\s*- \[ \]' "<FEATURE_DIR>/tasks.md" 2>/dev/null || echo "0")
echo $((incomplete_count + 10))
```

Use the resulting number as `ralph_max_iterations`.

Execute the Ralph loop using the shared loop orchestrator. Read and follow `.claude/agents/loop-orchestrator.md` with this LOOP_CONFIG:

- **AGENT_NAME**: ralph
- **AGENT_DISPLAY_NAME**: Ralph
- **AGENT_FILE**: .claude/agents/ralph.md
- **SLASH_COMMAND_REF**: /speckit.implement
- **PROMISE_TAG**: ALL_TASKS_COMPLETE
- **PREREQ_FLAGS**: --json --require-tasks --include-tasks
- **REQUIRED_ARTIFACTS**: spec.md, plan.md, tasks.md
- **MAX_ITERATIONS**: (use `ralph_max_iterations` calculated above)
- **EXTRA_PROMPT_SUFFIX**: Quality gates: (use the per-iteration gate command determined above)
- **REPORT_MODE**: tasks

Skip the orchestrator's Pre-Flight and Agent File checks (already done in pipeline pre-flight). Start from Step 1 (Parse Arguments) using the already-resolved `FEATURE_DIR`.

**Post-loop verification**: After the orchestrator reports completion via promise tag, also verify tasks.md directly — if any `- [ ]` tasks remain, report the discrepancy.

**End-of-loop full quality gate**: When the ralph loop exits via the success path (all tasks complete), run the full gate once via Bash tool:

```bash
bash .specify/quality-gates.sh
```

If it exits non-zero, abort the pipeline with completion status **failure** and reason "ralph end-of-loop full quality gates failed". Surface the failing output in the report and suggest resuming with `--from ralph`. Skip the simplify, security-review, and marge steps. Do NOT run this gate on max-iterations, stuck, or failure exits — those already terminate the pipeline.

**Failure handling**: If the loop aborts (stuck, stalled, oscillating, or sub agent failure), abort the pipeline immediately. Suggest manual review and resuming with `--from ralph`.

**Post-step stop check**: After the ralph step completes, check if `STOP_AFTER_STEP` is set and equals `ralph`. If it does, output: `Pipeline stopped after ralph per --stop-after parameter. Skipping: marge.` and **skip all remaining steps** — do NOT spawn any further sub-agents. Proceed directly to Step 6 (Report Results). If `STOP_AFTER_STEP` is empty/unset, this check is a no-op — continue to the next step.

