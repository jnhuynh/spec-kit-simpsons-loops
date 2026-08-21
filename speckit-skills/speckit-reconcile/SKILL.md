---
name: speckit-reconcile
description: Detect drift between what completed phases actually shipped and what the parent spec says, and correct the parent.
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Outline

Phase child specs reference the parent spec by ID; the parent is the single source of truth for user stories, requirements, key entities, and success criteria. When an earlier phase ships something other than what the parent describes, the parent -- not the child -- is the thing that has gone stale. This skill finds that drift and fixes it at the source, so every later phase picks up from reality rather than from the original plan.

There is nothing to merge and no conflict to resolve: each inherited item exists exactly once. Correcting the parent makes the correction visible to every child that references it.

## Instructions

1. **Resolve the parent directory**:
   - If `$ARGUMENTS` contains a directory path, use it as `PARENT_DIR`.
   - Otherwise run `bash .specify/scripts/bash/check-prerequisites.sh --json --paths-only` from repo root and parse `FEATURE_DIR`. If `FEATURE_DIR` matches the `--p{N}-{slug}` child pattern, strip that suffix to get `PARENT_DIR`. If it does not match, use `FEATURE_DIR` itself as `PARENT_DIR` -- running from the parent's own branch is valid, and step 2's manifest check gates specs that were never split.

2. **Read the parent spec** at `PARENT_DIR/spec.md`. If it has no `## Manifest` section, report this error and **STOP**:

   ```
   ERROR: No manifest found at {PARENT_DIR}/spec.md. Run /speckit-split first.
   ```

3. **Select the phases to reconcile against**: parse the manifest table and take every phase whose Status is **Complete**. Those have shipped; their code is the ground truth. Phases with status Draft, In Progress, or Cancelled are skipped -- nothing has landed to compare against. If no phase is Complete, report `No completed phases -- nothing to reconcile.` and **STOP**.

4. **Gather what each completed phase actually shipped**. For each Complete phase, read in this order and stop when you have enough to judge:

   - `specs/{child-directory}/tasks.md` -- the completed task list is the closest record of what was built
   - `specs/{child-directory}/plan.md` -- the technical decisions the phase made
   - The source files those artifacts name -- read the code when a task description and the parent spec disagree, because the code decides

5. **Compare against the parent spec, in both directions**. For each item in that phase's `## Inherited Scope` (user stories, `FR-###`, key entities, `SC-###`), determine whether the parent's description still matches what shipped. Then reverse the comparison: work the phase shipped (per step 4's artifacts) that no spec item covers is drift too -- the **Undocumented requirement shipped** row below. Classify each mismatch:

   | Drift | Example | Disposition |
   |-------|---------|-------------|
   | **Mechanism changed** | FR says "retry with exponential backoff"; the phase shipped a dead-letter queue | Auto-fix: rewrite the parent's FR text to describe what shipped |
   | **Entity shape changed** | Parent lists `Payment{amount, status}`; the phase shipped a separate `LedgerEntry` | Auto-fix: update the parent's Key Entities |
   | **Undocumented requirement shipped** | The phase added an idempotency key nothing in the spec asked for | Auto-fix: add a new `FR-###` to the parent and assign it to the phase that shipped it via that phase's `**Requirements**:` line in `## Phases` (create the line if absent -- split's refresh reads it) |
   | **Requirement not shipped** | `FR-007` was in the phase's scope but no task implemented it | Auto-fix: reassign `FR-007` by moving it onto a later phase's `**Requirements**:` line in the parent's `## Phases` section |
   | **Intent changed** | The phase shipped behavior that contradicts what the requirement was *for*, not just how it works | **NEEDS_HUMAN**: report it, change nothing |
   | **Success criterion invalidated** | `SC-002`'s threshold is no longer measurable against what shipped | **NEEDS_HUMAN**: report it, change nothing |

   Auto-fix only where the requirement's *purpose* is unchanged and the wording is what has gone stale. Anything that would alter what the feature is meant to do is a human decision -- report it and leave the parent untouched. This mirrors Marge's `NEEDS_HUMAN` rule: mechanical corrections are applied, design judgment is escalated.

6. **Apply auto-fixes to `PARENT_DIR/spec.md` only.** Never edit a sibling child spec's authored content (`## Phase Boundary`, `FR-P{N}-###`, `SC-P{N}-###`) -- that content belongs to whoever wrote it. Preserve the parent's `## Manifest` statuses exactly as they are.

7. **Refresh derived child content**: if any auto-fix changed which IDs a phase owns (a reassigned `FR-###`, a newly added requirement), run `/speckit-split {PARENT_DIR}` to regenerate every child's derived sections. Its refresh logic rewrites only derived content and leaves authored content alone. Skip this when the fixes changed requirement *text* but not requirement *assignment* -- children reference IDs, so a reworded FR needs no child update at all.

8. **Report**:

   ```
   Reconcile ({PARENT_DIR}):
     Phases compared: P1 (expand-schema), P2 (payment-integration)
     Auto-fixed: 3
       FR-004  mechanism changed -- rewritten to describe the dead-letter queue P1 shipped
       Payment mechanism changed -- Key Entities now include LedgerEntry
       FR-007  not shipped in P1 -- reassigned to Phase 3 in ## Phases
     NEEDS_HUMAN: 1
       SC-002  threshold no longer measurable against what P1 shipped -- re-decide before P3
     Children refreshed: yes (phase assignments changed)
   ```

   If nothing drifted, report `No drift detected across N completed phase(s).` and make no edits.

## Non-Goals

- **Not a merge tool.** Inherited content lives in one place, so there is nothing to reconcile between two copies and no conflict markers to emit.
- **Not a gate.** `NEEDS_HUMAN` findings are reported, not blocking. The pipeline continues; the developer decides.
- **Not a re-planner.** Reconcile corrects the spec. Re-running `/speckit-plan` or `/speckit-tasks` on the affected child is the developer's call.
