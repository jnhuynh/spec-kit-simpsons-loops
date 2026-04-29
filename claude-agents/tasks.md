# Tasks Generation Agent - Spec Kit Integration

Generate a dependency-ordered task list from the spec and plan. This is a **single-shot** agent — run once and exit.

## Feature Directory

The feature directory is provided via the `-p` prompt when this agent is invoked. Extract the path from the prompt (e.g., "Feature directory: specs/a1b2-feat-foo").

## Instructions

Run `/speckit.tasks` to generate the task list. This will read the spec and plan, then produce a `tasks.md` in the feature directory.

## Multi-Phase Detection (FR-004, FR-005, FR-022)

After `/speckit.tasks` produces `tasks.md`, detect whether the feature is multi-phase by checking for a `## Deploy Phases` section in the generated `plan.md`:

```bash
grep -q '^## Deploy Phases$' <FEATURE_DIR>/plan.md
```

If the section is **present**, the feature is multi-phase: rewrite the generated `tasks.md` to use the multi-phase structure described in "Multi-phase tasks structure" below. If the section is **absent**, the feature is single-phase: leave the generated `tasks.md` untouched — today's template is preserved as a strict subset of multi-phase behavior per FR-022. No flag, environment variable, or command-line switch is introduced — absence of `## Deploy Phases` in `plan.md` is the sole signal for single-phase mode.

### Multi-phase tasks structure (FR-004, FR-005)

When the feature is multi-phase, organize `tasks.md` so that **deploy phases are the sole top-level (`##`) organizing structure** of the file, listed in deploy order starting at Phase 1. The existing Setup / Foundational / User-Stories structure is preserved as **second-level (`###`) "Stage" headings nested inside each deploy-phase section**.

Skeleton:

```markdown
# Tasks: <Feature Title>

<existing preamble — Input, Prerequisites, Tests, Organization, Format, Path Conventions>

---

## Phase 1: <goal copied from plan.md "### Phase 1:" heading title>

### Stage: Setup

- [ ] T001 [phase-1] <setup task description>

### Stage: Foundational

- [ ] T002 [phase-1] <foundational task description>

### Stage: User Stories

- [ ] T003 [phase-1] [US1] <user-story task description>

---

## Phase 2: <goal copied from plan.md "### Phase 2:" heading title>

### Stage: User Stories

- [ ] T004 [phase-2] [US1] <user-story task description>

---

<existing tail — Dependencies & Execution Order, Implementation Strategy, Notes>
```

Rules:

1. **Deploy phases as top-level sections (FR-004)** — every `##` heading inside the body of `tasks.md` (between the preamble and the "Dependencies & Execution Order" trailer) MUST correspond to a deploy phase from `plan.md`'s `## Deploy Phases` section, in deploy order. The heading form is `## Phase K: <title>` where `K` is the integer phase number and `<title>` is the title from the plan's `### Phase K: <title>` heading. No other `##` sections are emitted in the body.

2. **Stages as second-level headings (FR-005)** — within each deploy-phase section, the existing Setup / Foundational / User-Stories structure is preserved as `###` headings with the literal form `### Stage: Setup`, `### Stage: Foundational`, and `### Stage: User Stories`. The `Stage:` prefix disambiguates these subdivisions from deploy phases.

3. **Omit empty stages** — a `### Stage:` heading MUST be emitted only when that stage actually contains one or more tasks for the enclosing deploy phase. Do NOT emit empty stage headings.

4. **Tag every task (FR-004)** — every task entry under any stage within deploy-phase K MUST carry the `[phase-K]` tag in the bracketed metadata, using the existing `[ID] [P?] [Story] Description` format. The phase tag goes alongside any existing `[P]` or `[USk]` tags. Example: `- [ ] T012 [P] [phase-2] [US1] <description>`.

5. **Allocate work across phases** — distribute Setup, Foundational, and User-Story tasks into the deploy phases that need them. A deploy phase MAY contain only User-Story tasks if it has no setup or foundational work of its own. The same kind of work (e.g., Setup) MAY appear in multiple deploy phases when each phase has its own distinct setup needs.

6. **Preserve preamble and trailer** — the file's preamble (Input, Prerequisites, Tests, Organization, Format, Path Conventions) and trailer sections (Dependencies & Execution Order, Implementation Strategy, Notes, Parallel Examples) are preserved verbatim from the `/speckit.tasks` output. Only the body between them is reorganized.

### Single-phase tasks structure (FR-022)

When `plan.md` does NOT contain a `## Deploy Phases` section, the feature is single-phase. Leave the generated `tasks.md` untouched: Setup / Foundational / User-Stories remain at the top level (`##`), no `### Stage:` relabel is applied, and no `[phase-N]` tags are added. This preserves today's tasks template as a strict subset of multi-phase behavior so existing single-phase features continue to work without modification.

## Commit and exit

After the tasks are generated (and reorganized when the feature is multi-phase), commit and push:

```bash
git add -A && type=$(git branch --show-current | cut -f 2 -d '-') && scope=$(git branch --show-current | cut -f 3- -d '-') && ticket=$(git branch --show-current | cut -f 1 -d '-') && git commit -m "$type($scope): [$ticket] generate dependency-ordered task list"
git push origin $(git branch --show-current)
```
