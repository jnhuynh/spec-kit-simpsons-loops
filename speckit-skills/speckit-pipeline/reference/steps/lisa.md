# Lisa (loop step)

Run the Lisa loop exactly as its standalone skill defines it: read and follow `.claude/skills/speckit-lisa-analyze/SKILL.md`, passing `<FEATURE_DIR>` through as the skill's spec-dir argument. The skill's own LOOP_CONFIG (including MAX_ITERATIONS) applies.

**Pipeline deltas**:

- Skip the loop orchestrator's Pre-Flight and Agent File checks (already done in pipeline pre-flight). Start from the orchestrator's Step 1 (Parse Arguments) using the already-resolved `FEATURE_DIR`.
- **Child specs**: if FEATURE_DIR matches the `--p{N}-` child pattern, pass this through to the analysis by appending it to the loop's `EXTRA_PROMPT_SUFFIX` (overriding the skill's `(none)`) so it reaches every iteration sub-agent: `This spec is a phase view — it references its parent by ID under ## Inherited Scope and deliberately holds no copy of the user stories, requirements, key entities, or success criteria. Read <PARENT_DIR>/spec.md and resolve those IDs before analyzing coverage. A requirement whose text lives only in the parent is NOT an underspecification finding, and an inherited ID with no restated prose is NOT a gap — the absence of duplication is the design. Do flag: an ID in Inherited Scope with no covering task, a phase-local FR-P{N}-### with no covering task, an ID that no longer exists in the parent, and an ID claimed by two phases (ownership lives in the children — scan the sibling `--p{N}-` directories' Inherited Scope tables for this check).`

**Stop check**: apply the pipeline skill's post-step stop check (its Step 5) with the step name `lisa`.
