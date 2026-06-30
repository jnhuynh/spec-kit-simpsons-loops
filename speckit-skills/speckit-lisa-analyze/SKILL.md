---
name: speckit-lisa-analyze
description: Orchestrate iterative cross-artifact analysis and remediation (Lisa loop) on spec.md, plan.md, and tasks.md until all findings are resolved.
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Loop Configuration

Set the following LOOP_CONFIG values for this execution:

- **AGENT_NAME**: lisa
- **AGENT_DISPLAY_NAME**: Lisa
- **AGENT_FILE**: .claude/agents/lisa.md
- **SLASH_COMMAND_REF**: /speckit-analyze
- **PROMISE_TAG**: ALL_FINDINGS_RESOLVED
- **PREREQ_FLAGS**: --json --require-tasks --include-tasks
- **REQUIRED_ARTIFACTS**: spec.md, plan.md, tasks.md
- **MAX_ITERATIONS**: 30
- **EXTRA_PROMPT_SUFFIX**: (none)
- **REPORT_MODE**: standard

## Execute

Read and follow the instructions in `.claude/agents/loop-orchestrator.md`, using the LOOP_CONFIG values above. Pass `$ARGUMENTS` through for argument parsing.

## Examples

- `/speckit-lisa-analyze` — Auto-detect spec dir from current branch, use default max iterations (30)
- `/speckit-lisa-analyze specs/003-fix-pipeline-delegation` — Run for specific spec dir
- `/speckit-lisa-analyze 5` — Auto-detect spec dir, limit to 5 iterations
- `/speckit-lisa-analyze specs/003-fix-pipeline-delegation 5` — Specific spec dir with 5 max iterations
