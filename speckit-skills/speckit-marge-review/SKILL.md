---
name: speckit-marge-review
description: Orchestrate iterative code review and remediation (Marge loop) over the feature branch diff until all findings are resolved.
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Pre-Flight: Review Skill Check

Verify that the single-pass review skill exists. Marge's review phase delegates to it:

```bash
if test -f ".claude/skills/speckit-review/SKILL.md"; then echo "speckit-review: EXISTS"; else echo "speckit-review: MISSING"; fi
if test -f ".claude/agents/findings-ledger.md"; then echo "findings-ledger: EXISTS"; else echo "findings-ledger: MISSING"; fi
```

If either is **MISSING**, display this error and **STOP**:

```
ERROR: Required file(s) not found.

Missing: <the missing path(s)>

Marge invokes /speckit-review during its review phase to generate findings, and
follows the shared ledger protocol in .claude/agents/findings-ledger.md for
reappearance detection. Run setup.sh to (re)install:
  .claude/skills/speckit-review/SKILL.md
  .claude/agents/findings-ledger.md
```

## Pre-Loop: Diff Existence Check

After resolving FEATURE_DIR (the orchestrator handles this), confirm there is a diff to review:

```bash
git diff --quiet $(git merge-base HEAD origin/main 2>/dev/null || git merge-base HEAD main)...HEAD
```

If the command exits 0 (no diff), abort: "No changes detected between the feature branch and main. Nothing to review — run /speckit-ralph-implement first."

## Pre-Loop: Quality Gates Validation

Marge uses two gates: an optional **fast** scoped gate (`.specify/quality-gates-fast.sh`) per iteration (invoked from `.claude/agents/marge.md`) and the **full** gate (`.specify/quality-gates.sh`) once after the loop terminates.

Validate that the full gate file exists and contains executable content. Run via Bash tool:

```bash
test -f .specify/quality-gates.sh && grep -v '^\s*#' .specify/quality-gates.sh | grep -v '^\s*$' | head -1
```

If the file is missing or contains only comments/whitespace (the command produces no output), **STOP** with this error:

```
ERROR: Quality gates file is missing or empty.

Expected: .specify/quality-gates.sh with executable commands.

The full quality gates file is required for Marge to validate review fixes.
Create or update .specify/quality-gates.sh with your project's quality gate
commands (e.g., npm test && npm run lint). The file must exit 0 for gates to pass.
```

Also check for the optional fast gate:

```bash
test -f .specify/quality-gates-fast.sh && echo "EXISTS" || echo "MISSING"
```

If the fast gate exists, note this — the marge agent will use it per iteration. If missing, the agent falls back to the full gate per iteration.

## Loop Configuration

Set the following LOOP_CONFIG values for this execution:

- **AGENT_NAME**: marge
- **AGENT_DISPLAY_NAME**: Marge
- **AGENT_FILE**: .claude/agents/marge.md
- **SLASH_COMMAND_REF**: /speckit-review
- **PROMISE_TAG**: ALL_FINDINGS_RESOLVED
- **PREREQ_FLAGS**: --json --require-tasks --include-tasks
- **REQUIRED_ARTIFACTS**: spec.md, plan.md, tasks.md
- **MAX_ITERATIONS**: 10
- **EXTRA_PROMPT_SUFFIX**: (none)
- **REPORT_MODE**: needs_human

## Execute

Read and follow the instructions in `.claude/agents/loop-orchestrator.md`, using the LOOP_CONFIG values above. Pass `$ARGUMENTS` through for argument parsing.

## Post-Loop: End-of-Loop Full Quality Gate

Run only when the loop exited via the **success** path (`<promise>ALL_FINDINGS_RESOLVED</promise>` observed). Skip on max-iterations, stuck, or failure exits.

Run via Bash tool:

```bash
bash .specify/quality-gates.sh
```

If it exits non-zero, treat the loop as **incomplete**: the fast gate missed a regression in files outside the per-iteration scope. Set the completion status to **failure** with reason "end-of-loop full quality gates failed", surface the failing output in the report, and suggest rerunning marge or fixing the issue manually before re-running this command.

If it exits zero, proceed to review report verification.

## Post-Loop: Review Report Verification

After the loop completes, confirm `<FEATURE_DIR>/review-report.md` exists and was written by the final sub agent — the persisted review report is the audit trail of what was found and fixed, and the ledger the next Marge run uses for reappearance detection. If the file is absent after the loop completes, surface this as a failure and instruct the user to re-run `/speckit-marge-review`.

## Persisted Review Report

Every iteration of this loop spawns a Marge sub agent (per `.claude/agents/marge.md`) that MUST overwrite `<FEATURE_DIR>/review-report.md` before exiting. This command does NOT write the file directly. The authoritative schema and status lifecycle live in the shared ledger protocol `.claude/agents/findings-ledger.md` (sourced from `claude-agents/findings-ledger.md`), which `claude-agents/marge.md` configures with `REPORT_FILE: <FEATURE_DIR>/review-report.md`. The report is the audit trail of what was found and fixed, and the ledger the next Marge run loads for reappearance detection — do not restate its schema here.

The orchestrator MUST treat absence of `<FEATURE_DIR>/review-report.md` after the loop completes as a Marge failure — without it the next Marge run has no ledger for reappearance detection.

## Examples

- `/speckit-marge-review` — Auto-detect spec dir from current branch, use default max iterations (10)
- `/speckit-marge-review specs/003-fix-pipeline-delegation` — Run for specific spec dir
- `/speckit-marge-review 5` — Auto-detect spec dir, limit to 5 iterations
- `/speckit-marge-review specs/003-fix-pipeline-delegation 5` — Specific spec dir with 5 max iterations
