# Marge (loop step)

Run the Marge loop exactly as its standalone skill defines it: read and follow `.claude/skills/speckit-marge-review/SKILL.md`, passing `<FEATURE_DIR>` through as the skill's spec-dir argument. The skill owns the review-skill pre-flight, diff existence check, quality-gate validation, LOOP_CONFIG (including MAX_ITERATIONS), the end-of-loop full quality gate, and review report verification.

**Pipeline deltas**:

- Skip the loop orchestrator's Pre-Flight and Agent File checks (already done in pipeline pre-flight). Start from the orchestrator's Step 1 (Parse Arguments) using the already-resolved `FEATURE_DIR`.
- If the skill reports **failure** (loop abort, or its end-of-loop full quality gate failed), set the pipeline completion status to **failure** with the skill's reason, surface the failing output in the report, and suggest resuming with `--from marge`. Do NOT run the manifest update below on failure exits — the phase is not complete.

**Post-marge manifest update (child specs only)**: When the marge loop exits via the success path (all findings resolved) AND the full quality gate passes, update the parent manifest to mark this phase as "Complete". Skip this entirely if FEATURE_DIR does not match the `--p{N}-` pattern (not a child spec).

1. Resolve `PARENT_DIR` by stripping `--p{N}-{slug}` from FEATURE_DIR. Extract the phase number `N`.

2. Read `{PARENT_DIR}/spec.md`, locate the `## Manifest` section, and parse the table. Find the row where the Directory column matches this child's directory name.

3. Check current status and apply transition:
   - If **"In Progress"**: Update to **"Complete"**.
   - If **"Draft"**: Update to **"Complete"** (the pipeline ran the full lifecycle, implicitly passing through In Progress).
   - If **"Complete"**: No-op — already marked. Do not write or commit.
   - If **"Cancelled"**: Log warning: `Phase {N} is marked Cancelled in the parent manifest. Pipeline completed but not updating status.` Do not update.

4. Write the update using the Edit tool — replace only the Status cell in the matching manifest table row in `{PARENT_DIR}/spec.md`. Preserve all other content.

5. Commit the change:

```bash
git add {PARENT_DIR}/spec.md && git commit -m "chore: mark phase {N} Complete in parent manifest"
```

6. Output phase status summary:

```
Phase Status Summary (parent: {PARENT_DIR}):
  P1: {slug} .... Complete
  P2: {slug} .... Complete  <-- complete
  P3: {slug} .... Draft
```

Use dot-padding to align status values. Mark the phase that was just completed with `<-- complete`.
