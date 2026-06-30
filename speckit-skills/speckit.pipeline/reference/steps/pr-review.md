# PR Review (optional single-shot step — skip if no open PR or skill absent)

Detect whether the `/speckit.review.pr` skill is installed. Run via Bash tool:

```bash
if test -f ".claude/skills/speckit.review.pr/SKILL.md" || test -f ".claude/commands/speckit.review.pr.md"; then echo "PRESENT"; else echo "ABSENT"; fi
```

If **ABSENT**, log `speckit.review.pr not installed — skipping PR review` and proceed to Step 6.

If **PRESENT**, check for an open PR:

```bash
gh pr view --json number --jq '.number' 2>/dev/null
```

If no PR exists, log `No open PR for current branch — skipping PR review` and proceed to Step 6.

If both conditions pass, spawn a sub agent:
- **subagent_type**: `general-purpose`
- **prompt**: `Read and follow the instructions in .claude/skills/speckit.review.pr/SKILL.md (or .claude/commands/speckit.review.pr.md if that file does not exist). Run non-interactively — auto-detect the PR from the current branch.`

**Failure handling**: If the sub agent fails, log `PR review phase failed — continuing pipeline`. Do NOT abort — PR review is informational, not a gate.

This phase is not an independent step in the `--stop-after` mapping; it runs implicitly after marge when its skill is present and an open PR exists.

