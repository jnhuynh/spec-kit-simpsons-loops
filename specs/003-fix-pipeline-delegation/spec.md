# Feature Specification: Fix Pipeline and Loop Command Delegation

**Feature Branch**: `003-fix-pipeline-delegation`
**Created**: 2026-03-09
**Status**: Draft
**Input**: User description: "Fix: /speckit.pipeline stops after specify phase — rewrite to delegate to pipeline.sh"

## Clarifications

### Session 2026-03-09

- Q: Should the delegation fix apply to all 4 orchestrator commands (pipeline, homer, lisa, ralph), not just pipeline? → A: Yes, fix all 4 commands.
- Q: Should commands delegate entirely to bash scripts? → A: No. Hybrid architecture: commands use the Agent tool for loop orchestration (one sub-agent per iteration), and call bash utilities via Bash tool for deterministic operations (feature dir resolution, task counting, quality gates, stuck detection).
- Q: Does this unify the execution logic so `/speckit.pipeline` and individual loop commands share the same code path? → A: Yes. Both `/speckit.pipeline` and standalone loop commands (e.g., `/speckit.homer.clarify`) use the same Agent tool loop pattern and the same bash utility scripts (e.g., `check-prerequisites.sh`). One orchestration pattern, no divergent implementations.
- Q: What orchestration architecture should be used? → A: Hybrid — Claude Code commands orchestrate loops via Agent tool sub-agents (one per iteration), calling bash utilities via Bash tool for deterministic operations. Agent tool handles iteration lifecycle; bash utilities handle feature dir resolution, task/finding counting, quality gate checks, and stuck detection.
- Q: What are the precise line-count limits for rewritten command files? → A: No hard line-count limits. The previous 40/60 limits were sized for thin bash delegation wrappers and are not appropriate for commands containing Agent tool loop orchestration. Focus on SC-001 (reliability — commands complete full execution) rather than arbitrary line counts.
- Q: What constitutes a "stuck" iteration for stuck detection? → A: An iteration is stuck when the sub-agent exits without producing a meaningful git diff (no file changes committed) AND the completion promise tag (e.g., `ALL_FINDINGS_RESOLVED`) was not emitted. Two consecutive stuck iterations should abort the loop.
- Q: Should SC-003 and SC-004 be updated to reflect hybrid terminology? → A: Yes. SC-003 updated to reference argument interpretation (not forwarding to bash scripts). SC-004 updated to reference utility scripts (not loop scripts).
- Q: What is explicitly out of scope for this fix? → A: Modifications to the bash scripts themselves, changes to agent files, adding new pipeline phases, and changes to supporting infrastructure scripts.

## Out of Scope

The following are explicitly excluded from this fix:

- **Agent definition files**: No modifications to `homer.md`, `lisa.md`, or `ralph.md` agent files.
- **New pipeline phases or steps**: No additions to the existing 6-phase pipeline sequence.
- **Claude Code tooling infrastructure**: No changes to the Agent tool, Bash tool, or their underlying behavior.
- **Bash utility scripts**: No modifications to `check-prerequisites.sh` or other utility scripts under `.specify/scripts/`. These are called as-is for deterministic operations.
- **Non-orchestrator slash commands**: Only the 4 orchestrator commands (pipeline, homer, lisa, ralph) are in scope. Other slash commands (e.g., `/speckit.specify`, `/speckit.plan`, `/speckit.tasks`) are not modified.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Full Pipeline Runs to Completion (Priority: P1)

A developer invokes `/speckit.pipeline` from a Claude Code session and the pipeline executes all 6 phases (specify, homer, plan, tasks, lisa, ralph) without stopping prematurely after the specify phase. One Claude Code session acts as the orchestrator, spawning sub-agents for each phase.

**Why this priority**: This is the core bug. The pipeline command exists to run end-to-end autonomously. If it only runs one phase, it provides no value over invoking individual slash commands manually.

**Independent Test**: Can be fully tested by invoking `/speckit.pipeline` in a project with the bash scripts installed and verifying that all 6 steps execute sequentially, producing the expected artifacts (spec.md, plan.md, tasks.md, and implementation changes).

**Acceptance Scenarios**:

1. **Given** a project with utility scripts installed and a feature branch checked out, **When** the user runs `/speckit.pipeline`, **Then** the Claude Code session orchestrates all 6 phases by spawning one Agent sub-agent per step. Loop steps (homer, lisa, ralph) use Agent tool sub-agents for iteration.
2. **Given** a project with an existing `spec.md`, **When** the user runs `/speckit.pipeline`, **Then** the orchestrator auto-detects the starting step based on existing artifacts and runs the remaining phases. Auto-detection logic (checked in order): if `tasks.md` exists with some `- [x]` completed tasks, start at **ralph**; if `tasks.md` exists with no completed tasks, start at **lisa**; if `plan.md` exists but no `tasks.md`, start at **tasks**; if `spec.md` exists but no `plan.md`, start at **homer**; if no `spec.md` but `--description` is provided, start at **specify**.
3. **Given** a project with utility scripts, **When** the user runs `/speckit.pipeline --from homer`, **Then** the orchestrator starts from the homer phase, resolving the feature directory via `check-prerequisites.sh`.

---

### User Story 2 - Loop Commands Run All Iterations (Priority: P1)

A developer invokes any of the standalone loop commands (`/speckit.homer.clarify`, `/speckit.lisa.analyze`, `/speckit.ralph.implement`) and the loop runs all iterations until its completion condition is met (all findings resolved, all tasks complete, or max iterations reached), rather than running a single iteration and stopping.

**Why this priority**: The loop commands must iterate reliably. The hybrid approach uses Agent tool sub-agents (one per iteration) for orchestration, with bash utilities for deterministic checks (counting findings/tasks, stuck detection, quality gates).

**Independent Test**: Can be tested by invoking each loop command in a project with findings/tasks to resolve and verifying multiple iterations execute until a completion condition is met.

**Acceptance Scenarios**:

1. **Given** a project with utility scripts installed and a spec with findings, **When** the user runs `/speckit.homer.clarify`, **Then** the command loops via Agent tool sub-agents (one per iteration), each reading the agent file and doing work, until all findings are resolved or max iterations reached.
2. **Given** a project with utility scripts installed and spec/plan/tasks artifacts, **When** the user runs `/speckit.lisa.analyze`, **Then** the command loops via Agent tool sub-agents until all findings are resolved or max iterations reached.
3. **Given** a project with utility scripts installed and incomplete tasks, **When** the user runs `/speckit.ralph.implement`, **Then** the command loops via Agent tool sub-agents until all tasks are complete or max iterations reached.

---

### User Story 3 - Helpful Error When Script Missing (Priority: P2)

A developer invokes any of the 4 commands in a project where the simpsons-loops setup has not been run (utility scripts do not exist). The command displays a clear error message with remediation instructions instead of silently failing.

**Why this priority**: Without the utility scripts (e.g., `check-prerequisites.sh`), the commands cannot resolve the feature directory or perform quality checks. A clear error prevents confusion and guides the developer toward the fix.

**Independent Test**: Can be tested by invoking each command in a project without the utility scripts and verifying the error message appears with setup instructions.

**Acceptance Scenarios**:

1. **Given** a project where `.specify/scripts/bash/check-prerequisites.sh` does not exist, **When** the user runs `/speckit.pipeline`, **Then** the command displays an error explaining the script is missing and instructs the user to run setup.
2. **Given** a project where `.specify/scripts/bash/check-prerequisites.sh` does not exist, **When** the user runs `/speckit.homer.clarify`, **Then** the command displays a similar error with setup instructions.
3. **Given** a project where utility scripts are missing, **When** the corresponding slash command is invoked, **Then** no partial execution occurs — the command exits cleanly after displaying the error.

---

### User Story 4 - Arguments Pass Through to Scripts (Priority: P2)

A developer invokes any of the 4 commands with arguments and the command interprets them correctly (e.g., spec-dir, max iterations, --from for pipeline).

**Why this priority**: The commands support options (--from, max iterations, spec-dir, etc.). Arguments must be parsed and applied correctly within the Agent tool orchestration.

**Independent Test**: Can be tested by running `/speckit.homer.clarify specs/003-fix-pipeline-delegation 5` and verifying the spec-dir and max-iterations are applied correctly.

**Acceptance Scenarios**:

1. **Given** a project with utility scripts installed, **When** the user runs `/speckit.pipeline --from homer`, **Then** the `--from` flag is interpreted and the pipeline starts from the homer phase.
2. **Given** a project with utility scripts installed, **When** the user runs `/speckit.homer.clarify specs/003-fix-pipeline-delegation 5`, **Then** the spec-dir and max-iterations arguments are applied correctly.
3. **Given** a project with utility scripts installed, **When** the user runs any command with no arguments, **Then** the command uses defaults (auto-detect feature dir from branch via `check-prerequisites.sh`, default max iterations).

---

### User Story 5 - All File Copies Stay in Sync (Priority: P3)

After the fix is applied, each command file is identical across all 3 locations where it exists: repo root (upstream source), `.claude/commands/` (local project copy), and `~/.openclaw/.claude/commands/` (global installed copy).

**Why this priority**: Inconsistent copies would cause the bug to persist in some contexts while appearing fixed in others.

**Independent Test**: Can be tested by running `diff` across all 3 locations for each of the 4 command files.

**Acceptance Scenarios**:

1. **Given** the fix has been applied to the upstream source files, **When** the local and global copies are synced, **Then** all 3 copies of each command file are byte-identical.

---

### Edge Cases

- What happens when utility scripts exist but are not executable? The command should still work because `bash <script>` invokes them via the bash interpreter, not as a direct executable.
- What happens when a bash utility call exits with a non-zero status? The command should report the failure to the user and stop iteration.
- What happens when the user provides no arguments? The command uses defaults: auto-detect feature directory from the current branch via `check-prerequisites.sh`, default max iterations.
- What happens when agent files (e.g., `homer.md`) are missing? The Agent tool sub-agent will fail to read the agent file. The orchestrator should detect this and report the error.
- What happens when a Bash tool call within a sub-agent takes longer than 10 minutes (600s)? Individual Bash tool calls within sub-agents still have the 10-minute/600s limit. However, since each iteration is a separate sub-agent, and Agent tool sub-agents themselves have no fixed timeout, this is only a concern for single bash operations that exceed 10 minutes. Most operations (running a single agent iteration, counting tasks, checking quality gates) complete well within this limit.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: All 4 orchestrator slash commands (`/speckit.pipeline`, `/speckit.homer.clarify`, `/speckit.lisa.analyze`, `/speckit.ralph.implement`) MUST use the Agent tool for loop orchestration (one sub-agent per iteration) and call bash utilities via Bash tool for deterministic operations (feature dir resolution via `check-prerequisites.sh`, task/finding counting, quality gates, stuck detection).
- **FR-002**: Each slash command MUST check for the existence of required utility scripts (e.g., `check-prerequisites.sh`) before attempting execution.
- **FR-003**: Each slash command MUST display a clear error message with remediation steps when required utility scripts are not found.
- **FR-004**: Each slash command MUST accept and correctly interpret user-provided arguments (spec-dir, max-iterations, --from for pipeline).
- **FR-005**: Each slash command MUST report the result of execution (success or failure) back to the user.
- **FR-006**: All 3 copies of each command file (repo root, `.claude/commands/`, and `~/.openclaw/.claude/commands/`) MUST contain identical content after the fix is applied.
- **FR-007**: Commands MUST iterate via Agent tool sub-agents (one per iteration). Each sub-agent reads the agent file, does its work, commits, and exits. The orchestrator performs stuck detection between iterations: an iteration is "stuck" when the sub-agent exits without a meaningful git diff (no file changes committed) AND the completion promise tag (e.g., `ALL_FINDINGS_RESOLVED`) was not emitted. Two consecutive stuck iterations MUST abort the loop.
- **FR-008**: The execution path MUST be unified: both `/speckit.pipeline` (running the homer phase) and `/speckit.homer.clarify` (standalone) MUST use the same Agent tool loop pattern and the same bash utility scripts. There MUST be exactly one orchestration pattern, not divergent implementations.
- **FR-009**: For `/speckit.pipeline`, the Claude Code session MUST act as the step-level orchestrator, spawning one Agent tool sub-agent per pipeline phase. Loop phases (homer, lisa, ralph) use the same Agent tool iteration pattern as their standalone commands. The session sequences the 6 steps and manages sub-agent lifecycle.

### Architecture: Hybrid Orchestration

**Principle**: Agent tool handles loop orchestration (one sub-agent per iteration); bash utilities handle deterministic operations (feature dir resolution, task counting, quality gates, stuck detection).

**For `/speckit.pipeline`** (multi-step orchestrator):
```
Claude Code session (orchestrator)
  ├─ Bash tool: check-prerequisites.sh --json (feature dir)
  ├─ Step 1: Agent sub-agent (specify — single-shot)
  ├─ Step 2: Loop — Agent tool sub-agent per iteration (homer)
  │   ├─ Sub-agent reads agent file + command file
  │   ├─ Sub-agent does work, commits, exits
  │   └─ Orchestrator checks promise tag + git diff (stuck detection)
  ├─ Step 3: Agent sub-agent (plan — single-shot)
  ├─ Step 4: Agent sub-agent (tasks — single-shot)
  ├─ Step 5: Loop — Agent tool sub-agent per iteration (lisa)
  ├─ Step 6: Loop — Agent tool sub-agent per iteration (ralph)
  └─ Reports results
```

**For standalone loop commands** (`/speckit.homer.clarify`, etc.):
```
Claude Code session (orchestrator)
  ├─ Bash tool: check-prerequisites.sh --json (feature dir)
  ├─ Loop: Agent tool sub-agent per iteration
  │   ├─ Sub-agent reads agent file + command file
  │   ├─ Sub-agent does work, commits, exits
  │   └─ Orchestrator checks promise tag + git diff (stuck detection)
  └─ Reports results
```

**Why hybrid**: Agent tool sub-agents provide isolated context windows per iteration and have no fixed timeout, making them ideal for orchestrating loops. Bash utilities provide deterministic, testable operations (parsing JSON output from `check-prerequisites.sh`, counting unchecked tasks, detecting stuck iterations via git diff). This separation keeps each concern in the right layer.

### Command-to-Utility Mapping

| Slash Command | Bash Utilities Used | Utility Location |
|---------------|---------------------|------------------|
| `/speckit.pipeline` | `check-prerequisites.sh` (feature dir resolution) | `.specify/scripts/bash/check-prerequisites.sh` |
| `/speckit.homer.clarify` | `check-prerequisites.sh` (feature dir resolution) | `.specify/scripts/bash/check-prerequisites.sh` |
| `/speckit.lisa.analyze` | `check-prerequisites.sh` (feature dir resolution) | `.specify/scripts/bash/check-prerequisites.sh` |
| `/speckit.ralph.implement` | `check-prerequisites.sh` (feature dir resolution) | `.specify/scripts/bash/check-prerequisites.sh` |

### File Locations Per Command

Each command file exists in 3 locations that must be kept in sync:

1. **Repo root** (upstream source): `speckit.<name>.md`
2. **Local project copy**: `.claude/commands/speckit.<name>.md`
3. **Global installed copy**: `~/.openclaw/.claude/commands/speckit.<name>.md`

### Key Entities

- **Slash Command Files**: The Claude Code command definitions (`.md` files) invoked when a user types the corresponding slash command. Each exists in 3 locations.
- **Bash Utility Scripts**: Deterministic shell scripts under `.specify/scripts/bash/` called via Bash tool for specific operations (feature dir resolution, prerequisite checks). Not used for loop orchestration.
- **Agent Sub-agents**: Claude Code sub-agents spawned via the Agent tool. For loop commands, one sub-agent per iteration (reads agent file, does work, commits, exits). For pipeline, one sub-agent per step. Each has its own context window.

## Assumptions

- Bash utility scripts (e.g., `check-prerequisites.sh`) are functionally correct and do not need modifications.
- The slash command file format supports frontmatter (YAML between `---` delimiters) for the description field.
- Agent tool sub-agents have no fixed timeout — they run until completion, making them suitable for loop iteration orchestration.
- Individual Bash tool calls within sub-agents have a 10-minute (600s) timeout, but single iteration operations complete well within this limit.
- The global copy location is `~/.openclaw/.claude/commands/` and is managed outside the repository.
- The `.claude/commands/` directory within the repo is a local project copy that Claude Code also resolves when looking up commands.
- Claude Code can reliably sequence 6 ordered Agent tool calls when the instructions are simple and explicit (no complex conditional logic, just "run step N, check result, proceed to step N+1").
- The Agent tool loop pattern (one sub-agent per iteration) has been proven working — homer ran 3 iterations successfully in the current session.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: All 4 orchestrator commands complete their full execution (all phases for pipeline, all iterations for loops) when invoked in a properly configured project, with zero manual intervention required.
- **SC-002**: No hard line-count limits on command files. Commands should be as concise as the hybrid architecture allows, but reliability (SC-001) takes precedence over brevity. Commands MUST NOT contain duplicated orchestration logic — the same Agent tool loop pattern and bash utilities must be used consistently across all commands.
- **SC-003**: 100% of user-provided arguments (spec-dir, max-iterations, --from) are correctly interpreted and applied by the corresponding slash command.
- **SC-004**: When required utility scripts (e.g., `check-prerequisites.sh`) are missing, the user sees an actionable error message within 1 second of invocation (no hanging or partial execution).
- **SC-005**: All 3 copies of each command file (repo root, `.claude/commands/`, global) are identical after deployment. 12 files total (4 commands x 3 locations).
- **SC-006**: Running `/speckit.pipeline` and running `/speckit.homer.clarify` independently both use the same Agent tool loop pattern and the same bash utility scripts — verified by checking that both execution flows follow the identical orchestration pattern.
