---
name: speckit-review
description: Analyze a feature branch diff against baseline and project-specific review packs; optionally remediate the single highest-severity finding.
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Modes

This command has two modes:

- **Report mode** (default) — analyze the diff, print a severity-ordered findings report, exit. No code changes.
- **Remediate-one mode** — if `$ARGUMENTS` contains natural-language text like "Remediate only the single highest-severity finding" (case-insensitive), analyze AND apply a fix to the single highest-severity actionable finding, then exit.

Marge's loop agent invokes this in remediate-one mode. Humans typically invoke it in report mode.

## Step 1: Determine scope

### Diff scope

- Default: `git diff $(git merge-base HEAD origin/main 2>/dev/null || git merge-base HEAD main)...HEAD`. This is the feature branch's diff against its merge base with main.
- If `$ARGUMENTS` contains a token matching `pr:<number>` or a GitHub PR URL, fetch via `gh pr diff <number>` instead.
- If the diff is empty, abort: "No changes to review."

Capture the diff AND the list of modified files.

### Feature artifacts (optional cross-reference)

If `$ARGUMENTS` contains a `spec-dir` token (path matching `specs/`), read `spec.md`, `plan.md`, `tasks.md` from that directory for context only — they inform what the diff was supposed to accomplish but are not themselves reviewed.

## Step 2: Load review packs

Discover every `*.md` **prose pack** via Glob from two directories:

- `.specify/marge/baseline/` — shipped baseline packs (generic code-quality rules)
- `.specify/marge/project/` — project packs (repo-specific rules; their findings are tagged `PROJECT_GATE` — see Step 4)

Expected baseline packs (installed by `setup.sh`): `generic-bugs.md`, `security.md`, `testing.md`, `architecture.md`, `concurrency.md`, `one-way-doors.md`.

Run every pack regardless of origin — the directories are the API. A pack's directory tells you its origin (baseline vs project); its extension tells you its mode (`.md` prose here, `.sh` script in Step 4b).

Some project packs are **config-backed**: the pack text instructs the sub agent to `Read` a data file under `.specify/marge/config/` and treat it as rule data (e.g. sibling-file sync groups). No special handling is needed here — the sub agent reads that file itself in Step 4. A config-backed pack whose config file is missing or empty emits zero findings. (Contract: `.specify/marge/README.md`.)

If `.specify/marge/baseline/` is empty or missing, abort: "No baseline review packs found at `.specify/marge/baseline/`. Run `setup.sh` to install baseline packs." (`.specify/marge/project/` may be absent — project packs are optional.)

## Step 3: Consult rule sources

Before running packs, read these authoritative sources (if present):

1. `.specify/memory/constitution.md` — project principles. Packs may reference it.
2. `CLAUDE.md` at repo root — project guidelines.

These are not rewritten; they are context the packs use to calibrate findings.

## Step 4: Run packs sequentially with corroborate/refute

For each pack in the discovered list, spawn a fresh sub agent via the **Agent tool** (`subagent_type: general-purpose`). Run them **one at a time** in this order:

1. Baseline packs (`baseline/*.md`) first, alphabetically by filename
2. Project packs (`project/*.md`) after baseline, alphabetically

Each sub agent receives:
- The diff
- The file list
- The pack's full text (read via the prompt or by instructing the sub agent to `Read` the pack path)
- Every prior pack's findings (aggregated so far)
- The constitution + CLAUDE.md content as context
- Whether the pack is a **project pack** (from `project/`). If so, instruct the sub agent to add `PROJECT_GATE` to the `tags` of every finding it emits — the tag is derived from the pack's location, not written into the pack text. Baseline packs never get `PROJECT_GATE`.

Each sub agent must return findings in this shape (one per finding):

```
- file: <path>:<line>
  severity: CRITICAL | HIGH | MEDIUM | LOW
  confidence: <0–100>
  pack: <pack filename>
  rule: <rule name from the pack>
  issue: <one-line description>
  fix: <concrete suggestion>
  tags: [PROJECT_GATE?, NEEDS_HUMAN?]   # PROJECT_GATE auto-added for project/ packs; NEEDS_HUMAN if it needs judgment
  corroborates: <prior finding id>?   # if duplicates an earlier finding — merges
  refutes: <prior finding id>?        # if refutes an earlier finding — drops it
```

**Strict sequential execution**: wait for one pack to return before spawning the next. Later packs see earlier findings and can corroborate / refute.

## Step 4b: Run script packs

Project **script packs** are deterministic continuity checks under `.specify/marge/project/*.sh`, executed by the shipped runner `.specify/marge/run-gates.sh` (contract: `.specify/marge/README.md`). The runner discovers the script packs, applies the per-pack timeout, exports the contract env, and emits findings — or one `pack-execution` meta-finding per failed pack — on stdout; it never aborts.

Run it **once, after the packs** (so script-pack findings can corroborate/refute prose-pack findings in Step 5) via the Bash tool. Pass the base ref from Step 1; the runner derives the changed-file list from it:

```bash
SPECKIT_STAGE=review \
SPECKIT_REPO_ROOT="$(pwd)" \
SPECKIT_BASE_REF="<the merge-base/base ref from Step 1>" \
bash .specify/marge/run-gates.sh
```

Treat the runner's stdout as a findings YAML sequence in the same shape as Step 4 — each item already carries `pack: project/<name>` and `PROJECT_GATE` (a failed pack appears as one LOW `pack-execution` finding tagged `[PROJECT_GATE, NEEDS_HUMAN]`). Empty stdout means zero script-pack findings. Append them to the aggregated findings list, then continue to Step 5. If `.specify/marge/project/` is absent the runner prints nothing — script packs are optional (only `.specify/marge/baseline/` is required).

## Step 5: Aggregate

1. Apply `corroborates:` — merge into the prior finding, bump its confidence by +10 (cap 100), append the corroborating source to its `pack` line.
2. Apply `refutes:` — drop the refuted finding; record it in a "Refuted" appendix.
3. Dedupe any remaining pairs at the same `file:line` with similar issue text. Keep the higher-confidence one; break ties by later source — project packs (`pack: project/*`, prose or script) win over baseline packs.
4. Filter findings with `confidence < 70` unless `$ARGUMENTS` contains `--strict`.
5. Sort within each severity bucket by confidence descending.

## Step 6: Remediate (only in remediate-one mode)

If in remediate-one mode:

1. Pick the single highest-severity finding that is NOT tagged `NEEDS_HUMAN`. Ties broken by confidence, then by file path.
2. If every finding is tagged `NEEDS_HUMAN`, skip remediation and proceed to reporting.
3. Apply the finding's `fix` directly to the modified files. Stay inside the blast radius of the single finding — do not opportunistically refactor or fix other findings.
4. After applying, re-read the modified files to confirm the edit is correct.
5. Do NOT commit. The Marge agent commits after its Phase 3 validation gate.

## Step 7: Report

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

If in remediate-one mode, additionally print which finding was remediated and which files were edited, so the calling agent (Marge) can validate.

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
- `/speckit-review Remediate only the single highest-severity finding without asking for confirmation` — Remediate-one mode (used by Marge Phase 0)
