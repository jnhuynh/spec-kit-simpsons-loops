# Research: Phase-Aware Specs with Splitting Skill

**Date**: 2026-05-28
**Feature**: `c31c-feat-phase-aware-specs`

## R1: Phase Annotation Storage Location within Spec

**Decision**: Add a dedicated `## Phases` section to spec.md, placed between the User Scenarios section and Requirements section. Each phase is a subsection with structured metadata fields.

**Rationale**: A dedicated section keeps phase metadata separate from user stories, making it parseable by the splitting skill without conflicting with existing spec structure. Placing it after User Scenarios means the phase groupings reference stories that have already been defined. The Requirements section follows naturally because requirements may reference phases. This matches the spec's FR-004 requirement that phase metadata be a dedicated section, not inline with stories.

**Alternatives considered**:
- Inline annotations within each user story (e.g., `(Phase: P1)`) -- harder to parse holistically, no place for cross-phase rationale, violates FR-004.
- YAML frontmatter block -- the spec template uses markdown, not YAML; would break consistency with existing specs.
- Separate `phases.md` file alongside `spec.md` -- adds file management complexity; the manifest already lives in the parent spec, so phase definitions should too.

## R2: Manifest Section Format

**Decision**: Add a `## Manifest` section at the end of the parent spec.md with a markdown table listing children in phase order. Columns: Phase, Directory, Description, Status, Release Strategy.

**Rationale**: A markdown table at the end of the spec is human-readable (FR-018), parseable by the splitting skill (grep for table rows), and does not interfere with existing sections. Placing it at the end means the splitting skill can append or update it without shifting other content. The table format matches existing data-model patterns in the project.

**Alternatives considered**:
- JSON block within the spec -- not human-readable, violates FR-018.
- Separate `manifest.md` file -- adds another file to track; the spec says "parent spec's manifest section" (FR-011), implying it belongs in spec.md.
- Checklist format (`- [ ] P1 ...`) -- less structured than a table, harder to parse status values reliably.

## R3: Child Spec Directory Naming and Filesystem Limits

**Decision**: Use `{parent-directory-name}--p{N}-{phase-slug}` exactly as specified in FR-008. Truncate the phase-slug portion if the total directory name exceeds 200 characters, preserving the `{parent}--p{N}-` prefix. Warn the developer on truncation.

**Rationale**: The `--` double-dash delimiter is safe per the spec's assumptions section (existing specs use single-dash kebab-case). 200 characters is a conservative limit well under the 255-byte ext4/APFS maximum while leaving room for nested file paths. Truncating only the slug preserves the parent relationship and phase ordering, which are more important than the descriptive label.

**Alternatives considered**:
- Hash-based naming (e.g., `{parent}--p{N}-{hash}`) -- loses human readability for marginal length savings.
- No truncation, error on overflow -- unfriendly; a warning with truncation is more practical since 200-char names are rare.

## R4: Reconciliation Strategy for Chain Awareness

**Decision**: Section-level comparison between child specs. When the splitting skill re-runs, it reads the current state of earlier child specs, regenerates the content for later child specs based on updated context, and diffs section-by-section against existing later child specs. Unchanged sections are preserved. Changed sections where the child spec has manual edits get conflict markers. Changed sections without manual edits are updated in place.

**Rationale**: Section-level granularity (using markdown heading boundaries) balances precision with simplicity. Line-level diffing would be fragile with markdown reformatting. Full-document regeneration would lose all manual edits. The spec requires that manual edits be preserved (FR-014) and conflicts be flagged (FR-014), which section-level comparison supports.

**Alternatives considered**:
- Full regeneration of later child specs -- violates FR-014 (preserve manual edits).
- Line-level three-way merge (like git merge) -- overly complex for markdown content; markdown reformatting causes spurious conflicts.
- No automatic reconciliation, just flags -- insufficient; FR-013 says later specs "MUST be updated," not just flagged.

## R5: Phase Detection Heuristics for the Specify Step

**Decision**: The specify step uses keyword and pattern-based heuristics to detect phase boundaries. Signals include: database migration terms (schema change, migration, expand-and-contract), third-party integration terms (API key, webhook, OAuth, payment provider), infrastructure-touching patterns (shared service, middleware, message queue), and estimated PR size (story count and complexity). Stories are grouped by dependency order: foundational changes first, dependent features second, user-facing reveals last.

**Rationale**: Heuristic-based detection is explicitly called out in the spec's assumptions as "best-effort." The signals cover the three categories mentioned in FR-001 (migrations, integrations, PR size). The grouping order (foundation, dependent, reveal) matches common deployment sequencing patterns. The developer reviews and adjusts before splitting, so false positives are recoverable.

**Alternatives considered**:
- LLM-based semantic analysis of stories -- the specify step already uses an LLM to generate the spec; the heuristics guide the LLM's phase grouping rather than replacing it. No separate analysis step needed.
- User-provided phase hints in the feature description -- adds friction; heuristic detection with review is lower-effort.

## R6: Splitting Skill Implementation Approach

**Decision**: Implement the splitting skill as a new SpecKit command file (`speckit.split.md`) in `speckit-commands/`, with a corresponding agent file (`split.md`) in `claude-agents/`. The command reads the parent spec's Phases and Manifest sections, creates/updates child spec directories, and updates the parent manifest.

**Rationale**: Following the existing SpecKit pattern (command file + agent file) keeps the project consistent. The splitting skill is a new pipeline step, not a modification to an existing step, so it gets its own command. The `setup.sh` script will copy it to `.claude/commands/` and `.claude/agents/` during installation, matching the existing deployment model.

**Alternatives considered**:
- Bash script implementation -- SpecKit commands are markdown files executed by Claude Code, not shell scripts. A bash script would break the established pattern.
- Embed splitting logic in the specify command -- violates separation of concerns; the specify step annotates phases, the splitting step acts on annotations. Different responsibilities, different commands.

## R7: Status Tracking Mechanism

**Decision**: Status is stored as a text value in the parent manifest table. The splitting skill reads and writes this field. Valid values are: Draft, In Progress, Complete, Cancelled. Transitions are validated by the splitting skill when updating: forward-only (Draft -> In Progress -> Complete) with any active state allowing Cancelled. The developer updates status manually by editing the manifest table or through a future convenience command.

**Rationale**: Storing status in the manifest table means the parent spec is the single source of truth (FR-017). Text values in a markdown table are human-readable and editable (FR-018). Transition validation in the splitting skill catches mistakes during re-runs. Manual editing is the simplest mechanism and aligns with the out-of-scope decision against automatic status detection.

**Alternatives considered**:
- Status in each child spec's frontmatter -- requires reading every child spec to get an overview; violates the "parent manifest alone" requirement (SC-005).
- Dedicated status command -- over-engineering for a text field edit; violates YAGNI. Can be added later if needed.

## R8: Conflict Marker Format

**Decision**: Use HTML comments with a structured format: `<!-- CONFLICT: [description of what changed in the earlier phase] -->` before the conflicting section, and `<!-- END CONFLICT -->` after it. The original content is preserved between the markers.

**Rationale**: HTML comments are invisible in rendered markdown but visible in source, making conflicts non-destructive to the reading experience while clearly flagged for the developer. The structured format includes context about what triggered the conflict, helping the developer resolve it. This matches the spec's explicit requirement for inline markers (FR-014).

**Alternatives considered**:
- Git-style conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`) -- these break markdown rendering and are confusing outside of git merge context.
- Markdown blockquotes with a warning prefix -- visible in rendered output, which clutters the spec view.
- Separate `conflicts.md` file -- harder to locate which section has the conflict; inline markers are more actionable.
