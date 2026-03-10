# Quickstart: Fix Subagent Delegation and Quality Gate Consolidation

## Overview

This feature makes five changes:
1. Deletes bash script fallbacks (`pipeline.sh`, `homer-loop.sh`, `lisa-loop.sh`, `ralph-loop.sh`) — command files are the sole invocation path (FR-005)
2. Reorganizes source directories: `agents/` → `claude-agents/`, root-level `speckit.*.md` → `speckit-commands/` (FR-006)
3. Consolidates quality gates to `.specify/quality-gates.sh` as sole source, with validation in ralph-related command files only (FR-004, FR-007, FR-010)
4. Standardizes iteration defaults to 30 (homer/lisa) and stuck detection to 2 in command files (FR-011, FR-013)
5. Updates README with architecture diagrams, corrected configuration tables, and removed bash script docs (FR-014–FR-018)

No structural changes to subagent spawning are needed — command files already describe Agent tool spawning correctly.

## Implementation Order

### Phase 1: Delete Bash Script Fallbacks (FR-005)

**Delete these files**:
- `pipeline.sh` (root)
- `homer-loop.sh` (root)
- `lisa-loop.sh` (root)
- `ralph-loop.sh` (root)

**Update `setup.sh`** to:
- Stop installing bash scripts to `.specify/scripts/bash/`
- Remove previously-installed copies from `.specify/scripts/bash/` when run on existing installations
- Remove corresponding permissions entries from `.claude/settings.local.json`

### Phase 2: Reorganize Source Directories (FR-006)

1. Rename `agents/` → `claude-agents/`
2. Create `speckit-commands/` directory
3. Move root-level `speckit.*.md` files into `speckit-commands/`
4. Update `setup.sh` to install from `claude-agents/` → `.claude/agents/` and `speckit-commands/` → `.claude/commands/`

### Phase 3: Quality Gate Text and Defaults in Command Files

**Files**: `speckit-commands/speckit.pipeline.md`, `speckit-commands/speckit.homer.clarify.md`, `speckit-commands/speckit.lisa.analyze.md`, `speckit-commands/speckit.ralph.implement.md`

1. **`speckit.pipeline.md`**: Update Ralph section to remove CLI/env override text, add quality gate file validation instruction, update iteration defaults to 30, stuck detection to 2
2. **`speckit.homer.clarify.md`**: Update default iterations to 30, stuck detection to 2, use `--json --paths-only` for prereqs
3. **`speckit.lisa.analyze.md`**: Update default iterations to 30, stuck detection to 2
4. **`speckit.ralph.implement.md`**: Add quality gate file validation step, update stuck detection to 2

### Phase 4: README Updates

**File**: `README.md`

1. Remove all references to `--quality-gates` CLI flag, `QUALITY_GATES` environment variable, and bash script invocation
2. Update iteration defaults: homer/lisa → 30, ralph → `incomplete_tasks + 10`
3. Update stuck detection: "two consecutive iterations" (not three)
4. Add new "Architecture" section with two mermaid diagrams
5. Consolidate "Quality gates" section to document file-only source

## Key Patterns

### Quality gate validation in command files (ralph only)

```markdown
Validate quality gates file exists and contains executable content:
bash: test -f .specify/quality-gates.sh && grep -v '^\s*#' .specify/quality-gates.sh | grep -v '^\s*$' | head -1
If the file is missing or the check returns empty, abort with: "Quality gates file missing or empty. Create/edit .specify/quality-gates.sh with your project's quality gate commands."
```

## Verification Checklist

### Bash Script Deletion (FR-005)

- [ ] `pipeline.sh`, `homer-loop.sh`, `lisa-loop.sh`, `ralph-loop.sh` do not exist at root level
- [ ] `.specify/scripts/bash/` does not contain loop scripts after `setup.sh` runs
- [ ] `.claude/settings.local.json` does not contain permissions for deleted bash scripts after `setup.sh` runs

### Source Directory Reorganization (FR-006)

- [ ] `claude-agents/` directory exists with agent source files (renamed from `agents/`)
- [ ] `speckit-commands/` directory exists with command source files (moved from root level)
- [ ] Old `agents/` directory does not exist
- [ ] No root-level `speckit.*.md` files exist outside `speckit-commands/`
- [ ] `setup.sh` installs from `claude-agents/` → `.claude/agents/` and `speckit-commands/` → `.claude/commands/`

### Quality Gates (FR-004, FR-007, FR-010)

- [ ] `speckit-commands/speckit.pipeline.md` Ralph section mentions only `.specify/quality-gates.sh`
- [ ] `speckit-commands/speckit.ralph.implement.md` includes file validation step
- [ ] Homer and lisa command files do NOT reference quality gates

### Iteration Defaults and Stuck Detection (FR-011, FR-013)

- [ ] Homer/lisa command files default to 30 iterations
- [ ] Ralph command file uses `incomplete_tasks + 10`
- [ ] All stuck detection thresholds are 2

### README (FR-014–FR-018)

- [ ] README has no `--quality-gates`, `QUALITY_GATES`, or bash script invocation references
- [ ] README shows 30 for homer/lisa defaults
- [ ] README shows "two consecutive iterations" for stuck detection
- [ ] README has "Architecture" section with two mermaid diagrams
