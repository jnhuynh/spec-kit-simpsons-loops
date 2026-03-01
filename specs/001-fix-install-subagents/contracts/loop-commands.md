# Contract: Loop Command Files

**Type**: Claude Code slash commands (Markdown files parsed by Claude Code)
**Interface**: Claude Code Agent tool with `subagent_type: general-purpose`

## Common Contract (applies to all 4 loop commands)

### Sub Agent Spawning

- **Mechanism**: Agent tool (NOT "Task tool")
- **`subagent_type`**: `general-purpose`
- **Context isolation**: Each sub agent gets a fresh context window
- **Concurrency**: Strictly sequential -- one sub agent at a time

### Autonomous Execution

- No permission prompts
- No confirmation dialogs
- No interactive pauses
- Back-to-back execution until completion condition

### Failure Handling

- On sub agent failure: abort immediately with error context (iteration number, agent type, error message)
- No automatic retry (distinct from bash scripts which allow retry)

### Stuck Detection

- Track consecutive identical outputs
- Abort after 3 identical consecutive outputs
- Suggest manual review on abort

### Reporting

On loop completion, report:
- Total iterations run
- Completion status (success, max iterations reached, stuck, or failure)
- Suggestion to rerun if not fully resolved

## Per-Command Contracts

### speckit.homer.clarify

| Parameter | Value |
|-----------|-------|
| Max iterations | 10 |
| Required artifacts | `spec.md` |
| Completion signal | `<promise>ALL_FINDINGS_RESOLVED</promise>` |
| Agent file | `.claude/agents/homer.md` |
| Delegates to | `/speckit.clarify` |

### speckit.lisa.analyze

| Parameter | Value |
|-----------|-------|
| Max iterations | 10 |
| Required artifacts | `spec.md`, `plan.md`, `tasks.md` |
| Completion signal | `<promise>ALL_FINDINGS_RESOLVED</promise>` |
| Agent file | `.claude/agents/lisa.md` |
| Delegates to | `/speckit.analyze` |

### speckit.ralph.implement

| Parameter | Value |
|-----------|-------|
| Max iterations | `incomplete_tasks + 10` |
| Required artifacts | `tasks.md` |
| Completion signal | `<promise>ALL_TASKS_COMPLETE</promise>` |
| Agent file | `.claude/agents/ralph.md` |
| Delegates to | `/speckit.implement` |
| Additional check | Verify `tasks.md` directly (no `- [ ]` remaining) |

### speckit.pipeline

| Parameter | Value |
|-----------|-------|
| Steps | homer -> plan -> tasks -> lisa -> ralph |
| Auto-detection | Inspects existing artifacts to determine start step |
| `--from` flag | Override start step |
| Per-step limits | Homer: 10, Lisa: 10, Ralph: incomplete_tasks + 10 |
| Single-shot steps | plan, tasks (skip if artifact exists) |
