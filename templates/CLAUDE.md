# Development Guidelines

## Code Principles

- **Readability first** — clean, human-readable code with meaningful variable names. Clarity over brevity.
- **Functional design** — services take inputs, yield deterministic outputs. No hidden side effects.
- **Maintainability over cleverness** — no premature optimizations. Code must be maintainable by developers who didn't write it.
- **Simplicity (KISS & YAGNI)** — build only what's needed. Prefer simpler solutions that can be validated before investing in sophisticated alternatives.
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
- **Homer (clarify)** → fix one finding per iteration, loop until `ALL_FINDINGS_RESOLVED`
- **Lisa (analyze)** → fix one finding per iteration, loop until `ALL_FINDINGS_RESOLVED`
- **Ralph (implement)** → implement one task per iteration, loop until `ALL_TASKS_COMPLETE`
- **Marge (review)** → fix one code-review finding per iteration, loop until `ALL_FINDINGS_RESOLVED`; skip findings tagged `NEEDS_HUMAN` (design judgment)
- Exit after each iteration — restart with fresh context

## Multi-Phase Deploys

Some features cannot ship in a single pull request without breaking production — the canonical example is renaming a database column that a running service still reads. SpecKit supports authoring such features as a stack of independently-deployable pull requests.

**When to use multi-phase deploys**:

- Schema migrations combined with reads/writes on the same data (e.g., column rename, column type change, table split/merge)
- Breaking API changes where prior-phase callers must be migrated before the old surface is removed
- Multi-service rollout coordination where one service's contract change requires deploys to land in a specific order

**How a multi-phase feature is authored**: there is no flag, environment variable, or command-line switch. The plan agent emits a `## Deploy Phases` section in `plan.md` automatically when the heuristics above fire. The presence of that section is the sole signal that the feature is multi-phase; absence means single-phase. Single-phase features keep working unchanged — no phase trailers required on commits, no per-phase findings, exactly one pull request opened by the split step.

**How to read the resulting pull request stack**: when the split step runs on a multi-phase feature, it produces a stack of pull requests named `[Phase K/N] <feature-branch-name>` with the base-branch chain `main <- phase1 <- phase2 <- ... <- phaseN`. Each PR body contains a `## Phase Goal` section, a `## Post-deploy production state` section, and a `## Stack` section listing every phase in deploy order. Read the stack in deploy order (phase 1 first), merge in deploy order (do not merge phase K+1 before phase K), and confirm each phase's post-deploy production state before merging the next.

**Migration-safety enforcement**: the migration-safety check pack at `.specify/marge/checks/migrations.md` is loaded automatically by Marge's check-pack discovery when present. It catalogs eight production-breaking patterns (NOT NULL without default, column drop while prior-phase reads, single-phase rename, long-transaction backfill on hot table, missing index for new read path, schema-plus-dependent-code in same phase, removed function with prior-phase callers, per-phase deployability) and four structural-consistency patterns (orphan phase tag, non-contiguous phases, malformed `Phase:` trailer, phase-trailer-without-deploy-phases). Every cataloged pattern is emitted at `high` severity. The split step refuses to open or update a pull request for any phase with an unresolved high-severity finding against it.
