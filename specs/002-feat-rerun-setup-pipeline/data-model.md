# Data Model: Rerunnable Setup & End-to-End Pipeline

**Date**: 2026-03-09
**Feature**: `002-feat-rerun-setup-pipeline`

## Entities

### Quality Gate File

**Path**: `.specify/quality-gates.sh` (in target project)
**Type**: Executable shell script
**Created by**: `setup.sh` (on first run or migration)
**Lifecycle**: Created once, never overwritten by setup.sh

| Property | Type | Description |
|----------|------|-------------|
| Content | Shell commands | One or more shell commands that validate code quality (e.g., `npm test && npm run lint`) |
| Sentinel | Comment line | `# SPECKIT_DEFAULT_QUALITY_GATE` — present only in the placeholder version; absence indicates user customization |
| Permissions | File mode | `0755` (executable) — set by `setup.sh` via `chmod +x` |

**States**:

```
[Not Exists] --setup.sh first run--> [Placeholder]
[Placeholder] --user edits--> [Configured]
[Configured] --setup.sh rerun--> [Configured] (unchanged)
[Not Exists] + [Ralph has custom gates] --setup.sh rerun--> [Configured] (extracted)
[Not Exists] + [Ralph has placeholder] --setup.sh rerun--> [Placeholder]
```

**Validation rules**:
- File must exist and be non-empty (after stripping comments and whitespace) for quality gates to be considered configured
- Placeholder file contains `exit 1` to fail the quality gate check until user configures it
- Empty file or comments-only file is treated as "not configured" — error exit

### Quality Gate Placeholder Content

```bash
#!/usr/bin/env bash
# SPECKIT_DEFAULT_QUALITY_GATE
#
# Quality Gates Configuration
# ──────────────────────────────────────────────────────────────
# Add your project's quality gate commands below.
# These commands run after each implementation step to verify code quality.
#
# Examples:
#   npm test && npm run lint
#   pytest && ruff check .
#   cargo test && cargo clippy
#   shellcheck *.sh
#
# This file is sourced by the pipeline and Ralph loop scripts.
# It must exit 0 for quality gates to pass.
# ──────────────────────────────────────────────────────────────

echo "ERROR: Quality gates not configured."
echo "Edit .specify/quality-gates.sh with your project's quality gate commands."
exit 1
```

### Quality Gate Resolution Order

**Entity**: Quality gate source resolution (runtime lookup)

| Priority | Source | How checked |
|----------|--------|-------------|
| 1 (highest) | CLI argument `--quality-gates <cmd>` | Parsed from script arguments |
| 2 | Environment variable `QUALITY_GATES` | Read from `$QUALITY_GATES` |
| 3 (lowest) | File `.specify/quality-gates.sh` | Read from filesystem |
| Error | None configured | Exit with error message |

### Pipeline Steps

**Entity**: Pipeline step sequence (extended)

| Order | Step | Type | Agent | Condition |
|-------|------|------|-------|-----------|
| 0 | specify | single-shot | specify agent | Only if `--from specify` or no `spec.md` exists and feature description provided |
| 1 | homer | loop | homer agent | Default first step (if spec.md exists) |
| 2 | plan | single-shot | plan agent | Skip if `plan.md` exists |
| 3 | tasks | single-shot | tasks agent | Skip if `tasks.md` exists |
| 4 | lisa | loop | lisa agent | Always runs (unless skipped via --from) |
| 5 | ralph | loop | ralph agent | Always runs (unless skipped via --from) |

### Setup.sh File Categories

**Entity**: Files managed by setup.sh, categorized by overwrite policy

| Category | Overwrite on Rerun | Files |
|----------|-------------------|-------|
| Always overwrite | Yes | Loop scripts (`ralph-loop.sh`, `lisa-loop.sh`, `homer-loop.sh`, `pipeline.sh`), agent files (`homer.md`, `lisa.md`, `ralph.md`, `plan.md`, `tasks.md`), command files (`speckit.*.md`) |
| Never overwrite | No | Quality gate file (`.specify/quality-gates.sh`) |
| Append-only | Conditional | `.gitignore` (only if marker not present) |
| Merge | Conditional | `.claude/settings.local.json` (add permissions, preserve existing) |

## Relationships

```
setup.sh ──creates──> .specify/quality-gates.sh
setup.sh ──overwrites──> .specify/scripts/bash/*.sh
setup.sh ──overwrites──> .claude/agents/*.md
setup.sh ──overwrites──> .claude/commands/speckit.*.md

pipeline.sh ──reads──> .specify/quality-gates.sh (fallback)
pipeline.sh ──invokes──> specify agent (new step 0)
pipeline.sh ──invokes──> homer-loop.sh
pipeline.sh ──invokes──> plan agent
pipeline.sh ──invokes──> tasks agent
pipeline.sh ──invokes──> lisa-loop.sh
pipeline.sh ──invokes──> ralph-loop.sh

ralph-loop.sh ──reads──> .specify/quality-gates.sh (fallback)
ralph-loop.sh ──passes──> quality gates to ralph agent

speckit.ralph.implement.md ──references──> .specify/quality-gates.sh
speckit.pipeline.md ──references──> .specify/quality-gates.sh
```
