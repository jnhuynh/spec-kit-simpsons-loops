# Security Review (optional single-shot step — skip if skill absent)

Detect whether the `/security-review` skill is installed. Run via Bash tool:

```bash
if test -d "$HOME/.claude/skills/security-review" || test -f "$HOME/.claude/commands/security-review.md" || test -f ".claude/commands/security-review.md"; then echo "PRESENT"; else echo "ABSENT"; fi
```

If **ABSENT**, log `security-review skill not installed — skipping pre-marge security pass` and proceed to marge. Do NOT spawn a sub agent.

If **PRESENT**, spawn a sub agent:

- **subagent_type**: `general-purpose`
- **prompt**: `Invoke the /security-review skill via the Skill tool. It will perform a security review of the pending changes on the current branch. Apply any straightforward fixes it recommends. When finished, stage and commit any resulting changes with: git add -A && type=$(git branch --show-current | cut -f 2 -d '-') && scope=$(git branch --show-current | cut -f 3- -d '-') && ticket=$(git branch --show-current | cut -f 1 -d '-') && git commit -m "chore($scope): [$ticket] pre-marge security review pass". If no changes were needed, exit without committing. Report "no changes" or a one-line summary of what was fixed; any residual findings will be picked up by marge.`

**Failure handling**: If the sub agent fails (crash, timeout, or error), log `security-review phase failed — continuing pipeline` and proceed to marge. Do NOT abort — security-review is optional polish.

This phase is not an independent step in the `--stop-after` mapping; it runs implicitly between ralph and marge when its skill is present.

