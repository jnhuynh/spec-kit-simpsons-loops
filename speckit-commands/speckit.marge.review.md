---
description: Orchestrate iterative code review and remediation (Marge loop) over the feature branch diff until all findings are resolved.
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Pre-Flight: Review Command Check

Verify that the single-pass review command exists. Marge's Phase 0 delegates to it:

```bash
test -f ".claude/commands/speckit.review.md" && echo "speckit.review.md: EXISTS" || echo "speckit.review.md: MISSING"
```

If **MISSING**, display this error and **STOP**:

```
ERROR: Required command file not found.

Missing: .claude/commands/speckit.review.md

Marge invokes /speckit.review during Phase 0 to generate findings.
Ensure the file is present at:
  .claude/commands/speckit.review.md
```

## Pre-Loop: Diff Existence Check

After resolving FEATURE_DIR (the orchestrator handles this), confirm there is a diff to review:

```bash
git diff --quiet $(git merge-base HEAD origin/main 2>/dev/null || git merge-base HEAD main)...HEAD
```

If the command exits 0 (no diff), abort: "No changes detected between the feature branch and main. Nothing to review — run /speckit.ralph.implement first."

## Loop Configuration

Set the following LOOP_CONFIG values for this execution:

- **AGENT_NAME**: marge
- **AGENT_DISPLAY_NAME**: Marge
- **AGENT_FILE**: .claude/agents/marge.md
- **SLASH_COMMAND_REF**: /speckit.review
- **PROMISE_TAG**: ALL_FINDINGS_RESOLVED
- **PREREQ_FLAGS**: --json --require-tasks --include-tasks
- **REQUIRED_ARTIFACTS**: spec.md, plan.md, tasks.md
- **MAX_ITERATIONS**: 30
- **EXTRA_PROMPT_SUFFIX**: (none)
- **REPORT_MODE**: needs_human

## Execute

Read and follow the instructions in `.claude/agents/loop-orchestrator.md`, using the LOOP_CONFIG values above. Pass `$ARGUMENTS` through for argument parsing.

## Post-Loop: Review Report Verification

After the loop completes, confirm `<FEATURE_DIR>/review-report.md` exists and was written by the final sub agent — the persisted review report is the contract the split step (`/speckit.split`) reads to enforce gating per FR-018. If the file is absent after the loop completes, surface this as a failure and instruct the user to re-run `/speckit.marge.review` before invoking `/speckit.split`.

## Persisted Review Report (FR-012a)

Every iteration of this loop spawns a Marge sub agent (per `.claude/agents/marge.md`) that MUST overwrite `<FEATURE_DIR>/review-report.md` before exiting. This command does NOT write the file directly; it relies on the agent's persistence contract documented in the **Persisted Review Report** section of `.claude/agents/marge.md` (sourced from `claude-agents/marge.md`).

The persisted report is the single source of truth the split step consumes for per-phase gating decisions. It MUST conform to the contract specified at `specs/008-feat-multi-phase-deploys/contracts/review-report.md`:

- A single GitHub Flavored Markdown table with the **exact** header row `| ID | Severity | Phase | Status | Check Pack | Summary |` in that order.
- Stable per-finding `ID` values reused across runs against the same branch state.
- `Severity` is one of `high`, `medium`, `low`, `informational`.
- `Phase` is the integer phase number for multi-phase findings attributable to a single phase, or the literal `-` for single-phase findings or multi-phase non-attributable structural inconsistencies.
- `Status` is `open` for new findings; transitions to `resolved` only when a subsequent run confirms the issue is gone.
- `Check Pack` is the source check pack filename (informational; not used for gating).
- `Summary` is a single-sentence human-readable description; pipe characters in cell values MUST be escaped as `\|` so `awk -F '|'` parses cleanly.
- The file is overwritten in full on every Marge run (never appended to).

The orchestrator MUST treat absence of `<FEATURE_DIR>/review-report.md` after the loop completes as a Marge failure, since downstream commands (`/speckit.split`) refuse to run without it.

## Examples

- `/speckit.marge.review` — Auto-detect spec dir from current branch, use default max iterations (30)
- `/speckit.marge.review specs/003-fix-pipeline-delegation` — Run for specific spec dir
- `/speckit.marge.review 5` — Auto-detect spec dir, limit to 5 iterations
- `/speckit.marge.review specs/003-fix-pipeline-delegation 5` — Specific spec dir with 5 max iterations
