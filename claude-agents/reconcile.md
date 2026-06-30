# Reconcile Agent - Spec Kit Integration

Reconcile a child spec with what earlier sibling phases actually built. This is a **single-shot** agent — run once and exit.

## Feature Directory

The feature directory (a child spec directory) is provided via the `-p` prompt when this agent is invoked. Extract the path from the prompt (e.g., "Feature directory: specs/c31c-feat-billing--p2-integration").

## Instructions

1. Resolve the parent directory by stripping the `--p{N}-{slug}` suffix from the child directory name. For example, `specs/c31c-feat-billing--p2-integration` -> `specs/c31c-feat-billing`.

2. Run `/speckit-split` targeting the parent directory. This reconciles all child specs with what earlier phases actually built, updating child spec content to reflect reality from earlier phases.

3. After reconciliation is complete, commit and push:

```bash
git add -A && type=$(git branch --show-current | cut -f 2 -d '-') && scope=$(git branch --show-current | cut -f 3- -d '-') && ticket=$(git branch --show-current | cut -f 1 -d '-') && git commit -m "$type($scope): [$ticket] reconcile child spec with earlier phases"
git push origin $(git branch --show-current)
```
