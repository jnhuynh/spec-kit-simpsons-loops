# Implementation Plan: [FEATURE]

**Branch**: `[###-feature-name]` | **Date**: [DATE] | **Spec**: [link]
**Input**: Feature specification from `/specs/[###-feature-name]/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

[Extract from feature spec: primary requirement + technical approach from research]

## Technical Context

<!--
  ACTION REQUIRED: Replace the content in this section with the technical details
  for the project. The structure here is presented in advisory capacity to guide
  the iteration process.
-->

**Language/Version**: [e.g., Python 3.11, Swift 5.9, Rust 1.75 or NEEDS CLARIFICATION]  
**Primary Dependencies**: [e.g., FastAPI, UIKit, LLVM or NEEDS CLARIFICATION]  
**Storage**: [if applicable, e.g., PostgreSQL, CoreData, files or N/A]  
**Testing**: [e.g., pytest, XCTest, cargo test or NEEDS CLARIFICATION]  
**Target Platform**: [e.g., Linux server, iOS 15+, WASM or NEEDS CLARIFICATION]
**Project Type**: [e.g., library/cli/web-service/mobile-app/compiler/desktop-app or NEEDS CLARIFICATION]  
**Performance Goals**: [domain-specific, e.g., 1000 req/s, 10k lines/sec, 60 fps or NEEDS CLARIFICATION]  
**Constraints**: [domain-specific, e.g., <200ms p95, <100MB memory, offline-capable or NEEDS CLARIFICATION]  
**Scale/Scope**: [domain-specific, e.g., 10k users, 1M LOC, 50 screens or NEEDS CLARIFICATION]

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

[Gates determined based on constitution file]

<!--
  OPTIONAL `## Deploy Phases` SECTION — the plan agent appends this section
  here only when the feature requires phased rollout (schema migration
  combined with reads/writes on the same data, breaking API change with live
  callers, multi-service rollout coordination). For single-phase features,
  the plan agent leaves this template comment untouched and emits NO
  `## Deploy Phases` heading. The presence or absence of the
  `## Deploy Phases` heading in the rendered plan.md is the sole signal
  that distinguishes multi-phase from single-phase mode (FR-002) — no flag,
  environment variable, or command-line switch is involved. Because the
  template ships without the heading rendered, a verbatim copy of this
  template into plan.md is single-phase by default, preserving FR-022
  backward compatibility for every existing feature.

  When the plan agent renders this section (multi-phase features only), it
  MUST use the canonical machine-parseable format pinned by FR-001 so the
  split step (`/speckit.split`) can deterministically extract the goal text
  and post-deploy text into each phase pull request's body per FR-016. The
  canonical format is:

    - A level-2 heading exactly `## Deploy Phases` (no trailing punctuation).
    - One level-3 heading per phase of the form `### Phase K: <title>` where
      `K` is the integer phase number starting at 1 and `<title>` is a short
      human-readable title.
    - Inside each phase heading, two labelled fields rendered exactly as
      `**Goal**: <single-paragraph goal text>` and
      `**Post-deploy production state**: <single-paragraph post-deploy text>`,
      each starting on its own line.
    - Phase numbers MUST start at 1 and be contiguous (no gaps). Non-contiguous
      phases are flagged by the migration-safety check pack as `high` severity.

  The split step parses this format directly — no alternative rendering is
  accepted. Field values that span multiple paragraphs continue until the
  next labelled field, the next `### Phase K:` heading, or the end of the
  section.

  Worked four-phase example (column rename — expand-contract):

    ## Deploy Phases

    ### Phase 1: Add new column (additive, backward-compatible)

    **Goal**: Schema in place; old code continues to work unchanged.

    **Post-deploy production state**: `users.email` exists, nullable, all rows
    NULL. `users.email_address` remains the source of truth for reads and
    writes.

    ### Phase 2: Dual-write + backfill

    **Goal**: New writes populate both columns. Historical rows backfilled in
    a non-blocking job.

    **Post-deploy production state**: `users.email` populated for all rows;
    reads still use `users.email_address`.

    ### Phase 3: Switch reads

    **Goal**: Reader code switched to `users.email`. Both columns continue to
    be written.

    **Post-deploy production state**: `users.email` is the read source of
    truth; `users.email_address` is still written but no longer read.

    ### Phase 4: Drop old column

    **Goal**: Stop writing `users.email_address`; drop it.

    **Post-deploy production state**: `users.email_address` is gone;
    `users.email` is the sole column.

  The four-phase pattern above is the default template for column-rename
  features (expand-contract). Adapt the count and titles for other migration
  shapes — for example, adding a NOT NULL column typically needs three
  phases: add nullable, backfill, alter to NOT NULL. For a non-migration
  multi-phase feature (such as a breaking API change), use phases that
  mirror the expand-contract shape: introduce the new contract, migrate
  callers, retire the old contract.
-->

## Project Structure

### Documentation (this feature)

```text
specs/[###-feature]/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)
<!--
  ACTION REQUIRED: Replace the placeholder tree below with the concrete layout
  for this feature. Delete unused options and expand the chosen structure with
  real paths (e.g., apps/admin, packages/something). The delivered plan must
  not include Option labels.
-->

```text
# [REMOVE IF UNUSED] Option 1: Single project (DEFAULT)
src/
├── models/
├── services/
├── cli/
└── lib/

tests/
├── contract/
├── integration/
└── unit/

# [REMOVE IF UNUSED] Option 2: Web application (when "frontend" + "backend" detected)
backend/
├── src/
│   ├── models/
│   ├── services/
│   └── api/
└── tests/

frontend/
├── src/
│   ├── components/
│   ├── pages/
│   └── services/
└── tests/

# [REMOVE IF UNUSED] Option 3: Mobile + API (when "iOS/Android" detected)
api/
└── [same as backend above]

ios/ or android/
└── [platform-specific structure: feature modules, UI flows, platform tests]
```

**Structure Decision**: [Document the selected structure and reference the real
directories captured above]

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| [e.g., 4th project] | [current need] | [why 3 projects insufficient] |
| [e.g., Repository pattern] | [specific problem] | [why direct DB access insufficient] |
