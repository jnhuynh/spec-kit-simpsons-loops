# Research: Fix Pipeline and Loop Command Delegation

**Feature**: 003-fix-pipeline-delegation
**Date**: 2026-03-09

## R1: Current Command File State Analysis

**Decision**: All 4 orchestrator command files already implement the hybrid Agent tool orchestration pattern. The `.claude/commands/` copies and repo root copies are functionally identical and already use Agent tool sub-agents for loop orchestration with Bash tool calls for `check-prerequisites.sh`.

**Rationale**: Reading all 8 files (4 commands x 2 locations) confirms they share the same content. The hybrid architecture is already in place: Agent tool sub-agents per iteration, Bash tool for feature dir resolution, promise tag checking, and stuck detection.

**Alternatives considered**: Full rewrite from scratch. Rejected because the commands already implement the correct pattern.

## R2: Stuck Detection Gap (Commands vs Spec)

**Decision**: Update stuck detection from "3 consecutive identical outputs" to git diff-based detection with 2-iteration threshold per spec FR-007.

**Rationale**: The spec defines stuck as: sub-agent exits without a meaningful git diff (no file changes committed) AND the completion promise tag was not emitted. Two consecutive stuck iterations abort. The current commands use output-hash comparison with a 3-iteration threshold, which is a different mechanism and threshold. Git diff-based detection is more reliable because it measures actual file changes rather than output similarity (which can vary due to timestamps, formatting).

**Alternatives considered**: Keeping the current 3-iteration output-hash approach. Rejected because it contradicts the spec's explicit definition in FR-007.

## R3: Utility Script Existence Check

**Decision**: Add explicit existence check for `.specify/scripts/bash/check-prerequisites.sh` at the top of each command, before any execution. Display actionable error with remediation instructions if missing.

**Rationale**: FR-002 requires checking for utility scripts before execution. FR-003 requires actionable error messages. Currently, commands call the script directly without checking existence first, which would produce a confusing bash error rather than a helpful message.

**Alternatives considered**: Checking for all scripts in `.specify/scripts/bash/`. Unnecessary because `check-prerequisites.sh` is the only utility the commands call directly. Checking for executable permission (`-x`) rejected per spec edge case -- `bash <script>` does not require execute permission.

## R4: Pipeline Unified Execution Path (FR-008)

**Decision**: The pipeline command uses the same Agent tool sub-agent pattern as standalone loop commands. For feature dir resolution, the pipeline keeps its own inline logic because it handles `--from` and `--description` arguments that `check-prerequisites.sh` does not support.

**Rationale**: FR-008 requires one orchestration pattern across all commands. The Agent tool loop pattern IS unified. The feature dir resolution differs because the pipeline has additional argument handling. Modifying `check-prerequisites.sh` to support `--from`/`--description` is out of scope per the spec.

**Alternatives considered**: Delegating pipeline execution to `pipeline.sh` via Bash tool. Rejected because: (1) `pipeline.sh` uses `claude --agent` internally which creates separate CLI sessions rather than Agent tool sub-agents, (2) FR-009 explicitly requires "the Claude Code session MUST act as the step-level orchestrator, spawning one Agent tool sub-agent per pipeline phase."

## R5: File Sync Strategy

**Decision**: Use `.claude/commands/` as the canonical source. After all modifications, copy each file to repo root and `~/.openclaw/.claude/commands/`. Verify with `diff` that all 3 copies are byte-identical.

**Rationale**: `.claude/commands/` is what Claude Code resolves commands from directly. FR-006 and SC-005 require all 3 copies to be identical. Using `cp` for exact copies is the simplest approach for 4 files.

**Alternatives considered**: Symlinks (rejected -- Claude Code may not follow symlinks, global copy is outside repo). Sync script (overengineering for 4 files).

## R6: Claude Code Slash Command File Format

**Decision**: Slash command files are Markdown with optional YAML frontmatter (between `---` delimiters). The `description` field provides help text. `$ARGUMENTS` is replaced with user-provided arguments at invocation time.

**Rationale**: Established convention used by all existing command files. No format change needed.

**Alternatives considered**: None -- this is an established convention.

## Summary

All research items resolved. The implementation work is:
1. Update stuck detection from output-hash to git-diff based (2-iteration threshold) in all 4 commands
2. Add utility script existence checks with actionable error messages to all 4 commands
3. Sync all file copies across 3 locations (12 files total)
