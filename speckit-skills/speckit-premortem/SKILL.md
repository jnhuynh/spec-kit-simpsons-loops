---
name: speckit-premortem
description: Run an interactive three-lens premortem (architecture, UX, support/ops) on a clarified feature spec — discover failure modes, disposition each one with the user, encode mitigations into the spec, and maintain a risk register at <FEATURE_DIR>/failure-modes.md.
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Outline

Goal: Imagine the shipped feature has failed, then work backwards. Systematically enumerate the failure modes the happy-path spec missed — the ticking-timebomb edge cases that surface as architectural incidents, broken user experiences, or support tickets — and force an explicit disposition (mitigate / accept / defer) for each one.

**This is not clarification.** `/speckit-clarify` runs an ambiguity-driven underspecification scan and asks "this is ambiguous — which interpretation?". This premortem runs a systematic multi-lens adversarial enumeration of failure modes against an already-clarified spec and asks "here's a failure scenario — what should the system do, or is this risk acceptable?". Read `## Clarifications` and the existing `### Edge Cases` first; never re-litigate anything already answered or covered there.

Placement: runs after `/speckit-clarify` (Homer) has clarified the spec and before `/speckit-phase`. **This is a human-judgment step**: the pipeline gates on its output (`<FEATURE_DIR>/failure-modes.md` with zero `open` rows) and never self-answers it. Risk disposition belongs to a person.

## Execution Steps

1. Run `.specify/scripts/bash/check-prerequisites.sh --json --paths-only` from repo root **once**. Parse minimal JSON payload fields:
   - `FEATURE_DIR`
   - `FEATURE_SPEC`
   - If JSON parsing fails, abort and instruct user to re-run `/speckit-specify` or verify feature branch environment.

2. Load context:
   - Read the spec file in full.
   - Read `## Clarifications` (if present) — this is answered ground, excluded from questioning. If the section is absent, warn that `/speckit-clarify` has not run (the premortem works best on a clarified spec) but proceed.
   - Read `<FEATURE_DIR>/failure-modes.md` if it exists and build the **exclusion set**: every row whose Status is `mitigated`, `accepted`, `deferred`, or `reappeared`. Decided rows are never re-raised — the register is the cross-session ledger (load it BEFORE scanning, always).
   - **Reappearance check**: for each `mitigated` row, verify its mitigation text is still present in the section named by its Spec Ref. If it is gone, set that row's Status to `reappeared` and report it in the completion report — never silently re-mitigate (a mitigation that vanished means a human edited it out; re-applying it would start an edit war).

3. Perform a three-lens adversarial scan of the spec. For each lens, enumerate candidate failure modes — concrete scenarios, not categories. Skip anything in the exclusion set, anything the spec's `### Edge Cases` or Functional Requirements already handle, and anything below the materiality floor (step 4).

   Architecture (`arch`):
   - Data integrity & corruption (partial writes, invalid states)
   - Migration & rollback sequencing (schema changes, backfill failures)
   - Concurrency: races, double-submits, lost updates
   - Scale & load limits (N grows past the design assumption)
   - Partial failure of multi-step operations (step 3 of 5 fails — what state remains?)
   - External-dependency failure (timeout, outage, contract change)
   - Idempotency & retry behavior (same request twice)

   UX (`ux`):
   - Error states & messaging (what does the user actually see?)
   - Recovery paths after failure (can the user get unstuck without support?)
   - Destructive actions (confirmation, undo, grace periods)
   - Empty & loading states (zero data, slow data)
   - Permission-denied paths (partial access, revoked mid-session)
   - Stale-data & concurrent-edit surprises (two tabs, two users)

   Support/Ops (`ops`):
   - Observability: can we see that it broke before the customer tells us?
   - Diagnosability: can support explain what happened to a specific user?
   - "What ticket does this generate?" — the support burden each failure creates
   - Admin tooling & manual remediation paths (who fixes stuck records, and how?)
   - Rollback & kill switch (can we turn it off without a deploy?)
   - Data correction & export requests (wrong data written — how is it fixed?)

4. Score and prioritize:
   - Assign each candidate a Severity (`critical` / `high` / `medium` / `low`) and Likelihood (`high` / `medium` / `low`).
   - Order the queue by (Severity × Likelihood), highest first, balancing lens coverage — don't spend all questions on one lens if another has unaddressed high scores.
   - **Materiality floor**: candidates that are severity `low` AND likelihood `low` are not registered and not asked. An adversarial scan can always invent one more exotic mode; the floor is what makes the premortem finite.

5. Sequential questioning loop (interactive):
   - Maximum of **5 questions per session**. Present EXACTLY ONE question at a time; never reveal future queued questions.
   - Frame each question as a failure scenario with its scoring:

     `Failure scenario (arch, severity: high, likelihood: medium): <concrete scenario — what happens, to whom, when>. What should the system do?`

   - Analyze the options and present your **recommended disposition prominently** first: `**Recommended:** Option [X] - <reasoning>`.
   - Then render options as a Markdown table: 2–4 concrete mitigation options, plus ALWAYS these two rows:

     | Option | Description |
     |--------|-------------|
     | A | <Mitigation option> |
     | B | <Mitigation option> |
     | Accept | Accept this risk — no spec change, rationale recorded in the register |
     | Defer | Defer the decision to planning / ops runbook — recorded in the register |

   - After the table, add: `You can reply with the option letter (e.g., "A"), accept the recommendation by saying "yes" or "recommended", or provide your own short answer.`
   - After the user answers: "yes"/"recommended" adopts your recommendation; otherwise validate the answer maps to an option or is a workable short mitigation; if ambiguous, disambiguate (same question, does not advance the count). Record the disposition and move on.
   - Stop when: 5 questions asked, OR the queue is exhausted, OR the user signals completion ("done", "stop", "good").
   - Candidates discovered but not asked this session are still registered with Status `open` and Decision `-` — the pipeline gate and the next session pick them up.

6. Integration after EACH accepted disposition:
   - **mitigate** → encode into the spec:
     - Failure behavior (what the system does when it happens) → add a bullet under `### Edge Cases`.
     - New required behavior (validation, guard, recovery mechanism) → add the next unused `- **FR-NNN**:` under `### Functional Requirements`.
     - Measurable operability/reliability target (alerting, latency under failure, retention) → add under `### Non-Functional Requirements` inside `## Requirements` (create that subsection on demand if missing).
     - If the mitigation invalidates existing happy-path text, replace that text — leave no contradictory statement. Never duplicate an existing requirement.
   - **accept** → register row only (Spec Ref `-`). Optionally add one "risk accepted:" line under `### Edge Cases` when readers would otherwise assume handling exists.
   - **defer** → register row only; note in the Failure Mode cell where it is deferred to (plan / ops runbook / later phase).
   - Save the spec after each integration (atomic overwrite). Preserve formatting and heading hierarchy; only allowed new heading: `### Non-Functional Requirements`.

7. Register write rules (`<FEATURE_DIR>/failure-modes.md`):
   - Create the file on first run; **overwrite in full** every session (never append duplicate rows).
   - Format: H1 `# Failure Modes: <feature name>`, then the table with this EXACT header:

     | ID | Lens | Failure Mode | Severity | Likelihood | Decision | Status | Spec Ref |
     |----|------|--------------|----------|------------|----------|--------|----------|

   - Column values — ID: `FM-001`, `FM-002`, … (stable: same lens + equivalent scenario = same row, reuse its ID; else mint the next unused number). Lens: `arch` / `ux` / `ops`. Severity: `critical` / `high` / `medium` / `low`. Likelihood: `high` / `medium` / `low`. Decision: `mitigate` / `accept` / `defer` / `-` (undecided). Status: `open` / `mitigated` / `accepted` / `deferred` / `reappeared`. Spec Ref: the section heading or FR ID the mitigation landed in, else `-`.
   - Status lifecycle: `open` (registered, undecided) → `mitigated` / `accepted` / `deferred` (dispositioned). `reappeared` is terminal and set only by the reappearance check in step 2.
   - Escape literal pipes in cell text as `\|`.

8. Validation (after EACH write plus a final pass):
   - Every `mitigated` row's mitigation is verifiably present in the section named by its Spec Ref (integrated, not just registered).
   - No contradictory or now-invalid happy-path text remains where mitigations were integrated.
   - Register has exactly one row per failure mode; Markdown structure valid.
   - Total questions asked this session ≤ 5.

9. Write the updated spec to `FEATURE_SPEC` and the register to `<FEATURE_DIR>/failure-modes.md`.

10. Commit the session's changes (spec + register) so a later pipeline step cannot swallow them under an unrelated commit message:

    ```bash
    bash .specify/scripts/bash/speckit-commit.sh "premortem spec: disposition N failure modes"
    ```

    (Replace N with the number of failure modes dispositioned this session. Skip the commit if the session changed nothing.)

11. Report completion:
    - Failure modes by lens and by decision (mitigated / accepted / deferred), new-this-session vs previously decided.
    - **Remaining `open` rows** — this is what the pipeline gate checks; say explicitly whether the gate will pass (zero `open`) or another session is needed.
    - Any `reappeared` rows (call these out prominently — a human removed a mitigation).
    - Spec sections touched; path to the register.
    - Suggested next command: another `/speckit-premortem` session while `open` rows remain; `/speckit-phase` (or `/speckit-pipeline --from premortem`) once the register is clean.

## Behavior Rules

- If the spec file is missing, instruct the user to run `/speckit-specify` first (do not create a spec here).
- If no material failure modes are found (all candidates covered or sub-floor), respond: "No material failure modes detected beyond existing spec coverage." — write/refresh the register (possibly with zero rows below the header) so the pipeline gate can pass, and suggest proceeding.
- Never exceed 5 asked questions per session (disambiguation retries do not count as new questions).
- Never re-raise a decided row; never duplicate `/speckit-clarify` ambiguity questions.
- Respect early-termination signals ("stop", "done", "proceed").
- **This skill is interactive only.** If invoked from an autonomous context (no human available to answer), stop and report that the premortem requires a human session — do not self-adopt dispositions.
