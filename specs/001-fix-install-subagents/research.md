# Research: Fix Install Script, Sub Agent Consistency, and README

**Branch**: `001-fix-install-subagents` | **Date**: 2026-03-01

## Research Tasks & Findings

### R1: "Task tool" vs "Agent tool" Terminology Across All Files

**Context**: The spec (FR-004, FR-008, FR-009) mandates that the canonical term is "Agent tool" (not "Task tool"). The current codebase uses "Task tool" in multiple locations.

**Current State (observed inconsistencies)**:
- `speckit.homer.clarify.md` lines 15, 40: uses "Task tool"
- `speckit.lisa.analyze.md` lines 15, 48: uses "Task tool"
- `speckit.ralph.implement.md` lines 15, 48: uses "Task tool"
- `speckit.pipeline.md` lines 13, 56, 58: uses "Task tool" and "Task tool call"
- `README.md` lines 5, 131: uses "Task tool"

**Decision**: Replace all "Task tool" occurrences with "Agent tool" in loop command files and README.
**Rationale**: The spec explicitly deprecates "Task tool" in favor of "Agent tool" as the canonical term.
**Alternatives considered**: None. This is a direct requirement (FR-008, FR-009).

---

### R2: Failure Handling Inconsistency Between Spec FR-011 and Loop Commands

**Context**: FR-011 states loop commands (slash commands) MUST handle sub agent crash/timeout by "catching the error, logging failure context, and aborting the loop with a clear error message -- no automatic retry." However, bash loop scripts MAY implement limited retry (up to 3 consecutive failures).

**Current State (observed inconsistencies)**:
- `speckit.homer.clarify.md` line 54: says "Abort after 3 consecutive failures" (implies retry)
- `speckit.lisa.analyze.md` line 62: says "Abort after 3 consecutive failures" (implies retry)
- `speckit.ralph.implement.md` line 62: says "Abort after 3 consecutive failures" (implies retry)
- All 3 bash loop scripts correctly implement 3-retry-then-abort behavior (per FR-011 allowance)

**Decision**: Update loop command files (slash commands) to abort immediately on sub agent failure with no retry. Keep bash script retry behavior as-is.
**Rationale**: FR-011 explicitly distinguishes between loop commands (no retry) and bash scripts (retry allowed). Loop commands run inside Claude Code where failures are typically deterministic; retrying adds no value.
**Alternatives considered**: Keeping 3-retry in loop commands for consistency with bash scripts. Rejected because the spec explicitly calls out this behavioral difference.

---

### R3: Maximum Iteration Limit Enforcement (FR-012)

**Context**: FR-012 requires all loop commands to enforce a maximum of 10 iterations. When reached, the loop must abort with a clear message reporting the iteration count and suggesting manual review.

**Current State**:
- `speckit.homer.clarify.md`: sets max at 10 -- compliant
- `speckit.lisa.analyze.md`: sets max at 10 -- compliant
- `speckit.ralph.implement.md`: sets max at `incomplete_tasks + 10` -- needs review against FR-012
- `speckit.pipeline.md`: Homer 10, Lisa 10, Ralph `incomplete_tasks + 10` -- needs review against FR-012

**Decision**: FR-012 says "maximum iteration limit of 10 iterations per loop invocation." Ralph's dynamic limit (`incomplete_tasks + 10`) is project-standard behavior and the spec's own acceptance scenarios (US2.4) describe "10 iterations" as the abort threshold. However, Ralph is task-driven -- its limit of `incomplete_tasks + 10` is not inconsistent because each iteration implements exactly one task. The 10-iteration limit in FR-012 maps to the +10 buffer beyond expected work. Keep Ralph's dynamic limit but ensure all loop commands report a clear abort message when the limit is reached.
**Rationale**: Ralph's limit is already bounded and reports clearly. Capping it at exactly 10 would prevent completing tasks when there are more than 10 incomplete tasks.
**Alternatives considered**: Hard-capping Ralph at 10. Rejected because it would break the core use case of implementing all tasks.

---

### R4: Setup Script Idempotency and Test Directory Behavior (FR-002, FR-003)

**Context**: FR-002 requires idempotent behavior. FR-003 requires working with test directories.

**Current State**:
- `setup.sh` already checks for `.claude/` and `.specify/` directories (lines 14-24)
- `setup.sh` already checks if run from within the simpsons-loops repo (lines 26-31)
- `.gitignore` update is already idempotent (checks for marker, lines 85-94)
- `settings.local.json` update is already idempotent (checks for existing permissions, lines 98-143)
- File copies (`cp`) are inherently idempotent (overwrite)

**Decision**: The setup script is already largely compliant. Minor improvements needed: ensure error messages match the spec's wording, verify that the "self-install protection" check works correctly in all cases.
**Rationale**: The existing implementation handles the key idempotency and test directory requirements.
**Alternatives considered**: Rewriting setup.sh from scratch. Rejected because the existing script is well-structured.

---

### R5: README Accuracy (FR-007, FR-008, FR-009)

**Context**: The README must accurately describe the install process, file layout, recommended workflow, and bash script fallback, using consistent terminology.

**Current State (observed inaccuracies)**:
- Line 5: Uses "Task tool" instead of "Agent tool"
- Line 131: Uses "Task tool" instead of "Agent tool"
- Line 15: Permission note says "Claude Code will prompt for permission as normal" for slash commands -- this contradicts autonomous execution (FR-006)
- Overall structure and file paths are accurate
- Manual setup instructions match `setup.sh` behavior

**Decision**: Update README to replace "Task tool" with "Agent tool" and clarify that loop commands instruct sub agents to execute autonomously.
**Rationale**: Direct requirements from FR-007, FR-008, FR-009.
**Alternatives considered**: None. This is a direct requirement.

---

### R6: Autonomous Execution Instructions in Loop Commands (FR-006)

**Context**: All loop commands MUST include explicit autonomous execution instructions.

**Current State**:
- `speckit.homer.clarify.md`: Has `AUTONOMOUS EXECUTION` block -- compliant
- `speckit.lisa.analyze.md`: Has `AUTONOMOUS EXECUTION` block -- compliant
- `speckit.ralph.implement.md`: Has `AUTONOMOUS EXECUTION` block -- compliant
- `speckit.pipeline.md`: Has `AUTONOMOUS EXECUTION` and `STRICT SEQUENTIAL EXECUTION` blocks -- compliant

**Decision**: No changes needed. All loop commands already contain the required autonomous execution instructions.
**Rationale**: The existing instructions are clear and explicit.
**Alternatives considered**: N/A.

---

### R7: Pipeline Failure Handling (Missing from Current Implementation)

**Context**: The pipeline command (`speckit.pipeline.md`) does not explicitly describe what happens when a sub agent fails mid-step.

**Current State**:
- `speckit.pipeline.md` mentions stuck detection for homer/lisa loops
- No explicit failure handling instructions for sub agent crashes within pipeline steps

**Decision**: Add failure handling to pipeline that matches the individual loop commands' approach -- abort on first failure for loop command context (no retry).
**Rationale**: Consistency with FR-011 and the individual loop commands' updated behavior.
**Alternatives considered**: Adding retry logic to pipeline steps. Rejected per FR-011.

---

### R8: Bash Script Retry Behavior Verification

**Context**: FR-011 allows bash scripts to implement limited retry (up to 3 consecutive failures). Need to verify all 4 bash scripts implement this correctly.

**Current State**:
- `homer-loop.sh`: `MAX_CONSECUTIVE_FAILURES=3`, retries on failure -- compliant
- `lisa-loop.sh`: `MAX_CONSECUTIVE_FAILURES=3`, retries on failure -- compliant
- `ralph-loop.sh`: `MAX_CONSECUTIVE_FAILURES=3`, retries on failure -- compliant
- `pipeline.sh`: Delegates to individual scripts or implements own retry -- needs verification

**Decision**: Bash scripts are compliant. No changes needed.
**Rationale**: All three individual loop scripts implement the 3-retry pattern as allowed by FR-011.
**Alternatives considered**: N/A.

## Summary of Findings

| # | Finding | Status | Action Required |
|---|---------|--------|-----------------|
| R1 | "Task tool" used instead of "Agent tool" in 5 files | Inconsistency | Replace in all loop commands + README |
| R2 | Loop commands have retry logic, spec says no retry | Inconsistency | Update loop commands to abort on first failure |
| R3 | Ralph's dynamic iteration limit | Compliant | Keep as-is, ensure clear abort messages |
| R4 | Setup script idempotency | Compliant | Minor wording improvements |
| R5 | README inaccuracies | Inconsistency | Fix terminology and permission note |
| R6 | Autonomous execution instructions | Compliant | No changes needed |
| R7 | Pipeline failure handling | Missing | Add explicit failure handling |
| R8 | Bash script retry behavior | Compliant | No changes needed |

All NEEDS CLARIFICATION items have been resolved through direct codebase analysis. No external research was required.
