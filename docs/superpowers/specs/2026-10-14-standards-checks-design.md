# Standards checks: damage level, PR shape, plain language, `/speckit-pr`

**Date**: 2026-10-14
**Status**: design approved in conversation; awaiting written review
**Branch**: `9cad-feat-standards-checks` (stacked on `6625-chore-port-reset-dogfood`)

## Goal

Generalize the review standards Reset built while dogfooding Simpsons Loops so every consumer gets them from `setup.sh`:

1. A **damage level** for a change, decided by which files it touches, with a reviewer line and a checklist per level.
2. **PR shape** rules: requirement ids kept out of the description, specs not mixed with code, a new spec opens with a short plain summary.
3. **Plain language** rules: sentence length, comment length, filler verbs, invented phrases, undefined terms.
4. A **`/speckit-pr`** skill that writes the pull request description from the diff, with the damage level and its checklist.
5. A **Stop hook** that sends an interactive agent back when a blocking finding exists in its uncommitted work.

Reset's implementation is Ruby (`bin/standards/check`, `lib/standards/`, RSpec). Simpsons Loops ships Bash and Markdown only, so the engine is rewritten in Bash with awk. Reset's rules, severities, config file names, and config shape are kept so Reset's data migrates by a small diff.

## Non-goals

- CI wiring. The engine runs where an agent runs: Marge, Lisa, `/speckit-pr`, the Stop hook, or a person's shell.
- Size or reading-grade metrics. The damage level says how hard to look; long words are never counted.
- A flag to lower a damage level. The level is a floor; an agent never lowers it, and a person does so in the description with a reason.
- YAML beyond the documented subset, anchors, flow mappings, multi-document files.
- `--format json`, a `--fix` mode, per-language parsers beyond a comment-prefix table.
- Reset's `servicer-suffix` and `sync-groups` checks. They are Rails and Reset specific and stay as Reset project packs.

## Decisions already made

| Question | Decision |
|---|---|
| Engine runtime | Bash 4 with awk, grep, sed, git. No Ruby, Python, jq, or yq required. jq is used only by `setup.sh` for the settings merge, as it already is for permissions cleanup. |
| Packaging | A **baseline script pack**: the engine is framework code (overwritten on update); a thin wrapper `baseline/standards.sh` is seeded once; `run-gates.sh` learns to run `baseline/*.sh`. Findings carry no `PROJECT_GATE` because they are generic standards, not project continuity rules. |
| Stop hook | Shipped, as the last phase. `setup.sh` merges the settings entry once with jq, never re-adds it. |
| Delivery | Three phases, each shippable alone (see Phases). |

---

## 1. Engine: `scripts/speckit-standards.sh`

Ship-source `scripts/speckit-standards.sh`; installed to `.specify/scripts/bash/speckit-standards.sh` (overwritten, `chmod +x`), next to `speckit-commit.sh`.

### 1.1 CLI

```
speckit-standards.sh (--base REF | --working-tree | --dir PATH [--base REF])
                     [--body-file FILE] [--only GROUP[,GROUP...]]
                     [--blocking-only] [--format text|marge|hook]
```

| Flag | Meaning |
|---|---|
| `--base REF` | The branch diff: `REF...HEAD`. Marge and `/speckit-pr`. |
| `--working-tree` | Uncommitted changes against `HEAD`, plus untracked files. The Stop hook. |
| `--dir PATH` | What the branch changed under `PATH` since its merge base with `--base` (default `origin/main`, falling back to `HEAD` when the ref is unknown), plus untracked files under `PATH`. Lisa, at planning time. |
| `--body-file FILE` | A pull request description to scan for requirement ids. |
| `--only` | Run only these groups: `lexicon`, `plain-language`, `pr-shape`, `unrated-path`. Default: all. An unknown group is a usage error (exit 2). |
| `--blocking-only` | Report only findings that block. |
| `--format` | `text` (default), `marge`, `hook`. See 1.7. |

Exactly one of `--base`, `--working-tree`, `--dir` is required. The engine changes directory to `git rev-parse --show-toplevel` before reading anything. Config is read from `.specify/marge/config/` under that root.

**Exit codes**: `0` clean or advice only; `1` at least one finding blocks; `2` the engine could not run (bad usage, git failure, unreadable config). A crash is never a verdict.

### 1.2 Change set

Every rule works from one list of changed files so all callers see the same lines.

- `--base REF`: `git diff --name-status -M REF...HEAD` for paths and status (first letter of `A`, `M`, `D`, `R100` and the like; a rename contributes its new path), and `git diff -U0 -M REF...HEAD` for added lines with their line numbers from each `@@ -a,b +c,d @@` header.
- `--working-tree`: the same two commands against `HEAD`, plus `git ls-files --others --exclude-standard`, each untracked file read from disk as status `A` with every line added.
- `--dir PATH`: the same against the merge base, limited with `-- PATH`, plus untracked files under `PATH`.

Files larger than 1 MB, binary files, and files whose bytes are not valid UTF-8 keep their path (the damage level still counts them) but carry no lines. `git` is run with `-c core.quotePath=false`.

**Prose lines** are the added lines a person reads:

- In `.md`, `.markdown`, `.txt`: added lines outside fenced code blocks. Fence state is computed over the whole file on disk when the file is the new side of the diff (every added line is where the diff says), else over the added lines alone.
- In code files: added lines that are comments, by extension. `#` for `rb`, `rake`, `py`, `sh`, `bash`, `zsh`, `yml`, `yaml`, `toml`; `//` for `ts`, `tsx`, `js`, `jsx`, `mjs`, `cjs`, `go`, `rs`, `java`, `kt`, `swift`, `c`, `h`, `cc`, `cpp`, `cs`, `scala`. The prefix is stripped before any rule sees the line. Other extensions have no prose lines.

Inline code (`` `...` ``) and URLs are blanked before any word rule runs, so a class name or a link never trips the lexicon.

### 1.3 Rules

Rule names, severities, and blocking are Reset's. `--only` group in the first column.

| Group | Rule | What it finds | Severity | Blocks | Tags |
|---|---|---|---|---|---|
| pr-shape | `requirement-id-in-body` | A requirement id (`FR-001`, `SC-P1-003`, `US2`, `NFR-`, `SR-`, `CHK-`, `AS-`) in the `--body-file` prose, outside inline code and URLs | HIGH | yes | |
| pr-shape | `specs-mixed-with-code` | The change set has a file under `specs/` and a code file (any changed path not under `specs/` or `docs/` and not `.md`/`.txt`) | MEDIUM | no | NEEDS_HUMAN |
| pr-shape | `many-boundaries` | Changed files match two or more distinct boundaries from `damage-levels.yml` `boundaries:` | MEDIUM | no | NEEDS_HUMAN |
| pr-shape | `plain-summary-missing` | A new `specs/*/spec.md` (status `A`) has no `## Plain summary` heading (case-insensitive) | HIGH | yes | |
| pr-shape | `plain-summary-too-long` | The text between `## Plain summary` and the next `#`/`##` heading is over 150 words | HIGH | yes | |
| plain-language | `long-sentence` | A sentence over 25 words in added prose. Sentences are found in the paragraph (consecutive added lines up to a blank line, heading, list item, table row, or quote), after Markdown is stripped: fences and inline code, tables, links to their text, headings and list items become their own sentences, emphasis marks removed | MEDIUM | no | |
| plain-language | `long-comment` | More than 4 consecutive added comment lines in a code file | MEDIUM | no | |
| lexicon | `lexicon-banned` | A `banned:` pattern in added prose | HIGH | yes | |
| lexicon | `lexicon-prefer` | A `prefer:` pattern | MEDIUM | no | |
| lexicon | `plain-verb` | A `soft_verbs:` pattern | LOW | no | |
| lexicon | `invented-phrase` | A modifier word followed by a listed generic noun (`vendor-neutral seam`, `the dispatch surface`), or any `<word>-<suffix>` compound before a noun. A listed noun after an article or on its own is not flagged; `allowed:` phrases never are | MEDIUM | no | |
| lexicon | `lexicon-new-term` | A Title Case phrase of 2 to 4 words first seen in a new `specs/` file, outside headings and tables, not in `known_terms:`. One hint per phrase per file; a phrase at sentence start loses its first word | LOW | no | NEEDS_HUMAN |
| unrated-path | `unrated-path` | An added file inside a `unit_dirs:` unit whose level was set only by a catch-all pattern (`<dir>/**/*`) or by the default, where every file on disk under that unit is in this change (a new unit) | MEDIUM | no | NEEDS_HUMAN |

Findings with `NEEDS_HUMAN` are decisions, not edits: Marge leaves them, `/speckit-review-pr` posts them. Everything else Marge may fix.

`lexicon.yml` `exempt_paths:` globs are never scanned by the lexicon group. Rules in `plain-language` and `pr-shape` have no exemptions.

### 1.4 Damage level

Read from `damage-levels.yml`. Not a finding: an **assessment** printed at the top of `--format text` and used by `/speckit-pr`.

- A file gets the level of the **most specific** matching pattern (specificity = pattern length without `*?[]{}`), a tie going to the more serious level. Levels are listed most to least serious in the file.
- A level's patterns are its `paths:` plus the `paths:` of its path-scoped checklist questions.
- `aliases:` let one path be matched as if it also lived elsewhere (Reset's "a job takes its service directory's level" becomes `from: app/jobs/`, `to: app/services/`).
- A path matching nothing gets `default_level`.
- The change gets the **highest** level of any file in it, `triggered_by` the files at that level, and the level's checklist with path-scoped questions included only when the change touches one of their paths. An empty change set gets the least serious level.

Globs use shell syntax with `**` crossing directories and `*` stopping at `/`, like Reset's `fnmatch` with `FNM_PATHNAME`. The engine converts each glob to an ERE once: `**/` to `(.*/)?`, `**` to `.*`, `*` to `[^/]*`, `?` to `[^/]`, other regex metacharacters escaped. Matching is against the path relative to the repo root.

### 1.5 Config files and the YAML subset

Both files live in `.specify/marge/config/`, both are consumer-owned, both are seeded once by `setup.sh` from `specify-marge/config/`. If `damage-levels.yml` is absent the engine prints nothing and exits 0 (inert by default, the convention for config-backed packs). If only `lexicon.yml` is absent the lexicon group is skipped.

**`damage-levels.yml`**

```yaml
default_level: user-facing
aliases:                       # optional
  - from: app/jobs/
    to: app/services/
unit_dirs:                     # optional; units for unrated-path
  - app/services/*
  - app/models/*.rb
boundaries:                    # optional; for many-boundaries. The first
  - app/services/vendor_*/**   # wildcard segment names the boundary.
levels:                        # most to least serious
  - name: critical
    reviewer: >-
      Read every line. Work the checklist.
    checklist:
      - What happens if this runs twice?
      - question: >-
          Who can reach this? Can a secret or personal data end up in a log?
        paths:
          - app/policies/**/*
    paths:
      - db/migrate/**/*
```

**`lexicon.yml`**

```yaml
banned:
  - pattern: 'underwrit[[:alnum:]_]*'
    use: risk assessment
    why: optional explanation shown in the finding
prefer:
  - pattern: 'consumers?'
    use: member
    unless:                    # optional; a line matching any of these is skipped for this entry
      - 'to-consumer'
      - 'consumer (product|app|codebase|side|flow)'
soft_verbs:
  - pattern: 'utili[sz][[:alnum:]_]+'
    use: use
invented_phrases:
  nouns: [seam, surface, layer, boundary, mechanism, harness, lever, facade, scaffold, shim, indirection, construct, topology, chokepoint, primitive, fabric, substrate, plane, scaffolding, machinery, touchpoint, affordance]
  compound_suffixes: [neutral, agnostic, aware, driven, centric, oriented]
  allowed: [test harness, attack surface]
exempt_paths:
  - .specify/marge/config/lexicon.yml
known_terms:
  - User Story
  - Success Criteria
```

Patterns are **POSIX ERE**, matched case-insensitively. The engine adds the word-boundary guards itself (`(^|[^[:alnum:]_])` before and `([^[:alnum:]_]|$)` after), so a pattern never needs `\b`. No lookaround: `unless:` replaces it, tested against the whole line.

**Parser subset** (one awk program, shared by both files):

- Two-space indentation. Mappings `key: value` or `key:` with a nested block. Sequences as `- item` or `- key: value` starting a nested mapping.
- Scalars: plain, single-quoted, double-quoted, or `>-` folded (following more-indented lines joined by single spaces, trailing newline dropped). Inline lists `[a, b, c]` of plain scalars are accepted for `nouns`, `compound_suffixes`, `allowed`, and the empty list `[]`.
- `#` starts a comment outside quotes. Blank lines are ignored.
- Anything else (anchors, flow mappings, multi-line quoted scalars, tabs) is a usage error: exit 2 with the file and line.

Condensed copies of Reset's `damage-levels.yml` and `lexicon.yml`, keeping every syntax feature they use (folded scalars, path-scoped questions, quoted globs, comments between list items), are the parser's fixtures under `scripts/tests/fixtures/standards/`, with the lookbehind patterns rewritten as `unless:`.

### 1.6 Finding fields

`file` (path relative to the root, or `PULL_REQUEST` for body findings), `line` (0 when not line-specific), `severity`, `rule`, `issue` (one line), `fix` (one line, present for every rule), `blocking`, `tags`. Findings are sorted blocking first, then severity HIGH, MEDIUM, LOW, then file, then line.

### 1.7 Output formats

**`text`** (people and `/speckit-pr`):

```
Damage level: critical (set by db/migrate/20261014_x.rb, app/services/pay/send.rb, app/policies/x.rb and 1 more)
Read every line. Work the checklist.
  - What happens if this runs twice?
  - Who can reach this? Can a secret or personal data end up in a log?
BLOCK HIGH   PULL_REQUEST:0  requirement-id-in-body: the description leans on requirement ids: FR-003
MEDIUM specs/9cad-feat-x/spec.md:14  long-sentence: 31 words: "The nightly job writes…"
```

`set by` lists up to three files; `nothing in this change raises it` when the default level won. `No findings.` when there are none.

**`marge`** (the pack contract in `.specify/marge/README.md`): one YAML sequence item per finding, nothing when there are none.

```yaml
- file: specs/9cad-feat-x/spec.md:14
  severity: MEDIUM
  confidence: 95
  pack: baseline/standards.sh
  rule: long-sentence
  issue: "31 words: ..."
  fix: "split it; aim for 15 words, never more than 25"
  tags: []
```

`tags: [NEEDS_HUMAN]` for the rules marked so above. Never `PROJECT_GATE`. Double-quoted scalars with `"` and `\` escaped.

**`hook`** (Claude Code Stop hook contract): empty output when nothing blocks; otherwise one JSON object `{"decision":"block","reason":"A standards check blocks this change. Fix these before finishing:\n<location>  <rule>: <issue>\n..."}` with at most 8 reasons, JSON-escaped.

---

## 2. Packs, runner, seeds

### 2.1 `run-gates.sh`

Today the runner globs `.specify/marge/project/*.sh`. It gains the same loop over `.specify/marge/baseline/*.sh`, run first, with the same 120 s timeout and the same stdout/stderr handling. A failed baseline pack produces the `pack-execution` meta-finding with `pack: baseline/<name>` and `tags: [NEEDS_HUMAN]`; a failed project pack keeps `pack: project/<name>` and `tags: [PROJECT_GATE, NEEDS_HUMAN]`. The planning-stage opt-in line applies to both directories.

### 2.2 Wrapper: `specify-marge/baseline/standards.sh`

Seeded once to `.specify/marge/baseline/standards.sh` (`chmod +x`), like the baseline prose packs: edit `--only` to tune, delete to opt out, updates never touch it.

```sh
#!/usr/bin/env bash
# Runs the shipped standards engine (damage level, lexicon, plain language,
# PR shape) as a baseline script pack. Edit --only to tune; delete to opt out.
# Contract: .specify/marge/README.md.
# speckit-stage: planning
set -uo pipefail

engine=".specify/scripts/bash/speckit-standards.sh"
[ -x "$engine" ] || exit 0
base="${SPECKIT_BASE_REF:-origin/main}"

# /speckit-review-pr passes the pull request's file list without checking out
# its head. Refuse when the checkout disagrees, rather than report on the wrong tree.
checkout_matches_pull_request() {
  [ -n "${SPECKIT_DIFF_FILES:-}" ] || return 0
  given="$(printf '%s\n' "$SPECKIT_DIFF_FILES" | sed '/^$/d' | sort -u)"
  local_all="$(git diff --name-only --no-renames "$base...HEAD" 2>/dev/null | sort -u)"
  local_new="$(git diff --name-only -M "$base...HEAD" 2>/dev/null | sort -u)"
  not_here="$(comm -23 <(printf '%s\n' "$given") <(printf '%s\n' "$local_all"))"
  not_in_pr="$(comm -23 <(printf '%s\n' "$local_new") <(printf '%s\n' "$given"))"
  [ -z "$not_here$not_in_pr" ] && return 0
  echo "standards.sh: the checkout is not the pull request head; check it out and run again" >&2
  return 1
}

code=0
if [ "${SPECKIT_STAGE:-review}" = planning ]; then
  [ -n "${SPECKIT_FEATURE_DIR:-}" ] || exit 0
  bash "$engine" --dir "$SPECKIT_FEATURE_DIR" --base "$base" \
       --only lexicon,plain-language,pr-shape --format marge || code=$?
else
  checkout_matches_pull_request || exit 2
  bash "$engine" --base "$base" --format marge || code=$?
fi
[ "$code" -le 1 ] || exit "$code"   # 1 = a finding blocks, a normal run for a pack
exit 0
```

### 2.3 Seeds: `specify-marge/config/damage-levels.yml` and `lexicon.yml`

Seeded once each. Not read by `setup.sh` from any hidden directory.

`damage-levels.yml` ships Reset's five levels with generic names and Reset's reviewer lines and checklists, worded for any product: `critical` (moves money or data of record, decides who may act, stores secrets or personal data, changes what a user is told or agrees to), `user-facing`, `specification` (`specs/**/*`), `internal`, `no runtime effect` (`docs/**/*`, `**/*.md`, test directories). `default_level: user-facing`. Every path list beyond `specs/`, `docs/`, and Markdown is a commented example the consumer replaces. `aliases:`, `unit_dirs:`, `boundaries:` are present, empty, and explained in comments.

`lexicon.yml` ships the generic `soft_verbs`, `invented_phrases` (nouns, suffixes, allowed), and `known_terms` (Spec Kit heading phrases: `User Story`, `Success Criteria`, `Functional Requirements`, `Key Entities`, `Edge Cases`, `Plain Summary`, `Acceptance Scenarios`, `Independent Test`, `Given`, `When`, `Then`), empty `banned:` and `prefer:`, and `exempt_paths:` naming itself.

### 2.4 Plain summary for parent specs

Upstream Spec Kit's `/speckit-specify` and `spec-template.md` stay untouched. Two shipped places add the section:

- The pipeline's specify step (`speckit-skills/speckit-pipeline/reference/steps/specify.md`) appends to its existing `EXTRA_INSTRUCTIONS`: *Open the spec with `## Plain summary` directly after the metadata block: 150 words or fewer saying who this is for, what changes for them, and what goes wrong if it is wrong.*
- Lisa's planning run executes the wrapper with `--dir <FEATURE_DIR>`, so a new spec without the section is a `plain-summary-missing` finding Lisa fixes by writing one.

`/speckit-split` already adds it to child specs (ported 2026-10-14).

---

## 3. `/speckit-pr` skill

New ship-source directory `speckit-skills/speckit-pr/SKILL.md`, installed by the existing skills loop. Trigger: `/speckit-pr [PR number | branch] [--dry-run]`, "write the PR description", "open a pull request".

What it produces: a description in the five sections of `.github/pull_request_template.md` when that file exists, else these built in: **What changed**, **How much damage if it is wrong**, **Where to look**, **How it was verified**, **Links**. It never pushes, never merges, never lowers the level.

Steps:

1. **Base and state.** `gh pr view --json number,url,baseRefName,headRefName,state` for the current branch; base is the PR's base ref, else `origin/main`. Note whether the branch is pushed (`git rev-parse --abbrev-ref @{upstream}`).
2. **Run the checks.** `bash .specify/scripts/bash/speckit-standards.sh --base <base> --format text`. If anything is marked `BLOCK`, fix it first; nothing checks the change again later. If the change adds or edits a spec, fix its advice findings too, because the spec is what the reviewer reads.
3. **Read the diff, not the spec.** `git diff <base>...HEAD --stat` and the hunks that matter.
4. **What changed.** Three to six sentences on what a user or an operator can now do, or no longer can. Use the words in `config/lexicon.yml` when it exists. Never a requirement id; step 9 checks.
5. **How much damage if it is wrong.** Copy the engine's header: level, `set by` files, reviewer line, checklist as `- [ ]` items. One sentence on why the level fits. Raise it if it understates the risk, with a reason. Never lower it.
6. **Where to look.** One to three `file:line` hunks that need judgment; say the rest is mechanical.
7. **How it was verified.** What was run and what it said, with numbers. Never claim a check that was not run.
8. **Links.** The spec directory once, the ticket, the error tracker item.
9. **Self-check.** Every sentence under 25 words, no term built from generic parts. Save the draft to a temp file and run `speckit-standards.sh --base <base> --body-file <draft> --format text`; a `BLOCK` is a requirement id to remove.
10. **Deliver.** `--dry-run` prints. Pushed with a PR: `gh pr edit <n> --body-file`. Pushed without one: `gh pr create --base <base> --body-file --title "<type>(<scope>): [<ticket>] <description>"` with type, scope, and ticket derived from the branch name the way `speckit-commit.sh` does. Not pushed: print the description and tell the person to push. End with the attribution lines the session gives.

**Ralph hint.** `claude-agents/ralph.md` Phase 3 step 3, `speckit-ralph-implement/SKILL.md` Post-Loop report, and the pipeline's ralph step `pr-boundary` message each add one line: `Open it with /speckit-pr.`

---

## 4. Stop hook (phase 3)

Ship-source `scripts/speckit-standards-stop.sh`; installed to `.claude/hooks/speckit-standards-stop.sh` (overwritten, `chmod +x`).

Behaviour, in order; every exit is `0` and silent except the last:

1. Read the hook JSON from stdin. Extract `stop_hook_active` and `cwd` with jq when available, else with sed on the two known keys. Unparseable input: no opinion.
2. `stop_hook_active` true: exit (Claude is already continuing because of this hook; never loop).
3. `cd` to `cwd`, else `$CLAUDE_PROJECT_DIR`, else `.`. Not inside a git work tree, engine not executable, or `git status --porcelain --untracked-files=all` empty: exit.
4. Run `.specify/scripts/bash/speckit-standards.sh --working-tree --blocking-only --only lexicon,pr-shape --format hook`. `plain-language` is advice and the slow group, so it is left out.
5. Engine exit `1` with non-empty output: print it (the `{"decision":"block",...}` object). Exit `0` or `2`: print nothing.

Fails open: any error in the script means no opinion, never a stuck session.

**`setup.sh`**: copies the script. On the install where the script did not previously exist, and `jq` is available, and `.claude/settings.json` has no `Stop` entry whose command contains `speckit-standards-stop.sh`, it merges one:

```json
{"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/speckit-standards-stop.sh", "timeout": 30}]}]}}
```

Atomic write (temp file, `mv`); other hooks untouched; the file is created when absent. Without jq, or when the script already existed, it prints the snippet instead. Removing the entry opts out permanently.

---

## 5. `setup.sh`, documentation, tests

### 5.1 `setup.sh`

- Copy `scripts/speckit-standards.sh` to `.specify/scripts/bash/` (overwrite, `chmod +x`), with the commit helper.
- Extend the baseline seeding loop from `*.md` to `*.md` and `*.sh` (`chmod +x` for `.sh`), so `baseline/standards.sh` is seeded once.
- Seed `config/damage-levels.yml` and `config/lexicon.yml` once, next to the refreshed `config/README.md`.
- Phase 3: copy the hook, merge the settings entry as in section 4.
- Echo each new path with the existing "Copied files" and "Seeded" lines. No change to `gitignore`.

### 5.2 Documentation

| File | Change |
|---|---|
| `README.md` | Install table rows for the engine, wrapper, two seeds, hook. `What's in the box`: a row for `/speckit-pr` (optional, after marge, needs `gh`). `## Customization`: new `### Standards checks` (what blocks, what advises, the level is a floor, filling the path lists, `--only`, opting out, the Stop hook). |
| `specify-marge/README.md` | Glossary and layout: `baseline/` holds shipped prose packs and the one shipped script pack; its findings never carry `PROJECT_GATE`. Script pack contract: the runner runs `baseline/*.sh` then `project/*.sh`; the meta-finding's `pack:` and tags follow the origin. |
| `specify-marge/config/README.md` | Names the two seeded files and the engine that reads them. |
| `speckit-skills/speckit-review/reference/pack-execution.md` §3 | Script packs come from both directories; items from `baseline/` carry no `PROJECT_GATE`. |
| `claude-agents/lisa.md` step 1, `claude-agents/marge.md` File Paths | Mention `baseline/*.sh`. |
| `speckit-skills/speckit-review-pr/SKILL.md` | Standards findings from `baseline/standards.sh` follow the existing rule: posted only when `NEEDS_HUMAN`. |
| `templates/CLAUDE.md` | One Speckit bullet: standards checks run in Marge and Lisa; `/speckit-pr` writes the description with the damage level. |
| `.specify/quality-gates.sh` (this repo) | Shellcheck `scripts/*.sh`, `scripts/tests/*.sh`, `specify-marge/baseline/*.sh`; run `bash scripts/tests/test-*.sh`. |

### 5.3 Tests

Same style as `scripts/tests/test-speckit-commit.sh`: a sandbox repo per case, `PASS`/`FAIL` lines, non-zero exit on any failure. Fixtures under `scripts/tests/fixtures/standards/`.

`scripts/tests/test-speckit-standards.sh`:

- Parser: the two fixture files load; level count, order, folded `reviewer`, a path-scoped question's `paths`, inline list, `>-` with blank continuation; a tab or an anchor exits 2 naming the line.
- Damage level: most specific wins; tie goes to the more serious level; alias; default level; `set by` list; path-scoped question asked only when touched; empty change set.
- Each rule: one positive and one negative case, including inline code and URL blanking, fence handling, comment prefix stripping, `unless:`, `allowed:`, `exempt_paths:`, `known_terms:`, sentence-start handling for `lexicon-new-term`, catch-all detection for `unrated-path`.
- Modes: `--base`, `--working-tree` with an untracked file, `--dir` with an untracked spec; a rename; a binary file.
- Output: exit codes 0, 1, 2; `--only`; `--blocking-only`; all three formats, including YAML escaping of `"` and `\` and JSON escaping in `hook`.
- Config absent: `damage-levels.yml` missing prints nothing and exits 0; `lexicon.yml` missing skips the lexicon group only.

`scripts/tests/test-run-gates.sh`: a baseline script pack is discovered and run before a project pack; a failing baseline pack yields `pack: baseline/<name>` with `[NEEDS_HUMAN]`; planning stage runs only opted-in packs from both directories.

`scripts/tests/test-speckit-standards-stop.sh` (phase 3): `stop_hook_active` true is silent; clean tree is silent; a banned word in an untracked `.md` prints the block JSON; engine exit 2 is silent; malformed JSON is silent.

---

## 6. Phases

| Phase | Ships | Done when |
|---|---|---|
| 1 | Engine, wrapper, two seeds, runner loop, `setup.sh`, docs, tests | A consumer runs `setup.sh`, fills `damage-levels.yml` paths, and Marge and Lisa report standards findings; `bash .specify/scripts/bash/speckit-standards.sh --base origin/main` prints the level and findings. |
| 2 | `/speckit-pr`, Ralph hint, specify-step instruction | `/speckit-pr --dry-run` prints a five-section description with the level and checklist; the pipeline's specify step produces a spec that opens with `## Plain summary`. |
| 3 | Stop hook, settings merge | An interactive session that writes a banned word into a new spec is sent back once with the reason. |

Each phase is one pull request on this branch's stack, or three stacked branches.

## 7. Reset migration (guaranteed here, done in Reset)

- `damage-levels.yml`: level names stay as data; add `aliases: [{from: app/jobs/, to: app/services/}]`, `unit_dirs: [app/services/*, app/models/*.rb]`, `boundaries: [app/services/reset_*/**, app/jobs/reset_*/**]`.
- `lexicon.yml`: `\w` becomes `[[:alnum:]_]`; the two lookaround patterns become `unless:` lists; `exempt_paths` drops the Ruby library entries.
- Delete `bin/standards/check`, `lib/standards/`, `spec/lib/standards/`, `.specify/marge/project/standards.sh`, `.claude/skills/reset-pr/`, `.claude/hooks/stop-standards.sh`, and the `Stop` entry it registered (the shipped hook replaces it).
- Keep `servicer-suffix` as a Reset project pack (script or prose) and `docs/standards/*` as the human guides, pointing at the shipped engine.

## 8. Size

Roughly: engine 700 lines of Bash and awk, wrapper 40, seeds 200, runner change 30, `setup.sh` 50, skill 120, hook 40, tests 600, docs 150.
