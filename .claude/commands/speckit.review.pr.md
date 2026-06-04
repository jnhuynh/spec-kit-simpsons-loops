---
description: Post a PR review with inline comments for findings requiring human judgment — one-way doors, concurrency risks, architectural decisions, and project-specific patterns.
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Modes

- **Post mode** (default) — analyze the diff, post findings as a GitHub PR review with inline comments.
- **Dry-run mode** — if `$ARGUMENTS` contains `--dry-run`, analyze and print findings to terminal without posting to GitHub.

## Step 1: Resolve PR

Determine the PR to review:

1. If `$ARGUMENTS` contains `pr:<number>` or a GitHub PR URL (`https://github.com/.../pull/<number>`), extract the PR number.
2. Otherwise, auto-detect from the current branch:
   ```bash
   gh pr view --json number,url,headRefName,baseRefName,headRefOid,state 2>/dev/null
   ```
3. If no open PR is found, abort: "No open PR found for the current branch. Push the branch and open a PR first, or pass `pr:<number>` explicitly."
4. If the PR state is not `OPEN`, abort: "PR #<number> is <state>. Can only review open PRs."

Capture: `PR_NUMBER`, `PR_URL`, `HEAD_SHA`, `BASE_REF`.

Also resolve the repo identifier:
```bash
gh repo view --json nameWithOwner --jq '.nameWithOwner'
```

## Step 2: Fetch the diff

Fetch the PR diff (this is the FINAL state post-Marge — things already fixed won't appear):

```bash
gh pr diff $PR_NUMBER
```

And the file list:
```bash
gh pr diff $PR_NUMBER --name-only
```

If the diff is empty, abort: "PR #$PR_NUMBER has no changes. Nothing to review."

## Step 3: Load context sources

Read the following files if they exist:

1. `.specify/memory/constitution.md` — project principles
2. `CLAUDE.md` at repo root — project guidelines
3. Every `*.md` file under `.specify/marge/checks/` — all review packs

If `.specify/marge/checks/` is empty or missing, abort: "No review packs found at `.specify/marge/checks/`. Run `setup.sh` to install baseline packs."

## Step 4: Analyze for human-judgment findings

Run packs sequentially via sub agents (same pattern as `/speckit.review` Step 4). For each pack, spawn a fresh sub agent via the **Agent tool** (`subagent_type: general-purpose`).

**Execution order:**
1. Baseline packs first, alphabetically by filename
2. Project-specific packs after baseline, alphabetically

Each sub agent receives:
- The PR diff
- The file list
- The pack's full text
- Every prior pack's findings (aggregated so far)
- Constitution + CLAUDE.md content as context

**Critical instruction to each sub agent:**

> You are analyzing for findings that require HUMAN JUDGMENT. Mechanical issues (style, linting, common bugs with obvious fixes) are handled by Marge's auto-fix loop and MUST NOT be flagged. Focus exclusively on:
>
> 1. **One-way doors** — irreversible changes (schema destruction, API breaks, permission changes, data deletion)
> 2. **Race conditions / concurrency** — shared mutable state, TOCTOU, missing transactions, non-atomic operations
> 3. **Architectural decisions** — new coupling, layer violations, abstraction boundary changes, dependency direction
> 4. **Project-specific patterns** — violations of constitution or CLAUDE.md principles that require judgment (not mechanical fixes)
> 5. **Project continuity gates** — findings from config-backed project packs tagged `PROJECT_GATE` (e.g. sibling-file sync). ALWAYS flag these, even if mechanical — they encode repo-specific continuity rules an out-of-band reviewer cannot otherwise see.
>
> For packs that contain both mechanical and judgment rules, ONLY flag findings tagged `NEEDS_HUMAN` in the pack's rule definitions — EXCEPT `PROJECT_GATE` findings, which are always flagged. Skip all others.

Each sub agent must return findings in this shape:

```
- file: <path>:<line>
  severity: CRITICAL | HIGH | MEDIUM | LOW
  confidence: <0–100>
  pack: <pack filename>
  rule: <rule name from the pack>
  issue: <one-line description>
  fix: <concrete suggestion if a safe fix exists, otherwise omit>
  tags: [NEEDS_HUMAN]
  corroborates: <prior finding id>?
  refutes: <prior finding id>?
```

**Strict sequential execution**: wait for one pack to return before spawning the next. Later packs see earlier findings and can corroborate / refute.

## Step 4b: Run script gates

Run project **script gates** (`.specify/marge/gates/*.sh`) exactly as in `/speckit.review` Step 4b (contract: `.specify/marge/gates/README.md`), so deterministic continuity findings reach out-of-band reviewers. Discover via Glob; skip if the directory is missing/empty. For each gate:

```bash
SPECKIT_DIFF_FILES="<files from `gh pr diff $PR_NUMBER --name-only`>" \
SPECKIT_BASE_REF="$BASE_REF" \
SPECKIT_REPO_ROOT="$(pwd)" \
SPECKIT_STAGE=review \
timeout 120 bash .specify/marge/gates/<gate-name>.sh
```

Exit 0 → parse stdout findings (default `pack: gates/<gate-name>`; each carries `PROJECT_GATE`). Non-zero/timeout → record one `gate-execution` meta-finding (`tags: [PROJECT_GATE, NEEDS_HUMAN]`) and continue. Append to the aggregated findings, then continue to Step 5.

## Step 5: Aggregate

1. Apply `corroborates:` — merge into the prior finding, bump its confidence by +10 (cap 100).
2. Apply `refutes:` — drop the refuted finding.
3. Dedupe any remaining pairs at the same `file:line` with similar issue text. Keep the higher-confidence one.
4. Filter findings with `confidence < 70`.
5. Sort by severity descending, then confidence descending within each severity.

## Step 6: Map to PR severity

Map the pack-native severity to the three-tier PR comment scheme:

| Pack severity | PR comment severity | Condition |
|---|---|---|
| CRITICAL | **CRITICAL** | Always (one-way doors, security-critical) |
| HIGH + NEEDS_HUMAN | **WARNING** | Concurrency, architecture, testing judgment |
| MEDIUM + NEEDS_HUMAN | **WARNING** | Architecture, testing judgment |
| LOW + NEEDS_HUMAN | **INFO** | Project pattern observations |
| `PROJECT_GATE` (any severity) | CRITICAL→**CRITICAL**, HIGH/MEDIUM→**WARNING**, LOW→**INFO** | Project continuity gates — always surfaced |
| Any other finding WITHOUT NEEDS_HUMAN, not from a keep-list source | *Dropped* | Marge handles these |

Findings from `one-way-doors.md` and `concurrency.md` packs, and ALL findings tagged `PROJECT_GATE` (script gates and config-backed project packs), are always kept regardless of the NEEDS_HUMAN tag — they encode repo-specific continuity an out-of-band reviewer cannot otherwise see.

## Step 7: Check idempotency

Before posting, check if a prior review from this command exists:

```bash
gh api "repos/$REPO/pulls/$PR_NUMBER/reviews" --jq '[.[] | select(.body | contains("<!-- speckit-review-pr -->"))] | last | .body // empty'
```

Parse the sentinel: `<!-- speckit-review-pr sha:<SHA> -->`

- If a prior review exists with the **same SHA** as the current `HEAD_SHA`: skip posting. Print: "Review already posted for commit `<short SHA>`. Push new commits to trigger a fresh review." Exit.
- If a prior review exists with a **different SHA**: proceed to post a new review. Note in the summary that this supersedes the prior review.
- If no prior review exists: proceed to post.

## Step 8: Post PR review

**If `--dry-run`:** print findings to terminal in the same format as `/speckit.review` Step 7 and exit. Do NOT post to GitHub.

**If posting:** build and submit a GitHub PR review.

### Construct the JSON payload

The payload must conform to the GitHub Reviews API:

```json
{
  "event": "COMMENT",
  "body": "<summary with sentinel>",
  "commit_id": "<HEAD_SHA>",
  "comments": [
    {
      "path": "<file path>",
      "line": <line number in the final file>,
      "side": "RIGHT",
      "body": "<formatted inline comment>"
    }
  ]
}
```

### Summary body format

```markdown
<!-- speckit-review-pr sha:<HEAD_SHA> -->

## speckit review — <N> findings requiring human attention

| Severity | Count |
|----------|-------|
| CRITICAL | <n> |
| WARNING  | <n> |
| INFO     | <n> |

**Risk assessment:** <one sentence characterizing the overall risk level of this PR>

<If CRITICAL findings exist:>
**One-way doors detected.** This PR contains irreversible changes that should be reviewed carefully before merging.

---
*Posted by `/speckit.review.pr` — re-run after pushing new commits for a fresh review.*
```

### Inline comment body format

```markdown
**[<SEVERITY>]** <category label>

<2-4 sentence explanation of WHY human attention is needed. Reference the specific code pattern detected and explain what could go wrong.>

<If a safe fix suggestion exists:>
```suggestion
<suggested code change>
```

> Source: pack `<pack filename>` rule `<rule ID>`
```

Category labels: `One-Way Door`, `Concurrency Risk`, `Architecture Decision`, `Project Pattern`, `Project Gate` (for `PROJECT_GATE` findings).

### Submit

Cap at 25 inline comments. If more than 25 findings exist, keep the top 25 by severity (CRITICAL first), then confidence within severity. Note in the summary: "Showing 25 of <N> findings. Address critical and warning findings first."

Post via:
```bash
echo '$JSON_PAYLOAD' | gh api "repos/$REPO/pulls/$PR_NUMBER/reviews" --method POST --input -
```

### Line number mapping

The `line` field must reference the line number in the final version of the file (the `+` side of the diff, `side: RIGHT`). If a finding references a line that is not part of the diff (pre-existing code not touched by this PR), fall back to a file-level comment by omitting the `line` and `side` fields (GitHub posts it as a general file comment).

## Step 9: Report

Print a terminal summary:

```
## PR Review Posted — PR #<number>

Posted <N> inline comments:
  CRITICAL: <n> (one-way doors)
  WARNING:  <n> (concurrency: <n>, architecture: <n>)
  INFO:     <n> (project patterns)

Review URL: <PR URL>
```

If zero findings requiring human judgment were found, post a brief summary-only review (no inline comments):

```markdown
<!-- speckit-review-pr sha:<HEAD_SHA> -->

## speckit review — no findings requiring human attention

All mechanical issues have been handled by Marge's auto-fix loop. No one-way doors, concurrency risks, or architectural concerns detected in this diff.

---
*Posted by `/speckit.review.pr`*
```

## Rules

- Never edit files or commit. This command is read-only + post-comments.
- Use `event: COMMENT`, not `REQUEST_CHANGES` or `APPROVE`. This is informational, not a merge gate.
- Review only lines the diff touches. Pre-existing issues are out of scope.
- Maximum 25 inline comments per review.
- If `gh` CLI is not authenticated, abort early: run `gh auth status` at start and fail fast.
- Do not duplicate findings that Marge already fixed — the diff is post-Marge, so fixed findings are not present.

## Examples

- `/speckit.review.pr` — Auto-detect PR from current branch, post review
- `/speckit.review.pr pr:42` — Review PR #42
- `/speckit.review.pr https://github.com/org/repo/pull/42` — Review by URL
- `/speckit.review.pr --dry-run` — Analyze and print findings without posting to GitHub
- `/speckit.review.pr pr:42 --dry-run` — Dry-run review of PR #42
