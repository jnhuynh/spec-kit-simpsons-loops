# Code Review Report — 008-feat-multi-phase-deploys

Marge ran the baseline and project-specific review packs against the integrated feature branch. The report below reflects the post-remediation finding set: the just-fixed finding transitions to `resolved`; remaining mechanical findings remain `open` for subsequent iterations.

This is a single-phase feature for the spec-kit repository itself (`plan.md` has no `## Deploy Phases` section); every finding's `Phase` column is the literal `-` per FR-012a.

| ID | Severity | Phase | Status | Check Pack | Summary |
| --- | -------- | ----- | -------- | ---------------- | ------- |
| F001 | low | - | resolved | architecture.md | M8 entry in `.specify/marge/checks/migrations.md` had a duplicated `**Severity:** HIGH.` marker and two consecutive `Signal:` paragraphs (A6 / A7); consolidated into one severity marker and one merged signal description. |
| F002 | low | - | resolved | architecture.md | `CLAUDE.md` Active Technologies entry for 008-feat-multi-phase-deploys listed `Claude CLI (\`claude\` command)` twice (A7 copy-paste duplication); removed the trailing duplicate so the entry mirrors the structure of the other Active Technologies rows. |
| F003 | high | - | resolved | architecture.md | `.specify/templates/plan-template.md` rendered a literal `## Deploy Phases` heading plus example Phase 1-4 content outside HTML comments, so `setup-plan.sh`'s verbatim copy made every new plan.md trigger the FR-002 multi-phase detector — silently breaking FR-002 ("Absence MUST mean single-phase") and FR-022 ("single-phase keeps working unchanged"); wrapped the entire Deploy Phases example block inside a single HTML comment so a template copy is single-phase by default. |
