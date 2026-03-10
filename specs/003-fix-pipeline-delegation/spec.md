# Feature Specification: Fix Pipeline and Loop Command Delegation

**Feature Branch**: `003-fix-pipeline-delegation`
**Created**: 2026-03-09
**Status**: Draft
**Input**: User description: "Fix: /speckit.pipeline stops after specify phase — rewrite to delegate to pipeline.sh"

## Clarifications

### Session 2026-03-09

- Q: Should the delegation fix apply to all 4 orchestrator commands (pipeline, homer, lisa, ralph), not just pipeline? → A: Yes, rewrite all 4 commands to delegate to their respective bash scripts.
- Q: Does this unify the execution logic so `/speckit.pipeline` and individual loop commands share the same code path? → A: Yes. `pipeline.sh` already calls `homer-loop.sh`, `lisa-loop.sh`, and `ralph-loop.sh` internally. After this fix, both `/speckit.pipeline` (via pipeline.sh) and `/speckit.homer.clarify` (directly) invoke the same `homer-loop.sh` — one unified execution path, no divergent implementations.
- Q: What orchestration architecture should be used? → A: Hybrid — Claude Code session orchestrates at the step level via Agent tool sub-agents, but each sub-agent runs its corresponding bash script via Bash tool. Bash scripts handle loop iteration, stuck detection, and quality gates deterministically. Claude Code handles step sequencing and sub-agent lifecycle.
- Q: What are the precise line-count limits for rewritten command files? → A: Standalone loop commands (homer, lisa, ralph) must not exceed 40 lines. The pipeline command must not exceed 60 lines. These are hard upper bounds replacing the previous vague "approximately 30" and "~50" targets.
- Q: What is explicitly out of scope for this fix? → A: Modifications to the bash scripts themselves, changes to agent files, adding new pipeline phases, and changes to supporting infrastructure scripts.

## Out of Scope

The following are explicitly excluded from this fix:

- **Bash orchestrator scripts**: No modifications to `pipeline.sh`, `homer-loop.sh`, `lisa-loop.sh`, or `ralph-loop.sh`. These are assumed to be functionally correct.
- **Agent definition files**: No modifications to `homer.md`, `lisa.md`, or `ralph.md` agent files.
- **New pipeline phases or steps**: No additions to the existing 6-phase pipeline sequence.
- **Claude Code tooling infrastructure**: No changes to the Agent tool, Bash tool, or their underlying behavior.
- **Supporting scripts**: No modifications to `check-prerequisites.sh` or other utility scripts under `.specify/scripts/`.
- **Non-orchestrator slash commands**: Only the 4 orchestrator commands (pipeline, homer, lisa, ralph) are in scope. Other slash commands (e.g., `/speckit.specify`, `/speckit.plan`, `/speckit.tasks`) are not modified.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Full Pipeline Runs to Completion (Priority: P1)

A developer invokes `/speckit.pipeline` from a Claude Code session and the pipeline executes all 6 phases (specify, homer, plan, tasks, lisa, ralph) without stopping prematurely after the specify phase. One Claude Code session acts as the orchestrator, spawning sub-agents for each phase.

**Why this priority**: This is the core bug. The pipeline command exists to run end-to-end autonomously. If it only runs one phase, it provides no value over invoking individual slash commands manually.

**Independent Test**: Can be fully tested by invoking `/speckit.pipeline` in a project with the bash scripts installed and verifying that all 6 steps execute sequentially, producing the expected artifacts (spec.md, plan.md, tasks.md, and implementation changes).

**Acceptance Scenarios**:

1. **Given** a project with the bash scripts installed and a feature branch checked out, **When** the user runs `/speckit.pipeline`, **Then** the Claude Code session orchestrates all 6 phases by spawning one Agent sub-agent per step, each running the corresponding bash script.
2. **Given** a project with an existing `spec.md`, **When** the user runs `/speckit.pipeline`, **Then** the orchestrator auto-detects the starting step (skipping specify) and runs the remaining phases.
3. **Given** a project with the bash scripts, **When** the user runs `/speckit.pipeline --from homer`, **Then** the orchestrator starts from the homer phase, passing the feature directory to `homer-loop.sh`.

---

### User Story 2 - Loop Commands Run All Iterations (Priority: P1)

A developer invokes any of the standalone loop commands (`/speckit.homer.clarify`, `/speckit.lisa.analyze`, `/speckit.ralph.implement`) and the loop runs all iterations until its completion condition is met (all findings resolved, all tasks complete, or max iterations reached), rather than running a single iteration and stopping.

**Why this priority**: The loop commands suffer the same root cause as pipeline — Agent-tool orchestration reimplemented in Claude instructions fails on weaker models or when agent files are missing. Delegating to the existing bash loop scripts makes them reliable.

**Independent Test**: Can be tested by invoking each loop command in a project with findings/tasks to resolve and verifying multiple iterations execute until a completion condition is met.

**Acceptance Scenarios**:

1. **Given** a project with `homer-loop.sh` installed and a spec with findings, **When** the user runs `/speckit.homer.clarify`, **Then** the command delegates to `homer-loop.sh` and iterates until all findings are resolved or max iterations reached.
2. **Given** a project with `lisa-loop.sh` installed and spec/plan/tasks artifacts, **When** the user runs `/speckit.lisa.analyze`, **Then** the command delegates to `lisa-loop.sh` and iterates until all findings are resolved or max iterations reached.
3. **Given** a project with `ralph-loop.sh` installed and incomplete tasks, **When** the user runs `/speckit.ralph.implement`, **Then** the command delegates to `ralph-loop.sh` and iterates until all tasks are complete or max iterations reached.

---

### User Story 3 - Helpful Error When Script Missing (Priority: P2)

A developer invokes any of the 4 commands in a project where the simpsons-loops setup has not been run (corresponding bash script does not exist). The command displays a clear error message with remediation instructions instead of silently failing.

**Why this priority**: Without the bash scripts, the commands cannot function. A clear error prevents confusion and guides the developer toward the fix.

**Independent Test**: Can be tested by invoking each command in a project without the corresponding bash script and verifying the error message appears with setup instructions.

**Acceptance Scenarios**:

1. **Given** a project where `.specify/scripts/bash/pipeline.sh` does not exist, **When** the user runs `/speckit.pipeline`, **Then** the command displays an error explaining the script is missing and instructs the user to run setup.
2. **Given** a project where `.specify/scripts/bash/homer-loop.sh` does not exist, **When** the user runs `/speckit.homer.clarify`, **Then** the command displays a similar error with setup instructions.
3. **Given** a project where any of the 4 bash scripts is missing, **When** the corresponding slash command is invoked, **Then** no partial execution occurs — the command exits cleanly after displaying the error.

---

### User Story 4 - Arguments Pass Through to Scripts (Priority: P2)

A developer invokes any of the 4 commands with arguments and all arguments are forwarded to the corresponding bash script unchanged.

**Why this priority**: The bash scripts support options (--from, --dry-run, --model, max iterations, spec-dir, etc.). The slash commands must act as transparent pass-throughs to preserve this functionality.

**Independent Test**: Can be tested by running `/speckit.pipeline --dry-run` and verifying the dry-run output from `pipeline.sh` shows all planned steps without executing them.

**Acceptance Scenarios**:

1. **Given** a project with the scripts installed, **When** the user runs `/speckit.pipeline --dry-run`, **Then** the `--dry-run` flag is passed to `pipeline.sh` and dry-run output is displayed.
2. **Given** a project with the scripts installed, **When** the user runs `/speckit.homer.clarify specs/003-fix-pipeline-delegation 5`, **Then** the spec-dir and max-iterations arguments are forwarded to `homer-loop.sh`.
3. **Given** a project with the scripts installed, **When** the user runs any command with no arguments, **Then** the bash script receives no arguments and uses its own defaults (auto-detect from branch, default max iterations).

---

### User Story 5 - All File Copies Stay in Sync (Priority: P3)

After the fix is applied, each command file is identical across all 3 locations where it exists: repo root (upstream source), `.claude/commands/` (local project copy), and `~/.openclaw/.claude/commands/` (global installed copy).

**Why this priority**: Inconsistent copies would cause the bug to persist in some contexts while appearing fixed in others.

**Independent Test**: Can be tested by running `diff` across all 3 locations for each of the 4 command files.

**Acceptance Scenarios**:

1. **Given** the fix has been applied to the upstream source files, **When** the local and global copies are synced, **Then** all 3 copies of each command file are byte-identical.

---

### Edge Cases

- What happens when a bash script exists but is not executable? The command should still work because `bash <script>` invokes it via the bash interpreter, not as a direct executable.
- What happens when a bash script exits with a non-zero status? The slash command should report the failure and the exit status to the user.
- What happens when the user provides no arguments? The slash command should pass no arguments, and the bash script will use its own defaults (auto-detect feature directory from the current branch, default max iterations).
- What happens when a bash script is present but its dependencies (agent files, other scripts) are missing? This is handled by the bash scripts themselves, which validate their own dependencies. The slash command's only responsibility is to check for the corresponding bash script.
- What happens when `pipeline.sh` is invoked non-interactively (from Claude's Bash tool)? The `[[ -t 0 ]]` check in the stop-after menu returns false, defaulting to "run all the way through." This is the desired behavior.
- What happens when a loop bash script takes longer than the Bash tool's 10-minute timeout? Long-running scripts (loop steps especially) must be run with `run_in_background` so they are not killed by the timeout. The bash scripts log all output to `.specify/logs/`.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: All 4 orchestrator slash commands (`/speckit.pipeline`, `/speckit.homer.clarify`, `/speckit.lisa.analyze`, `/speckit.ralph.implement`) MUST delegate loop/iteration execution to their corresponding bash scripts (`pipeline.sh`, `homer-loop.sh`, `lisa-loop.sh`, `ralph-loop.sh`) instead of implementing orchestration logic in Claude instructions.
- **FR-002**: Each slash command MUST check for the existence of its corresponding bash script before attempting execution.
- **FR-003**: Each slash command MUST display a clear error message with remediation steps when its bash script is not found.
- **FR-004**: Each slash command MUST pass all user-provided arguments through to its bash script without modification.
- **FR-005**: Each slash command MUST report the result of script execution (success or failure) back to the user.
- **FR-006**: All 3 copies of each command file (repo root, `.claude/commands/`, and `~/.openclaw/.claude/commands/`) MUST contain identical content after the fix is applied.
- **FR-007**: The rewritten commands MUST NOT re-implement any orchestration logic that already exists in the bash scripts (no loop iteration, no stuck detection, no quality gate resolution, no agent spawning for individual iterations).
- **FR-008**: The execution path MUST be unified: when `/speckit.pipeline` runs the homer phase, it MUST invoke the same `homer-loop.sh` script that `/speckit.homer.clarify` invokes directly. The same applies to lisa and ralph. There MUST be exactly one implementation of each loop's orchestration logic.
- **FR-009**: For `/speckit.pipeline`, the Claude Code session MUST act as the step-level orchestrator, spawning one Agent tool sub-agent per pipeline phase. Each sub-agent runs the bash script for its assigned step. The session sequences the 6 steps and manages sub-agent lifecycle.
- **FR-010**: Long-running bash scripts (loop steps that may exceed 10 minutes) MUST be executed using the Bash tool's background execution mode to avoid timeout termination.

### Architecture: Hybrid Orchestration

**Principle**: Claude Code orchestrates step sequencing; bash scripts handle loop iteration and step-internal complexity.

**For `/speckit.pipeline`** (multi-step orchestrator):
```
Claude Code session (orchestrator)
  ├─ determines feature dir, starting step, stop-after
  ├─ Step 1: Agent sub-agent → bash homer-loop.sh (loop logic in bash)
  ├─ Step 2: Agent sub-agent → bash plan agent call (single-shot)
  ├─ Step 3: Agent sub-agent → bash tasks agent call (single-shot)
  ├─ Step 4: Agent sub-agent → bash lisa-loop.sh (loop logic in bash)
  ├─ Step 5: Agent sub-agent → bash ralph-loop.sh (loop logic in bash)
  └─ reports final results
```

**For standalone loop commands** (`/speckit.homer.clarify`, etc.):
```
Claude Code session
  ├─ checks script exists
  ├─ runs bash homer-loop.sh via Bash tool (background for long runs)
  └─ reports results
```

**Why hybrid**: Step sequencing (6 ordered steps) is simple enough for Claude Code instructions to handle reliably. Loop iteration (20+ cycles with stuck detection, output parsing, and error handling) is complex and must remain in deterministic bash scripts. This separation keeps slash commands thin (~30 lines) while ensuring reliable end-to-end execution.

### Command-to-Script Mapping

| Slash Command | Bash Script | Script Location |
|---------------|-------------|-----------------|
| `/speckit.pipeline` | `pipeline.sh` (step sequencing reference) + individual loop scripts | `.specify/scripts/bash/pipeline.sh` |
| `/speckit.homer.clarify` | `homer-loop.sh` | `.specify/scripts/bash/homer-loop.sh` |
| `/speckit.lisa.analyze` | `lisa-loop.sh` | `.specify/scripts/bash/lisa-loop.sh` |
| `/speckit.ralph.implement` | `ralph-loop.sh` | `.specify/scripts/bash/ralph-loop.sh` |

### File Locations Per Command

Each command file exists in 3 locations that must be kept in sync:

1. **Repo root** (upstream source): `speckit.<name>.md`
2. **Local project copy**: `.claude/commands/speckit.<name>.md`
3. **Global installed copy**: `~/.openclaw/.claude/commands/speckit.<name>.md`

### Key Entities

- **Slash Command Files**: The Claude Code command definitions (`.md` files) invoked when a user types the corresponding slash command. Each exists in 3 locations.
- **Bash Orchestrator Scripts**: The deterministic shell scripts under `.specify/scripts/bash/` that handle loop iteration, stuck detection, quality gates, logging, error handling, and `claude --agent` invocations.
- **Agent Sub-agents**: Claude Code sub-agents spawned via the Agent tool within the pipeline orchestrator session. Each sub-agent handles one pipeline step and has its own context window.

## Assumptions

- All 4 bash scripts (`pipeline.sh`, `homer-loop.sh`, `lisa-loop.sh`, `ralph-loop.sh`) are functionally correct and do not need modifications.
- The slash command file format supports frontmatter (YAML between `---` delimiters) for the description field.
- Claude Code's Bash tool `run_in_background` mode allows scripts to run without the 10-minute timeout constraint.
- The global copy location is `~/.openclaw/.claude/commands/` and is managed outside the repository.
- The `.claude/commands/` directory within the repo is a local project copy that Claude Code also resolves when looking up commands.
- Claude Code can reliably sequence 6 ordered Agent tool calls when the instructions are simple and explicit (no complex conditional logic, just "run step N, check result, proceed to step N+1").

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: All 4 orchestrator commands complete their full execution (all phases for pipeline, all iterations for loops) when invoked in a properly configured project, with zero manual intervention required.
- **SC-002**: Each standalone loop slash command file (homer, lisa, ralph) MUST NOT exceed 40 lines of delegation logic. The pipeline command MUST NOT exceed 60 lines. All commands MUST be reduced from their current sizes (64-146 lines) by removing orchestration logic that duplicates the bash scripts.
- **SC-003**: 100% of bash script CLI arguments are correctly forwarded when passed through the corresponding slash command.
- **SC-004**: When a bash script is missing, the user sees an actionable error message within 1 second of invocation (no hanging or partial execution).
- **SC-005**: All 3 copies of each command file (repo root, `.claude/commands/`, global) are identical after deployment. 12 files total (4 commands x 3 locations).
- **SC-006**: Running `/speckit.pipeline` and running `/speckit.homer.clarify` independently both invoke the same `homer-loop.sh` — verified by checking that the script path in both execution flows is identical.
