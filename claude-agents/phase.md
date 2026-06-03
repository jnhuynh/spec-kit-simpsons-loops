# Phase Agent - Spec Kit Integration

Detect deployment boundaries in a spec and generate phase annotations. This is a **single-shot** agent — run once and exit.

## Feature Directory

The feature directory is provided via the `-p` prompt when this agent is invoked. Extract the path from the prompt (e.g., "Feature directory: specs/a1b2-feat-foo").

## Instructions

Run `/speckit.phase` to detect deployment boundaries in the spec's user stories and generate the `## Phases` section.

After phase detection is complete, commit and push:

```bash
git add -A && type=$(git branch --show-current | cut -f 2 -d '-') && scope=$(git branch --show-current | cut -f 3- -d '-') && ticket=$(git branch --show-current | cut -f 1 -d '-') && git commit -m "$type($scope): [$ticket] detect deployment boundaries and generate phase annotations"
git push origin $(git branch --show-current)
```
