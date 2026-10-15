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

- Constitution at `.specify/memory/constitution.md` is **authoritative** — never modify it during implementation
- Adjust spec, plan, or tasks instead
- **Homer (clarify)** → answer up to 5 clarification questions per iteration (self-answered), loop until `ALL_FINDINGS_RESOLVED`
- **Premortem (human gate)** → `/speckit-premortem` interactive failure-mode discovery across architecture, UX, and support/ops lenses; mitigations encoded into the spec, decisions tracked in `failure-modes.md`; the pipeline halts at this step until the register has zero `open` rows — never self-answered, never automated
- **Lisa (analyze)** → fix all auto-fixable findings per iteration, then verify with a clean re-scan, loop until `ALL_FINDINGS_RESOLVED`
- **Ralph (implement)** → implement one task per iteration, loop until `ALL_TASKS_COMPLETE`; when `tasks.md` carries a `## Pull Request Plan`, work one PR group at a time and halt at each boundary (`PR_BOUNDARY_REACHED`) so the group can be opened, reviewed, and merged before the next one starts
- **Marge (review)** → fix all auto-fixable code-review findings per iteration, then verify with a clean re-review, loop until `ALL_FINDINGS_RESOLVED`; skip findings tagged `NEEDS_HUMAN` (design judgment); a finding that reappears after being fixed is escalated to `NEEDS_HUMAN`, never re-fixed
- **Standards checks** → Marge and Lisa run `.specify/scripts/bash/speckit-standards.sh` through the baseline pack `standards.sh`: damage level from `.specify/marge/config/damage-levels.yml`, PR shape, plain language, and the words in `config/lexicon.yml`. A banned word, a requirement id in a PR description, or a new spec without a `## Plain summary` blocks; the level is a floor an agent never lowers; `/speckit-pr` writes the pull request description with the level and its checklist; the Stop hook (`.claude/hooks/speckit-standards-stop.sh`) sends an interactive session back, once per stop attempt, while a blocking finding sits in its uncommitted work
- **Project packs** → repo-specific continuity rules (e.g. sibling files must change together): script packs (`.specify/marge/project/*.sh`) and prose packs (`.specify/marge/project/*.md`, optionally config-backed via `.specify/marge/config/`). Findings are tagged `PROJECT_GATE` and flow through the normal review pipeline — auto-fixed if mechanical, else `NEEDS_HUMAN` — across Marge, Lisa (planning), and PR review. Contract: `.specify/marge/README.md`
- Exit after each iteration — restart with fresh context
