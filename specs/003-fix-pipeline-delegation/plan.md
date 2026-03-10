# Implementation Plan: Fix Pipeline and Loop Command Delegation

**Branch**: `003-fix-pipeline-delegation` | **Date**: 2026-03-09 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/003-fix-pipeline-delegation/spec.md`

## Summary

Rewrite 4 orchestrator slash commands (`/speckit.pipeline`, `/speckit.homer.clarify`, `/speckit.lisa.analyze`, `/speckit.ralph.implement`) to use a hybrid architecture: Agent tool sub-agents for loop orchestration (one per iteration) and Bash tool calls for deterministic operations (feature dir resolution via `check-prerequisites.sh`, stuck detection, quality gates). The current commands already implement this pattern correctly in the `.claude/commands/` copies but the repo root copies may be out of sync, and all 3 locations (repo root, `.claude/commands/`, global `~/.openclaw/.claude/commands/`) must be byte-identical.

## Technical Context

**Language/Version**: Bash 4+ (shell scripts), Markdown (Claude Code command files)
**Primary Dependencies**: Claude CLI (`claude` command), Claude Code Agent tool, Bash tool
**Storage**: Filesystem only -- `.md` command files, `.sh` scripts
**Testing**: Manual invocation of slash commands; `diff` across file copies for sync verification; `shellcheck` for bash scripts
**Target Platform**: Linux/macOS with Claude Code CLI installed
**Project Type**: CLI tooling / developer workflow automation
**Performance Goals**: N/A -- human-interactive workflow
**Constraints**: Agent tool sub-agents have no fixed timeout; individual Bash tool calls have 10-minute (600s) limit
**Scale/Scope**: 4 command files, each existing in 3 locations (12 files total)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Readability First | PASS | Command files use clear markdown structure with meaningful section headers |
| II. Functional Design | PASS | Each command is a deterministic orchestration sequence; bash utilities are pure input/output |
| III. Maintainability Over Cleverness | PASS | Unified orchestration pattern across all 4 commands; no clever tricks |
| IV. Best Practices | PASS | Follows Claude Code command file conventions; bash scripts use `set -e`, `set -u`, `set -o pipefail` |
| V. Simplicity (KISS & YAGNI) | PASS | Only modifying the 4 orchestrator commands; no new infrastructure |
| Test-First Development | N/A | No unit-testable code being written; changes are markdown command files and file sync operations |
| Quality Gates | PASS | `shellcheck` for bash scripts; `diff` for file sync verification |
| Spec & Branch Naming | PASS | `003-fix-pipeline-delegation` follows `XXXX-type-description` pattern |

No violations. No complexity tracking needed.

## Project Structure

### Documentation (this feature)

```text
specs/003-fix-pipeline-delegation/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
└── tasks.md             # Phase 2 output (created by /speckit.tasks)
```

### Source Code (repository root)

```text
# Orchestrator command files (in-scope, 3 locations each)
speckit.pipeline.md                              # Repo root (upstream)
speckit.homer.clarify.md                         # Repo root (upstream)
speckit.lisa.analyze.md                          # Repo root (upstream)
speckit.ralph.implement.md                       # Repo root (upstream)

.claude/commands/speckit.pipeline.md             # Local project copy
.claude/commands/speckit.homer.clarify.md        # Local project copy
.claude/commands/speckit.lisa.analyze.md         # Local project copy
.claude/commands/speckit.ralph.implement.md      # Local project copy

~/.openclaw/.claude/commands/speckit.pipeline.md      # Global installed copy
~/.openclaw/.claude/commands/speckit.homer.clarify.md  # Global installed copy
~/.openclaw/.claude/commands/speckit.lisa.analyze.md   # Global installed copy
~/.openclaw/.claude/commands/speckit.ralph.implement.md # Global installed copy

# Bash utility scripts (out-of-scope, called as-is)
.specify/scripts/bash/check-prerequisites.sh     # Feature dir resolution
.specify/scripts/bash/common.sh                  # Shared bash functions
.specify/scripts/bash/pipeline.sh                # Legacy bash pipeline (replaced by command)
.specify/scripts/bash/homer-loop.sh              # Legacy bash loop (replaced by command)
.specify/scripts/bash/lisa-loop.sh               # Legacy bash loop (replaced by command)
.specify/scripts/bash/ralph-loop.sh              # Legacy bash loop (replaced by command)

# Agent files (out-of-scope, read by sub-agents)
.claude/agents/homer.md
.claude/agents/lisa.md
.claude/agents/ralph.md
.claude/agents/plan.md
.claude/agents/tasks.md
.claude/agents/specify.md
```

**Structure Decision**: No new directories or files are created. The fix modifies existing command files in-place and syncs them across 3 locations.

## Phase 0: Research

### Research Findings

#### 1. Current State of Command Files

**Decision**: The `.claude/commands/` copies already contain the correct hybrid Agent tool orchestration pattern. The repo root copies also appear identical based on file comparison.

**Rationale**: Reading all 4 command files in both `.claude/commands/` and repo root locations shows they already implement the Agent tool sub-agent pattern with Bash tool calls for `check-prerequisites.sh`. The original bug (pipeline stopping after specify) was in the legacy bash `pipeline.sh` script which delegated to `claude --agent`. The new command files orchestrate directly via Agent tool, solving the delegation gap.

**Alternatives considered**: Rewriting commands to delegate entirely to bash scripts was rejected in the spec (hybrid architecture chosen instead).

#### 2. Stuck Detection Pattern

**Decision**: Use git diff-based stuck detection. An iteration is "stuck" when the sub-agent exits without producing a meaningful git diff AND the completion promise tag was not emitted. Two consecutive stuck iterations abort the loop.

**Rationale**: The spec defines stuck detection as: no file changes committed + no promise tag. The current command files use "3 consecutive identical outputs" for stuck detection. The spec says 2 consecutive stuck iterations should abort. The commands need to be updated to match the spec's definition (git diff-based, 2 consecutive).

**Alternatives considered**: Output-hash comparison (current approach in commands). The spec explicitly prefers git diff-based detection since it measures actual progress rather than output similarity.

#### 3. File Sync Strategy

**Decision**: After modifying command files, copy each from `.claude/commands/` (canonical source) to repo root and `~/.openclaw/.claude/commands/`.

**Rationale**: The `.claude/commands/` directory is where Claude Code resolves commands from. Making this the canonical source ensures the working copy is always correct, with copies distributed to the other locations.

**Alternatives considered**: Using repo root as canonical source. Either works, but `.claude/commands/` is what Claude Code actually reads.

#### 4. Utility Script Existence Check

**Decision**: Each command checks for `.specify/scripts/bash/check-prerequisites.sh` existence before execution. If missing, display an error with remediation instructions.

**Rationale**: Required by FR-002 and FR-003. The `check-prerequisites.sh` script is the primary utility used by all 4 commands for feature directory resolution.

**Alternatives considered**: Checking for all scripts in `.specify/scripts/bash/`. Unnecessary since `check-prerequisites.sh` is the only utility the commands call directly.

#### 5. Stuck Detection Gap: Commands vs Spec

**Decision**: Update stuck detection in all 4 commands from "3 consecutive identical outputs" to "2 consecutive iterations with no git diff and no promise tag" per spec FR-007.

**Rationale**: The spec explicitly defines stuck detection as git diff-based with a 2-iteration threshold (FR-007). The current commands use output-hash comparison with a 3-iteration threshold. This is a correctness fix.

**Alternatives considered**: Keeping the current 3-iteration output-hash approach. Rejected because it contradicts the spec.

## Phase 1: Design

### Data Model

#### Entities

This feature modifies markdown command files, not code with traditional data models. The key entities are:

**1. Command File**
- Fields: frontmatter (YAML description), user input section, goal/overview, execution steps, configuration, examples
- Relationships: Each command file exists in 3 locations; loop commands reference agent files; pipeline references all 6 agent files
- Validation: Must contain Agent tool orchestration pattern; must check for utility scripts; must support argument parsing
- State transitions: N/A (stateless markdown files)

**2. Iteration State** (runtime, within command execution)
- Fields: iteration_number, max_iterations, consecutive_stuck_count, last_git_diff_empty, last_promise_found
- Relationships: Tracked by the orchestrator between Agent tool sub-agent calls
- Validation: consecutive_stuck_count must not exceed 2; iteration_number must not exceed max_iterations
- State transitions: running -> (completed | max_iterations_reached | stuck | failed)

**3. Pipeline State** (runtime, within pipeline execution)
- Fields: current_step, feature_dir, from_step, steps_executed, iterations_per_loop_step
- Relationships: Sequences through 6 steps; each step may be a single-shot or loop step
- Validation: Steps must execute in order; loop steps must complete before next step starts
- State transitions: For each step: pending -> running -> (completed | failed)

### Contracts

This project is an internal CLI tooling system. The commands expose no external APIs. The "contracts" are the slash command interfaces, which are already fully defined in the spec (FR-001 through FR-009) and do not require separate contract documentation.

**Command interface contract** (already documented in spec):
- `/speckit.pipeline [spec-dir] [--from <step>] [--description <text>]`
- `/speckit.homer.clarify [spec-dir] [max-iterations]`
- `/speckit.lisa.analyze [spec-dir] [max-iterations]`
- `/speckit.ralph.implement [spec-dir] [max-iterations]`

### Implementation Approach

The implementation has 3 main work areas:

#### Area 1: Update Stuck Detection (all 4 commands)

Change stuck detection from "3 consecutive identical outputs" to git diff-based detection per FR-007:
- After each Agent tool sub-agent returns, run `git diff HEAD~1 --stat` to check if files changed
- Check sub-agent output for the completion promise tag
- If no files changed AND no promise tag: increment consecutive_stuck_count
- If files changed OR promise tag found: reset consecutive_stuck_count to 0
- If consecutive_stuck_count reaches 2: abort loop

#### Area 2: Sync All File Copies (12 files)

After updating the 4 command files in `.claude/commands/`:
1. Copy each to repo root (strip `.claude/commands/` prefix)
2. Copy each to `~/.openclaw/.claude/commands/`
3. Verify with `diff` that all 3 copies are byte-identical

#### Area 3: Verify Utility Script Check (all 4 commands)

Confirm each command checks for `check-prerequisites.sh` existence before execution. The current commands call `check-prerequisites.sh` via Bash tool but may not explicitly check existence first. Add explicit existence check with actionable error message per FR-002/FR-003 if missing.

### Re-evaluated Constitution Check (Post-Design)

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Readability First | PASS | Clear markdown structure maintained |
| II. Functional Design | PASS | Deterministic orchestration pattern |
| III. Maintainability Over Cleverness | PASS | Single pattern across all 4 commands |
| IV. Best Practices | PASS | Follows Claude Code conventions |
| V. Simplicity (KISS & YAGNI) | PASS | Minimal changes: stuck detection fix + file sync |
| Test-First Development | N/A | Markdown files, not unit-testable code |
| Quality Gates | PASS | shellcheck + diff verification |

No violations. Design is minimal and focused.
