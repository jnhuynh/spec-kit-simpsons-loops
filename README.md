# Simpsons Loops for Speckit + Claude Code

Automated iteration loops and pipeline orchestration for [Speckit](https://github.com/speckit)-powered projects using Claude Code CLI.

- **Pipeline** — End-to-end orchestrator that runs the full workflow: homer → plan → tasks → lisa → ralph. Auto-detects the feature directory from the current git branch, supports resuming from any step, and manages prompt generation internally.
- **Ralph Loop** — Task-by-task implementation. Picks up the next incomplete task from `tasks.md`, implements it, validates, commits, and exits. Repeats with fresh context until all tasks are done.
- **Lisa Loop** — Iterative cross-artifact analysis. Runs `/speckit.analyze` on `spec.md`, `plan.md`, and `tasks.md`, fixes the single highest-severity finding, commits, and exits. Repeats until zero findings remain.
- **Homer Loop** — Iterative spec clarification. Runs `/speckit.clarify` on `spec.md`, resolves ambiguities and unanswered questions at the highest severity level, commits, and exits. Repeats until zero findings remain.

The loops invoke `claude -p` with a fresh context per iteration, which avoids context window limits and keeps each run focused. The pipeline orchestrates the loops in sequence with smart auto-detection of where to start based on existing artifacts.

## Important: API key vs. Claude subscription

The loops invoke `claude -p`, which will use your `ANTHROPIC_API_KEY` environment variable if one is set. If you want the loops to run against your **Claude subscription** (Pro/Max) instead, unset that variable before running them:

```bash
unset ANTHROPIC_API_KEY
```

Otherwise every iteration will consume API credits from the key.

## Prerequisites

- A project already set up with Speckit (`.specify/` directory exists)
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) installed
- Existing Speckit commands in `.claude/commands/` (at minimum: `speckit.implement.md`, `speckit.analyze.md`, `speckit.clarify.md`, `speckit.plan.md`, `speckit.tasks.md`)

## Setup

### Option A: Automated (recommended)

From the root of your target project, run the setup script:

```bash
bash <path-to-simpsons-loops>/setup.sh
```

This copies all files (loop scripts, pipeline script, prompt templates, and Claude Code commands), makes scripts executable, appends `.gitignore` entries, and updates `.claude/settings.local.json` permissions. Requires `jq` for the permissions step (you'll get manual instructions if it's missing).

### Option B: Manual

<details>
<summary>Click to expand manual steps</summary>

#### 1. Copy files into your project

From the root of your project, copy each file to its destination:

```bash
# Shell scripts → .specify/scripts/bash/
cp <path-to-simpsons-loops>/ralph-loop.sh   .specify/scripts/bash/ralph-loop.sh
cp <path-to-simpsons-loops>/lisa-loop.sh     .specify/scripts/bash/lisa-loop.sh
cp <path-to-simpsons-loops>/homer-loop.sh    .specify/scripts/bash/homer-loop.sh
cp <path-to-simpsons-loops>/pipeline.sh      .specify/scripts/bash/pipeline.sh

# Prompt templates → .specify/templates/
cp <path-to-simpsons-loops>/ralph-prompt.template.md   .specify/templates/ralph-prompt.template.md
cp <path-to-simpsons-loops>/lisa-prompt.template.md    .specify/templates/lisa-prompt.template.md
cp <path-to-simpsons-loops>/homer-prompt.template.md   .specify/templates/homer-prompt.template.md

# Claude Code commands → .claude/commands/
cp <path-to-simpsons-loops>/speckit.ralph.implement.md   .claude/commands/speckit.ralph.implement.md
cp <path-to-simpsons-loops>/speckit.lisa.analyze.md      .claude/commands/speckit.lisa.analyze.md
cp <path-to-simpsons-loops>/speckit.homer.clarify.md     .claude/commands/speckit.homer.clarify.md
cp <path-to-simpsons-loops>/speckit.pipeline.md          .claude/commands/speckit.pipeline.md
```

#### 2. Make scripts executable

```bash
chmod +x .specify/scripts/bash/ralph-loop.sh
chmod +x .specify/scripts/bash/lisa-loop.sh
chmod +x .specify/scripts/bash/homer-loop.sh
chmod +x .specify/scripts/bash/pipeline.sh
```

#### 3. Update `.gitignore`

Append the entries from the included `gitignore` file to your project's `.gitignore`:

```gitignore
# Simpsons loops - generated at runtime

*.ralph-prompt.md*
*.ralph-prev-output*    # Stuck detection state
*.ralph-state*          # Resumption state

# Lisa loop temp files
*.lisa-prompt.md*
*.lisa-prev-output*
*.lisa-state*

# Homer loop temp files
*.homer-prompt.md*
*.homer-prev-output*
*.homer-state*

.specify/logs/          # All log files
```

#### 4. Allow loop scripts in Claude Code permissions

Add the loop scripts to your `.claude/settings.local.json` allow list so Claude Code can run them without prompting:

```json
{
  "permissions": {
    "allow": [
      "Bash(.specify/scripts/bash/ralph-loop.sh*)",
      "Bash(.specify/scripts/bash/lisa-loop.sh*)",
      "Bash(.specify/scripts/bash/homer-loop.sh*)",
      "Bash(.specify/scripts/bash/pipeline.sh*)"
    ]
  }
}
```

</details>

## File mapping reference

| Source file                  | Destination                                     | Purpose                        |
| ---------------------------- | ----------------------------------------------- | ------------------------------ |
| `pipeline.sh`                | `.specify/scripts/bash/pipeline.sh`             | End-to-end pipeline orchestrator |
| `ralph-loop.sh`              | `.specify/scripts/bash/ralph-loop.sh`           | Bash orchestrator for Ralph    |
| `lisa-loop.sh`               | `.specify/scripts/bash/lisa-loop.sh`            | Bash orchestrator for Lisa     |
| `homer-loop.sh`              | `.specify/scripts/bash/homer-loop.sh`           | Bash orchestrator for Homer    |
| `ralph-prompt.template.md`   | `.specify/templates/ralph-prompt.template.md`   | Prompt template for Ralph      |
| `lisa-prompt.template.md`    | `.specify/templates/lisa-prompt.template.md`    | Prompt template for Lisa       |
| `homer-prompt.template.md`   | `.specify/templates/homer-prompt.template.md`   | Prompt template for Homer      |
| `speckit.pipeline.md`        | `.claude/commands/speckit.pipeline.md`          | Claude Code slash command      |
| `speckit.ralph.implement.md` | `.claude/commands/speckit.ralph.implement.md`   | Claude Code slash command      |
| `speckit.lisa.analyze.md`    | `.claude/commands/speckit.lisa.analyze.md`      | Claude Code slash command      |
| `speckit.homer.clarify.md`   | `.claude/commands/speckit.homer.clarify.md`     | Claude Code slash command      |

## Usage

### Pipeline (end-to-end)

After creating a spec with `/speckit.specify`, run the pipeline command inside Claude Code:

```
/speckit.pipeline
```

This prints a bash command to start the full pipeline:

```bash
.specify/scripts/bash/pipeline.sh specs/a1b2-feat-user-auth
```

Copy and run that command in your terminal. The pipeline will auto-detect the feature directory from your current git branch and run all five steps in sequence: homer → plan → tasks → lisa → ralph.

**Options:**

| Flag               | Description                                        | Default |
| ------------------ | -------------------------------------------------- | ------- |
| `--from <step>`    | Resume from a specific step (homer/plan/tasks/lisa/ralph) | auto-detect |
| `--homer-max <n>`  | Max homer loop iterations                          | 10      |
| `--lisa-max <n>`   | Max lisa loop iterations                            | 10      |
| `--ralph-max <n>`  | Max ralph loop iterations                           | 20      |
| `--model <model>`  | Claude model to use                                | opus    |
| `--dry-run`        | Show what would run without executing              | —       |

**Smart auto-detection:** If `--from` is not specified, the pipeline inspects existing artifacts in the spec directory and starts from the right step automatically:

- `tasks.md` exists with some tasks completed → starts at **ralph**
- `tasks.md` exists with no tasks started → starts at **lisa**
- `plan.md` exists → starts at **tasks**
- `spec.md` exists → starts at **homer**

**Resuming after interruption:** All work is committed after each loop iteration, so you can safely interrupt with Ctrl+C and resume later:

```bash
.specify/scripts/bash/pipeline.sh --from ralph specs/a1b2-feat-user-auth
```

### Ralph Loop (implementation)

Once you have a `tasks.md` generated by `/speckit.tasks`, run the Ralph command inside Claude Code:

```
/speckit.ralph.implement
```

This generates the prompt and prints a bash command to start the loop:

```bash
.specify/scripts/bash/ralph-loop.sh .specify/.ralph-prompt.md <MAX> <FEATURE_DIR>/tasks.md
```

Copy and run that command in your terminal. Ralph will iterate — one task per cycle — until all tasks in `tasks.md` are marked `[x]`.

### Lisa Loop (analysis)

Once you have `spec.md`, `plan.md`, and `tasks.md`, run the Lisa command inside Claude Code:

```
/speckit.lisa.analyze
```

This prints a bash command:

```bash
.specify/scripts/bash/lisa-loop.sh <FEATURE_DIR> 10
```

Copy and run that command in your terminal. Lisa will iterate — one finding per cycle (highest severity first) — until zero findings remain.

### Homer Loop (clarification)

After running `/speckit.specify` to create `spec.md`, run the Homer command inside Claude Code:

```
/speckit.homer.clarify
```

This prints a bash command:

```bash
.specify/scripts/bash/homer-loop.sh <FEATURE_DIR> 10
```

Copy and run that command in your terminal. Homer will iterate — one finding per cycle (highest severity first) — resolving ambiguities and unclear requirements until zero findings remain.

## How the loops work

### Fresh context per iteration

Each loop calls `claude -p` as a subprocess for each iteration. This means every cycle starts with zero prior context, preventing hallucination drift and context window exhaustion.

### Completion detection

Each loop detects completion via promise tags in the Claude output:

- Ralph: `<promise>ALL_TASKS_COMPLETE</promise>`
- Lisa: `<promise>ALL_FINDINGS_RESOLVED</promise>`
- Homer: `<promise>ALL_FINDINGS_RESOLVED</promise>`

### Stuck detection

If three consecutive iterations produce identical output, the loop aborts automatically to avoid infinite cycling.

### Logging

All iterations are logged to `.specify/logs/` with timestamps:

```
.specify/logs/pipeline-20260218-130522.log
.specify/logs/ralph-20260218-130522.log
.specify/logs/lisa-20260218-220639.log
.specify/logs/homer-20260218-231045.log
```

## Customization

### Quality gates (Ralph)

The quality gate in `speckit.ralph.implement.md` ships as a **placeholder** that will intentionally fail. Before running Ralph standalone, open the command file and replace the placeholder command in Step 3 with your project's actual quality gates (e.g., `npm run lint && npm run typecheck && npm test`). The command is substituted into the `{QUALITY_GATES}` slot in the prompt template at runtime.

When running Ralph via the pipeline or directly with a spec directory, set the `QUALITY_GATES` environment variable:

```bash
QUALITY_GATES="npm run lint && npm run typecheck && npm test" .specify/scripts/bash/pipeline.sh
```

### Max iterations

- Ralph defaults to `incomplete_tasks + 10` (standalone) or `20` (pipeline)
- Lisa defaults to `10` (4 severity levels + buffer)
- Homer defaults to `10` (4 severity levels + buffer)

Override by editing the generated bash command (standalone) or passing `--ralph-max`, `--homer-max`, `--lisa-max` flags (pipeline).

## References

- [Speckit Ralph Loop: Fresh Context AI Development](https://dominic-boettger.com/blog/speckit-ralph-loop-fresh-context-ai-development/)
