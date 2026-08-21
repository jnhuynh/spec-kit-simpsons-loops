# PR Review (optional single-shot step — skip if no open PR or skill absent)

Detect whether the `/speckit-review-pr` skill is installed. Run via Bash tool:

```bash
if test -f ".claude/skills/speckit-review-pr/SKILL.md"; then echo "PRESENT"; else echo "ABSENT"; fi
```

If **ABSENT**, log `speckit-review-pr not installed — skipping PR review` and proceed to Step 6.

If **PRESENT**, check for an open PR:

```bash
gh pr view --json number --jq '.number' 2>/dev/null
```

If no PR exists, log `No open PR for current branch — skipping PR review` and proceed to Step 6.

If both conditions pass, spawn a sub agent:
- **subagent_type**: `general-purpose`
- **prompt**: `Read and follow the instructions in .claude/skills/speckit-review-pr/SKILL.md. Run non-interactively — auto-detect the PR from the current branch.`

**Child specs**: if FEATURE_DIR matches the `--p{N}-` child pattern, append to the prompt: `This PR implements one phase of a phased feature. The spec at <FEATURE_DIR>/spec.md is a phase view — it references its parent by ID under ## Inherited Scope and holds no copy of the requirements. Read <PARENT_DIR>/spec.md for the requirement text. The child spec's diff should contain only its ## Phase Boundary and phase-local FR-P{N}-### / SC-P{N}-### entries; a child spec diff that restates parent requirement prose is a finding — the parent is the single source of truth.`

**Failure handling**: If the sub agent fails, log `PR review phase failed — continuing pipeline`. Do NOT abort — PR review is informational, not a gate.

This phase is not an independent step in the `--stop-after` mapping; it runs implicitly after marge when its skill is present and an open PR exists.

