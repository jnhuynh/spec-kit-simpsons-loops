# Research: Fix Pipeline and Loop Command Delegation

## R1: Claude Code Slash Command File Format

**Decision**: Slash command files are Markdown files with optional YAML frontmatter (between `---` delimiters). The `description` field in frontmatter provides the help text. The body contains instructions that Claude follows when the command is invoked. `$ARGUMENTS` is replaced with user-provided arguments at invocation time.

**Rationale**: This is the existing format used by all current command files in the project. No format change is needed.

**Alternatives considered**: None — this is an established convention, not a design choice.

## R2: Bash Tool Background Execution for Long-Running Scripts

**Decision**: Use the Bash tool's `run_in_background` parameter for loop scripts (homer-loop.sh, lisa-loop.sh, ralph-loop.sh) that may exceed the 10-minute Bash tool timeout. The slash command instructs Claude to use `run_in_background: true` when invoking the script.

**Rationale**: Loop scripts can run 20+ iterations, each spawning a `claude --agent` call. A single iteration may take several minutes, so the total runtime can exceed 10 minutes. The `run_in_background` mode prevents timeout termination while still allowing Claude to receive the result when the script completes.

**Alternatives considered**:
- Splitting scripts into per-iteration calls from the command file: Rejected because this reintroduces the orchestration logic in Claude instructions, which is the root cause of the current bug.
- Using `timeout` parameter on Bash tool: Rejected because the max timeout is 10 minutes, which may still be insufficient.

## R3: Hybrid Orchestration Architecture for Pipeline Command

**Decision**: The pipeline command uses a hybrid approach: Claude Code sequences the 6 pipeline steps (using Agent tool sub-agents for single-shot steps like specify/plan/tasks, and Bash tool for loop steps like homer/lisa/ralph), while bash scripts handle all loop iteration logic internally.

**Rationale**: Step sequencing (6 ordered steps) is simple and reliable in Claude instructions. Loop iteration (20+ cycles with stuck detection) is complex and must remain in deterministic bash scripts. The pipeline.sh script serves as a reference for step ordering and argument handling, but the slash command reimplements step sequencing to leverage Claude Code's Agent tool for single-shot sub-agents (specify, plan, tasks) that need Claude Code-specific features (reading agent files, following slash command instructions).

**Alternatives considered**:
- Pure bash delegation (just call pipeline.sh): This would work for the pipeline, but pipeline.sh internally calls `claude --agent` which creates its own sessions. The slash command approach allows the orchestrator session to use Agent tool sub-agents, which have better integration with the Claude Code session context. However, this is actually the simpler path and should be preferred per KISS principle. The spec explicitly states hybrid orchestration, so we follow the spec.
- Pure Claude instructions: Rejected — this is the current broken approach.

**Update after deeper analysis**: Re-reading the spec more carefully, the architecture section says for standalone loop commands the pattern is simply: check script exists -> run bash script via Bash tool -> report results. For the pipeline command, the spec says "Claude Code session MUST act as the step-level orchestrator, spawning one Agent tool sub-agent per pipeline phase." However, given that pipeline.sh already handles all step sequencing and invokes the loop scripts internally, the simplest approach that satisfies FR-001 through FR-010 is to delegate pipeline.sh execution via Bash tool as well — pipeline.sh already calls homer-loop.sh, lisa-loop.sh, etc. The spec's hybrid architecture diagram shows Agent sub-agents, but the unified execution path requirement (FR-008) and the delegation requirement (FR-001) are better served by delegating to pipeline.sh directly. The pipeline command will run `bash .specify/scripts/bash/pipeline.sh $ARGUMENTS` and let pipeline.sh handle all orchestration.

## R4: Script Existence Check Pattern

**Decision**: Each command file checks for its corresponding script using `[[ -f .specify/scripts/bash/<script>.sh ]]` before attempting execution. On failure, display a clear error message with remediation instructions.

**Rationale**: Simple, reliable, and produces an immediate actionable error (FR-002, FR-003, SC-004).

**Alternatives considered**:
- Checking for executable permission (`-x`): Rejected per edge case in spec — the command uses `bash <script>` which doesn't require execute permission.
- Checking for all scripts at once: Rejected — each command only needs its own script.

## R5: Argument Pass-Through Pattern

**Decision**: Pass `$ARGUMENTS` directly to the bash script invocation: `bash .specify/scripts/bash/<script>.sh $ARGUMENTS`. The `$ARGUMENTS` variable is already expanded by Claude Code before the command body is interpreted.

**Rationale**: Direct pass-through preserves all arguments without modification (FR-004, SC-003). The bash scripts handle their own argument parsing.

**Alternatives considered**: None — direct pass-through is the simplest correct approach.

## R6: File Sync Strategy (3 Locations)

**Decision**: Edit the repo root copies (upstream source) first, then copy to `.claude/commands/` and `~/.openclaw/.claude/commands/`. Use `cp` for exact copies.

**Rationale**: The repo root files are the upstream source of truth. The other two locations are copies that must stay in sync (FR-006, SC-005).

**Alternatives considered**:
- Symlinks: Rejected — Claude Code may not follow symlinks for command resolution, and the global copy is outside the repo.
- A sync script: Overengineering for 4 files. Manual `cp` during implementation is sufficient.
