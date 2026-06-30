# Simplify (optional single-shot step — skip if skill absent)

Detect whether the `/simplify` skill is installed. Run via Bash tool:

```bash
if test -d "$HOME/.claude/skills/simplify" || test -f "$HOME/.claude/commands/simplify.md" || test -f ".claude/commands/simplify.md"; then echo "PRESENT"; else echo "ABSENT"; fi
```

If **ABSENT**, log `simplify skill not installed — skipping post-ralph simplify pass` and proceed to the security-review phase. Do NOT spawn a sub agent.

If **PRESENT**, spawn a sub agent:

- **subagent_type**: `general-purpose`
- **prompt**: `Invoke the /simplify skill via the Skill tool. It will review the current diff for reuse, quality, and efficiency issues and apply fixes. When it finishes, stage and commit any resulting changes with: git add -A && type=$(git branch --show-current | cut -f 2 -d '-') && scope=$(git branch --show-current | cut -f 3- -d '-') && ticket=$(git branch --show-current | cut -f 1 -d '-') && git commit -m "chore($scope): [$ticket] post-ralph simplify pass". If the skill made no changes, exit without committing. Report "no changes" or a one-line summary of what was fixed.`

**Failure handling**: If the sub agent fails (crash, timeout, or error), log `simplify phase failed — continuing pipeline` and proceed to security-review. Do NOT abort — simplify is optional polish.

This phase is not an independent step in the `--stop-after` mapping; it runs implicitly between ralph and marge when its skill is present.

