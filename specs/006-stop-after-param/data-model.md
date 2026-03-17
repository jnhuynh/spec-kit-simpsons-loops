# Data Model: Stop-After Pipeline Parameter

## Entities

### Pipeline Step

| Attribute | Type | Description |
|---|---|---|
| Name | Enum | One of: `specify`, `homer`, `plan`, `tasks`, `lisa`, `ralph` |
| Index | Integer (0-5) | Position in the fixed pipeline sequence |
| Type | Enum | `single-shot` (specify, plan, tasks) or `loop` (homer, lisa, ralph) |
| Status | Enum | `executed`, `skipped`, `stopped-by-param` |

**Validation rules**:
- Step names are case-sensitive and must exactly match the six valid values
- Step ordering is immutable: specify(0) -> homer(1) -> plan(2) -> tasks(3) -> lisa(4) -> ralph(5)
- Status is assigned after pipeline execution completes (or stops early)

**State transitions**:
- Before execution: no status assigned
- During execution: step is `executed` or `skipped` (artifact exists)
- After `--stop-after` triggers: all remaining steps become `stopped-by-param`

### Pipeline Arguments

| Attribute | Type | Description |
|---|---|---|
| `--from` | Optional step name | Starting step override (existing) |
| `--stop-after` | Optional step name | Last step to execute before halting (new) |
| `--description` | Optional string | Feature description for specify step (existing) |
| `spec-dir` | Optional path | Feature directory path (existing) |

**Validation rules**:
- `--stop-after` must be one of the six valid step names (FR-006)
- `--stop-after` must not precede the starting step in sequence (FR-005)
- `--stop-after` and `--from` are independently optional
- When both are provided, they define an inclusive range of steps
- When `--stop-after` equals `--from` (or the auto-detected start), exactly one step executes (FR-004)
- `--stop-after` without a value is an error (edge case from spec)

### Execution Plan

| Attribute | Type | Description |
|---|---|---|
| Start step | Step name | First step to execute (from `--from` or auto-detected) |
| Stop step | Step name or empty | Last step to execute (from `--stop-after` or empty for full run) |
| Planned steps | List of step names | Steps between start and stop (inclusive) |

**Validation rules**:
- Planned steps list is computed before any step executes
- Announced to the user before execution begins (FR-011)

### Completion Report

| Attribute | Type | Description |
|---|---|---|
| Step statuses | Map of step name to status | All six steps with their status |
| Last executed step | Step name | The final step that ran (may differ from stop step if a step was skipped) |
| Was stopped early | Boolean | True when `--stop-after` caused termination before ralph |
| Completion status | Enum | `success`, `max iterations reached`, `stuck`, `failure` (existing) |

**Validation rules**:
- All six steps must be listed regardless of whether they were in the execution range
- Steps before the start step are listed as `skipped`
- Steps after the stop step are listed as `stopped-by-param`

## Relationships

```text
Pipeline Arguments
  ├── --from ──────→ determines start step (index)
  ├── --stop-after ─→ determines stop step (index)
  └── validation ───→ stop_index >= start_index

Execution Plan
  ├── computed from → Pipeline Arguments (start + stop)
  └── announced ───→ before any step executes (FR-011)

Pipeline Step Execution
  ├── for each step in [start..stop]:
  │     ├── check artifact → skipped (if exists and applicable)
  │     └── spawn sub-agent → executed
  ├── after stop step completes:
  │     └── output stop message (FR-010)
  └── remaining steps → stopped-by-param

Completion Report
  ├── aggregates → all Pipeline Step statuses
  └── includes → stop message context
```

## Error Conditions

| Condition | Error Message | Steps Executed |
|---|---|---|
| Invalid step name for `--stop-after` | "Invalid --stop-after value '<value>'. Valid steps: specify, homer, plan, tasks, lisa, ralph." | None |
| Stop step precedes start step | "Invalid range: --stop-after '<stop>' comes before starting step '<start>' in the pipeline sequence (specify -> homer -> plan -> tasks -> lisa -> ralph)." | None |
| `--stop-after` with no value | "Error: --stop-after requires a step name. Valid steps: specify, homer, plan, tasks, lisa, ralph." | None |
