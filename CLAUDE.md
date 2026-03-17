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

- Before starting a dev server: check if one is already running. Reuse it — do NOT start a duplicate.
- Verify UI and integration work against the running application. Unit tests alone are insufficient.
- Stop any dev servers, watchers, or child processes when implementation is complete. No straggling processes.

## Speckit

- Constitution at `.specify/memory/constitution.md` is **authoritative** — never modify it during implementation
- Adjust spec, plan, or tasks instead
- **Homer (clarify)** → fix one finding per iteration, loop until `ALL_FINDINGS_RESOLVED`
- **Lisa (analyze)** → fix one finding per iteration, loop until `ALL_FINDINGS_RESOLVED`
- **Ralph (implement)** → implement one task per iteration, loop until `ALL_TASKS_COMPLETE`
- Exit after each iteration — restart with fresh context

### Source vs Installed Files

The **source of truth** for SpecKit command and agent files lives in the repo root:

- `speckit-commands/*.md` → installed to `.claude/commands/` by `setup.sh`
- `claude-agents/*.md` → installed to `.claude/agents/` by `setup.sh`

**Always edit the source files** (`speckit-commands/`, `claude-agents/`), never the installed copies (`.claude/commands/`, `.claude/agents/`). The installed copies are overwritten by `setup.sh` and exist only for dogfooding. After editing source files, run `setup.sh` or manually copy to `.claude/` to update the installed versions.

<!-- ====== PROJECT SPECIFIC ====== -->

<!-- Add project-specific guidelines below (technologies, commands, structure, etc.) -->

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

## Recent Changes
- 002-rerun-setup-pipeline: Added Bash 4+ (shell scripts), Markdown (command/agent files) + Claude CLI (`claude` command), `jq` (optional, for settings updates), standard Unix utilities (`grep`, `sed`, `awk`, `mktemp`, `mv`, `chmod`)
