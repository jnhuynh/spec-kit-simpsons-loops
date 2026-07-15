---
name: speckit-lisa-analyze
description: Orchestrate iterative cross-artifact analysis and remediation (Lisa loop) on spec.md, plan.md, and tasks.md until all findings are resolved.
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Pre-Flight: Ledger Protocol Check

Lisa's agent follows the shared ledger protocol for reappearance detection:

```bash
if test -f ".claude/agents/findings-ledger.md"; then echo "findings-ledger: EXISTS"; else echo "findings-ledger: MISSING"; fi
```

If **MISSING**, display this error and **STOP**:

```
ERROR: Required ledger protocol not found.

Missing: .claude/agents/findings-ledger.md

Lisa persists <FEATURE_DIR>/analysis-report.md per this shared protocol.
Run setup.sh to (re)install it.
```

## Loop Configuration

Set the following LOOP_CONFIG values for this execution:

- **AGENT_NAME**: lisa
- **AGENT_DISPLAY_NAME**: Lisa
- **AGENT_FILE**: .claude/agents/lisa.md
- **SLASH_COMMAND_REF**: /speckit-analyze
- **PROMISE_TAG**: ALL_FINDINGS_RESOLVED
- **PREREQ_FLAGS**: --json --require-tasks --include-tasks
- **REQUIRED_ARTIFACTS**: spec.md, plan.md, tasks.md
- **MAX_ITERATIONS**: 10
- **EXTRA_PROMPT_SUFFIX**: (none)
- **REPORT_MODE**: needs_human

## Execute

Read and follow the instructions in `.claude/agents/loop-orchestrator.md`, using the LOOP_CONFIG values above. Pass `$ARGUMENTS` through for argument parsing.

## Post-Loop: Analysis Report Verification

After the loop completes, confirm `<FEATURE_DIR>/analysis-report.md` exists and was written by the final sub agent — it is the ledger the next Lisa run loads for reappearance detection (contract: `.claude/agents/findings-ledger.md`). If the file is absent after the loop completes, surface this as a failure and instruct the user to re-run `/speckit-lisa-analyze` — without the ledger, reappearance detection silently never fires.

## Examples

- `/speckit-lisa-analyze` — Auto-detect spec dir from current branch, use default max iterations (10)
- `/speckit-lisa-analyze specs/003-fix-pipeline-delegation` — Run for specific spec dir
- `/speckit-lisa-analyze 5` — Auto-detect spec dir, limit to 5 iterations
- `/speckit-lisa-analyze specs/003-fix-pipeline-delegation 5` — Specific spec dir with 5 max iterations
