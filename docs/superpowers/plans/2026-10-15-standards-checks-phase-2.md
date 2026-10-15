# Standards Checks, Phase 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the `/speckit-pr` skill, the Ralph hint that points at it, and the pipeline's specify-step instruction that opens every new spec with `## Plain summary`.

**Architecture:** One new skill directory, `speckit-skills/speckit-pr/SKILL.md`, installed by the existing skills loop in `setup.sh`. It runs the phase 1 engine (`.specify/scripts/bash/speckit-standards.sh --base <base> --format text`) and copies the damage level header into a five-section description, delivered through `gh`. Three one-line hints and one appended instruction land in existing Markdown. The install test (`scripts/tests/test-setup-standards.sh`) grows checks for every installed file this phase touches, so the quality gate proves the ship-source reaches a consumer.

**Tech Stack:** Markdown skill and agent files, Bash tests in the style of `scripts/tests/test-speckit-commit.sh`. The skill itself needs `gh` and `git` at run time. No new scripts.

**Spec:** `docs/superpowers/specs/2026-10-14-standards-checks-design.md` (sections 2.4, 3, the `/speckit-pr` rows of 5.2, and the phase 2 row of section 6). Phase 1 shipped on `9cad-feat-standards-checks`; this plan stacks on it as `9cad-feat-speckit-pr`.

## Global Constraints

- Ship-source only: edit `speckit-skills/`, `claude-agents/`, `templates/`, `README.md`, `scripts/tests/`. Never edit anything under `.specify/` or `.claude/`.
- The skill never pushes, never merges, never lowers the damage level, never claims a check it did not run, never puts a requirement id in the description. These five rules are stated in the skill under `## Never` and are the Review Focus below.
- The built-in section headings are exactly: `What changed`, `How much damage if it is wrong`, `Where to look`, `How it was verified`, `Links`.
- The engine's text format is the contract the skill reads: first line `Damage level: <name> (set by <files>)` or `Damage level: <name> (nothing in this change raises it)`, second line the reviewer line, then `  - ` checklist items, then findings with `BLOCK ` prefixed on blocking ones.
- The Ralph hint is the same sentence in all three places: `Open it with /speckit-pr.`
- The specify-step sentence is appended inside the existing single-backtick prompt string, so it uses no backticks.
- Commit format: `type(scope): [9cad] description`, one logical change per commit, never push. Every commit ends with the two attribution lines the session gives.
- Quality gate before every commit: `bash .specify/quality-gates.sh` green (it runs shellcheck and every `scripts/tests/test-*.sh`).

## Review Focus

Behaviours the spec implies that a person using the skill would be hurt by if missing. Each is a sentence in the skill, and Task 1's install test greps the installed copy for the phrase in brackets.

1. A pull request named with `pr:<n>` whose head branch is not checked out must stop, not describe the wrong tree [`reads the local tree`].
2. `--dry-run` must change nothing: no file edits, no commits, no GitHub calls [`change nothing`].
3. A branch that is not on the remote gets the description printed and the push command shown, never pushed [`never push`].
4. The damage level from the engine is copied; it may be raised with a reason and never lowered [`Never lower`].
5. A requirement id in the draft is caught by running the engine with `--body-file` on the draft before delivery [`--body-file`].

---

### Task 1: The `/speckit-pr` skill and its install test

**Files:**
- Create: `speckit-skills/speckit-pr/SKILL.md`
- Modify: `scripts/tests/test-setup-standards.sh` (after the `lexicon seeded` check, line 24)

**Interfaces:**
- Consumes: `.specify/scripts/bash/speckit-standards.sh --base REF [--body-file FILE] [--only pr-shape] [--blocking-only] --format text` (phase 1); `gh pr view|edit|create`; the branch name format `<ticket>-<type>-<scope...>` from `scripts/speckit-commit.sh`.
- Produces: the installed skill at `.claude/skills/speckit-pr/SKILL.md`; the phrase `Open it with /speckit-pr.` that Task 2 points at.

- [ ] **Step 1: Write the failing install checks**

In `scripts/tests/test-setup-standards.sh`, after line 24 (`check_file "lexicon seeded" ...`), add:

```bash
check_file "speckit-pr skill installed" .claude/skills/speckit-pr/SKILL.md
check_eq "speckit-pr skill is named" "$(sed -n 2p .claude/skills/speckit-pr/SKILL.md 2>/dev/null)" "name: speckit-pr"
for phrase in 'reads the local tree' 'change nothing' 'never push' 'Never lower' '--body-file' '## What changed' '## How much damage if it is wrong' '## Where to look' '## How it was verified' '## Links'; do
  if grep -qF -- "$phrase" .claude/skills/speckit-pr/SKILL.md 2>/dev/null; then pass "speckit-pr skill says: $phrase"; else fail "speckit-pr skill says: $phrase"; fi
done
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash scripts/tests/test-setup-standards.sh 2>&1 | grep -c '^FAIL'`
Expected: `12` (the file check, the name check, and the ten phrases).

- [ ] **Step 3: Write the skill**

Create `speckit-skills/speckit-pr/SKILL.md` with exactly this content:

````markdown
---
name: speckit-pr
description: Write the pull request description from the diff — what changed, how much damage if it is wrong (the damage level, reviewer line, and checklist from the standards engine), where to look, how it was verified, links. Use when asked to write or update a PR description or to open a pull request. Never pushes, never merges, never lowers the damage level.
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Modes

- **Deliver mode** (default) — write the description to the open pull request with `gh`, or create the pull request when the branch is pushed and has none.
- **Dry-run mode** — if `$ARGUMENTS` contains `--dry-run`, print the description and change nothing: no file edits, no commits, no GitHub calls.

`$ARGUMENTS` may also name the pull request: `pr:<number>`, a GitHub pull request URL, or a branch name. With nothing, the current branch is used.

## Never

- Never push, merge, rebase, or check out a branch. A branch that is not on the remote gets its description printed, with the push command for the person to run. You never push it.
- Never lower the damage level. It is a floor. Raising it with a reason is allowed.
- Never claim a check that was not run in this session.
- Never put a requirement id (`FR-001`, `SC-P1-003`, `US2`) in the description. The reviewer reads the diff, not the spec.
- Never ask for confirmation between steps. Run end to end, then report.

## Pre-flight: engine check

```bash
if test -x .specify/scripts/bash/speckit-standards.sh; then echo "engine: OK"; else echo "engine: MISSING"; fi
```

If **MISSING**, display this error and **STOP**:

```
ERROR: Standards engine not found.

Missing: .specify/scripts/bash/speckit-standards.sh

/speckit-pr copies the damage level and its checklist from the engine
installed by setup.sh. Run setup.sh, then re-run.
```

## Step 1: Base and state

1. Find the pull request. With `pr:<number>` or a pull request URL in `$ARGUMENTS`, run `gh pr view <number> --json number,url,baseRefName,headRefName,state`. With a branch name, run `gh pr view <branch> --json number,url,baseRefName,headRefName,state`. Otherwise:
   ```bash
   git branch --show-current
   gh pr view --json number,url,baseRefName,headRefName,state 2>/dev/null
   ```
   No output from `gh pr view` means there is no pull request yet. That is not an error.
2. If a pull request exists and its `headRefName` is not the current branch, **STOP**: `Check out <headRefName> and run again: /speckit-pr reads the local tree.` If its `state` is not `OPEN`, **STOP**: `PR #<number> is <state>.`
3. **BASE**: `origin/<baseRefName>` when a pull request exists. Otherwise the first of `origin/main`, `main`, `master` that this accepts (exit 0):
   ```bash
   git rev-parse --verify --quiet origin/main^{commit}
   ```
4. **Pushed**: true when `git rev-parse --abbrev-ref @{upstream} 2>/dev/null` prints a name. When pushed, **UNPUSHED** is `git rev-list --count @{upstream}..HEAD`; otherwise it is every commit on the branch.

Capture `PR_NUMBER`, `PR_URL`, `BASE_REF_NAME`, `BASE`, `BRANCH`, `PUSHED`, `UNPUSHED`. Each Bash call is a fresh shell: substitute the literal values in later commands.

## Step 2: Run the checks

```bash
bash .specify/scripts/bash/speckit-standards.sh --base <BASE> --format text
```

Keep the whole output. The first lines are the damage level header, copied in Step 5:

```
Damage level: critical (set by db/migrate/20261014_x.rb, app/services/pay/send.rb and 2 more)
Read every line. Work the checklist.
  - What happens if this runs twice?
```

Then the findings, one per line, blocking ones first with a `BLOCK` prefix:

```
BLOCK HIGH   specs/9cad-feat-x/spec.md:0  plain-summary-missing: a new spec opens with a plain summary ...
MEDIUM       specs/9cad-feat-x/spec.md:14  long-sentence: 31 words: "The nightly job writes…"
```

- Exit code 2 means the engine could not run. Print its message and **STOP**.
- In dry-run mode, edit nothing. Keep the `BLOCK` lines for the report in Step 10.
- In deliver mode, a `BLOCK` line is fixed now, in the file it names, and committed before the description is written: nothing checks the change again later. Commit with `git commit`, never with `speckit-commit.sh` (it pushes). Subject: `fix(<scope>): [<ticket>] <what was fixed>`, with `<ticket>` and `<scope>` from the branch name as in Step 10. Re-run the engine and confirm no `BLOCK` line remains.
- In deliver mode, when the change adds or edits a file under `specs/`, fix its advice findings too (`long-sentence`, `plain-verb`, `invented-phrase`, `lexicon-prefer`) in the same commit: the spec is what the reviewer reads.
- `specs-mixed-with-code`, `many-boundaries`, `unrated-path`, and `lexicon-new-term` are decisions for a person, not edits. Leave them. They go under "Where to look" in Step 6.

## Step 3: Read the diff, not the spec

```bash
git log --oneline <BASE>..HEAD
git diff --stat <BASE>...HEAD
git diff <BASE>...HEAD -- <the files that matter>
```

Read every hunk in a file the damage level header names, and every hunk in a file a finding names. Skim the rest from `--stat`. Do not read `spec.md` to learn what changed: the description must match the code.

## Step 4: What changed

Three to six sentences on what a user or an operator can now do, or no longer can. Each sentence under 25 words. When `.specify/marge/config/lexicon.yml` exists, write with the `use:` words of its `banned:` and `prefer:` entries, never with the words those patterns catch. No requirement ids (Step 9 checks). A file name only when the reader has to go there.

## Step 5: How much damage if it is wrong

Copy the engine's header from Step 2 into this shape:

```markdown
**<level>** — set by `<file>`, `<file>`.
<reviewer line>

- [ ] <checklist item>
- [ ] <checklist item>
```

When the header says `nothing in this change raises it`, the first line is `**<level>** — nothing in this change raises it; the default level applies.`

Then one sentence on why the level fits the change. If the change does something the level understates (moves money or data of record, changes who may act, stores a secret or personal data, deletes data, changes what a user is told or agrees to), raise the level in that sentence and say why. Never lower it, whatever the diff looks like: a person lowers a level in the description, with a reason, never an agent.

## Step 6: Where to look

One to three `path:line` hunks that need judgment, each with one sentence on what to judge. Then `The rest is mechanical.`, or what else it is (renames, generated files, tests). Findings left for a person in Step 2 go here, one line each: the rule, the file, the question it raises.

## Step 7: How it was verified

What was run in this session and what it said, with numbers. If `.specify/quality-gates.sh` exists, run it now and report its result:

```bash
bash .specify/quality-gates.sh
```

Always report the standards engine run from Step 2: the level and the number of findings. Never list a check that was not run. If nothing but the engine ran, say so.

## Step 8: Links

- The spec directory once, when `specs/<BRANCH>/` exists.
- The ticket from the branch name (the part before the first `-`), written the way `CLAUDE.md` says the project writes ticket links, else the bare id.
- An error-tracker item when the commits or the person mention one.

No link, no line.

## Step 9: Self-check

1. Every sentence under 25 words. No term built from generic words (`the dispatch surface`, `vendor-neutral seam`): name the thing.
2. Save the draft to a temp file (`mktemp`) and run the engine on it:
   ```bash
   bash .specify/scripts/bash/speckit-standards.sh --base <BASE> --body-file <draft> --only pr-shape --blocking-only --format text
   ```
   A `BLOCK HIGH   PULL_REQUEST:0  requirement-id-in-body: ...` line names the ids to remove. Rewrite the sentence without them, save, and run again until no `BLOCK` line is printed. Never deliver a draft the engine blocks.

## Step 10: Deliver

Build the title from the branch name the way `speckit-commit.sh` does: `<ticket>-<type>-<scope...>` gives `<type>(<scope>): [<ticket>] <description>`, where `<description>` is a phrase under 60 characters taken from Step 4. A branch that does not fit `<ticket>-<type>-<scope>` gets `<description>` alone as the title.

The description ends with the attribution lines the session gives (the `🤖 Generated with ...` block), when it gives any.

- **Dry-run**: print the title and the description. Then print any `BLOCK` lines from Step 2 under `Blocked by:`; deliver mode fixes them. Done.
- **A pull request exists**: `gh pr edit <PR_NUMBER> --body-file <draft>`. Print `PR_URL`.
- **No pull request, pushed, `UNPUSHED` is 0**: `gh pr create --base <BASE_REF_NAME> --head <BRANCH> --title "<title>" --body-file <draft>`. Print the URL it returns.
- **Not pushed, or `UNPUSHED` above 0 with no pull request, or `gh` missing**: print the title and the description, then `Not on the remote. Push it, then run /speckit-pr again:` and the command `git push -u origin <BRANCH>`. You never push it.

End with a report: what was delivered (edited #N, created #N, or printed), `UNPUSHED` when above 0 (`<n> local commits are not on the remote; push before review`), and the fix commit from Step 2 when one was made.

## Template

When `.github/pull_request_template.md` exists, keep its headings in its order and put the matching section under each: what changed, damage, where to look, verification, links. A template heading with no counterpart gets `None.`. A section with no template heading is appended at the end under its built-in heading. Without a template, use these headings in this order:

```markdown
## What changed
## How much damage if it is wrong
## Where to look
## How it was verified
## Links
```

## Examples

- `/speckit-pr` — describe the current branch: edit its open pull request, or create one when the branch is pushed
- `/speckit-pr --dry-run` — print the description and change nothing
- `/speckit-pr pr:42` — pull request 42; its head branch must be checked out
- `/speckit-pr 9cad-feat-standards-checks` — a branch by name
````

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash scripts/tests/test-setup-standards.sh 2>&1 | tail -n 3`
Expected: the last line is `ALL TESTS PASSED` and no `FAIL:` line appears above it.

- [ ] **Step 5: Run the quality gate**

Run: `bash .specify/quality-gates.sh 2>&1 | tail -n 5`
Expected: exit 0; the test suites report `ALL TESTS PASSED`.

- [ ] **Step 6: Commit**

```bash
git add speckit-skills/speckit-pr/SKILL.md scripts/tests/test-setup-standards.sh
git commit -m "feat(skills): [9cad] /speckit-pr writes the pull request description with the damage level"
```

(with the session's two attribution lines appended to the message body)

---

### Task 2: The Ralph hint in three places

**Files:**
- Modify: `claude-agents/ralph.md:57-61`
- Modify: `speckit-skills/speckit-ralph-implement/SKILL.md:91-95`
- Modify: `speckit-skills/speckit-pipeline/reference/steps/ralph.md:10`
- Modify: `scripts/tests/test-setup-standards.sh` (after the Task 1 checks)

**Interfaces:**
- Consumes: the skill name `speckit-pr` from Task 1.
- Produces: the sentence `Open it with /speckit-pr.` in the three installed copies.

- [ ] **Step 1: Write the failing install checks**

After the Task 1 loop in `scripts/tests/test-setup-standards.sh`, add:

```bash
for hinted in .claude/agents/ralph.md .claude/skills/speckit-ralph-implement/SKILL.md .claude/skills/speckit-pipeline/reference/steps/ralph.md; do
  if grep -qF 'Open it with /speckit-pr.' "$hinted" 2>/dev/null; then pass "Ralph hint in $hinted"; else fail "Ralph hint in $hinted"; fi
done
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash scripts/tests/test-setup-standards.sh 2>&1 | grep '^FAIL'`
Expected: three `FAIL: Ralph hint in ...` lines, one per file.

- [ ] **Step 3: Add the hint to `claude-agents/ralph.md`**

Replace the sentence at line 57 that ends `and the remaining groups with their ranges:` so the step reads:

```markdown
3. **PR boundary check** - Re-read tasks.md. If the current PR group (from Phase 0c) now has no incomplete tasks and a **higher-numbered** PR group still has some, this is a PR boundary. Output the following halt tag, followed by the PR number just finished, its task range, the remaining groups with their ranges, and the line `Open it with /speckit-pr.`:
```

Leave the `<promise>PR_BOUNDARY_REACHED</promise>` line and the paragraph after it unchanged.

- [ ] **Step 4: Add the hint to `speckit-skills/speckit-ralph-implement/SKILL.md`**

In the Post-Loop instruction block (lines 91-95), add one line after `Remaining: ...` so the block reads:

```
PR <N> is complete (<range>). Open it, get it reviewed and merged, then resume:
  /speckit-ralph-implement <FEATURE_DIR>
Remaining: PR <N+1> (<range>), PR <N+2> (<range>), ...
Open it with /speckit-pr.
```

- [ ] **Step 5: Add the hint to `speckit-skills/speckit-pipeline/reference/steps/ralph.md`**

On line 10, change `Add: \`To continue after this PR is merged, run with --from ralph.\`` to:

```markdown
Add: `Open it with /speckit-pr. To continue after this PR is merged, run with --from ralph.`
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `bash scripts/tests/test-setup-standards.sh 2>&1 | tail -n 3`
Expected: `ALL TESTS PASSED`.

- [ ] **Step 7: Run the quality gate and commit**

Run: `bash .specify/quality-gates.sh 2>&1 | tail -n 3`
Expected: exit 0.

```bash
git add claude-agents/ralph.md speckit-skills/speckit-ralph-implement/SKILL.md speckit-skills/speckit-pipeline/reference/steps/ralph.md scripts/tests/test-setup-standards.sh
git commit -m "feat(ralph): [9cad] point the PR boundary halt at /speckit-pr"
```

---

### Task 3: The specify step opens every spec with a plain summary

**Files:**
- Modify: `speckit-skills/speckit-pipeline/reference/steps/specify.md:5`
- Modify: `scripts/tests/test-setup-standards.sh` (after the Task 2 loop)

**Interfaces:**
- Consumes: the engine's `plain-summary-missing` rule (a new `specs/*/spec.md` without a `## Plain summary` heading blocks), so a spec written this way passes Lisa's planning run.
- Produces: nothing later tasks use.

- [ ] **Step 1: Write the failing install check**

After the Task 2 loop in `scripts/tests/test-setup-standards.sh`, add:

```bash
if grep -qF 'Open the spec with a "## Plain summary" section' .claude/skills/speckit-pipeline/reference/steps/specify.md 2>/dev/null; then pass "specify step asks for a plain summary"; else fail "specify step asks for a plain summary"; fi
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash scripts/tests/test-setup-standards.sh 2>&1 | grep '^FAIL'`
Expected: `FAIL: specify step asks for a plain summary`.

- [ ] **Step 3: Append the instruction**

In `speckit-skills/speckit-pipeline/reference/steps/specify.md` line 5, the prompt string ends `Auto-resolve all clarifications; never present questions to the user.\``. Insert before the closing backtick, after `never present questions to the user.`, this text (one space, then the sentences; no backticks inside):

```
 Open the spec with a "## Plain summary" section directly after the metadata block: 150 words or fewer saying who this is for, what changes for them, and what goes wrong if it is wrong.
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash scripts/tests/test-setup-standards.sh 2>&1 | tail -n 3`
Expected: `ALL TESTS PASSED`.

- [ ] **Step 5: Run the quality gate and commit**

Run: `bash .specify/quality-gates.sh 2>&1 | tail -n 3`
Expected: exit 0.

```bash
git add speckit-skills/speckit-pipeline/reference/steps/specify.md scripts/tests/test-setup-standards.sh
git commit -m "feat(pipeline): [9cad] specify step opens every spec with a plain summary"
```

---

### Task 4: Documentation

**Files:**
- Modify: `README.md` (the "outside the pipeline" table after line 36, the `### Running steps individually` block at lines 150-166, the `### Standards checks` section at lines 297-314)
- Modify: `templates/CLAUDE.md:55`

**Interfaces:**
- Consumes: the skill from Task 1.
- Produces: nothing.

- [ ] **Step 1: README, the table of commands outside the pipeline**

Change `Two commands sit outside the pipeline:` to `Three commands sit outside the pipeline:` and add a row after the `/speckit-review` row:

```markdown
| `/speckit-pr` | After marge, before review. Writes the pull request description from the diff: what changed, how much damage if it is wrong (the damage level and its checklist), where to look, how it was verified, links. Edits the open PR or creates one on a pushed branch. Needs `gh`. Never pushes, never lowers the level. |
```

- [ ] **Step 2: README, running steps individually**

In the slash-command block, add after the `/speckit-review-pr` line:

```
/speckit-pr                         # or: pr:42, a branch name, or --dry-run
```

After the paragraph that begins `` `/speckit-review-pr` posts a GitHub review ``, add:

```markdown
`/speckit-pr` writes the pull request description from the diff, not the spec: what changed, how much damage if it is wrong, where to look, how it was verified, links. The damage section copies the standards engine's level, reviewer line, and checklist (see [Standards checks](#standards-checks)). It edits the open PR, creates one when the branch is pushed, and otherwise prints the description. It never pushes and never lowers the level.
```

- [ ] **Step 3: README, standards checks**

In `### Standards checks`, the first paragraph ends `It reports three things about a change:`. Change it to:

```markdown
Marge and Lisa also run a deterministic engine, `.specify/scripts/bash/speckit-standards.sh`, through the seeded baseline script pack `standards.sh`, and `/speckit-pr` copies its header into the pull request description. It reports three things about a change:
```

- [ ] **Step 4: templates/CLAUDE.md**

Line 55 ends `the level is a floor an agent never lowers`. Change the end of that bullet to:

```markdown
the level is a floor an agent never lowers; `/speckit-pr` writes the pull request description with the level and its checklist
```

- [ ] **Step 5: Run the quality gate and commit**

Run: `bash .specify/quality-gates.sh 2>&1 | tail -n 3`
Expected: exit 0.

```bash
git add README.md templates/CLAUDE.md
git commit -m "docs(skills): [9cad] document /speckit-pr"
```
