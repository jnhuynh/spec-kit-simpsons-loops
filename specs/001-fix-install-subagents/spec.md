# Feature Specification: Fix Install Script, Sub Agent Consistency, and README

**Feature Branch**: `001-fix-install-subagents`
**Created**: 2026-03-01
**Status**: Draft
**Input**: User description: "Review all of the changes, fix any inconsistencies, ensure the install script works with a test directory. The code should run sub agents. Things execute in sequence. It should not ask users for permissions. Update the readme as well."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Install Script Works with a Test Directory (Priority: P1)

A developer wants to verify that `setup.sh` installs correctly without polluting a real project. They create a temporary test directory with the required `.claude/` and `.specify/` scaffolding, run `setup.sh` against it, and confirm all files are copied, scripts are executable, `.gitignore` entries are appended, and permissions are set. After testing, the test directory can be discarded.

**Why this priority**: The install script is the primary distribution mechanism. If it cannot be tested in isolation, regressions go unnoticed and users hit broken installs.

**Independent Test**: Run `setup.sh` against a prepared test directory and verify all expected files exist, scripts are executable, `.gitignore` contains the marker block, and `settings.local.json` has the permission entries.

**Acceptance Scenarios**:

1. **Given** a test directory with `.claude/` and `.specify/` subdirectories, **When** a developer runs `bash setup.sh` from within that test directory, **Then** all 13 files are copied to the correct destinations, 4 scripts are executable, `.gitignore` is updated, and `settings.local.json` contains all 4 permission entries
2. **Given** `setup.sh` has already been run once in the test directory, **When** it is run again, **Then** it succeeds without errors and skips `.gitignore` and permissions entries that already exist (idempotent)
3. **Given** the test directory lacks `jq`, **When** `setup.sh` is run, **Then** it prints manual permission instructions and completes without error

---

### User Story 2 - Loop Commands Use Sub Agents with Sequential Execution (Priority: P1)

A developer runs `/speckit.pipeline`, `/speckit.homer.clarify`, `/speckit.lisa.analyze`, or `/speckit.ralph.implement` and the loop command spawns fresh sub agents (via the Agent tool) that execute one at a time in strict sequence. No two sub agents run concurrently. Each sub agent gets a fresh context window to prevent hallucination drift.

**Why this priority**: Sub agents with fresh context windows are the core mechanism that makes iterative loops reliable. If they run in parallel or share context, the quality-iteration model breaks.

**Independent Test**: Run any loop command and observe that each iteration spawns exactly one sub agent at a time, each completes before the next starts, and the loop terminates on the expected completion signal.

**Acceptance Scenarios**:

1. **Given** a spec directory with `spec.md`, **When** `/speckit.homer.clarify` is run, **Then** each iteration spawns one `general-purpose` sub agent via the Agent tool, waits for it to return, then checks the output before spawning the next
2. **Given** a spec directory with `spec.md`, `plan.md`, and `tasks.md`, **When** `/speckit.pipeline` is run, **Then** the pipeline executes steps in order (homer, plan, tasks, lisa, ralph), each step completes fully before the next step begins, and within loop steps each iteration completes before the next iteration starts
3. **Given** any loop command is running, **When** the sub agent returns output containing the promise tag, **Then** the loop stops and reports success without spawning additional sub agents
4. **Given** any loop command is running, **When** 10 iterations complete without the promise tag being returned and without stuck detection triggering, **Then** the loop aborts with a clear message reporting the iteration count and suggesting manual review

---

### User Story 3 - Fully Autonomous Execution Without Permission Prompts (Priority: P1)

A developer kicks off a loop or pipeline and walks away. The entire process runs unattended from start to finish. No permission prompts, no confirmation dialogs, no "are you sure?" pauses. The loop commands explicitly instruct Claude Code to skip all interactive prompts.

**Why this priority**: The value of automated loops is hands-off execution. Permission prompts interrupt the flow and defeat the purpose of autonomous iteration.

**Independent Test**: Run `/speckit.pipeline` on a spec directory and confirm the entire pipeline completes without any user interaction required.

**Acceptance Scenarios**:

1. **Given** a loop command is invoked, **When** sub agents are spawned via the Agent tool, **Then** the loop command's prompt instructs agents to execute autonomously and not ask for user confirmation
2. **Given** the pipeline is running through multiple steps, **When** transitioning between steps (e.g., homer to plan), **Then** no permission or confirmation prompt is presented to the user
3. **Given** the bash script fallback is used, **When** `claude --agent` is invoked, **Then** the `--dangerously-skip-permissions` flag is passed

---

### User Story 4 - Accurate README Reflecting Current Behavior (Priority: P2)

A developer reads the README and gets an accurate picture of how the project works. All file paths, commands, and behavioral descriptions match the actual code. The README describes both the recommended workflow (slash commands with sub agents) and the bash script fallback. Terminology is consistent (e.g., "sub agents" not "Task tool" when referring to the Agent tool).

**Why this priority**: The README is the primary onboarding document. Inaccurate documentation erodes trust and wastes time.

**Independent Test**: A developer can follow every instruction in the README and achieve the described outcome without encountering missing files, incorrect paths, or misleading descriptions.

**Acceptance Scenarios**:

1. **Given** the README describes file paths for setup, **When** a developer checks those paths, **Then** every referenced file exists in the repository
2. **Given** the README describes how loops work (sub agents, sequential execution, no permissions), **When** the reader compares to actual loop command files, **Then** the behavior described matches the implementation
3. **Given** the README uses terminology for the Agent tool, **When** compared to the loop command files, **Then** the terminology is consistent across all files

---

### Edge Cases

- What happens if `setup.sh` is run from a directory that has `.claude/` but not `.specify/` (or vice versa)? It fails with a clear error message identifying which directory is missing.
- What happens if a loop command cannot find the spec directory? It reports the error clearly and suggests running `/speckit.specify`.
- What happens if stuck detection triggers during autonomous execution? The loop aborts after 3 identical outputs and suggests manual review.
- What happens if `setup.sh` is run from inside the simpsons-loops repo itself? It fails with a clear error explaining to run it from the target project instead.
- What happens if a sub agent crashes or times out mid-iteration (as opposed to stuck detection for identical outputs)? **Loop commands** (slash commands) catch the error, log the failure context (iteration number, agent type, error message), and abort the loop with a clear error message suggesting manual review. Loop commands do NOT retry automatically to avoid cascading failures. **Bash loop scripts** implement limited retry (up to 3 consecutive failures before aborting) as a resilience measure, since CLI process failures are more common and often transient.
- What happens if a loop reaches 10 iterations without the sub agent returning the promise tag and without stuck detection triggering? The loop aborts with a clear message reporting the iteration count (10) and suggesting manual review. This prevents runaway execution when outputs vary enough to bypass stuck detection but never converge on the completion signal.

## Clarifications

### Session 2026-03-01

- Q: What are the canonical terms for the sub agent spawning mechanism, and what deprecated synonyms should be avoided for consistency across all project files? → A: The canonical term is "Agent tool" (not "Task tool"). All references to spawning sub agents must use "Agent tool" or "sub agents via the Agent tool". The term "Task tool" is deprecated and must be replaced wherever it appears in loop command files and the README.
- Q: What should happen if a sub agent crashes or times out mid-iteration, distinct from stuck detection? → A: The loop command catches the error, logs failure context (iteration number, agent type, error message), and aborts with a clear error suggesting manual review. No automatic retry to avoid cascading failures.
- Q: What is the maximum iteration limit for loop commands to prevent runaway execution when stuck detection does not trigger? → A: All loop commands MUST enforce a maximum of 10 iterations per loop invocation. When the limit is reached, the loop aborts with a clear message reporting the iteration count and suggesting manual review. This safeguards against non-converging outputs that vary enough to bypass stuck detection but never reach the promise tag.
- Q: What are the exact 13 distribution files referenced in FR-001, and what are their source-to-destination mappings? → A: The 13 files are enumerated in the Distribution File Manifest under Key Entities. They comprise 4 bash loop scripts, 5 agent definitions, and 4 loop command files, each with an explicit source path and destination path in the target project.
- Q: Does the no-retry policy for sub agent failures (FR-011) apply to both loop commands and bash loop scripts, or only to loop commands? → A: FR-011's no-retry policy applies to loop commands (slash commands) only. Bash loop scripts implement limited retry (up to 3 consecutive failures) as a resilience measure for transient CLI process failures. This distinction is intentional: loop commands run inside Claude Code where failures are typically deterministic, while bash scripts invoke external CLI processes where transient failures are common.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: `setup.sh` MUST copy all 13 distribution files to the correct destinations in the target project (4 scripts, 5 agent definitions, 4 command files)
- **FR-002**: `setup.sh` MUST be idempotent — running it twice on the same target directory produces the same result without errors
- **FR-003**: `setup.sh` MUST work when run from a test directory that has the required `.claude/` and `.specify/` scaffolding
- **FR-004**: All loop command files (`speckit.homer.clarify.md`, `speckit.lisa.analyze.md`, `speckit.ralph.implement.md`, `speckit.pipeline.md`) MUST instruct spawning sub agents via the Agent tool with `subagent_type: general-purpose`
- **FR-005**: All loop commands MUST enforce strict sequential execution — one sub agent at a time, each completing before the next is spawned
- **FR-006**: All loop commands MUST include explicit autonomous execution instructions — no permission prompts, no confirmation dialogs, no interactive pauses
- **FR-007**: The README MUST accurately describe the install process, file layout, recommended workflow, and bash script fallback
- **FR-008**: The README MUST use consistent terminology that matches the loop command files and agent definitions
- **FR-009**: All loop command files and the README MUST be internally consistent — the same behavior described the same way across all files
- **FR-010**: The bash script fallback (`homer-loop.sh`, `lisa-loop.sh`, `ralph-loop.sh`, `pipeline.sh`) MUST use `--dangerously-skip-permissions` when invoking `claude --agent`
- **FR-011**: All loop commands (slash commands) MUST handle sub agent crash or timeout by catching the error, logging failure context (iteration number, agent type, error message), and aborting the loop with a clear error message — no automatic retry. Bash loop scripts MAY implement limited retry (up to 3 consecutive failures) for transient CLI process failures before aborting.
- **FR-012**: All loop commands MUST enforce a maximum iteration limit of 10 iterations per loop invocation — when the limit is reached, the loop aborts with a clear message reporting the iteration count and suggesting manual review

### Key Entities

- **Install script (`setup.sh`)**: The primary distribution mechanism that copies loop files into a target project
- **Loop command files**: The Claude Code command definitions (`.claude/commands/speckit.*.md`) that orchestrate iterative sub agent execution
- **Agent definitions**: The `.claude/agents/*.md` files that define behavior for each sub agent type (homer, lisa, ralph, plan, tasks)
- **Bash loop scripts**: The standalone shell scripts (`homer-loop.sh`, `lisa-loop.sh`, `ralph-loop.sh`, `pipeline.sh`) that provide a fallback outside of Claude Code
- **README**: The primary documentation file describing setup, usage, and behavior

### Distribution File Manifest

The 13 files distributed by `setup.sh` (referenced in FR-001 and SC-001) are:

**Bash loop scripts (4 files — copied to `.specify/scripts/bash/` and made executable):**

| # | Source | Destination |
|---|--------|-------------|
| 1 | `homer-loop.sh` | `.specify/scripts/bash/homer-loop.sh` |
| 2 | `lisa-loop.sh` | `.specify/scripts/bash/lisa-loop.sh` |
| 3 | `ralph-loop.sh` | `.specify/scripts/bash/ralph-loop.sh` |
| 4 | `pipeline.sh` | `.specify/scripts/bash/pipeline.sh` |

**Agent definitions (5 files — copied to `.claude/agents/`):**

| # | Source | Destination |
|---|--------|-------------|
| 5 | `agents/homer.md` | `.claude/agents/homer.md` |
| 6 | `agents/lisa.md` | `.claude/agents/lisa.md` |
| 7 | `agents/ralph.md` | `.claude/agents/ralph.md` |
| 8 | `agents/plan.md` | `.claude/agents/plan.md` |
| 9 | `agents/tasks.md` | `.claude/agents/tasks.md` |

**Loop command files (4 files — copied to `.claude/commands/`):**

| # | Source | Destination |
|---|--------|-------------|
| 10 | `speckit.homer.clarify.md` | `.claude/commands/speckit.homer.clarify.md` |
| 11 | `speckit.lisa.analyze.md` | `.claude/commands/speckit.lisa.analyze.md` |
| 12 | `speckit.ralph.implement.md` | `.claude/commands/speckit.ralph.implement.md` |
| 13 | `speckit.pipeline.md` | `.claude/commands/speckit.pipeline.md` |

### Terminology & Consistency

The following canonical terms MUST be used consistently across all project files (loop command files, agent definitions, README, and spec):

| Canonical Term | Definition | Deprecated Synonyms |
|---------------|------------|---------------------|
| **Agent tool** | The Claude Code mechanism for spawning sub agents with `subagent_type` parameter | "Task tool" |
| **sub agent** | A fresh-context agent instance spawned by the Agent tool within a loop iteration | "task", "child agent" |
| **loop command** | A Claude Code slash command (`.claude/commands/speckit.*.md`) that orchestrates iterative sub agent execution | "loop script" (reserved for bash fallback) |
| **bash loop script** | A standalone shell script (`*-loop.sh`, `pipeline.sh`) that provides fallback execution outside Claude Code | — |
| **promise tag** | The XML-style completion signal (e.g., `<promise>ALL_FINDINGS_RESOLVED</promise>`) returned by sub agents | "completion signal" (acceptable but less precise) |
| **stuck detection** | The mechanism that aborts a loop after 3 consecutive identical outputs | — |

**Enforcement**: FR-008 and FR-009 require that all files use the canonical terms above. Any occurrence of a deprecated synonym MUST be replaced with the canonical term.

## Assumptions

- The project uses Claude Code's Agent tool (with `subagent_type` parameter) as the mechanism for spawning fresh-context sub agents within slash commands
- The bash script fallback uses `claude --agent` CLI with `--dangerously-skip-permissions` as a separate mechanism from the slash command approach
- `setup.sh` targets projects that already have both `.claude/` and `.specify/` directories (Claude Code and Speckit enabled)
- Developers testing `setup.sh` will create a temporary directory with the required scaffolding rather than modifying a real project

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Running `setup.sh` against a test directory with `.claude/` and `.specify/` scaffolding completes without errors and produces all 13 expected files in their correct locations
- **SC-002**: Running `setup.sh` twice on the same directory produces identical results without errors or duplicated entries
- **SC-003**: All 4 loop command files reference the Agent tool with `subagent_type: general-purpose` for spawning sub agents
- **SC-004**: All 4 loop command files contain explicit instructions for sequential execution and autonomous operation without permission prompts
- **SC-005**: 100% of file paths and commands referenced in the README correspond to actual files and working commands in the repository
- **SC-006**: Terminology across the README, loop command files, and agent definitions is consistent — no conflicting names for the same concept
- **SC-007**: All 4 loop command files enforce a maximum iteration limit of 10, aborting with a clear message when the limit is reached
