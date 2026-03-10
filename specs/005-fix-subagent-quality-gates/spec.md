# Feature Specification: Fix Subagent Delegation and Quality Gate Consolidation

**Feature Branch**: `005-fix-subagent-quality-gates`
**Created**: 2026-03-10
**Status**: Draft
**Input**: User description: "can we make quality-gates.sh the only option for accessing quality gates? Also why is the pipeline not kicking off claude subagents? Can we ensure that and all the loops are actually kicking off sub agents?"

## Clarifications

### Session 2026-03-10

- Q: Should command files validate that `.specify/quality-gates.sh` is non-empty before executing it, given that `bash` on an empty file silently exits 0? → A: Yes — command files must validate existence and non-empty content, aborting with a clear error if the file is missing or contains only comments/whitespace. This aligns command file behavior with the bash script `resolve_quality_gates()` function and the stated edge case.
- Q: Should the 30-iteration default for homer and lisa apply uniformly across all three invocation paths (standalone commands, pipeline, bash scripts)? → A: Yes — uniform 30 for standalone commands, pipeline, AND bash scripts.
- Q: Should ralph's iteration default also be standardized across invocation paths? → A: Yes — keep `incomplete_tasks + 10` for commands, bump bash script default from 5 to 30.
- Q: Should stuck detection threshold be standardized across commands and bash scripts? → A: Yes — standardize at 2 consecutive stuck iterations for both commands and bash scripts.
- Q: What level of detail should the mermaid diagrams convey? → A: Two diagrams — one for the pipeline flow showing sequential steps and subagent spawning, one for the standalone loop iteration lifecycle.
- Q: Should the README update also restructure sections beyond fixing stale content? → A: Yes — fix stale content, add diagrams, consolidate the quality gates section to reflect single-file-only, and add a new "Architecture" top-level section for the diagrams.
- Q: Should the bash script fallbacks (`pipeline.sh`, `homer-loop.sh`, `lisa-loop.sh`, `ralph-loop.sh`) be kept, removed, or frozen? → A: Remove entirely — this project is about Claude Code and SpecKit; bash scripts are dead weight that creates maintenance drift risk across 8 duplicate file pairs.
- Q: Should root-level command file copies also be removed? → A: No — root-level files are the **source** files; `.claude/` and `.specify/` directories are installed copies managed by `setup.sh`. Edits go to root-level source files, and `setup.sh` propagates to installed locations. Do not modify `.claude/` or `.specify/` contents directly.
- Q: Do agent files need content changes, and should the source directories be reorganized? → A: No content changes to agent files. Reorganize source directories: `agents/` → `claude-agents/`, root-level `speckit.*.md` files → `speckit-commands/` directory. Update `setup.sh` to install from new source locations.
- Q: To enable homer right after specify (without plan.md/tasks.md), should the prerequisite script be refactored or should homer handle its own validation? → A: Homer switches to `--json --paths-only` and validates spec.md itself; the prerequisite script stays unchanged.
- Q: Should quality gate validation (FR-010) apply to all loop commands or only ralph? → A: Only ralph (and the pipeline's ralph phase) validates quality-gates.sh; homer and lisa skip it entirely.
- Q: Should `setup.sh` also clean up previously-installed bash script copies at `.specify/scripts/bash/` and their permissions in `.claude/settings.local.json` when run on existing installations? → A: Yes — `setup.sh` must remove previously-installed bash loop scripts from `.specify/scripts/bash/` and remove their corresponding permissions entries from `.claude/settings.local.json` to prevent orphaned artifacts and stale configuration.

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
4. **Given** a feature branch with only `spec.md` (no `plan.md` or `tasks.md`), **When** the user runs `/speckit.homer.clarify`, **Then** the homer loop starts successfully and spawns subagents — it does not require plan or tasks artifacts.

---

### User Story 3 - Quality Gates Use Only quality-gates.sh (Priority: P2)

A developer sets up project quality gates by editing `.specify/quality-gates.sh`. This is the only mechanism for defining quality gates. There are no CLI argument overrides (`--quality-gates`), no environment variable overrides (`QUALITY_GATES`), and no alternative resolution paths. The file is the single source of truth.

**Why this priority**: Simplifies configuration, eliminates confusion about precedence, and ensures consistent quality gate behavior regardless of how the pipeline or loops are invoked.

**Independent Test**: Can be verified by confirming that no code path reads quality gates from CLI arguments or environment variables, and that all quality gate references point exclusively to `.specify/quality-gates.sh`.

**Acceptance Scenarios**:

1. **Given** a project with `.specify/quality-gates.sh` containing valid commands, **When** the ralph loop runs, **Then** quality gates are read exclusively from `.specify/quality-gates.sh`.
2. **Given** a project where `.specify/quality-gates.sh` does not exist, **When** the ralph loop attempts to run, **Then** the loop aborts with a clear error instructing the user to create the file.
3. **Given** a project where `.specify/quality-gates.sh` exists but contains only comments and whitespace, **When** the ralph loop command file attempts to run, **Then** the system aborts with a clear error instructing the user to add executable commands — quality gates do not silently pass.

---

### User Story 4 - Bash Script Fallbacks Removed (Priority: P2)

The bash script fallback mechanism (`pipeline.sh`, `homer-loop.sh`, `lisa-loop.sh`, `ralph-loop.sh`) is deleted from the root-level source files, and `setup.sh` is updated to stop installing them. The project's sole invocation path is Claude Code command files. The README is updated to remove all bash script documentation.

**Why this priority**: Bash scripts are a secondary invocation path that creates maintenance drift risk. Since this project is designed for Claude Code and SpecKit, the scripts are dead weight.

**Independent Test**: Can be verified by confirming that `pipeline.sh`, `homer-loop.sh`, `lisa-loop.sh`, and `ralph-loop.sh` do not exist at root level and `setup.sh` no longer references them.

**Acceptance Scenarios**:

1. **Given** the repository after implementation, **When** a developer searches for `pipeline.sh`, `homer-loop.sh`, `lisa-loop.sh`, or `ralph-loop.sh`, **Then** none of these files exist at root level.
2. **Given** the `setup.sh` script, **When** it runs, **Then** it does not copy or install any loop bash scripts.
3. **Given** a project that previously had bash loop scripts installed at `.specify/scripts/bash/`, **When** `setup.sh` runs, **Then** it removes `pipeline.sh`, `homer-loop.sh`, `lisa-loop.sh`, and `ralph-loop.sh` from `.specify/scripts/bash/` and removes their corresponding permissions entries from `.claude/settings.local.json`.
4. **Given** the updated README, **When** a developer reads the documentation, **Then** there are no references to bash script invocation, `pipeline.sh`, or the loop `.sh` scripts.

---

### User Story 5 - README Reflects Architecture and Configuration Changes (Priority: P2)

A developer reads the project README to understand how the pipeline and loops work. The README accurately reflects the current architecture: Claude Code command files as the sole invocation path, subagent delegation pattern, quality gates sourced exclusively from `.specify/quality-gates.sh`, updated iteration defaults, and stuck detection threshold. A new "Architecture" section contains two mermaid diagrams — one showing the pipeline's sequential flow with subagent spawning per step/iteration, and one showing the standalone loop iteration lifecycle. All bash script documentation is removed.

**Why this priority**: Documentation that contradicts the implementation causes confusion and support burden. The README currently documents removed features (`--quality-gates` flag, `QUALITY_GATES` env var, bash script invocation) and incorrect defaults (20 iterations, 3 stuck threshold). Equal priority to the quality gates fix since both affect developer experience.

**Independent Test**: Can be verified by reading the README and confirming: no references to `--quality-gates` flag, `QUALITY_GATES` env var, or bash script invocation; iteration defaults show 30 for homer/lisa; stuck detection says 2; mermaid diagrams render correctly; and a new "Architecture" section exists with two diagrams.

**Acceptance Scenarios**:

1. **Given** the updated README, **When** a developer reads the documentation, **Then** there are no references to `pipeline.sh`, `homer-loop.sh`, `lisa-loop.sh`, `ralph-loop.sh`, or bash script invocation.
2. **Given** the updated README, **When** a developer reads the "How the loops work" section, **Then** stuck detection says "two consecutive iterations" (not three).
3. **Given** the updated README, **When** a developer reads the "Customization > Quality gates" section, **Then** it documents `.specify/quality-gates.sh` as the single source with no mention of `QUALITY_GATES` env var override.
4. **Given** the updated README, **When** a developer views the "Architecture" section, **Then** two mermaid diagrams render: one for pipeline flow (specify → homer loop → plan → tasks → lisa loop → ralph loop, each spawning subagents), one for standalone loop lifecycle (orchestrator → spawn subagent → check completion/stuck → next iteration or exit).
5. **Given** the updated README, **When** a developer reads the max iterations table, **Then** homer and lisa show 30, ralph shows `incomplete_tasks + 10`.

---

### Edge Cases

- What happens when `.specify/quality-gates.sh` exists but is empty (only comments/whitespace)? The system aborts with a clear error instructing the user to add executable commands.
- What happens when `.specify/quality-gates.sh` is not executable? The system uses `bash .specify/quality-gates.sh` which does not require the execute bit, so this is a non-issue.
- What happens when a subagent crashes mid-iteration? The orchestrator catches the failure, logs context, and aborts the loop/pipeline per existing failure handling.
- What happens when a subagent exceeds the token limit? The Agent tool returns with whatever output was produced. The orchestrator treats this as a potential failure and checks for stuck detection.
- What happens when a loop hits max iterations without completing? The orchestrator reports "max iterations reached" with the count, remaining items, and suggests re-running if needed.
- What is the stuck detection threshold? 2 consecutive iterations with no file changes and no completion signal triggers stuck abort.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The pipeline command (`speckit.pipeline.md`) MUST spawn each pipeline step as a separate subagent using the Agent tool with `subagent_type: general-purpose`
- **FR-002**: Each loop command (homer, lisa, ralph) MUST spawn each iteration as a separate subagent using the Agent tool with `subagent_type: general-purpose`
- **FR-003**: Subagent prompts MUST instruct the subagent to read and follow its corresponding agent file from `.claude/agents/` and to treat slash command references as file reads from `.claude/commands/`
- **FR-004**: All quality gate references MUST be resolved exclusively from `.specify/quality-gates.sh` — no CLI argument, no environment variable, no alternative sources
- **FR-005**: The bash script fallbacks (`pipeline.sh`, `homer-loop.sh`, `lisa-loop.sh`, `ralph-loop.sh`) MUST be deleted from the root level. The `setup.sh` script MUST be updated to stop installing these files AND MUST remove previously-installed copies from `.specify/scripts/bash/` and their corresponding permissions entries from `.claude/settings.local.json` when run on existing installations
- **FR-006**: Source directories MUST be reorganized: `agents/` renamed to `claude-agents/`, root-level `speckit.*.md` command files moved into a new `speckit-commands/` directory. All command file edits MUST target files in `speckit-commands/`. `setup.sh` MUST be updated to install from the new source locations (`claude-agents/` → `.claude/agents/`, `speckit-commands/` → `.claude/commands/`)
- **FR-007**: The ralph command file and the pipeline's ralph phase MUST reference quality gates as `bash .specify/quality-gates.sh` without any override mechanism
- **FR-008**: The pipeline command MUST wait for each subagent to complete before spawning the next (strict sequential execution)
- **FR-009**: Each subagent prompt MUST include the feature directory path
- **FR-010**: The ralph command file and the pipeline's ralph phase MUST validate that `.specify/quality-gates.sh` exists and contains non-empty executable content (not just comments/whitespace) before executing it, aborting with a clear error if validation fails. Homer and lisa MUST NOT validate quality gates
- **FR-011**: Default max iterations for homer and lisa MUST be 30 across standalone commands and pipeline orchestrator
- **FR-012**: Default max iterations for ralph MUST be `incomplete_tasks + 10` for command files
- **FR-013**: Stuck detection MUST trigger after 2 consecutive iterations with no file changes and no completion signal
- **FR-014**: The README MUST be updated to remove all references to bash script invocation, `--quality-gates` CLI flag, and `QUALITY_GATES` environment variable
- **FR-015**: The README MUST be updated to reflect iteration defaults of 30 for homer/lisa and `incomplete_tasks + 10` for ralph
- **FR-016**: The README MUST contain a new "Architecture" section with two mermaid diagrams: (1) pipeline flow showing sequential steps with subagent spawning per step/iteration, (2) standalone loop iteration lifecycle showing orchestrator → subagent → completion/stuck check → next iteration or exit
- **FR-017**: The README "Customization > Quality gates" section MUST be consolidated to document `.specify/quality-gates.sh` as the single source of truth with no override mechanisms
- **FR-018**: The README stuck detection description MUST state "two consecutive iterations" (not three)
- **FR-019**: The homer loop command MUST use `check-prerequisites.sh --json --paths-only` for feature directory resolution and MUST validate only that `spec.md` exists in the feature directory — it MUST NOT require `plan.md` or `tasks.md`
- **FR-020**: The homer loop MUST be runnable immediately after `/speckit.specify` without requiring `/speckit.plan` or `/speckit.tasks` to have been run first

### Key Entities

- **Pipeline Orchestrator**: The command file (`speckit-commands/speckit.pipeline.md`) that coordinates the 6-step pipeline (specify, homer, plan, tasks, lisa, ralph) and manages subagent lifecycle
- **Loop Orchestrator**: The command file (`speckit-commands/speckit.{homer.clarify,lisa.analyze,ralph.implement}.md`) that manages iterative loops with fresh-context subagent per iteration, stuck detection, and completion checking
- **Agent File**: Markdown source file in `claude-agents/` (e.g., `homer.md`), installed to `.claude/agents/` by `setup.sh`. Defines single-iteration behavior for each step
- **Command File**: Markdown source file in `speckit-commands/` (e.g., `speckit.pipeline.md`), installed to `.claude/commands/` by `setup.sh`
- **Quality Gates File**: `.specify/quality-gates.sh` — the single source of quality gate commands
- **Setup Script**: `setup.sh` — installs source files from `claude-agents/` and `speckit-commands/` into `.claude/agents/` and `.claude/commands/` respectively

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Running `/speckit.pipeline` spawns distinct subagents (via Agent tool) for 100% of pipeline steps and loop iterations — zero inline executions
- **SC-002**: Running any standalone loop command (`/speckit.homer.clarify`, `/speckit.lisa.analyze`, `/speckit.ralph.implement`) spawns a new subagent for every iteration
- **SC-003**: Zero code paths exist that read quality gates from CLI arguments or environment variables
- **SC-004**: All quality gate references in command files resolve to `.specify/quality-gates.sh` exclusively
- **SC-005**: A developer can set up quality gates by editing a single file (`.specify/quality-gates.sh`) with no additional configuration required
- **SC-006**: Bash script fallbacks (`pipeline.sh`, `homer-loop.sh`, `lisa-loop.sh`, `ralph-loop.sh`) do not exist at root level, `setup.sh` no longer installs them, and `setup.sh` removes previously-installed copies from `.specify/scripts/bash/` and their permissions from `.claude/settings.local.json`
- **SC-007**: Source directories are reorganized: `claude-agents/` contains agent source files, `speckit-commands/` contains command source files. Old `agents/` directory and root-level `speckit.*.md` files no longer exist
- **SC-008**: `setup.sh` installs from `claude-agents/` → `.claude/agents/` and `speckit-commands/` → `.claude/commands/`
- **SC-009**: Homer and lisa default max iterations are 30 (standalone commands and pipeline)
- **SC-010**: Ralph command files use `incomplete_tasks + 10` for max iterations
- **SC-011**: Stuck detection threshold is 2 consecutive iterations
- **SC-012**: README contains zero references to `--quality-gates` flag, `QUALITY_GATES` environment variable, or bash script invocation
- **SC-013**: README "Architecture" section contains two renderable mermaid diagrams covering pipeline flow and standalone loop lifecycle
- **SC-014**: README max iterations table reflects the updated defaults (30 for homer/lisa, `incomplete_tasks + 10` for ralph)
- **SC-015**: Homer loop runs successfully on a feature with only `spec.md` — no `plan.md` or `tasks.md` required
- **SC-016**: Quality gate validation occurs only in the ralph command file and pipeline's ralph phase — homer and lisa do not validate or reference quality gates
