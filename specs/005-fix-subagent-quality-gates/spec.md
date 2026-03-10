# Feature Specification: Fix Subagent Delegation and Quality Gate Consolidation

**Feature Branch**: `005-fix-subagent-quality-gates`
**Created**: 2026-03-10
**Status**: Draft
**Input**: User description: "can we make quality-gates.sh the only option for accessing quality gates? Also why is the pipeline not kicking off claude subagents? Can we ensure that and all the loops are actually kicking off sub agents?"

## Clarifications

### Session 2026-03-10

- Q: Should command files validate that `.specify/quality-gates.sh` is non-empty before executing it, given that `bash` on an empty file silently exits 0? → A: Yes — command files must validate existence and non-empty content, aborting with a clear error if the file is missing or contains only comments/whitespace. This aligns command file behavior with the bash script `resolve_quality_gates()` function and the stated edge case.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Pipeline Spawns Subagents for Every Step (Priority: P1)

A developer invokes `/speckit.pipeline` inside a Claude Code session. The pipeline orchestrator uses the Agent tool to spawn a fresh, isolated subagent for each pipeline step (specify, homer iterations, plan, tasks, lisa iterations, ralph iterations). Each subagent receives an explicit prompt with the feature directory and any step-specific context, and runs in its own context window.

**Why this priority**: This is the core value proposition of the loop architecture. Without actual subagent delegation, each iteration accumulates context and risks hallucination drift, token exhaustion, and loss of deterministic behavior. This is the highest-impact fix.

**Independent Test**: Can be verified by running `/speckit.pipeline` on a feature with an existing spec and confirming that each step shows evidence of Agent tool invocation (separate subagent output blocks in the Claude Code UI), rather than inline execution within the orchestrator's own context.

**Acceptance Scenarios**:

1. **Given** a feature branch with `spec.md` only, **When** the user runs `/speckit.pipeline`, **Then** the pipeline spawns a subagent (via the Agent tool) for the homer loop's first iteration, waits for it to return, then spawns a new subagent for the next iteration (or next step), and so on through plan, tasks, lisa, and ralph.
2. **Given** the pipeline is running the homer loop, **When** homer iteration 1 completes, **Then** a NEW subagent is spawned for homer iteration 2 (not the same agent continuing inline).
3. **Given** the pipeline is running any loop step, **When** a subagent returns its result, **Then** the orchestrator checks for the completion promise tag and stuck detection BEFORE deciding whether to spawn the next subagent.

---

### User Story 2 - Standalone Loop Commands Spawn Subagents (Priority: P1)

A developer invokes `/speckit.homer.clarify`, `/speckit.lisa.analyze`, or `/speckit.ralph.implement` as standalone commands (not as part of the pipeline). Each loop orchestrator spawns a fresh subagent (via the Agent tool) for every iteration, with isolated context windows.

**Why this priority**: Standalone loops are the most common usage pattern. If these don't spawn subagents, developers get degraded quality across all loop-based workflows. Equal priority to the pipeline fix since the root cause and fix are the same.

**Independent Test**: Can be verified by running `/speckit.homer.clarify` on a feature with findings and confirming that each iteration shows as a separate subagent invocation in the Claude Code UI.

**Acceptance Scenarios**:

1. **Given** a feature with clarification findings in spec.md, **When** the user runs `/speckit.homer.clarify`, **Then** each iteration spawns a new subagent via the Agent tool with `subagent_type: general-purpose`.
2. **Given** the homer loop has completed all iterations, **When** the loop reports results, **Then** it reports the number of subagent iterations spawned, not inline executions.
3. **Given** the ralph loop is running, **When** a subagent is spawned for an iteration, **Then** the prompt includes the feature directory AND quality gates command.

---

### User Story 3 - Quality Gates Use Only quality-gates.sh (Priority: P2)

A developer sets up project quality gates by editing `.specify/quality-gates.sh`. This is the only mechanism for defining quality gates. There are no CLI argument overrides (`--quality-gates`), no environment variable overrides (`QUALITY_GATES`), and no alternative resolution paths. The file is the single source of truth.

**Why this priority**: Simplifies configuration, eliminates confusion about precedence, and ensures consistent quality gate behavior regardless of how the pipeline or loops are invoked.

**Independent Test**: Can be verified by confirming that no code path reads quality gates from CLI arguments or environment variables, and that all quality gate references point exclusively to `.specify/quality-gates.sh`.

**Acceptance Scenarios**:

1. **Given** a project with `.specify/quality-gates.sh` containing valid commands, **When** the ralph loop runs, **Then** quality gates are read exclusively from `.specify/quality-gates.sh`.
2. **Given** a project where someone passes `--quality-gates "echo skip"` to `pipeline.sh`, **When** the pipeline runs, **Then** the `--quality-gates` flag is not recognized (removed from the interface).
3. **Given** a project where `QUALITY_GATES` environment variable is set, **When** the ralph loop runs, **Then** the environment variable is ignored and `.specify/quality-gates.sh` is used.
4. **Given** a project where `.specify/quality-gates.sh` does not exist, **When** the ralph loop attempts to run, **Then** the loop aborts with a clear error instructing the user to create the file.
5. **Given** a project where `.specify/quality-gates.sh` exists but contains only comments and whitespace, **When** the ralph loop (command file or bash script) attempts to run, **Then** the system aborts with a clear error instructing the user to add executable commands — quality gates do not silently pass.

---

### User Story 4 - Bash Script Fallbacks Also Spawn Subagents (Priority: P3)

A developer runs the pipeline or loops via the bash script fallback mechanism (`pipeline.sh`, `homer-loop.sh`, `lisa-loop.sh`, `ralph-loop.sh`) outside of Claude Code. Each script uses `claude --agent` CLI to spawn fresh-context subagents for every iteration.

**Why this priority**: Bash scripts are the secondary invocation path. They already use `claude --agent` but should also have quality gate consolidation applied and consistent behavior with the command file versions.

**Independent Test**: Can be verified by running `pipeline.sh` from a terminal and confirming each step/iteration invokes `claude --agent` with the correct agent file.

**Acceptance Scenarios**:

1. **Given** a developer running `pipeline.sh` from the terminal, **When** the homer step runs, **Then** it delegates to `homer-loop.sh` which uses `claude --agent homer` for each iteration.
2. **Given** `ralph-loop.sh` is invoked, **When** quality gates are resolved, **Then** they are read from `.specify/quality-gates.sh` only (no CLI arg or env var resolution).
3. **Given** `pipeline.sh` is invoked with the old `--quality-gates` flag, **When** argument parsing runs, **Then** the flag is not recognized and an error is shown.

---

### Edge Cases

- What happens when `.specify/quality-gates.sh` exists but is empty (only comments/whitespace)? The system aborts with a clear error instructing the user to add executable commands.
- What happens when `.specify/quality-gates.sh` is not executable? The system uses `bash .specify/quality-gates.sh` which does not require the execute bit, so this is a non-issue.
- What happens when a subagent crashes mid-iteration? The orchestrator catches the failure, logs context, and aborts the loop/pipeline per existing failure handling.
- What happens when a subagent exceeds the token limit? The Agent tool returns with whatever output was produced. The orchestrator treats this as a potential failure and checks for stuck detection.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The pipeline command (`speckit.pipeline.md`) MUST spawn each pipeline step as a separate subagent using the Agent tool with `subagent_type: general-purpose`
- **FR-002**: Each loop command (homer, lisa, ralph) MUST spawn each iteration as a separate subagent using the Agent tool with `subagent_type: general-purpose`
- **FR-003**: Subagent prompts MUST instruct the subagent to read and follow its corresponding agent file from `.claude/agents/` and to treat slash command references as file reads from `.claude/commands/`
- **FR-004**: All quality gate references MUST be resolved exclusively from `.specify/quality-gates.sh` — no CLI argument, no environment variable, no alternative sources
- **FR-005**: The `--quality-gates` flag MUST be removed from `pipeline.sh` argument parsing and help text
- **FR-006**: The `QUALITY_GATES` environment variable resolution MUST be removed from `pipeline.sh` and `ralph-loop.sh`
- **FR-007**: The `resolve_quality_gates()` function in bash scripts MUST be simplified to read only from `.specify/quality-gates.sh`, erroring if the file is missing or empty
- **FR-008**: The pipeline and loop command files MUST reference quality gates as `bash .specify/quality-gates.sh` without any override mechanism
- **FR-009**: The pipeline command MUST wait for each subagent to complete before spawning the next (strict sequential execution)
- **FR-010**: Each subagent prompt MUST include the feature directory path
- **FR-011**: Command files (pipeline and loop orchestrators) MUST validate that `.specify/quality-gates.sh` exists and contains non-empty executable content (not just comments/whitespace) before executing it, aborting with a clear error if validation fails — this ensures the empty-file edge case is caught on both command file and bash script invocation paths

### Key Entities

- **Pipeline Orchestrator**: The command/script that coordinates the 6-step pipeline (specify, homer, plan, tasks, lisa, ralph) and manages subagent lifecycle
- **Loop Orchestrator**: The command/script that manages iterative loops (homer, lisa, ralph) with fresh-context subagent per iteration, stuck detection, and completion checking
- **Agent File**: Markdown file in `.claude/agents/` defining single-iteration behavior for each step
- **Command File**: Markdown file in `.claude/commands/` defining orchestrator behavior for each pipeline step or loop
- **Quality Gates File**: `.specify/quality-gates.sh` — the single source of quality gate commands

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Running `/speckit.pipeline` spawns distinct subagents (via Agent tool) for 100% of pipeline steps and loop iterations — zero inline executions
- **SC-002**: Running any standalone loop command (`/speckit.homer.clarify`, `/speckit.lisa.analyze`, `/speckit.ralph.implement`) spawns a new subagent for every iteration
- **SC-003**: Zero code paths exist that read quality gates from CLI arguments or environment variables
- **SC-004**: All quality gate references across command files and bash scripts resolve to `.specify/quality-gates.sh` exclusively
- **SC-005**: A developer can set up quality gates by editing a single file (`.specify/quality-gates.sh`) with no additional configuration required
