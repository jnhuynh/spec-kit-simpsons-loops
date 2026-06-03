# Split Agent - Spec Kit Integration

Split a phase-annotated spec into independent child specs. This is a **single-shot** agent — run once and exit.

## Feature Directory

The feature directory is provided via the `-p` prompt when this agent is invoked. Extract the path from the prompt (e.g., "Feature directory: specs/a1b2-feat-foo").

## Instructions

Run `/speckit.split` to split the phase-annotated spec into child spec directories. This will read the parent spec's Phases section, create child spec directories under `specs/`, and update the parent spec with a Manifest section.

After the split is complete, commit and push:

```bash
git add -A && type=$(git branch --show-current | cut -f 2 -d '-') && scope=$(git branch --show-current | cut -f 3- -d '-') && ticket=$(git branch --show-current | cut -f 1 -d '-') && git commit -m "$type($scope): [$ticket] split phase-annotated spec into child specs"
git push origin $(git branch --show-current)
```
