# Split (conditional single-shot step — multi-phase parent specs only)
Check if the current spec is a child spec (directory name matches `--p{N}-` pattern). If it IS a child spec, **skip** — no recursive splitting. Continue to ralph.

If not a child spec, check if spec.md has 2+ phases (count `### Phase` subsections within `## Phases`). If single-phase or no phases, **skip** and continue to ralph.

If multi-phase parent spec (2+ phases): spawn a sub agent:
- **subagent_type**: `general-purpose`
- **agent file**: `.claude/agents/split.md`
- **prompt**: `Feature directory: <FEATURE_DIR>. Run non-interactively.`

After split completes, read the parent spec's `## Manifest` section to get the list of child directories. Then prompt the user with two options using the AskUserQuestion tool:

**Option 1 (Recommended)**: "Stop and work on children" — Display the child spec directories and guidance:
"This parent spec has been split into {N} child specs:

  {list child directories}

The parent spec's plan and tasks describe the full feature scope. Each child spec should now be run through its own pipeline.

To pipeline each child spec (run in phase order):

  /speckit.pipeline {child-dir-1}
  /speckit.pipeline {child-dir-2}
  ...

Deploy and validate each phase in production before starting the next. When you pipeline a child spec, it auto-reconciles with what earlier phases actually built."

**Option 2**: "Continue implementing full parent spec as a monolith" — With description: "WARNING: This will implement all phases as a single deployment, producing one large PR with all changes across all phases. This defeats the purpose of phased delivery. Only choose this if phased delivery is not needed despite having multiple phases."

If user selects option 1 (default/recommended): stop the pipeline. Set completion status to **split-complete**. Proceed to Step 6 (Report Results).
If user selects option 2: log the warning and continue to ralph/marge.

**Failure handling**: If the sub agent fails, abort. Suggest resuming with `--from split`.

**Post-step stop check**: After split completes, if STOP_AFTER_STEP equals `split`, output: `Pipeline stopped after split per --stop-after parameter. Skipping: ralph, marge.` and skip all remaining steps.

