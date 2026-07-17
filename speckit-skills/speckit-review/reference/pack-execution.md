# Pack Execution Engine

Shared by `/speckit-review` and `/speckit-review-pr`: runs every review pack against a diff and aggregates their findings. The calling skill provides (from its own earlier steps):

- **DIFF** — the diff under review
- **FILE_LIST** — the changed-file list
- **PER_PACK_INSTRUCTION** — an extra instruction block included in every pack sub agent's prompt, or `(none)`
- **RUNNER_ENV** — env assignments for the script-pack runner. Must include `SPECKIT_BASE_REF`; callers whose diff is not local git state (PR scope) also pass `SPECKIT_DIFF_FILES` explicitly.
- **CONFIDENCE_RULE** — which findings to drop by confidence in aggregation

## 1. Discover prose packs

Discover every `*.md` **prose pack** via Glob from two directories:

- `.specify/marge/baseline/` — shipped baseline packs (generic code-quality rules)
- `.specify/marge/project/` — project packs (repo-specific rules; their findings are tagged `PROJECT_GATE`)

Expected baseline packs (installed by `setup.sh`): `generic-bugs.md`, `security.md`, `testing.md`, `architecture.md`, `concurrency.md`, `one-way-doors.md`.

Run every pack regardless of origin — the directories are the API. A pack's directory tells you its origin (baseline vs project); its extension tells you its mode (`.md` prose here, `.sh` script in §3).

Some project packs are **config-backed**: the pack text instructs the sub agent to `Read` a data file under `.specify/marge/config/` and treat it as rule data. No special handling is needed here — the sub agent reads that file itself in §2. A config-backed pack whose config file is missing or empty emits zero findings. (Contract: `.specify/marge/README.md`.)

If `.specify/marge/baseline/` is empty or missing, abort: "No baseline review packs found at `.specify/marge/baseline/`. Run `setup.sh` to install baseline packs." (`.specify/marge/project/` may be absent — project packs are optional.)

## 2. Run prose packs sequentially with corroborate/refute

For each pack in the discovered list, spawn a fresh sub agent via the **Agent tool** (`subagent_type: general-purpose`). Run them **one at a time** in this order:

1. Baseline packs (`baseline/*.md`) first, alphabetically by filename
2. Project packs (`project/*.md`) after baseline, alphabetically

Each sub agent receives:

- The DIFF
- The FILE_LIST
- The pack's full text (read via the prompt or by instructing the sub agent to `Read` the pack path)
- Every prior pack's findings (aggregated so far)
- The constitution + CLAUDE.md content as context (the caller loaded these)
- PER_PACK_INSTRUCTION, if not `(none)`
- Whether the pack is a **project pack** (from `project/`). If so, instruct the sub agent to add `PROJECT_GATE` to the `tags` of every finding it emits — the tag is derived from the pack's location, not written into the pack text. Baseline packs never get `PROJECT_GATE`.

Each sub agent must return findings in this shape (one per finding):

```
- file: <path>:<line>
  severity: CRITICAL | HIGH | MEDIUM | LOW
  confidence: <0–100>
  pack: <pack filename>
  rule: <rule name from the pack>
  issue: <one-line description>
  fix: <concrete suggestion; omit ONLY if no safe fix exists>
  tags: [PROJECT_GATE?, NEEDS_HUMAN?]   # PROJECT_GATE auto-added for project/ packs; NEEDS_HUMAN if it needs judgment. A finding WITHOUT a fix MUST carry NEEDS_HUMAN — fix-less untagged findings are unremediable and stall remediation loops.
  corroborates: <prior finding id>?   # if duplicates an earlier finding — merges
  refutes: <prior finding id>?        # if refutes an earlier finding — drops it
```

**Strict sequential execution**: wait for one pack to return before spawning the next. Later packs see earlier findings and can corroborate / refute.

## 3. Run script packs

Project **script packs** are deterministic continuity checks under `.specify/marge/project/*.sh`, executed by the shipped runner `.specify/marge/run-gates.sh` (contract: `.specify/marge/README.md`). The runner discovers the script packs, applies the per-pack timeout, exports the contract env, and emits findings — or one `pack-execution` meta-finding per failed pack — on stdout; it never aborts.

Run it **once, after the prose packs** (so script-pack findings can corroborate/refute prose-pack findings in §4) via the Bash tool, with the caller's RUNNER_ENV:

```bash
<RUNNER_ENV> bash .specify/marge/run-gates.sh
```

Treat the runner's stdout as a findings YAML sequence in the same shape as §2 — each item already carries `pack: project/<name>` and `PROJECT_GATE` (a failed pack appears as one LOW `pack-execution` finding tagged `[PROJECT_GATE, NEEDS_HUMAN]`). Empty stdout means zero script-pack findings. Append them to the aggregated findings list, then continue to §4. If `.specify/marge/project/` is absent the runner prints nothing — script packs are optional (only `.specify/marge/baseline/` is required).

## 4. Aggregate

1. Apply `corroborates:` — merge into the prior finding, bump its confidence by +10 (cap 100), append the corroborating source to its `pack` line.
2. Apply `refutes:` — drop the refuted finding; record it in a "Refuted" appendix.
3. Dedupe any remaining pairs at the same `file:line` with similar issue text. Keep the higher-confidence one; break ties by later source — project packs (`pack: project/*`, prose or script) win over baseline packs.
4. Apply CONFIDENCE_RULE.
5. Sort by severity, then confidence descending within each severity.

Return the aggregated findings list to the calling skill's next step.
