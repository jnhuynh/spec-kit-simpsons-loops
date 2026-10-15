# Development Guidelines

## Code Principles

- **Readability first** — clean, human-readable code with meaningful variable names. Clarity over brevity.
- **Functional design** — services take inputs, yield deterministic outputs. No hidden side effects.
- **Maintainability over cleverness** — no premature optimizations. Code must be maintainable by developers who didn't write it.
- **Simplicity (KISS & YAGNI)** — build only what's needed _now_. Before adding any speculative structure — a column, model, abstraction, state, status field, snapshot, or async-ordering machinery — apply the **one-way-door test**: if the decision is reversible (it can be added later when a real consumer needs it, without an irreversible migration, backfill, or breaking contract change), default to the smaller solution and **don't build it yet**. Reserve upfront flexibility for true one-way doors (destructive/narrowing migrations, public API contracts, data shapes that would later need a backfill). Concretely: don't add fields, states, or scopes with no current consumer; don't snapshot a value when a derived read of the current value suffices; and don't assume unspecified requirements like extreme asynchrony or arbitrary input ordering — prefer the simpler, more sequential design until a concrete requirement forces otherwise. When a spec, plan, prior artifact, or reviewer pushes for speculative complexity, push back and name it as YAGNI rather than silently implementing it. Capable models bias toward over-building; lean deliberately the other way.
- **Follow best practices** — established conventions for the languages, frameworks, and packages in use. Community standards over novel approaches.

## Test-First Development

Unit tests for new logic MUST be written before the implementation code:

1. Write the test
2. Run it — verify it **fails**
3. Write the minimum implementation to make it pass

Applies to: new service functions, business logic, hooks, utilities, and bug fixes (reproduce the bug in a test first). Never proceed with failing tests.

## Quality Gates

All changes must pass before committing:

- All tests pass
- Linting passes with zero errors
- Type checking passes with zero errors (typed languages)

## Git Discipline

- **Never push without explicit permission** — commits are fine, pushing is gated
- Commit format: `type(scope): [ticket] description`
- One logical change per commit
- Branch naming follows spec directory: `XXXX-type-description` where type is `feat`, `fix`, or `chore`

## Process Hygiene

Cleanup is mandatory. Every process started during a session must be stopped before the session ends. A session that completes but leaves orphaned processes is **incomplete**.

- **Dev servers**: before starting one, check if one is already running (`pgrep -f "vite\|webpack-dev-server\|next dev\|rails s"`). Reuse it — never start a duplicate.
- **Docker**: any container started during this session MUST be stopped and removed before finishing. Use `docker stop <id> && docker rm <id>`, or `docker compose down`. Never leave containers running.
- **Watchers, file observers, background build processes**: stop all of them when done.
- **Verification step**: before marking work complete, run `ps aux | grep <project-pattern>` to confirm nothing from this session is still running.
- Verify UI and integration work against the running application. Unit tests alone are insufficient.

## Speckit

- Constitution at `.specify/memory/constitution.md` is **authoritative** — never modify it during implementation. Adjust spec, plan, or tasks instead.
- Every loop iteration and pipeline step runs in a fresh sub agent. Exit after each iteration; nothing carries over but the files on disk.
- **Homer (clarify)** → answer up to 5 clarification questions per iteration (self-answered), loop until `ALL_FINDINGS_RESOLVED`.
- **Premortem (human gate)** → `/speckit-premortem` works three failure-mode lenses (architecture, UX, support/ops) interactively. Mitigations land in the spec; every risk is tracked in `failure-modes.md`. The pipeline halts here until no row is `open`. Never self-answered, never automated.
- **Lisa (analyze)** → fix every auto-fixable finding per iteration, then verify with a clean re-scan, loop until `ALL_FINDINGS_RESOLVED`.
- **Ralph (implement)** → implement one task per iteration, loop until `ALL_TASKS_COMPLETE`. When `tasks.md` carries a `## Pull Request Plan`, work one PR group at a time. Halt at each boundary (`PR_BOUNDARY_REACHED`) so the group can be opened, reviewed, and merged first.
- **Marge (review)** → fix every auto-fixable code-review finding per iteration, then verify with a clean re-review, loop until `ALL_FINDINGS_RESOLVED`. Skip findings tagged `NEEDS_HUMAN`. A finding that reappears after being fixed is escalated to `NEEDS_HUMAN`, never re-fixed.
- **Phased specs** → a child spec (`{parent}--p{N}-{slug}`) is a **phase view**, never a copy. The parent holds every user story, requirement, key entity, and success criterion exactly once. The child names the ones in its phase by ID under `## Inherited Scope`. It adds only phase-local `FR-P{N}-###` / `SC-P{N}-###` entries and a `## Phase Boundary`. Requirement edits and clarifications go to the parent, so `homer`, `premortem`, and `phase` never run on a child. `/speckit-reconcile` corrects the parent where a completed phase shipped something else.
- **Standards checks** → Marge and Lisa run `.specify/scripts/bash/speckit-standards.sh` through the baseline pack `standards.sh`: damage level (`.specify/marge/config/damage-levels.yml`), PR shape, plain language, and the words in `config/lexicon.yml`. A banned word, a requirement id in a PR description, or a new spec without a `## Plain summary` blocks. The damage level is a floor an agent never lowers. `/speckit-pr` writes the pull request description with the level and its checklist. The Stop hook (`.claude/hooks/speckit-standards-stop.sh`) sends an interactive session back once per stop attempt while a blocking finding sits in its uncommitted work.
- **Project packs** → repo-specific continuity rules (e.g. sibling files must change together) in `.specify/marge/project/`: `.sh` script packs and `.md` prose packs (optionally config-backed via `.specify/marge/config/`). Findings are tagged `PROJECT_GATE` and flow through the normal review pipeline — auto-fixed if mechanical, else `NEEDS_HUMAN` — across Marge, Lisa (planning), and PR review. Contract: `.specify/marge/README.md`.

<!-- ====== PROJECT SPECIFIC ====== -->

## Karpathy-Inspired Claude Code Guidelines

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.

## Source vs Installed Files

**Ship-source lives in the non-hidden top-level directories** (`speckit-skills/`, `claude-agents/`, `specify-marge/`, `scripts/`, `templates/`), and `setup.sh` never reads install content from `.specify/` or `.claude/`. The README's install table ("What setup.sh installs") is the map from each source to its destination. **Always edit the source files, never an installed copy.**

Installed copies are not committed here. Everything `setup.sh --self` writes is gitignored; run it only to dogfood locally and never commit its output. (`$PROJECT_DIR/...` reads that preserve a consumer's customizations are fine; `$SCRIPT_DIR/.specify` or `$SCRIPT_DIR/.claude` reads are not.)

What remains committed under the hidden directories is repo-owned or upstream Spec Kit material. That is `.claude/commands/speckit.*.md` (upstream commands, with the Pull Request Plan rules added), `.specify/memory/constitution.md`, `.specify/scripts/bash/` (Spec Kit's own scripts), and `.specify/templates/`. Also the quality gates and the hand-authored project packs in `.specify/marge/project/`.

This file is `templates/CLAUDE.md` above the separator and repo-specific below it. After editing the template, sync with `bash templates/setup.sh update .`.

## Active Technologies

- Bash 4+ shell scripts that must also run on macOS `/bin/bash` 3.2. Markdown skill and agent files. Claude CLI with the Agent tool. Standard Unix utilities (`grep`, `sed`, `awk`; `jq` optional). Filesystem only: `.md` skill files, `.sh` scripts, spec directories under `specs/`.
