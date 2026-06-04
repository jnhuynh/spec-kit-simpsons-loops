# Project review gates

Project review gates enforce **continuity / consistency rules unique to a repo** — e.g. "these N sibling files must change together", "a generated file stays in sync with its source", "the naming surface stays consistent". They run during code review and feed findings into the **same pipeline** as the baseline review packs in `../checks/`: Marge auto-remediates mechanical findings or tags `NEEDS_HUMAN` for judgment ones. Project gates are not a separate hard-block — they are findings.

There are **two forms**. Use whichever fits the rule:

| Form | Lives in | Best for |
|------|----------|----------|
| **Script gate** (`gates/*.sh`) | this directory | Deterministic, mechanical checks (file co-change, generated-file sync, greppable invariants). No LLM. |
| **Config-backed pack** (`../checks/*.md` + `../config/*.yml`) | `checks/` + `config/` | Data-driven / judgment checks (e.g. a list of sync-groups). LLM-interpreted. |

Both forms emit findings tagged `PROJECT_GATE`.

## Where gates run (venues)

- **Marge** — `/speckit.review` (the review loop) runs every gate against the branch diff. *(default)*
- **PR review** — `/speckit.review.pr` posts `PROJECT_GATE` findings as inline GitHub comments (they are never dropped, unlike generic mechanical findings that Marge already fixed).
- **Lisa** — `/speckit.lisa.analyze` (planning) runs only gates that opt in: script gates marked `# speckit-stage: planning`, or packs with a `Stage: planning` line. These run against `spec.md`/`plan.md`/`tasks.md`, before code exists.

---

## Script gate contract (`gates/*.sh`)

`/speckit.review` discovers every `*.sh` in this directory and runs it, folding stdout into the findings pipeline. **Findings — not exit codes — drive enforcement.**

### Inputs (environment)

The runner exports these before running each gate:

| Variable | Stage | Meaning |
|----------|-------|---------|
| `SPECKIT_DIFF_FILES` | review | newline-separated list of changed file paths |
| `SPECKIT_BASE_REF` | review | base ref the diff is against (`git diff "$SPECKIT_BASE_REF"...HEAD`) |
| `SPECKIT_FEATURE_DIR` | planning | the feature spec dir, e.g. `specs/1a2b-feat-x` |
| `SPECKIT_STAGE` | both | `review` (default) or `planning` |
| `SPECKIT_REPO_ROOT` | both | absolute repo root |

A gate may also call `git` directly.

### Output (stdout): zero or more findings

Print a YAML sequence; each item EXACTLY:

```yaml
- file: path/to/file.rb:42      # :line may be :0 when not line-specific
  severity: HIGH                # CRITICAL | HIGH | MEDIUM | LOW
  confidence: 95                # 0-100
  pack: gates/<this-file>.sh    # source label
  rule: <short-rule-name>
  issue: <one-line description of the problem>
  fix: <concrete suggestion>    # omit the line entirely if there is no mechanical fix
  tags: [PROJECT_GATE]          # always; use [PROJECT_GATE, NEEDS_HUMAN] when it needs judgment
```

- **No findings → print nothing** and exit 0. Empty stdout means clean.
- Write diagnostics to **stderr** (never parsed as findings).
- Always include `PROJECT_GATE` in `tags`. Add `NEEDS_HUMAN` when resolution needs human judgment — Marge then leaves it for `/speckit.review.pr` instead of auto-fixing.

### Exit code (decoupled from findings)

- **`0`** — ran successfully, with or without findings. The normal case, **even when emitting findings**.
- **non-zero / timeout** — treated as an execution error: the runner records one `LOW` / `NEEDS_HUMAN` meta-finding (`rule: gate-execution`) and continues. **A failing gate never aborts the review.**

Each gate runs under a ~120s timeout.

### Stage opt-in

A gate runs at the **review** stage by default (Marge + PR, diff-scoped). To ALSO run it at the **planning** stage (Lisa, against spec/plan/tasks), add this line near the top of the script:

```sh
# speckit-stage: planning
```

Planning runs get `SPECKIT_STAGE=planning` and `SPECKIT_FEATURE_DIR`; point `file:` at the relevant `spec.md`/`plan.md`/`tasks.md` line.

### Template

```sh
#!/usr/bin/env bash
# <one-line description of what this gate enforces>
# Emits PROJECT_GATE findings on stdout. See specify-marge/gates/README.md.
set -euo pipefail

# Example rule: every file in this group must change together.
group="app/a.rb app/b.rb app/c.rb"

# Did any group member change in this diff?
changed_any=false
for f in $group; do
  printf '%s\n' "$SPECKIT_DIFF_FILES" | grep -qxF "$f" && changed_any=true
done
$changed_any || exit 0          # group untouched → nothing to check, clean

# Flag every member that did NOT change.
for f in $group; do
  if ! printf '%s\n' "$SPECKIT_DIFF_FILES" | grep -qxF "$f"; then
    cat <<YAML
- file: $f:0
  severity: HIGH
  confidence: 95
  pack: gates/$(basename "$0")
  rule: sibling-sync
  issue: "$f did not change but a sibling in its sync group did"
  fix: "update $f to match the sibling change, or document why it can diverge"
  tags: [PROJECT_GATE]
YAML
  fi
done
```

---

## Config-backed pack (`../checks/<name>.md` + `../config/<name>.yml`)

For data-driven or judgment checks, write an ordinary review pack in `../checks/` that reads data from `../config/`. No special runner is needed — the review sub-agent reads whatever path the pack references.

In the pack `.md`, declare the data file and stage, and instruct the sub-agent:

```markdown
Config: .specify/marge/config/<name>.yml
Stage: review            # add `planning` to also run in Lisa

Read the config file above and treat its contents as this rule's data.
Emit findings tagged [PROJECT_GATE]. If the config file is absent or empty,
emit zero findings (inert by default).
```

This is how a `dsl-sync`-style check works: a `sync-groups.md` pack reads `config/sync-groups.yml` (a list of file groups that must change together) and flags out-of-sync groups — without hard-coding the group list into the rule.

---

## The `PROJECT_GATE` tag

Every gate finding (both forms) carries `PROJECT_GATE` in `tags`. It:

- makes `/speckit.review.pr` **preserve and post** the finding as an inline comment (generic mechanical findings are dropped there, because Marge already fixed them); and
- labels the finding as a project-continuity gate in reports.

It does **not** change auto-remediation — Marge still auto-fixes a `PROJECT_GATE` finding unless it is also tagged `NEEDS_HUMAN`.
