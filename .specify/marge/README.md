# Marge review packs

Marge (`/speckit.review`) and Lisa (`/speckit.lisa.analyze`) find issues by running **packs** against a code diff or a spec. This directory holds them.

## Glossary — read this first

Three terms get confused because they share words. They are different things:

- **Pack** — a finding source the review/planning loops run. Every pack emits findings in one shared YAML shape (below). A pack runs in one of two **modes**, told apart by file extension:
  - **prose pack** (`.md`) — a sub-agent reads the rule text and applies it. LLM-interpreted.
  - **script pack** (`.sh`) — `run-gates.sh` executes it; no LLM. Deterministic.

  The extension *is* the mode. You never choose a mode by picking a directory.

- **`PROJECT_GATE`** — a *tag* a finding carries, not a file and not a directory. It marks the finding as a repo-specific continuity rule (e.g. "these sibling files must change together") rather than a generic code-quality issue. **It is derived from location:** every finding from a pack under `project/` carries it; findings from `baseline/` never do. Its one effect: `/speckit.review.pr` always posts `PROJECT_GATE` findings as inline comments, even mechanical ones. Orthogonal to mode — both prose and script packs carry it, though they get it differently: a prose pack has it **stamped automatically**, a script pack **writes it into its own YAML** (see Authoring).

- **Quality gate** (`.specify/quality-gates.sh`) — **unrelated to the above.** The CI-style lint / test / type-check script whose non-zero exit reverts a fix and can stop the Ralph and Marge loops. Pass/fail, not findings. Not a pack, not a `PROJECT_GATE`. Named here only to retire the collision: inside this directory, "gate" never means a pack — it survives only in the tag name `PROJECT_GATE` and in "quality gate."

## Layout

| Path | Holds | Owner |
|------|-------|-------|
| `baseline/` | shipped prose packs (`security.md`, `concurrency.md`, …) — generic code-quality rules | framework. `setup.sh` seeds them; customize in `project/`, not here. |
| `project/` | your repo's packs: `.md` (prose) and `.sh` (script), side by side. Findings are tagged `PROJECT_GATE`. | you |
| `config/` | `*.yml` / `*.json` data read by config-backed prose packs in `project/` | you |
| `run-gates.sh` | the runner that executes every `project/*.sh` script pack | framework |

A file's path and suffix tell you everything: `baseline/security.md` is a shipped prose pack; `project/dsl-sync.md` is a project prose pack (its findings get `PROJECT_GATE`); `project/sibling-sync.sh` is a project script pack (same tag). Origin lives in the directory, mode lives in the extension.

There are deliberately **no READMEs inside `baseline/` or `project/`**: the loops glob those directories for packs (`*.md`) and scripts (`*.sh`), so a stray doc would be read as a pack. All authoring docs live in this file and in `config/README.md`.

## Where packs run (venues)

- **Marge** — `/speckit.review` runs every `baseline/` and `project/` pack against the branch diff. *(default)*
- **PR review** — `/speckit.review.pr` posts `PROJECT_GATE` findings as inline GitHub comments. Generic findings Marge already fixed are dropped there; `PROJECT_GATE` findings are always kept, because an out-of-band reviewer cannot otherwise see them.
- **Lisa** — `/speckit.lisa.analyze` (planning) runs only the packs that opt into the planning stage, against `spec.md` / `plan.md` / `tasks.md`, before code exists.

Script packs are repo-committed shell, executed locally by whoever runs a review. Checking out a branch and reviewing it runs that branch's script packs — the same trust model as running its tests. Read script-pack changes in untrusted PRs before invoking the runner.

---

## Authoring a project pack

Drop a file in `project/`. Its extension decides the mode.

**Choosing a mode.** Use a **script pack** (`.sh`) when the rule is a deterministic, greppable check (file co-change, generated-file sync). Use a **config-backed prose pack** (`.md` + `config/`) when the data changes often or the judgment is fuzzy. The sibling-files rule works as either: a script pack for a fixed file list, or a config-backed prose pack to keep the list as data.

### The shared finding shape

Both modes emit a YAML sequence; each item:

```yaml
- file: path/to/file.rb:42      # :line may be :0 when not line-specific
  severity: HIGH                # CRITICAL | HIGH | MEDIUM | LOW
  confidence: 95                # 0-100
  pack: project/<this-file>     # source label
  rule: <short-rule-name>
  issue: <one-line description of the problem>
  fix: <concrete suggestion>    # omit the line entirely if there is no mechanical fix
  tags: [PROJECT_GATE]          # mode-dependent: stamped for prose packs (don't type it),
                                # emitted by you for script packs. Add NEEDS_HUMAN for judgment.
```

`PROJECT_GATE` marks the finding as a project-continuity rule. Add `NEEDS_HUMAN` when resolution needs human judgment — Marge then leaves it for `/speckit.review.pr` instead of auto-fixing. `PROJECT_GATE` alone does **not** stop auto-remediation; Marge still auto-fixes a mechanical `PROJECT_GATE` finding.

> Derivation, by mode. For **prose packs**, the review/planning command stamps `PROJECT_GATE` on every finding because the pack lives under `project/` — you do not write the tag yourself. For **script packs**, the runner passes your stdout through verbatim (it does not parse or rewrite YAML), so you emit `tags: [PROJECT_GATE]` yourself; the template below already does.

### Script pack contract (`project/*.sh`)

The shipped runner `.specify/marge/run-gates.sh` discovers every `*.sh` in `project/` and runs each under a ~120s timeout, folding stdout into the findings pipeline. **Findings — not exit codes — drive enforcement.** All three venues call this one runner.

**Inputs (environment).** The runner exports these before running each script pack:

| Variable | Stage | Meaning |
|----------|-------|---------|
| `SPECKIT_DIFF_FILES` | review | newline-separated list of changed file paths |
| `SPECKIT_BASE_REF` | review | base ref the diff is against (`git diff "$SPECKIT_BASE_REF"...HEAD`) |
| `SPECKIT_FEATURE_DIR` | planning | the feature spec dir, e.g. `specs/1a2b-feat-x` |
| `SPECKIT_STAGE` | both | `review` (default) or `planning` |
| `SPECKIT_REPO_ROOT` | both | absolute repo root (also the working directory) |

For **review**, the runner derives `SPECKIT_DIFF_FILES` from `SPECKIT_BASE_REF` when the caller doesn't pass an explicit list, so it is always populated. Parse it with `printf '%s\n' "${SPECKIT_DIFF_FILES:-}" | grep -qxF "<path>"`.

**Output (stdout).** Print zero or more findings in the shape above.

- **No findings → print nothing** and exit 0. Empty stdout means clean.
- Write diagnostics to **stderr** (never parsed as findings).
- **Emit your own `pack:` line** (`project/<this-file>.sh`). The runner passes stdout through verbatim — it only ever *adds* the `pack-execution` meta-finding when your script exits non-zero.
- Always include `PROJECT_GATE` in `tags`. Add `NEEDS_HUMAN` when resolution needs judgment.

**Exit code (decoupled from findings).**

- **`0`** — ran successfully, with or without findings. The normal case, even when emitting findings.
- **non-zero / timeout** — treated as an execution error: the runner records one `LOW` / `NEEDS_HUMAN` meta-finding (`rule: pack-execution`) and continues. A failing script pack never aborts the review.

**Stage opt-in.** A script pack runs at the **review** stage by default (Marge + PR, diff-scoped). To ALSO run it at the **planning** stage (Lisa, against spec/plan/tasks), add this line near the top:

```sh
# speckit-stage: planning
```

Planning runs get `SPECKIT_STAGE=planning` and `SPECKIT_FEATURE_DIR`; point `file:` at the relevant `spec.md` / `plan.md` / `tasks.md` line.

**Template.**

```sh
#!/usr/bin/env bash
# <one-line description of what this pack enforces>
# Emits PROJECT_GATE findings on stdout. See .specify/marge/README.md.
set -euo pipefail

# Example rule: every file in this group must change together.
group="app/a.rb app/b.rb app/c.rb"

# Did any group member change in this diff?
changed_any=false
for f in $group; do
  printf '%s\n' "${SPECKIT_DIFF_FILES:-}" | grep -qxF "$f" && changed_any=true
done
$changed_any || exit 0          # group untouched → nothing to check, clean

# Flag every member that did NOT change.
for f in $group; do
  if ! printf '%s\n' "${SPECKIT_DIFF_FILES:-}" | grep -qxF "$f"; then
    cat <<YAML
- file: $f:0
  severity: HIGH
  confidence: 95
  pack: project/$(basename "$0")
  rule: sibling-sync
  issue: "$f did not change but a sibling in its sync group did"
  fix: "update $f to match the sibling change, or document why it can diverge"
  tags: [PROJECT_GATE]
YAML
  fi
done
```

### Config-backed prose pack (`project/<name>.md` + `config/<name>.yml`)

For data-driven or judgment rules, write an ordinary prose pack in `project/` (still prose mode — just with its data factored into `config/`) that reads its data from `config/`. No special runner is needed — the review sub-agent reads whatever path the pack references. Keeping the data in `config/` lets one pack serve many cases without editing the rule prose.

In the pack `.md`, declare the data file and stage, and instruct the sub-agent:

```markdown
Config: .specify/marge/config/<name>.yml
Stage: review            # to also run in Lisa, include `planning`: e.g. `Stage: review planning`

Read the config file above and treat its contents as this rule's data.
If the config file is absent or empty, emit zero findings (inert by default).
```

The command stamps `PROJECT_GATE` on the findings because the pack lives under `project/` — you don't write the tag in a prose pack. For example, a `linked-files.md` pack can read `config/linked-files.yml` (groups of files that must change together) and flag when a member changes without its group.
