# Data Model: Fix Pipeline and Loop Command Delegation

## Entities

This feature does not introduce new data entities, databases, or persistent state. It modifies existing Markdown command files. The "data model" here describes the structure of the files being modified and the runtime state tracked during execution.

### Slash Command File

A Claude Code command definition file in Markdown format.

| Field | Type | Description |
|-------|------|-------------|
| frontmatter.description | string | Help text shown in Claude Code command list |
| body | markdown | Instructions Claude follows when the command is invoked |
| $ARGUMENTS | template variable | Replaced with user-provided arguments at invocation time |

**Locations**: Each command file exists in 3 locations:
1. Repo root: `speckit.<name>.md` (upstream source)
2. Local project: `.claude/commands/speckit.<name>.md`
3. Global installed: `~/.openclaw/.claude/commands/speckit.<name>.md`

**Validation rules**:
- No hard line-count limits (spec explicitly removed previous 40/60 limits)
- All 3 copies must be byte-identical after deployment (FR-006, SC-005)
- Must contain Agent tool orchestration pattern (FR-001)
- Must check for utility script existence before execution (FR-002)
- Must display actionable error when utility scripts missing (FR-003)

### Command-to-Utility Mapping

| Command File | Bash Utility | Utility Path |
|-------------|-------------|-------------|
| `speckit.pipeline.md` | `check-prerequisites.sh` | `.specify/scripts/bash/check-prerequisites.sh` |
| `speckit.homer.clarify.md` | `check-prerequisites.sh` | `.specify/scripts/bash/check-prerequisites.sh` |
| `speckit.lisa.analyze.md` | `check-prerequisites.sh` | `.specify/scripts/bash/check-prerequisites.sh` |
| `speckit.ralph.implement.md` | `check-prerequisites.sh` | `.specify/scripts/bash/check-prerequisites.sh` |

### Iteration State (Runtime)

Tracked by the orchestrator between Agent tool sub-agent calls during loop execution.

| Field | Type | Description |
|-------|------|-------------|
| iteration_number | integer | Current iteration (1-based) |
| max_iterations | integer | Maximum allowed iterations |
| consecutive_stuck_count | integer | Number of consecutive stuck iterations (reset on progress) |
| last_git_diff_empty | boolean | Whether the last sub-agent produced no file changes |
| last_promise_found | boolean | Whether the last sub-agent emitted the completion promise tag |

**Stuck detection rule** (FR-007): An iteration is stuck when `last_git_diff_empty == true` AND `last_promise_found == false`. Two consecutive stuck iterations (`consecutive_stuck_count >= 2`) abort the loop.

### Pipeline State (Runtime)

Tracked by the pipeline orchestrator during multi-step execution.

| Field | Type | Description |
|-------|------|-------------|
| current_step | enum | One of: specify, homer, plan, tasks, lisa, ralph |
| feature_dir | string | Resolved feature directory path |
| from_step | enum or null | Starting step (from --from flag or auto-detected) |
| steps_executed | list | Steps that have been executed |
| iterations_per_loop_step | map | Map of loop step name to iteration count |

**Step transitions**: specify -> homer -> plan -> tasks -> lisa -> ralph (strictly sequential, FR-009).

## State Transitions

### Loop Command Lifecycle

```
start
  -> check_utility_scripts_exist
    -> [missing] -> error_with_remediation -> exit
    -> [found] -> resolve_feature_dir
      -> [failed] -> error -> exit
      -> [success] -> verify_artifacts
        -> [missing] -> error_with_guidance -> exit
        -> [found] -> run_loop
          -> spawn_sub_agent
            -> [promise_tag_found] -> report_success -> exit
            -> [git_diff + no_promise] -> reset_stuck_count -> next_iteration
            -> [no_git_diff + no_promise] -> increment_stuck_count
              -> [stuck_count >= 2] -> report_stuck -> exit
              -> [stuck_count < 2] -> next_iteration
            -> [sub_agent_failed] -> report_failure -> exit
          -> [max_iterations_reached] -> report_max_iterations -> exit
```

### Pipeline Command Lifecycle

```
start
  -> check_utility_scripts_exist
    -> [missing] -> error_with_remediation -> exit
    -> [found] -> resolve_feature_dir
      -> detect_or_parse_starting_step
        -> for each step (from starting step to ralph):
          -> [single-shot step] -> spawn_sub_agent -> check_result
            -> [success] -> next_step
            -> [failure] -> report_failure -> exit
          -> [loop step] -> run_loop (same as loop command lifecycle)
            -> [completed] -> next_step
            -> [stuck/failed/max] -> report -> exit
        -> all steps complete -> report_success -> exit
```
