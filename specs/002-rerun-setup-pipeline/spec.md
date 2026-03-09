# Feature Specification: Rerunnable Setup & End-to-End Pipeline

**Feature Branch**: `002-rerun-setup-pipeline`
**Created**: 2026-03-09
**Status**: Draft
**Input**: User description: "Let's update this project to support rerunning setup.sh to update a project's spec kit simpsons loops. The key thing is not wiping out the existing quality gate if it exists. Should it exist in a separate file that we never rewrite and have the various loops read the quality gate from the file? Also, let's update speckit.pipeline to support /speckit.specify so that it's a true end to end pipeline from initial spec user input to implementation."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Rerun setup.sh Without Losing Quality Gates (Priority: P1)

A project maintainer who previously installed simpsons-loops wants to update to the latest version by rerunning `setup.sh`. They have already configured project-specific quality gates (e.g., `npm run lint && npm test`). After rerunning setup.sh, their quality gate configuration remains intact while all scripts, agents, and commands are updated to the latest versions.

**Why this priority**: This is the core safety guarantee. Without it, every update risks breaking a project's CI workflow by wiping custom quality gate configuration. This directly blocks adoption of updates.

**Independent Test**: Can be tested by configuring a quality gate file, rerunning setup.sh, and verifying the quality gate file is unchanged while other files are updated.

**Acceptance Scenarios**:

1. **Given** a project with simpsons-loops installed and a quality gate file containing `npm run lint && npm test`, **When** the maintainer reruns `setup.sh`, **Then** all loop scripts, agents, and commands are updated to latest versions AND the quality gate file remains unchanged.
2. **Given** a project with simpsons-loops installed but NO quality gate file AND custom quality gates exist in the Ralph command file, **When** the maintainer reruns `setup.sh`, **Then** the existing quality gates are extracted from the command file and written to the new quality gate file.
3. **Given** a project with simpsons-loops installed but NO quality gate file AND the Ralph command file still contains the default placeholder, **When** the maintainer reruns `setup.sh`, **Then** a new quality gate file is created with placeholder content instructing the user to configure it.
4. **Given** a project where setup.sh is run for the first time, **When** setup completes, **Then** a quality gate file with placeholder content is created alongside all other artifacts.

---

### User Story 2 - Quality Gates Read from Dedicated File (Priority: P1)

A project maintainer configures their quality gates once in a dedicated file. All loop scripts (Ralph, pipeline) automatically read quality gates from this file instead of requiring them as CLI arguments or environment variables. The file serves as the single source of truth for quality gate configuration.

**Why this priority**: This is tightly coupled with Story 1 — the dedicated file is the mechanism that enables safe re-runs. It also simplifies the developer experience by eliminating the need to pass quality gates on every invocation.

**Independent Test**: Can be tested by writing a quality gate file, running the pipeline or Ralph loop, and verifying the quality gates from the file are executed.

**Acceptance Scenarios**:

1. **Given** a quality gate file containing `shellcheck *.sh`, **When** Ralph loop executes, **Then** Ralph reads and executes the quality gates from the file.
2. **Given** a quality gate file exists AND a `--quality-gates` CLI argument is provided, **When** the pipeline runs, **Then** the CLI argument takes precedence over the file (explicit override).
3. **Given** a quality gate file exists AND the `QUALITY_GATES` environment variable is set, **When** the pipeline runs, **Then** the environment variable takes precedence over the file (explicit override).
4. **Given** no quality gate file exists and no CLI/env override is provided, **When** the pipeline runs, **Then** the pipeline exits with an error instructing the user to create the quality gate file or pass quality gates explicitly.

---

### User Story 3 - End-to-End Pipeline from Spec to Implementation (Priority: P2)

A developer starting a new feature wants to go from an initial feature description all the way through to implementation using a single pipeline command. The pipeline now includes `/speckit.specify` as its first step, creating the spec from a feature description before proceeding through clarification, planning, task generation, analysis, and implementation.

**Why this priority**: This completes the pipeline vision by closing the gap between "I have an idea" and "the pipeline runs." Currently users must manually run `/speckit.specify` before invoking the pipeline. Adding it as an optional first step makes the workflow seamless.

**Independent Test**: Can be tested by invoking the pipeline with a feature description and verifying it creates a spec, runs Homer, generates a plan, generates tasks, runs Lisa, and runs Ralph in sequence.

**Acceptance Scenarios**:

1. **Given** a feature description provided as input, **When** the pipeline is invoked with the specify step enabled, **Then** the pipeline creates a spec from the description, then proceeds through all subsequent steps (Homer, Plan, Tasks, Lisa, Ralph).
2. **Given** a spec already exists, **When** the pipeline is invoked, **Then** the specify step is skipped (existing behavior preserved) and the pipeline starts from Homer or the appropriate step.
3. **Given** the pipeline is invoked with `--from specify`, **When** the pipeline runs, **Then** it starts from the specify step regardless of existing artifacts.

---

### User Story 4 - Existing Projects Migrate Quality Gates to File (Priority: P3)

A project maintainer who previously configured quality gates via environment variable or CLI argument wants to migrate to the file-based approach. The setup or documentation guides them through creating the quality gate file from their existing configuration.

**Why this priority**: Provides a smooth migration path for existing users. Lower priority because existing mechanisms (env var, CLI) continue to work as overrides.

**Independent Test**: Can be tested by verifying that a project with `QUALITY_GATES` env var set can create the file and subsequently run without the env var.

**Acceptance Scenarios**:

1. **Given** a project using `QUALITY_GATES` env var, **When** the maintainer creates the quality gate file with the same content, **Then** subsequent pipeline runs work without the env var.

---

### Edge Cases

- What happens when the quality gate file exists but is empty? The system treats it as "no quality gates configured" and exits with an error prompting the user to add content.
- What happens when the quality gate file contains only comments? The system strips comments and whitespace; if nothing executable remains, it treats it as empty.
- What happens when setup.sh is interrupted mid-run? Since the quality gate file is never overwritten, partial runs cannot corrupt it. Other files being overwritten mid-copy are acceptable since they'll be correct on the next successful run.
- What happens when the quality gate file has a syntax error? The quality gate commands are executed as-is; shell errors propagate naturally and fail the quality gate check, which is the correct behavior.
- What happens when the pipeline is invoked with `--from specify` but no feature description is provided? The pipeline exits with an error requesting a feature description.
- What happens when the specify step fails mid-pipeline? The pipeline halts immediately with a clear error message and non-zero exit code. The user can fix the issue and re-invoke with `--from specify` to retry from that step.

## Out of Scope

The following are explicitly excluded from this feature:

- **Multi-project / shared quality gate configurations** — each project maintains its own `.specify/quality-gates.sh`; shared or inherited quality gate files across repositories are not supported.
- **Remote quality gate sources** — quality gates are always read from the local filesystem; fetching from URLs, git submodules, or remote registries is not supported.
- **Quality gate file format versioning or migration** — the file is a plain shell script with no schema version; format evolution (if needed) is a future concern.
- **GUI or web interface for quality gate management** — configuration is file-based and CLI-driven only.
- **Quality gate dependency resolution or ordering** — commands in the quality gate file are executed sequentially as written; the system does not analyze dependencies between gate commands.
- **Parallel or conditional quality gate execution** — all gates run linearly; conditional logic must be expressed by the user within the shell script itself.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST store quality gate configuration in a dedicated file at a well-known path within the project (`.specify/quality-gates.sh`).
- **FR-002**: `setup.sh` MUST NOT overwrite the quality gate file if it already exists when rerun.
- **FR-003**: `setup.sh` MUST create the quality gate file with placeholder content on first installation (when the file does not exist and no existing quality gates are found in command files). Placeholder content is defined by FR-015.
- **FR-012**: `setup.sh` MUST detect existing quality gates embedded in the Ralph command file (`speckit.ralph.implement.md`) during re-run and extract them to the quality gate file if no quality gate file exists yet.
- **FR-013**: `setup.sh` MUST distinguish between the default placeholder quality gate and a custom user-configured quality gate using the sentinel comment mechanism defined in FR-016; only custom gates are extracted (placeholder results in a new placeholder file).
- **FR-014**: The Ralph command template MUST replace the inline quality gate code block with a reference to `.specify/quality-gates.sh`, keeping the "Extract Quality Gates" section for visibility while centralizing configuration in the file.
- **FR-004**: All loop scripts (`ralph-loop.sh`, `pipeline.sh`) MUST read quality gates from the dedicated file when no CLI argument or environment variable override is provided.
- **FR-005**: CLI arguments (`--quality-gates`) and environment variables (`QUALITY_GATES`) MUST take precedence over the quality gate file when provided.
- **FR-006**: The pipeline MUST support a "specify" step as an optional first stage that creates a spec from a feature description, operating non-interactively (auto-resolving clarifications with best guesses; Homer refines gaps afterward).
- **FR-007**: The pipeline MUST skip the specify step if a spec already exists (unless explicitly requested via `--from specify`).
- **FR-008**: The pipeline MUST accept a feature description as input when the specify step is included.
- **FR-009**: The quality gate file MUST be executable as a shell script (sourced or executed by the loop scripts).
- **FR-010**: `setup.sh` MUST continue to overwrite all other artifacts (scripts, agents, commands) on re-run to enable updates.
- **FR-011**: The system MUST exit with a clear error message and non-zero exit code when no quality gates are configured (no file, no env var, no CLI arg).
- **FR-015**: The quality gate placeholder file MUST contain a commented shell script with usage instructions, an example command, and an `exit 1` statement so that the placeholder fails the quality gate check until the user configures it.
- **FR-016**: `setup.sh` MUST detect the default placeholder in the Ralph command file by pattern-matching a sentinel comment (`# SPECKIT_DEFAULT_QUALITY_GATE`); presence of the sentinel means unconfigured (create placeholder file), absence means custom (extract to quality gate file).
- **FR-017**: `setup.sh` MUST create the quality gate file with executable permissions (`chmod +x`).
- **FR-018**: If the specify step fails during the pipeline, the pipeline MUST halt immediately with a clear error message and non-zero exit code; the user can re-invoke with `--from specify` to retry.

### Non-Functional Requirements

- **NFR-001**: `setup.sh` MUST be idempotent — running it multiple times in succession produces the same result as running it once, with no cumulative side effects.
- **NFR-002**: All error conditions MUST produce a clear, actionable error message and exit with a non-zero exit code.
- **NFR-003**: The quality gate file MUST never be partially written or corrupted; `setup.sh` writes it atomically (write to temp file, then move) or skips it entirely if it already exists.

### Key Entities

- **Quality Gate File** (`.specify/quality-gates.sh`): A shell script containing the project's quality gate commands. Created once by setup.sh with placeholder content, never overwritten on subsequent runs. Read by loop scripts as the default quality gate source. Precedence order: CLI arg > env var > file.
- **Pipeline Step "specify"**: A new optional first step in the pipeline that invokes the specify workflow to create a feature spec from a natural language description. Skipped when a spec already exists unless explicitly requested.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: After rerunning setup.sh, 100% of previously configured quality gate content is preserved unchanged.
- **SC-002**: A new installation creates all required files including the quality gate placeholder in a single setup.sh run.
- **SC-003**: Loop scripts successfully read and execute quality gates from the dedicated file without requiring CLI arguments or environment variables.
- **SC-004**: The full pipeline can take a feature from natural language description to completed implementation without manual intermediate steps.
- **SC-005**: Existing projects using environment variable or CLI-based quality gates continue to work without modification (backward compatibility).

## Clarifications

### Session 2026-03-09

- Q: After migration to file-based quality gates, should the Ralph command template still contain an inline quality gate section? → A: Keep the section but replace the inline code block with a reference to `.specify/quality-gates.sh`, preserving visibility while centralizing configuration.
- Q: When the specify step runs as part of the pipeline, should it operate interactively or non-interactively? → A: Non-interactive; auto-resolve all clarifications with best guesses. Homer loop refines gaps afterward.
- Q: What is explicitly out of scope for this feature? → A: Multi-project/shared quality gates, remote quality gate sources, file format versioning, GUI management, dependency resolution/ordering between gate commands, and parallel/conditional gate execution.
- Q: Should the spec include measurable non-functional requirements for setup.sh and pipeline operations? → A: Yes, add minimal practical NFRs: idempotency guarantee for setup.sh, clear error messages with non-zero exit codes on failure, and no partial corruption of the quality gate file.
- Q: What should happen if the specify step fails during the pipeline? → A: Pipeline halts with a clear error message; the user can fix the issue and re-invoke with `--from specify`.
- Q: What should the quality gate placeholder file contain? → A: A commented shell script with instructions, an example command, and an `exit 1` so the placeholder fails the quality gate check until the user configures it.
- Q: How does setup.sh distinguish custom quality gates from the default placeholder in the Ralph command file? → A: Pattern match against a known sentinel comment (`# SPECKIT_DEFAULT_QUALITY_GATE`); if the sentinel is present, treat as unconfigured (create placeholder file); if absent, treat as custom (extract to file).
- Q: Should the quality gate file be created with executable permissions? → A: Yes, `setup.sh` creates the file with executable permissions (`chmod +x`) since FR-009 requires it to be executable as a shell script.

## Assumptions

- The quality gate file path `.specify/quality-gates.sh` is appropriate and does not conflict with existing project conventions.
- Quality gates are always expressible as shell commands (consistent with current behavior).
- The "specify" pipeline step will invoke the same logic as `/speckit.specify` but in non-interactive mode: all clarifications are auto-resolved with best guesses, and the Homer loop handles refinement afterward.
- Projects using this framework have `bash` available (consistent with existing setup.sh requirements).
