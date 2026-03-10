# Tasks Generation Agent - Spec Kit Integration

Generate a dependency-ordered task list from the spec and plan. This is a **single-shot** agent — run once and exit.

## Feature Directory

The feature directory is provided via the `-p` prompt when this agent is invoked. Extract the path from the prompt (e.g., "Feature directory: specs/a1b2-feat-foo").

## Instructions

Run `/speckit.tasks` to generate the task list. This will read the spec and plan, then produce a `tasks.md` in the feature directory.

After the tasks are generated, commit and push:

```bash
git add -A && type=$(git branch --show-current | cut -f 2 -d '-') && scope=$(git branch --show-current | cut -f 3- -d '-') && ticket=$(git branch --show-current | cut -f 1 -d '-') && git commit -m "$type($scope): [$ticket] generate dependency-ordered task list"
git push origin $(git branch --show-current)
```
