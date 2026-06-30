# Marge (loop step)

**Diff existence check**: Confirm there is a diff to review. Run `git diff --quiet $(git merge-base HEAD origin/main 2>/dev/null || git merge-base HEAD main)...HEAD` via Bash tool; if the command exits 0 (no diff), abort: "No changes detected between the feature branch and main. Nothing to review."

Execute the Marge loop using the shared loop orchestrator. Read and follow `.claude/agents/loop-orchestrator.md` with this LOOP_CONFIG:

- **AGENT_NAME**: marge
- **AGENT_DISPLAY_NAME**: Marge
- **AGENT_FILE**: .claude/agents/marge.md
- **SLASH_COMMAND_REF**: /speckit.review
- **PROMISE_TAG**: ALL_FINDINGS_RESOLVED
- **PREREQ_FLAGS**: --json --require-tasks --include-tasks
- **REQUIRED_ARTIFACTS**: spec.md, plan.md, tasks.md
- **MAX_ITERATIONS**: 30 (or marge max from Step 4)
- **EXTRA_PROMPT_SUFFIX**: (none)
- **REPORT_MODE**: needs_human

Skip the orchestrator's Pre-Flight and Agent File checks (already done in pipeline pre-flight). Start from Step 1 (Parse Arguments) using the already-resolved `FEATURE_DIR`.

**End-of-loop full quality gate**: When the marge loop exits via the success path (all findings resolved), run the full gate once via Bash tool:

```bash
bash .specify/quality-gates.sh
```

If it exits non-zero, set the pipeline completion status to **failure** with reason "marge end-of-loop full quality gates failed", surface the failing output in the report, and suggest resuming with `--from marge`. Do NOT run this gate on max-iterations, stuck, or failure exits.

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

**Failure handling**: If the loop aborts (stuck, stalled, oscillating, or sub agent failure), abort the pipeline immediately. Do NOT run the manifest update on failure exits — the phase is not complete. Suggest manual review and resuming with `--from marge`.

