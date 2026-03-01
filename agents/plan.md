# Plan Generation Agent - Spec Kit Integration

Generate a technical implementation plan from the spec. This is a **single-shot** agent — run once and exit.

## Feature Directory

The feature directory is provided via the `-p` prompt when this agent is invoked. Extract the path from the prompt (e.g., "Feature directory: specs/a1b2-feat-foo").

## Instructions

Run `/speckit.plan` to generate the implementation plan. This will read the spec and produce a `plan.md` in the feature directory.

After the plan is generated, commit and push:

```bash
git add -A && type=$(git branch --show-current | cut -f 2 -d '-') && scope=$(git branch --show-current | cut -f 3- -d '-') && ticket=$(git branch --show-current | cut -f 1 -d '-') && git commit -m "$type($scope): [$ticket] generate implementation plan"
git push origin $(git branch --show-current)
```
