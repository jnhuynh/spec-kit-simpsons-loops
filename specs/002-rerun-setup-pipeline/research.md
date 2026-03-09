# Research: Rerunnable Setup & End-to-End Pipeline

**Date**: 2026-03-09
**Feature**: `002-rerun-setup-pipeline`

## R1: Quality Gate File Location and Format

**Decision**: `.specify/quality-gates.sh` — a plain executable shell script in the `.specify/` directory.

**Rationale**: The `.specify/` directory already serves as the project's speckit configuration root (containing `memory/`, `scripts/`, `templates/`). Placing the quality gate file here keeps all speckit configuration co-located. A `.sh` extension makes the file's purpose clear and signals it should be executable. The file is sourced/executed by loop scripts, so plain shell is the simplest format with no parsing overhead.

**Alternatives considered**:
- `.specify/config/quality-gates.sh` — adds unnecessary nesting; `.specify/` is flat enough already.
- `.speckit.json` with a `qualityGates` key — requires JSON parsing in bash; adds complexity for no benefit.
- `quality-gates.yml` — requires a YAML parser; violates KISS.

## R2: Atomic File Write Pattern for Quality Gate File

**Decision**: Use the `mktemp` + `mv` pattern for atomic file creation. Write to a temp file first, then `mv` it to the target path. Skip entirely if the file already exists.

**Rationale**: The `mv` operation on the same filesystem is atomic at the OS level. This prevents partial writes if `setup.sh` is interrupted. The existing `setup.sh` already uses `cp` for other files, but the quality gate file has a special "never overwrite" contract that requires explicit existence checks before any write.

**Alternatives considered**:
- Direct write with `>` redirect — risk of partial content on interruption.
- `set -o noclobber` — prevents overwriting but doesn't guarantee atomicity of content.

## R3: Sentinel Comment for Placeholder Detection

**Decision**: Use `# SPECKIT_DEFAULT_QUALITY_GATE` as a sentinel comment in both the Ralph command file (current inline quality gates) and the placeholder quality gate file.

**Rationale**: Pattern matching a known sentinel is deterministic and does not depend on fragile content matching. The sentinel is a single line that can be checked with `grep -q`. If the sentinel is present in the Ralph command file during re-run, the quality gates are still the default placeholder (unconfigured). If absent, the user has customized them and they should be extracted to the quality gate file.

**Alternatives considered**:
- Hash/checksum comparison of the quality gate block — fragile if whitespace or formatting varies.
- Diffing against a stored template — requires keeping a reference copy; adds maintenance burden.

## R4: Quality Gate Precedence Order

**Decision**: CLI argument (`--quality-gates`) > Environment variable (`QUALITY_GATES`) > File (`.specify/quality-gates.sh`). Error if none are configured.

**Rationale**: This follows the standard Unix convention where explicit arguments override environment, which overrides configuration files. Existing behavior already uses `QUALITY_GATES` env var and `--quality-gates` CLI arg. Adding file-based configuration as the fallback default is additive and backward-compatible.

**Alternatives considered**:
- File takes precedence over env var — breaks existing workflows where users set `QUALITY_GATES` in CI.
- No precedence; file is the only source — removes flexibility for CI/CD overrides.

## R5: Pipeline "Specify" Step Integration

**Decision**: Add `specify` as step 0 (before `homer`) in the pipeline. It is skipped by default if `spec.md` already exists. It can be explicitly requested with `--from specify`. When invoked, it runs non-interactively, auto-resolving all clarifications.

**Rationale**: The pipeline's purpose is end-to-end automation. Currently users must manually run `/speckit.specify` before the pipeline. Adding it as an optional first step closes this gap. Non-interactive mode is required because the pipeline runs unattended. Homer loop handles refinement of any auto-resolved gaps.

**Alternatives considered**:
- Always run specify step — wasteful when spec already exists; would require conflict resolution.
- Separate "full pipeline" command — duplicates orchestration logic; violates DRY.

## R6: Non-Interactive Specify Invocation

**Decision**: Pass the feature description to the specify agent with an explicit instruction to auto-resolve all clarifications (make best guesses, no `[NEEDS CLARIFICATION]` markers). The Homer loop refines gaps afterward.

**Rationale**: The specify command normally presents interactive clarification questions. In pipeline mode, there is no user to respond. Auto-resolving with best guesses produces a complete (if imperfect) spec that Homer can iteratively refine. This aligns with the spec's acceptance scenario: "auto-resolve all clarifications with best guesses."

**Alternatives considered**:
- Pre-fill answers from a config file — over-engineered for this use case; violates YAGNI.
- Skip specify entirely and require manual spec creation — defeats the purpose of end-to-end automation.

## R7: Quality Gate Extraction from Ralph Command File

**Decision**: During re-run, `setup.sh` inspects the Ralph command file for the sentinel comment `# SPECKIT_DEFAULT_QUALITY_GATE`. If the sentinel is present, the quality gates are still the placeholder (create a new placeholder file). If absent, extract the code block content from the "Extract Quality Gates" section and write it to the quality gate file.

**Rationale**: This handles migration for existing projects that have already customized their quality gates in the Ralph command file. The extraction is a one-time operation — once the quality gate file exists, subsequent re-runs skip it entirely.

**Alternatives considered**:
- Require manual migration — poor developer experience; users may not notice the change.
- Parse the entire Ralph command file AST — overkill; a simple `sed`/`awk` extraction between known markers is sufficient.
