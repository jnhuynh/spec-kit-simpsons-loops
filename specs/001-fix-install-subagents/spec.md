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

### Key Entities

- **Install script (`setup.sh`)**: The primary distribution mechanism that copies loop files into a target project
- **Loop command files**: The Claude Code command definitions (`.claude/commands/speckit.*.md`) that orchestrate iterative sub agent execution
- **Agent definitions**: The `.claude/agents/*.md` files that define behavior for each sub agent type (homer, lisa, ralph, plan, tasks)
- **Bash loop scripts**: The standalone shell scripts (`homer-loop.sh`, `lisa-loop.sh`, `ralph-loop.sh`, `pipeline.sh`) that provide a fallback outside of Claude Code
- **README**: The primary documentation file describing setup, usage, and behavior

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
