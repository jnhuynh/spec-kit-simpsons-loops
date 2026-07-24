# Premortem (human gate)

Failure-mode discovery is a **human-required step** — the pipeline never runs it autonomously and never spawns a sub agent for it. This step only checks that the human work is done: the risk register `<FEATURE_DIR>/failure-modes.md` exists and every failure mode is dispositioned.

**Skip check**: If `SKIP_PREMORTEM` is true, log `Premortem gate skipped per --skip-premortem.` and continue to the next step.

**Gate check** (Read tool): Read `<FEATURE_DIR>/failure-modes.md`. The gate passes when the file exists AND its table contains zero rows with Status `open`.

**Pass**: Log one line — `Premortem gate passed: N failure modes dispositioned (X mitigated, Y accepted, Z deferred).` If any rows have Status `reappeared`, add a warning line listing them (a previously mitigated failure mode's mitigation is no longer in the spec — a human must re-decide). Continue to the next step.

**Fail**: Output the halt message below, record the premortem step's status as `awaiting-human`, and **skip all remaining steps** — do NOT spawn any further sub-agents. Proceed directly to Step 6 (Report Results) with completion status `awaiting-human`. This is NOT a pipeline failure.

```
PREMORTEM REQUIRED: failure-mode discovery is a human step and has not been completed.

<either: No failure-modes.md found in <FEATURE_DIR>. | N failure mode(s) still open in <FEATURE_DIR>/failure-modes.md: FM-00X, FM-00Y, ...>

Run /speckit-premortem to work the failure-mode session(s) interactively, then resume:
  /speckit-pipeline --from premortem

To bypass intentionally (not recommended): re-run with --skip-premortem.
```

**Post-step stop check**: After the premortem gate passes (or is skipped via `--skip-premortem`), check if `STOP_AFTER_STEP` is set and equals `premortem`. If it does, output: `Pipeline stopped after premortem per --stop-after parameter. Skipping: phase, plan, tasks, lisa, split, ralph, marge.` and **skip all remaining steps** — do NOT spawn any further sub-agents. Proceed directly to Step 6 (Report Results). If `STOP_AFTER_STEP` is empty/unset, this check is a no-op — continue to the next step.
