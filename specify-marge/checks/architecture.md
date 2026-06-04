# architecture

Baseline pack. Design-level concerns that only become visible when you look at the diff as a whole.

---

## A1. Scope creep

Rule: A PR / feature branch should do one logical thing. Flag when the diff touches concerns obviously unrelated to the feature described in the branch name or `spec.md`.

**Severity:** MEDIUM.

Signal: branch name or spec implies a narrow change but the diff modifies 3+ unrelated modules / top-level directories.

Tag `NEEDS_HUMAN` because the judgment of "related" depends on the repo's module boundaries.

---

## A2. Duplicated helpers

Rule: A new utility / helper / constant added by the diff should not duplicate one that already exists in the repo. Before flagging, `Grep` or `Glob` for similar names and confirm semantic overlap.

**Severity:** MEDIUM.

Fix suggestion must cite the existing helper's path and name.

---

## A3. Dead code

Rule: New functions, imports, exports, or types that are never referenced after the diff lands.

**Severity:** LOW.

Signal: added symbol with zero call-sites in the diff or the existing codebase. Most linters catch unused imports; focus on unused functions / types / constants.

---

## A4. Abstraction for one caller

Rule: A new abstraction (class, interface, factory) introduced with a single call site is usually premature. Prefer inlining until there are 2+ callers.

**Severity:** LOW.

---

## A5. Layer violation

Rule: Code in a layer (controller / service / model / view) that reaches across layer boundaries it shouldn't. E.g., a view that issues DB queries, a model that calls an HTTP client, a controller that contains business rules.

**Severity:** MEDIUM.

Tag `NEEDS_HUMAN` since layering conventions vary per project — the constitution or CLAUDE.md defines them.

---

## A6. Comments that lie

Rule: A comment describing behaviour that the adjacent code does NOT do. Usually occurs when code is edited but the comment is left.

**Severity:** LOW.

Signal: look for comments above / beside modified lines that describe a different operation than what the new code performs.

---

## A7. Copy-pasted logic

Rule: Three or more near-identical blocks added in the diff — often a sign that a shared helper should be extracted, OR a sign of a missing loop.

**Severity:** LOW.

---

## A8. God function / god file

Rule: A single new function exceeding ~80 lines or a file exceeding ~500 lines is a smell. Usually indicates the change should have been split into smaller pieces.

**Severity:** LOW.

---

## A9. Broken invariant expression

Rule: If the spec or constitution declares an invariant (e.g. "every order has exactly one user"), check that new code doesn't violate it. Requires reading `spec.md` / `plan.md` / `.specify/memory/constitution.md` for context.

**Severity:** HIGH.

Tag `NEEDS_HUMAN` unless the invariant is explicit and the violation is unambiguous.

---

## A10. Missing error handling at boundaries

Rule: New code that crosses a trust boundary (HTTP call, DB transaction, external process) should have explicit error handling — not just rely on "it'll throw up the stack".

**Severity:** MEDIUM.

---

## Confidence guidance

- 90–100: A2 duplicated helper with a named existing helper to cite.
- 80–90: A3 unreferenced new symbol; A10 obvious missing boundary handling.
- 70–80: A1 / A5 / A9 judgment calls — tag `NEEDS_HUMAN` when the decision isn't mechanical.
- <70: drop unless `--strict`.

## NEEDS_HUMAN tagging

Architecture findings are the most judgment-heavy pack. Tag `NEEDS_HUMAN` generously — Marge should fix only unambiguous mechanical issues (duplicated helpers, dead code, comment lies). Design decisions belong to humans.
