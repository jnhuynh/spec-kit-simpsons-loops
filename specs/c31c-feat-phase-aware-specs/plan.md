# Implementation Plan: Phase-Aware Specs with Splitting Skill

**Branch**: `c31c-feat-phase-aware-specs` | **Date**: 2026-05-28 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/c31c-feat-phase-aware-specs/spec.md`

## Summary

Extend SpecKit's specify step to analyze user stories for natural deployment boundaries and group them into ordered phases within the spec, with release strategy recommendations per phase. Add a new splitting skill that reads phase annotations from a parent spec and generates independent child spec directories, each processable through the full SpecKit pipeline. The parent spec tracks children via a manifest section with status tracking and forward-only state transitions. Re-running the splitting skill reconciles later child specs with changes in earlier ones, flagging conflicts with inline markers when manual edits conflict with propagated changes.

## Technical Context

**Language/Version**: Bash 4+ (shell scripts), Markdown (command/agent files)
**Primary Dependencies**: Claude CLI (`claude` command), Claude Code Agent tool, standard Unix utilities (`grep`, `sed`, `test`, `mkdir`)
**Storage**: Filesystem only -- `.md` command files, `.sh` scripts, spec directories under `specs/`
**Testing**: Manual validation via functional testing; shellcheck for any shell script changes
**Target Platform**: macOS/Linux developer workstations
**Project Type**: CLI toolkit / developer tooling (markdown command files + shell scripts)
**Performance Goals**: N/A (developer tooling, not performance-critical)
**Constraints**: Must be idempotent; must preserve manual edits in child specs; must not break existing specs without phase annotations
**Scale/Scope**: 2 new source files (command + agent), 3 modified files (specify command, spec template, setup.sh); child spec directories under `specs/`

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Readability First | **PASS** | Phase annotations use structured markdown with labeled fields; manifest uses a human-readable table; conflict markers include descriptive context |
| II. Functional Design | **PASS** | Phase detection takes user stories as input and produces phase groupings as output; splitting skill takes a phase-annotated spec and produces child spec directories deterministically |
| III. Maintainability Over Cleverness | **PASS** | Phase detection uses straightforward keyword heuristics, not complex NLP; reconciliation uses section-level comparison, not line-level diffing |
| IV. Best Practices | **PASS** | Follows existing SpecKit patterns (command file + agent file); child specs use identical structure to standard specs; naming convention extends existing kebab-case pattern |
| V. Simplicity (KISS & YAGNI) | **PASS** | Two release strategy categories (not a taxonomy); text-based status in manifest (not a state machine engine); conflict markers (not auto-resolution) |
| Test-First Development | **PASS** | Markdown command/agent files have no testable application logic. Shell script changes (setup.sh) are validated by T012 (shellcheck) and T013 (functional testing checklist from quickstart.md). No unit-testable business logic is introduced. |
| Dev Server Verification | **N/A** | No web UI or API |
| Process Cleanup | **N/A** | No long-running processes involved |

**Post-Phase 1 re-check**: All principles still PASS. The design adds two new files following existing patterns, modifies three existing files with additive changes, and introduces no new abstractions or dependencies beyond what the requirements mandate.

## Project Structure

### Documentation (this feature)

```text
specs/c31c-feat-phase-aware-specs/
├── plan.md              # This file
├── research.md          # Phase 0 output -- research decisions
├── data-model.md        # Phase 1 output -- entity definitions
├── quickstart.md        # Phase 1 output -- implementation quick reference
├── contracts/           # Phase 1 output -- interface contracts
│   ├── speckit-specify-phases.md
│   ├── speckit-split.md
│   └── manifest-format.md
└── tasks.md             # Phase 2 output (created by /speckit.tasks)
```

### Source Code (repository root)

```text
# Files MODIFIED (existing)
speckit-commands/speckit.specify.md     # NEW source copy (from .claude/commands/), then extended with phase-aware logic
.specify/templates/spec-template.md     # Add Phases section placeholder
setup.sh                                # Add copying of split command and agent files

# Files CREATED (new)
speckit-commands/speckit.split.md       # Splitting skill command file
claude-agents/split.md                  # Splitting skill agent file
```

**Structure Decision**: This is a modification-heavy feature within the existing flat project structure. Source command files live in `speckit-commands/`, agent files in `claude-agents/`, both copied to `.claude/commands/` and `.claude/agents/` by `setup.sh`. No new directories are created in the source layout. Child spec directories are created at runtime by the splitting skill under the consumer project's `specs/` directory.

## Complexity Tracking

No constitution violations to justify. All changes follow existing patterns and add minimal complexity.
