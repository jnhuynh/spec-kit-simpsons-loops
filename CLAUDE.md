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

<!-- ====== PROJECT SPECIFIC ====== -->

<!-- Add project-specific guidelines below (technologies, commands, structure, etc.) -->

## Source vs Installed Files

**Ship-source lives in non-hidden top-level directories; `setup.sh` never sources install-content from `.specify/` or `.claude/`.** The hidden `.specify/` and `.claude/` trees are dogfooding **output** — `setup.sh --self` regenerates them by running the installer on this repo. They are committed only as dogfooding snapshots and must never be an installation source. (`$PROJECT_DIR/...` reads that preserve a consumer's existing customizations are fine; `$SCRIPT_DIR/.specify` or `$SCRIPT_DIR/.claude` reads are not.)

The source of truth:

- `speckit-commands/*.md` → installed to `.claude/commands/` by `setup.sh`
- `claude-agents/*.md` → installed to `.claude/agents/` by `setup.sh`
- `specify-marge/checks/*.md` → seeded into consumer `.specify/marge/checks/` by `setup.sh` (idempotent — existing files preserved)
- `specify-marge/gates/`, `specify-marge/config/` → seeded into consumer `.specify/marge/gates/` and `.specify/marge/config/` by `setup.sh`

**Always edit the source files** (`speckit-commands/`, `claude-agents/`, `specify-marge/`), never the installed/seeded copies (`.claude/commands/`, `.claude/agents/`, `.specify/marge/`). The hidden copies are overwritten/regenerated by `setup.sh` and exist only for dogfooding. After editing source files, run `setup.sh --self` to refresh the dogfooding copies. A repo's own project gates live in its `.specify/marge/gates/` (dogfooding — committed, but not shipped).

## Active Technologies
- Bash 4+ (shell scripts), Markdown (command/agent files) + Claude CLI (`claude` command), `jq` (optional, for settings updates), standard Unix utilities (`grep`, `sed`, `awk`, `mktemp`, `mv`, `chmod`) (002-rerun-setup-pipeline)
- Filesystem only — shell scripts, markdown files, and configuration files (002-rerun-setup-pipeline)
- Bash 4+ (shell scripts), Markdown (command files) + Claude CLI (`claude` command), Agent tool, Bash tool (003-fix-pipeline-delegation)
- Filesystem only — `.md` command files, `.sh` scripts (003-fix-pipeline-delegation)
- Filesystem only -- `.md` command files, `.sh` scripts (003-fix-pipeline-delegation)
- Bash 4+ (shell scripts), Markdown (command files) + Claude CLI (`claude` command), standard Unix utilities (`grep`, `sed`, `test`) (004-fix-prereq-bootstrap)
- Bash 4+ (shell scripts), Markdown (command/agent files) + Claude CLI (`claude` command), Agent tool, standard Unix utilities (`grep`, `sed`, `test`, `bash`) (005-fix-subagent-quality-gates)
- Filesystem only — `.md` command files, `.sh` scripts, `.specify/` configuration (005-fix-subagent-quality-gates)
- Bash 4+ (shell scripts), Markdown (command/agent files) + Claude CLI (`claude` command), Agent tool, standard Unix utilities (`grep`, `sed`, `test`, `jq`) (005-fix-subagent-quality-gates)
- Bash 4+ (shell scripts), Markdown (command/agent files) + Claude CLI (`claude` command), Agent tool, standard Unix utilities (`grep`, `sed`, `test`) (006-stop-after-param)
- Bash 4+ (shell scripts), Markdown (command/agent files) + Claude CLI (`claude` command), Claude Code Agent tool, standard Unix utilities (`grep`, `sed`, `test`, `mkdir`) (c31c-feat-phase-aware-specs)
- Filesystem only -- `.md` command files, `.sh` scripts, spec directories under `specs/` (c31c-feat-phase-aware-specs)

## Recent Changes
- 002-rerun-setup-pipeline: Added Bash 4+ (shell scripts), Markdown (command/agent files) + Claude CLI (`claude` command), `jq` (optional, for settings updates), standard Unix utilities (`grep`, `sed`, `awk`, `mktemp`, `mv`, `chmod`)
