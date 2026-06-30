---
name: speckit.homer.clarify
description: Orchestrate iterative spec clarification and remediation (Homer loop) on spec.md until all findings are resolved.
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Loop Configuration

Set the following LOOP_CONFIG values for this execution:

- **AGENT_NAME**: homer
- **AGENT_DISPLAY_NAME**: Homer
- **AGENT_FILE**: .claude/agents/homer.md
- **SLASH_COMMAND_REF**: /speckit.clarify
- **PROMISE_TAG**: ALL_FINDINGS_RESOLVED
- **PREREQ_FLAGS**: --json --paths-only
- **REQUIRED_ARTIFACTS**: spec.md
- **MAX_ITERATIONS**: 30
- **EXTRA_PROMPT_SUFFIX**: (none)
- **REPORT_MODE**: standard

## Execute

Read and follow the instructions in `.claude/agents/loop-orchestrator.md`, using the LOOP_CONFIG values above. Pass `$ARGUMENTS` through for argument parsing.

## Examples

- `/speckit.homer.clarify` — Auto-detect spec dir from current branch, use default max iterations (30)
- `/speckit.homer.clarify specs/003-fix-pipeline-delegation` — Run for specific spec dir
- `/speckit.homer.clarify 5` — Auto-detect spec dir, limit to 5 iterations
- `/speckit.homer.clarify specs/003-fix-pipeline-delegation 5` — Specific spec dir with 5 max iterations
