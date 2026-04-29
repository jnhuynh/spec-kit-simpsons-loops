# Implementation Plan: Multi-Phase Deploy Support

**Branch**: `008-feat-multi-phase-deploys` | **Date**: 2026-04-27 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/008-feat-multi-phase-deploys/spec.md`

## Summary

Add multi-phase deploy support to the SpecKit + Simpsons-loops pipeline so a single feature can ship as a stack of independently-deployable pull requests. The pipeline runs end to end on a single feature branch (specify -> homer -> plan -> tasks -> lisa -> ralph -> marge) and then a new **split** step groups commits by `Phase: N` git trailer, builds stacked branches `NNNN-<type>-<slug>-phaseK`, and opens stacked pull requests with the correct base-branch chain. Multi-phase mode is detected structurally — by the presence of a `## Deploy Phases` section in `plan.md` — with no flag, environment variable, or command-line switch involved. Single-phase features keep working unchanged: no phase trailers, no per-phase findings, exactly one pull request.

The implementation is concentrated in markdown command files (`speckit-commands/*.md`), agent files (`claude-agents/*.md`), the marge check pack directory (`.specify/marge/checks/migrations.md`), the SpecKit templates (`.specify/templates/*.md`), and the downstream-consumer template (`templates/CLAUDE.md`). No new bash scripts are added; the split step is implemented entirely as agent instructions executing `git`, `gh`, and standard Unix tooling. Two new persisted artifacts (`<FEATURE_DIR>/review-report.md` and `<FEATURE_DIR>/split-report.md`) carry machine-readable Markdown tables that connect the review step's findings to the split step's gating decisions.

## Technical Context

**Language/Version**: Bash 4+ (shell scripts), Markdown (command/agent files) + Claude CLI (`claude` command)
**Primary Dependencies**: Claude CLI (`claude` command), Agent tool, Bash tool, `git` (with trailer support — Git 2.32+ for `--format='%(trailers:key=Phase,valueonly)'`), `gh` CLI (authenticated for the repository), standard Unix utilities (`grep`, `sed`, `awk`, `test`)
**Storage**: Filesystem only — `.md` command files, `.md` agent files, `.md` check pack files, `.md` template files, `.sh` scripts. Two new persisted artifacts per feature directory: `review-report.md` and `split-report.md`. No databases, no network state beyond Git remote refs and GitHub pull requests opened by `gh`.
**Testing**: shellcheck for shell scripts (existing quality gates); manual end-to-end pipeline verification per the quickstart checklist; spot-check regression against `001-consistency-cleanup` to confirm single-phase backward compatibility (FR-022, SC-003).
**Target Platform**: macOS/Linux developer workstations running the Claude CLI with `gh` and `git` configured for a GitHub repository.
**Project Type**: CLI toolkit / developer tooling
**Performance Goals**: N/A (developer-tool feature; the split step's runtime is bounded by the number of phases and the size of the feature branch's commit set, not by throughput targets).
**Constraints**: Must work within Claude Code Agent tool invocation model. The split step MUST use `origin/main` as the canonical base for all decisions and MUST run `git fetch origin main` at the start of every run (per FR-013). Force-pushes to phase branches MUST use `--force-with-lease` (per FR-017). Phase pull-request title and body are pipeline-managed and overwritten on every run (per FR-016). Persisted reports MUST use the exact GitHub Flavored Markdown table column headers fixed by FR-012a and FR-019a so consumers can parse them with `awk -F '|'` without introducing a new dependency.
**Scale/Scope**: Realistic phase counts: 2-6. The branch-naming convention `NNNN-<type>-<slug>-phaseK` fits within GitHub's 244-byte branch-name limit for all realistic phase counts. The multi-phase tasks.md is bounded by phase count times the existing single-phase tasks-template scale; no quadratic blowup.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Readability First | **PASS** | New command and agent files follow existing patterns. Variable names are descriptive (`PHASE_COUNT`, `phase_branch`, `review_report_path`). The persisted-report tables use explicit column headers fixed by spec rather than positional encodings. |
| II. Functional Design | **PASS** | The split step is a deterministic function of `(feature branch commit set with Phase: trailers, plan.md Deploy Phases section, review-report.md, origin/main)`. Two independent working copies running the split step against the same inputs produce the same stacked branches, pull-request titles, pull-request bodies, and split-report rows. The fetch of `origin/main` (FR-013) is the single point of remote state ingress. |
| III. Maintainability | **PASS** | Implementation lives entirely in markdown command files, agent files, and templates — the same surface every existing pipeline step uses. No new bash scripts, no new utility modules. Multi-phase behavior is structurally toggled by the `## Deploy Phases` section in `plan.md` rather than gated behind a flag (FR-002, FR-020). Existing utilities (`check-prerequisites.sh`, `quality-gates.sh`, marge check-pack discovery) are reused without modification. |
| IV. Best Practices | **PASS** | Uses Git's standard trailer mechanism (`Phase: N` per RFC 5322 / `git interpret-trailers`) rather than ad-hoc commit-message conventions. Uses `gh pr create --base` for stacked PR base-branch chaining, which is GitHub's documented mechanism for stacked PRs. Uses `--force-with-lease` for phase-branch force-push, which is the community-standard safe force-push primitive. The persisted-report tables use GitHub Flavored Markdown — the same format the rest of SpecKit uses for human-readable artifacts. |
| V. Simplicity (KISS & YAGNI) | **PASS** | Multi-phase detection is the presence of one section in one file (`## Deploy Phases` in `plan.md`); there is no flag, no env var, no config file. The split step is a single new command file plus a single new agent file; no orchestrator refactor, no new shell scripts, no new utility module. The single global quality gate (`.specify/quality-gates.sh`) applies to the integrated branch as a whole — there are no per-phase quality gates (per Assumptions). Spec freeze is a documented social rule rather than enforced tooling (per Assumptions). Cross-feature phase coordination, deploy automation, deploy-state tracking, and rollback automation are explicitly out of scope (per Out of Scope in spec). |
| Test-First Development | **N/A** | This feature modifies markdown command files (`.claude/commands/*.md`), markdown agent files (`.claude/agents/*.md`), markdown check pack files (`.specify/marge/checks/*.md`), and markdown template files (`.specify/templates/*.md`) — all interpreted by the Claude CLI as declarative instructions, not executable code. The constitution's test-first requirement targets executable logic ("new service functions, business logic, hooks, utilities, and bug fixes"); markdown command files are declarative instructions, not testable code units. **Alternative verification** substitutes for automated unit tests: (1) the quickstart.md verification checklist defines concrete acceptance checks covering each functional requirement; (2) spec User Story 3's independent test (re-run pipeline against `001-consistency-cleanup`) covers single-phase regression per SC-003; (3) spec User Story 1's independent test (synthetic column-rename feature) covers the multi-phase happy path per SC-001 and SC-002; (4) spec User Story 2's independent test (deliberately broken plan) covers migration-safety check pack severity assignments per SC-004. This approach mirrors the verification strategy that 005-fix-subagent-quality-gates and 006-stop-after-param used successfully for the same medium. |
| Dev Server Verification | **N/A** | No web UI or API. Verification is via the synthetic feature, the regression spot-check, and the deliberately-broken-plan exercises documented in the spec's User Stories. |
| Process Cleanup | **N/A** | The split step does not start dev servers, watchers, or containers. The only side effects are git operations on phase branches and `gh pr create` / `gh pr edit` invocations against the GitHub remote. No cleanup obligations beyond the standard `git fetch` / `gh` invocations the step already performs. |

**Post-Phase 1 re-check**: All applicable principles still PASS after Phase 1 design (data-model.md, contracts/, quickstart.md). The split step's contract surface is small (one command file, one agent file, two persisted-report formats) and matches the simplicity gate. No new violations introduced; Complexity Tracking remains empty.

## Project Structure

### Documentation (this feature)

```text
specs/008-feat-multi-phase-deploys/
├── checklists/
│   └── requirements.md          # Specification quality checklist (existing)
├── spec.md                      # Feature specification (existing)
├── plan.md                      # This file (/speckit.plan command output)
├── research.md                  # Phase 0 output — design decisions documented
├── data-model.md                # Phase 1 output — entity definitions
├── contracts/
│   ├── split-command.md         # Contract for /speckit.split command
│   ├── review-report.md         # Contract for <FEATURE_DIR>/review-report.md
│   └── split-report.md          # Contract for <FEATURE_DIR>/split-report.md
├── quickstart.md                # Phase 1 output — implementation order and verification checklist
└── tasks.md                     # Phase 2 output (created by /speckit.tasks — NOT created here)
```

### Source Code (repository root)

```text
speckit-commands/                                # Source-of-truth slash commands
├── speckit.pipeline.md                          # MODIFIED — append post-marge split step; multi-phase detection
├── speckit.split.md                             # NEW — split-step command file
├── speckit.ralph.implement.md                   # MODIFIED — emit Phase: N trailer when task tag is [phase-N]
├── speckit.marge.review.md                      # MODIFIED — load migrations.md; emit per-phase findings; persist review-report.md
└── (others UNCHANGED)                           # speckit.homer.clarify.md, speckit.lisa.analyze.md, speckit.review.md

claude-agents/                                   # Source-of-truth agent definitions
├── plan.md                                      # MODIFIED — emit Deploy Phases section when heuristics fire
├── tasks.md                                     # MODIFIED — organize by phase + tag tasks [phase-N]
├── ralph.md                                     # MODIFIED — append Phase: N trailer to task commits
├── marge.md                                     # MODIFIED — pack discovery picks up migrations.md; per-phase finding emission; persist review-report.md
├── split.md                                     # NEW — agent definition for split step
└── (others UNCHANGED)                           # specify.md, homer.md, lisa.md

.specify/
├── marge/checks/
│   └── migrations.md                            # NEW — migration-safety check pack (M1-M8 + structural checks)
├── templates/
│   ├── plan-template.md                         # MODIFIED — document optional "Deploy Phases" section
│   └── tasks-template.md                        # MODIFIED — document phase tagging and per-phase top-level structure
├── memory/constitution.md                       # UNCHANGED (per CLAUDE.md "constitution is authoritative")
├── quality-gates.sh                             # UNCHANGED (single global gate; no per-phase override)
└── scripts/bash/                                # UNCHANGED — no new bash scripts
    ├── check-prerequisites.sh
    ├── common.sh
    ├── create-new-feature.sh
    ├── setup-plan.sh
    └── update-agent-context.sh

templates/
└── CLAUDE.md                                    # MODIFIED — section on multi-phase deploys for downstream consumers

setup.sh                                         # UNCHANGED — already idempotently seeds .specify/marge/checks/

README.md                                        # MODIFIED — add multi-phase deploys to feature list

.claude/                                         # Installed copies — overwritten by setup.sh; never edited directly
├── commands/
│   ├── speckit.pipeline.md                      # MIRRORS speckit-commands/speckit.pipeline.md
│   ├── speckit.split.md                         # MIRRORS speckit-commands/speckit.split.md
│   ├── speckit.ralph.implement.md               # MIRRORS speckit-commands/speckit.ralph.implement.md
│   └── speckit.marge.review.md                  # MIRRORS speckit-commands/speckit.marge.review.md
└── agents/
    ├── plan.md                                  # MIRRORS claude-agents/plan.md
    ├── tasks.md                                  # MIRRORS claude-agents/tasks.md
    ├── ralph.md                                  # MIRRORS claude-agents/ralph.md
    ├── marge.md                                  # MIRRORS claude-agents/marge.md
    └── split.md                                  # MIRRORS claude-agents/split.md
```

**Structure Decision**: Source-of-truth files live in the repo root (`speckit-commands/`, `claude-agents/`, `.specify/marge/checks/`, `.specify/templates/`, `templates/`) per CLAUDE.md ("Source vs Installed Files"). Installed copies under `.claude/` are seeded by `setup.sh` and exist only for dogfooding within this repo; they MUST NOT be edited directly. The implementation surface is one new check pack file, one new command file, one new agent file, and targeted modifications to four existing command files, four existing agent files, two existing templates, one downstream-consumer template, and the README. No new bash scripts, no new utility modules, no changes to `.specify/scripts/bash/`, no changes to the constitution.

## Design Decisions

### D-001: Multi-phase detection signal

The presence of a `## Deploy Phases` section in `plan.md` is the **sole** signal that marks a feature as multi-phase (FR-002, FR-020). No flag, environment variable, command-line switch, or config file. The pipeline orchestrator and the split step both read `plan.md` and grep for the section header to decide which mode to run. Backward compatibility is structural: every existing single-phase plan has no `## Deploy Phases` section, so the multi-phase branches are dead code paths for those features.

### D-002: Phase-trailer commit format

Implementation commits for tasks tagged `[phase-N]` carry a `Phase: N` git trailer per RFC 5322 (FR-006). The trailer is appended by Ralph when it composes the commit message. The split step reads trailers via `git log origin/main..HEAD --format='%H %(trailers:key=Phase,valueonly)'` (FR-013) — this is Git's standard trailer-extraction format. Untrailerd commits group into phase 1 deterministically, without consulting neighboring commits (FR-014, per the clarification recorded in spec.md). Authors who need an infrastructure commit to land in a different phase must attach the `Phase: N` trailer manually or rebase to attach it.

### D-003: Stacked branch naming and base-branch chain

For multi-phase features, the split step creates branches named `NNNN-<type>-<slug>-phaseK` (FR-015). Phase 1 is based on `origin/main`; phase K>1 is based on the previous phase's branch. Pull requests are opened with `gh pr create --base <base-branch>` so the stack chains correctly: `main <- phase1 <- phase2 <- ... <- phaseN` (FR-016). For single-phase features, the existing single-PR behavior is preserved: one pull request against `main` from the feature branch (FR-019).

### D-004: Idempotent rebuild via reset + cherry-pick + force-with-lease

When the split step re-runs and a phase's commit set has changed (commits added, removed, or amended), the step deterministically rebuilds the phase branch by `git reset --hard <base>` followed by `git cherry-pick <phase-commits>`, then force-pushes with `--force-with-lease` (FR-017). Phase branches are pipeline-managed artifacts; humans MUST NOT commit directly to them. The only safeguard is FR-017's `skipped-merged` rule: when a phase pull request is already merged into `origin/main`, the split step skips rebuild and reports the skip — protecting shipped history from accidental rewrite.

### D-005: `origin/main` as canonical base

Every reference to "main" in the split step's logic means `origin/main` after `git fetch origin main` (FR-013, per the clarification recorded in spec.md). This includes commit enumeration, phase-1 cherry-pick base, phase-1 reset target during idempotent rebuild, and `skipped-merged` detection. The split step never consults the local `main` branch. Two independent working copies running the split step against the same feature branch and the same remote state produce identical stacks. If `git fetch origin main` itself fails, the split step fails fast with a `failed` row in the split report, before any branch is rebuilt.

### D-006: Persisted review report as single source of truth for gating

The review step (Marge) writes findings to `<FEATURE_DIR>/review-report.md` on every run (FR-012a). The split step reads that file to identify unresolved high-severity findings (`Status` other than `resolved`) and gates pull-request creation per FR-018. The split step does NOT independently re-verify any structural invariant from FR-010; the review report is the single source of truth for gating decisions. If the review report is missing, the split step refuses to run and instructs the author to run review first. The report's machine-readable surface is a single GFM table with columns `| ID | Severity | Phase | Status | Check Pack | Summary |` — fixed by spec, so the split step can parse it with `awk -F '|'` without introducing a new dependency.

### D-007: Migration-safety check pack with high-severity gating contract

A new check pack `migrations.md` covers the eight FR-010 patterns (M1-M8 in research.md) plus four structural-consistency checks (orphan phase tag, non-contiguous phases, malformed `Phase:` trailer, phase-trailer-without-deploy-phases) per the clarifications in spec.md. **Every** pattern enumerated in FR-010 is emitted at `high` severity (per the clarification on severity assignment), so the gating contract is uniform: any FR-010 detection blocks the affected phase. The pack MAY emit lower-severity findings for advisory observations outside the catalog, but FR-010-cataloged patterns are always `high`. Marge's existing check-pack discovery loop picks up the new pack automatically (FR-023), so no agent-discovery code changes.

### D-008: Phase pull-request title and body are pipeline-managed

The split step generates each phase pull request's title and body deterministically from the feature branch name and the plan artifact (FR-016, per the clarification on PR title/body in spec.md). Title format for multi-phase: `[Phase K/N] <feature-branch-name>`. Title format for single-phase: `<feature-branch-name>` (matches today). Body composition: a `Part of <FEATURE_DIR>/spec.md` first line; for multi-phase, `## Phase Goal`, `## Post-deploy production state`, and `## Stack` sections rendered from the plan's "Deploy Phases" entry; for single-phase, only the first line. The split step recomputes title and body on every run, compares against `gh pr view --json title,body`, and overwrites via `gh pr edit --title --body` when they differ. Human edits WILL be overwritten on the next run. This makes the `unchanged` status of FR-019a deterministically computable from `(commit SHAs, title, body)`.

### D-009: Persisted split report mirrors stdout summary

The split step writes `<FEATURE_DIR>/split-report.md` on every run (FR-019a) with one row per phase enumerated. Statuses: `created`, `updated`, `unchanged`, `skipped-merged`, `gated`, `failed`. Columns are fixed: `| Phase | Status | Branch | PR URL | Reason |`. The pipeline orchestrator reads the file to determine the split step's outcome without re-running it; absence of the file is treated as a split-step failure. A concise human-readable summary mirrors the table to stdout so the author sees the result immediately.

### D-010: Per-phase findings via Marge — no separate per-phase review pass

Marge runs **once** on the integrated feature branch (FR-012) and emits per-phase findings tagged with the phase that introduced the issue (FR-011). The Phase column of each row in `review-report.md` carries the integer phase number for findings attributable to a single phase, or the literal `-` for structural inconsistencies the migration-safety check pack cannot attribute (e.g., malformed trailer, phase-trailer-without-deploy-phases). The split step treats any `high`-severity finding with Phase `-` as gating every phase in the run (a global gate). Marge does not run K separate per-phase passes; per-phase scope is expressed entirely via finding tags.

### D-011: Stage relabel inside multi-phase tasks.md

For multi-phase features, deploy phases are the sole top-level (`##`) organizing structure of `tasks.md` (FR-004). The existing per-story task structure (`Phase 1: Setup`, `Phase 2: Foundational`, `Phase 3+: User Stories`) is preserved as second-level (`###`) "Stage" headings nested inside each top-level deploy phase, using the form `### Stage: Setup`, `### Stage: Foundational`, `### Stage: User Stories` (FR-005, per the Stages clarification in spec.md). Empty stages are omitted. Every task under any stage within deploy-phase K carries `[phase-K]`. For single-phase features, the existing template is preserved unchanged — Setup/Foundational/User Stories remain at the top level, no "Stages" relabel, no `[phase-N]` tags. This keeps single-phase tasks.md a strict subset of multi-phase tasks.md.

### D-012: No new bash scripts; reuse existing utilities

The split step is implemented entirely in markdown (the new command file plus the new agent file) executing `git`, `gh`, `awk`, and other standard Unix tools via the Bash tool. No new `.specify/scripts/bash/*.sh` is added. The setup script (`setup.sh`) requires no changes — its existing idempotent check-pack seeding loop picks up `migrations.md` automatically (FR-024). The single global quality gate (`.specify/quality-gates.sh`) applies to the integrated branch as a whole, with no per-phase variants (per Assumptions in spec.md).

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

No constitution violations to justify — all applicable principles PASS. Test-First Development is N/A for the markdown medium per the table above; alternative verification (quickstart checklist, regression spot-check, synthetic-feature happy path, deliberately-broken-plan failure path) substitutes per the precedent established by 005-fix-subagent-quality-gates and 006-stop-after-param.
