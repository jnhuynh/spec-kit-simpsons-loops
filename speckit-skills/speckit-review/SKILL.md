---
name: speckit-review
description: Analyze a feature branch diff against baseline and project-specific review packs; optionally remediate the auto-fixable findings in severity order.
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Modes

This command has two modes:

- **Report mode** (default) — analyze the diff, print a severity-ordered findings report, exit. No code changes.
- **Remediate-all mode** — if `$ARGUMENTS` contains natural-language text like "Remediate all auto-fixable findings" (case-insensitive), analyze AND apply fixes to every finding not tagged `NEEDS_HUMAN`, in severity order, then exit. The invocation may also carry a **known-findings exclusion list** (file + rule + summary per entry, e.g. findings that reappeared after being fixed): report matching findings, but do NOT remediate them.

Marge's loop agent invokes this in remediate-all mode (with exclusions from its ledger). Humans typically invoke it in report mode.

## Step 1: Determine scope

### Diff scope

- Default: `git diff $(git merge-base HEAD origin/main 2>/dev/null || git merge-base HEAD main)...HEAD`. This is the feature branch's diff against its merge base with main.
- If `$ARGUMENTS` contains a token matching `pr:<number>` or a GitHub PR URL, fetch via `gh pr diff <number>` instead.
- If the diff is empty, abort: "No changes to review."

Capture the diff AND the list of modified files.

### Feature artifacts (optional cross-reference)

If `$ARGUMENTS` contains a `spec-dir` token (path matching `specs/`), read `spec.md`, `plan.md`, `tasks.md` from that directory for context only — they inform what the diff was supposed to accomplish but are not themselves reviewed.

## Step 2: Consult rule sources

Before running packs, read these authoritative sources (if present):

1. `.specify/memory/constitution.md` — project principles. Packs may reference it.
2. `CLAUDE.md` at repo root — project guidelines.

These are not rewritten; they are context the packs use to calibrate findings.

## Step 3: Run the pack engine

Read and follow `.claude/skills/speckit-review/reference/pack-execution.md` — the shared engine that discovers packs, runs them sequentially with corroborate/refute, runs script packs, and aggregates. Provide it:

- **DIFF** / **FILE_LIST**: from Step 1
- **PER_PACK_INSTRUCTION**: (none)
- **RUNNER_ENV**: for the default local scope, `SPECKIT_STAGE=review SPECKIT_REPO_ROOT="$(pwd)" SPECKIT_BASE_REF="<the merge-base ref from Step 1>"`. For PR scope (`pr:<number>` in Step 1), the diff is not local git state — substitute the literal PR number and base branch captured in Step 1 and additionally pass the changed files: `SPECKIT_STAGE=review SPECKIT_REPO_ROOT="$(pwd)" SPECKIT_BASE_REF="<PR base branch>" SPECKIT_DIFF_FILES="$(gh pr diff <number> --name-only)"`
- **CONFIDENCE_RULE**: drop findings with `confidence < 70` unless `$ARGUMENTS` contains `--strict`

## Step 4: Remediate (remediate-all mode only)

1. Sort the auto-fixable findings in severity order: CRITICAL, HIGH, MEDIUM, LOW; confidence descending within a severity. Auto-fixable = not tagged `NEEDS_HUMAN` AND not matching the invocation's known-findings exclusion list (same file + rule + equivalent summary).
2. If no auto-fixable findings remain, skip remediation and proceed to reporting.
3. Apply each finding's `fix` one at a time, in that order. Stay inside each finding's blast radius — no opportunistic refactoring beyond the listed fixes.
4. After each edit, re-read the touched file to confirm the edit is correct before moving to the next finding.
5. Do NOT commit. The Marge agent commits after its validation gate.

## Step 5: Report

Print a single markdown report to stdout:

```
## Code Review — <branch-name> (<N> files changed, <M> findings)

### Critical (<count>)
- `<file>:<line>` — <issue>
  Fix: <suggestion>
  Source: <pack> · confidence <n>[ · NEEDS_HUMAN]

### High (<count>)
...

### Medium (<count>)
...

### Low (<count>) — collapsed
<N> low-severity findings hidden. Pass `--show low` to expand.
```

Rules:
- Omit severity headings with zero findings.
- "Low" is collapsed by default. Show the count line; expand only if `--show low` appears in `$ARGUMENTS`.
- Append a "Refuted" appendix only if refutations occurred and `--strict` is set.
- End with a one-line summary: total counts by severity + NEEDS_HUMAN count + the command that was run.

In remediate-all mode, additionally print which findings were remediated (the full list, in the order applied), which findings were skipped as excluded, and which files were edited, so the calling agent (Marge) can validate.

## Rules

- Never post to GitHub. Terminal output only. Never call `gh pr comment` / `gh pr review`.
- Never commit. Remediation edits files but does not stage or commit.
- Review only lines the diff touches. Pre-existing issues are out of scope.
- If `.specify/marge/baseline/` is missing or empty, abort with a helpful error.

## Examples

- `/speckit-review` — Report mode, default scope (feature branch vs main)
- `/speckit-review specs/001-feat-auth` — Report mode with feature-artifact cross-reference
- `/speckit-review pr:123` — Report mode against PR #123
- `/speckit-review --strict` — Report mode, include low-confidence findings
- `/speckit-review --show low` — Report mode, expand the Low bucket
- `/speckit-review Remediate all auto-fixable findings in severity order without asking for confirmation` — Remediate-all mode (used by the Marge loop agent)
