# Feature Specification: Repository Consistency Cleanup

**Feature Branch**: `001-consistency-cleanup`
**Created**: 2026-03-01
**Status**: Draft
**Input**: User description: "Review all of the changes and clean up everything so that it is consistent with itself and we can begin using speckit to improve this repo."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Accurate README Documentation (Priority: P1)

A contributor clones the repo and follows the README to install Simpsons Loops into their project. Every file path, command, and instruction in the README matches actual files in the repository. No references to non-existent files. No outdated instructions from a prior architecture.

**Why this priority**: If the README doesn't match reality, users cannot onboard. This is the primary entry point for adoption.

**Independent Test**: A new user can follow every instruction in the README (both automated and manual setup) and successfully install and run the loops without hitting missing files or incorrect paths.

**Acceptance Scenarios**:

1. **Given** the README references prompt template files (`ralph-prompt.template.md`, `lisa-prompt.template.md`, `homer-prompt.template.md`), **When** a user looks for those files in the repo, **Then** those references have been removed or updated to reflect the current agent-based architecture
2. **Given** the README's manual setup section lists files to copy, **When** a user follows those instructions, **Then** every listed source file exists and every destination path is correct
3. **Given** the README describes usage commands and their output, **When** a user runs those commands, **Then** the behavior matches the documentation

---

### User Story 2 - Correct .gitignore for Source Repo (Priority: P1)

A contributor working on this source repo can commit and track all essential project files. The `.gitignore` does not exclude the repo's own core files (`.specify/`, `.claude/commands/`, `.claude/agents/`) while still properly ignoring runtime-generated temp files.

**Why this priority**: The current `.gitignore` is written for a target project that installs speckit, not for this source repo. It excludes the repo's own core directories, which could cause file loss or confusion.

**Independent Test**: Run `git status` after modifying any file in `.specify/`, `.claude/commands/`, or `.claude/agents/` and confirm git tracks the changes.

**Acceptance Scenarios**:

1. **Given** the `.gitignore` currently excludes `.specify/`, `.claude/commands/`, and `.claude/agents/`, **When** the cleanup is applied, **Then** the `.gitignore` tracks those directories while still ignoring runtime temp files (loop state files, logs)
2. **Given** a separate `gitignore` template file exists (without the dot), **When** the cleanup is applied, **Then** the template file is clearly distinguished from the repo's own `.gitignore` (e.g., renamed or moved to `.specify/templates/`)

---

### User Story 3 - Consistent File Organization (Priority: P2)

A contributor navigating the repo can easily understand where each type of file lives. Agent definitions, loop commands, shell scripts, and templates each have a single canonical location. Symlinks (if used) point in a consistent direction and are clearly intentional.

**Why this priority**: Currently, agent files live in root `agents/` with symlinks in `.claude/agents/`, loop commands live at root with symlinks in `.claude/commands/`, but other commands live directly in `.claude/commands/`. This mixed pattern makes the project harder to understand and maintain.

**Independent Test**: Every file type (agents, commands, scripts, templates) has a single source-of-truth location. A contributor can identify where to edit any file without confusion about which copy is canonical.

**Acceptance Scenarios**:

1. **Given** agent definition files currently live in root `agents/` with symlinks in `.claude/agents/`, **When** the cleanup is applied, **Then** all agent files follow a single, consistent organizational pattern
2. **Given** four loop command files live at root with symlinks in `.claude/commands/` while other commands live directly in `.claude/commands/`, **When** the cleanup is applied, **Then** all commands follow one consistent pattern
3. **Given** setup.sh copies files from root-level locations to `.specify/scripts/bash/` in target projects, **When** the cleanup is applied, **Then** setup.sh file references remain correct for wherever the source files actually live

---

### User Story 4 - Self-Describing Project for Claude Code (Priority: P3)

A developer opening this repo with Claude Code gets immediate context about the project's purpose, structure, and conventions via a CLAUDE.md file at the project root. This enables effective use of speckit workflows on the repo itself.

**Why this priority**: Without a CLAUDE.md, Claude Code has no persistent project context. Adding one enables the repo to dogfood its own speckit tooling effectively.

**Independent Test**: Opening the repo in Claude Code and asking about the project structure yields accurate, helpful responses informed by CLAUDE.md.

**Acceptance Scenarios**:

1. **Given** no CLAUDE.md exists, **When** the cleanup is applied, **Then** a CLAUDE.md exists at the repo root describing the project purpose, structure, and key conventions
2. **Given** the CLAUDE.md exists, **When** a developer uses Claude Code on this repo, **Then** Claude Code understands the project layout and can navigate it effectively

---

### Edge Cases

- What happens if setup.sh is run on a project that already has an older version of simpsons loops installed? (Currently handled: gitignore marker check, permissions merge)
- What happens if symlinks are broken after file reorganization? All symlinks must be verified or replaced during cleanup.
- What if external projects have already installed using the current file layout? setup.sh must remain compatible or be updated alongside the reorganization.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: README MUST accurately describe the current architecture (agent-based, not prompt-template-based) with no references to non-existent files
- **FR-002**: README manual setup section MUST list only files that exist in the repository with correct source and destination paths
- **FR-003**: `.gitignore` MUST track the repo's own core files (`.specify/`, `.claude/commands/`, `.claude/agents/`) while ignoring runtime-generated files (loop state, logs, temp prompts)
- **FR-004**: The `gitignore` template (used by setup.sh for target projects) MUST be clearly separated from the repo's own `.gitignore`
- **FR-005**: All agent definition files MUST have a single canonical location with no conflicting duplicates
- **FR-006**: All command files MUST follow one consistent organizational pattern
- **FR-007**: setup.sh MUST correctly reference all source files after any reorganization
- **FR-008**: All symlinks MUST be valid and point to existing files after cleanup
- **FR-009**: A CLAUDE.md MUST exist at the project root providing project context for Claude Code

### Key Entities

- **Source files**: Shell scripts, agent definitions, command definitions, and templates that constitute the simpsons-loops distribution
- **Target project files**: The copies/installations created by setup.sh in a user's project
- **Gitignore template**: The template appended to a target project's `.gitignore` during setup (currently the root `gitignore` file without dot)
- **Symlinks**: Filesystem links in `.claude/agents/` and `.claude/commands/` pointing to canonical file locations

## Assumptions

- The repo is the **source distribution** of simpsons-loops, not a target project. The `.gitignore` should reflect this role.
- The prompt-template architecture (`*-prompt.template.md` files) has been fully replaced by the agent-based architecture (`claude --agent`). All references to prompt templates are stale.
- setup.sh is the primary installation mechanism and must remain functional after any file reorganization.
- Existing users who have already installed simpsons-loops do not need migration support — they can re-run setup.sh.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of file paths referenced in the README correspond to actual files in the repository
- **SC-002**: A new contributor can complete the automated setup (setup.sh) on a fresh target project without encountering any missing file errors
- **SC-003**: A new contributor can complete the manual setup following README instructions without encountering any missing file or incorrect path errors
- **SC-004**: All files in `.specify/`, `.claude/commands/`, and `.claude/agents/` are tracked by git (not excluded by `.gitignore`)
- **SC-005**: Every symlink in the repository resolves to an existing file
- **SC-006**: A CLAUDE.md file exists at the project root and accurately describes the project
