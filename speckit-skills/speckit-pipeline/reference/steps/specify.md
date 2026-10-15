# Specify (single-shot step)
Skip if `spec.md` already exists. Otherwise, spawn a sub agent:
- **subagent_type**: `general-purpose`
- **agent file**: `.claude/agents/single-shot.md`
- **prompt**: `Read and follow .claude/agents/single-shot.md with SINGLE_SHOT_CONFIG — STEP_COMMAND: /speckit-specify <DESCRIPTION>; COMMIT_DESCRIPTION: generate feature specification; FEATURE_DIR: <FEATURE_DIR>; EXTRA_INSTRUCTIONS: For anything that would normally get a [NEEDS CLARIFICATION] marker, make an informed guess and document it in the spec's Assumptions section — the Homer loop refines gaps afterward. Auto-resolve all clarifications; never present questions to the user. Open the spec with a "## Plain summary" section directly after the metadata block: 150 words or fewer saying who this is for, what changes for them, and what goes wrong if it is wrong.`

**Post-specify re-resolution**: After the specify step completes successfully, if `FEATURE_DIR` is empty or the directory does not exist, re-resolve by running `bash .specify/scripts/bash/check-prerequisites.sh --json --paths-only` from repo root via Bash tool and parsing the JSON output for `FEATURE_DIR`. This is required because the specify step (via `create-new-feature.sh`) creates the feature branch and directory. If re-resolution fails, abort the pipeline with: "Specify step completed but feature directory could not be resolved." The re-resolved `FEATURE_DIR` MUST be used for all subsequent steps.

**Stop check**: apply the pipeline skill's post-step stop check (its Step 5) with the step name `specify`.
