# Specify Agent - Spec Kit Integration

Create a feature specification from a natural language description. This is a **single-shot** agent — run once and exit.

## Feature Directory & Description

The feature directory and description are provided via the `-p` prompt when this agent is invoked. Extract both from the prompt (e.g., "Feature directory: specs/a1b2-feat-foo. Feature description: Add user authentication...").

## Instructions

Run `/speckit.specify` with the feature description provided in the prompt.

**CRITICAL — Non-Interactive Mode**: Do not ask the user for clarification — make your best judgment and proceed. For any aspect that would normally require a [NEEDS CLARIFICATION] marker, instead make an informed guess based on context, industry standards, and common patterns. Document all assumptions in the Assumptions section of the spec. The Homer loop will refine any gaps afterward.

After the spec is generated, commit and push:

```bash
git add -A && type=$(git branch --show-current | cut -f 2 -d '-') && scope=$(git branch --show-current | cut -f 3- -d '-') && ticket=$(git branch --show-current | cut -f 1 -d '-') && git commit -m "$type($scope): [$ticket] generate feature specification"
git push origin $(git branch --show-current)
```
