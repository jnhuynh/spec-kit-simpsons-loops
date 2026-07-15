# Homer Clarification Mode - Spec Kit Integration

Clarify spec artifacts by resolving ambiguities, unanswered questions, and unclear requirements. Run **one full clarification session** per iteration (up to 5 questions, self-answered), then exit. Each iteration runs with FRESH CONTEXT. Loop until a fresh scan finds nothing left worth clarifying.

> **Note:** One clarify session per iteration. `/speckit-clarify` caps each session at 5 questions, so an iteration resolves up to 5 ambiguities.

## Feature Directory

The feature directory is provided in the invocation prompt (each iteration is spawned via the Agent tool). Extract the path from the prompt (e.g., "Feature directory: specs/a1b2-feat-foo").

## Phase 0: Clarify

Run `/speckit-clarify` with this argument:

> Autonomous mode: no human is available. Run your ambiguity & coverage scan and queue questions as usual (up to your 5-per-session cap). For each question, adopt your own Recommended/Suggested answer immediately instead of waiting for user input, and integrate it into the spec per your integration rules (recording it under `## Clarifications`). Never re-ask anything already answered under `## Clarifications`; if a category remains Partial after a recorded answer, mark it Deferred rather than re-asking. In your coverage summary, distinguish WHY a category is Deferred: "Deferred (planning)" for items better suited to the planning phase or already answered, vs "Deferred (quota)" for categories skipped only because the 5-question session cap was reached.

One iteration therefore resolves up to 5 ambiguities, prioritized by the skill's own (Impact × Uncertainty) heuristic. The spec's `## Clarifications` section is the ledger — it prevents re-asking across iterations.

## Phase 1: Assess

1. Review the coverage summary from the `/speckit-clarify` run
2. Categories deferred ONLY because the session quota was reached ("Deferred (quota)") are NOT terminal — they are unresolved work for the next iteration. Count them as Outstanding.
3. If the skill reported no critical ambiguities worth formal clarification, or every taxonomy category is Clear, Resolved, or Deferred (planning) — with no Outstanding and no quota-deferred categories — output the following promise tag and exit. Deferred (planning) items are judgment calls left for humans or the planning phase; list them in your final report so they surface. If this session answered questions, complete Phases 2-3 (validate + commit) FIRST, then emit the tag; exiting without committing would strand the integrated answers:

<promise>ALL_FINDINGS_RESOLVED</promise>

4. Otherwise, confirm the session's answers were integrated into the spec. Report the count of Outstanding categories (including quota-deferred ones) as the work-remaining count and exit — the next iteration's session picks them up.

## Phase 2: Validate

1. Re-read the modified spec
2. Verify each recorded answer was integrated into the relevant section (not just appended to `## Clarifications`)
3. Check no contradictory or vague text remains where answers were integrated

## Phase 3: Commit & Exit

1. Commit all changes:
   ```bash
   bash .specify/scripts/bash/speckit-commit.sh "clarify spec: answer N questions"
   ```
   (Replace N with the number of questions answered this iteration.)
2. Exit immediately — you will restart with fresh context for the next session

## Guardrails

| #   | Rule                                                                                             |
| --- | ------------------------------------------------------------------------------------------------ |
| 999 | **One clarify session per iteration** — One full session (max 5 questions, all self-answered), then exit |
| 998 | **Constitution is authoritative** — Never modify constitution.md; adjust spec/plan/tasks instead |
| 997 | **Spec artifacts only** — Only modify files within the feature directory                         |
| 996 | **Validate after integration** — Re-read the spec and verify answers landed before committing    |
| 995 | **Highest impact first** — Rely on the skill's own (Impact × Uncertainty) prioritization         |
| 992 | **Never re-ask an answered question** — `## Clarifications` is the ledger; a category still Partial after a recorded answer is marked Deferred, not re-asked |

## File Paths

- Spec: `<FEATURE_DIR>/spec.md`
- Constitution: `.specify/memory/constitution.md`
