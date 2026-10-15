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
- **Dry-run mode** — if `$ARGUMENTS` contains `--dry-run`, print the description and change nothing: no file edits, no commits, no GitHub writes. `gh pr view` and `git fetch` are read-only and still run.

`$ARGUMENTS` may also name the pull request: `pr:<number>`, a GitHub pull request URL, or a branch name. With nothing, the current branch is used.

## Never

- Never push, merge, rebase, or check out a branch. A branch that is not on the remote gets its description printed, with the push command for the person to run. You never push it.
- Never lower the damage level. It is a floor. Raising it with a reason is allowed.
- Never claim a check that was not run in this session.
- Never put a requirement id (`FR-001`, `SC-P1-003`, `US2`) in the description. The reviewer reads the diff, not the spec.
- Never ask for confirmation between steps. Run end to end, then report.

## Pre-flight: engine check

```bash
if test -x .specify/scripts/bash/speckit-standards.sh && test -f .specify/marge/config/damage-levels.yml; then echo "standards: OK"; else echo "standards: MISSING"; fi
```

If **MISSING**, display this error and **STOP**:

```
ERROR: Standards engine or its damage levels not found.

Needed: .specify/scripts/bash/speckit-standards.sh   (installed by setup.sh)
        .specify/marge/config/damage-levels.yml       (seeded by setup.sh)

/speckit-pr copies the damage level and its checklist from the engine, and
the engine is silent without damage-levels.yml. Run setup.sh, then re-run.
```

## Step 1: Base and state

1. **BRANCH** is `git branch --show-current`. If `$ARGUMENTS` names a branch that is not the current branch, **STOP**: `Check out <branch> and run again: /speckit-pr reads the local tree.`
2. Find the pull request. With `pr:<number>` or a pull request URL in `$ARGUMENTS`, run `gh pr view <number> --json number,url,baseRefName,headRefName,state 2>&1`. Otherwise:
   ```bash
   gh pr view --json number,url,baseRefName,headRefName,state 2>&1
   ```
   `no pull requests found` means there is none yet; that is not an error. Any other failure (not signed in, offline) is: **STOP** with the message gh printed. When `gh` is not installed, continue as if there were no pull request; Step 10 then prints instead of delivering.
3. If a pull request exists and its `headRefName` is not `BRANCH`, **STOP**: `Check out <headRefName> and run again: /speckit-pr reads the local tree.` If its `state` is not `OPEN`, **STOP**: `PR #<number> is <state>.`
4. **BASE_REF_NAME**: the pull request's `baseRefName`. Without a pull request: `main`, or `master` when neither `origin/main` nor `main` resolves with `git rev-parse --verify --quiet <ref>^{commit}`.
5. Fetch, so the base and the remote copy of the branch are current. A fetch is a read: it is neither a push nor a checkout.
   ```bash
   git fetch origin <BASE_REF_NAME> 2>/dev/null
   git fetch origin <BRANCH> 2>/dev/null
   ```
   Either may fail (no remote, branch never pushed). Continue.
6. **BASE**: `origin/<BASE_REF_NAME>` when `git rev-parse --verify --quiet origin/<BASE_REF_NAME>^{commit}` succeeds, else `<BASE_REF_NAME>`.
7. **PUSHED**: true when `git rev-parse --verify --quiet origin/<BRANCH>^{commit}` succeeds. (Do not use `@{upstream}`: `speckit-commit.sh` pushes without setting one.)
   - When pushed, **UNPUSHED** is `git rev-list --count origin/<BRANCH>..HEAD`, and **BEHIND** is `git rev-list --count HEAD..origin/<BRANCH>`. If `BEHIND` is above 0, **STOP**: `origin/<BRANCH> has <BEHIND> commits this checkout lacks. Pull them and run again.`
   - When not pushed, **UNPUSHED** is `git rev-list --count <BASE>..HEAD`.

Capture `PR_NUMBER`, `PR_URL`, `BASE_REF_NAME`, `BASE`, `BRANCH`, `PUSHED`, `UNPUSHED`. Each Bash call is a fresh shell: substitute the literal values in later commands.

## Step 2: Run the checks

```bash
bash .specify/scripts/bash/speckit-standards.sh --base <BASE> --format text
```

Keep the whole output. The first lines are the damage level header, copied in Step 5:

```
Damage level: critical (set by app/policies/x.rb, app/services/pay/send.rb, app/services/pay/z.rb and 2 more)
Read every line. Work the checklist.
  - What happens if this runs twice?
  - Who can reach this? Can a secret or personal data end up in a log?
```

Then the findings, one per line, blocking ones first with a `BLOCK` prefix:

```
BLOCK HIGH   specs/9cad-feat-x/spec.md:1  plain-summary-missing: a new spec must open with a "## Plain summary" section
MEDIUM specs/9cad-feat-x/spec.md:5  long-sentence: 31 words: "The nightly job writes every open order to the ledger before the…"
```

- Exit code 2 means the engine could not run. Print its message and **STOP**.
- In dry-run mode, edit nothing. Keep the `BLOCK` lines for the report in Step 10.
- In deliver mode, a `BLOCK` line is fixed now, in the file it names, and committed before the description is written: nothing checks the change again later. Stage only the files you edited (`git add <file>`), then commit with `git commit`, never with `speckit-commit.sh` (it pushes). Subject: `fix(<scope>): [<ticket>] <what was fixed>`, with `<ticket>` and `<scope>` from the branch name as in Step 10. Re-run the engine and confirm no `BLOCK` line remains. Recount `UNPUSHED`: a fix commit makes it at least 1.
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
   Only a `PULL_REQUEST:0` line is about the draft: `BLOCK HIGH   PULL_REQUEST:0  requirement-id-in-body: ...` names the ids to remove. Rewrite the sentence without them, save, and run again until no `PULL_REQUEST:0` line is printed. Any other `BLOCK` line is one Step 2 kept in dry-run mode; it goes under `Blocked by:` in Step 10. Never deliver a draft the engine blocks.

## Step 10: Deliver

Build the title from the branch name the way `speckit-commit.sh` does: `<ticket>-<type>-<scope...>` gives `<type>(<scope>): [<ticket>] <description>`, where `<description>` is a phrase under 60 characters taken from Step 4. A branch that does not fit `<ticket>-<type>-<scope>` gets `<description>` alone as the title.

The description ends with the attribution lines the session gives (the `🤖 Generated with ...` block), when it gives any.

- **Dry-run**: print the title and the description. Then print any `BLOCK` lines from Step 2 under `Blocked by:`; deliver mode fixes them. Done.
- **A pull request exists**: `gh pr edit <PR_NUMBER> --body-file <draft>`. Print `PR_URL`.
- **No pull request, pushed, `UNPUSHED` is 0**: `gh pr create --base <BASE_REF_NAME> --head <BRANCH> --title "<title>" --body-file <draft>`. Print the URL it returns.
- **Not pushed, or `UNPUSHED` above 0 with no pull request, or `gh` missing**: print the title and the description, then `Not on the remote. Push it, then run /speckit-pr again:` and the command `git push -u origin <BRANCH>`. You never push it.

End with a report: what was delivered (edited #N, created #N, or printed), `UNPUSHED` when above 0 (`<n> local commits are not on the remote; push before review`), and the fix commit from Step 2 when one was made, and, when `git status --porcelain` prints anything, `<n> uncommitted changes are not in this description`.

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
- `/speckit-pr 9cad-feat-standards-checks` — a branch by name; it must be the checked-out branch
