# Simpsons Loops for Speckit + Claude Code

Automated iteration loops for [Speckit](https://github.com/speckit)-powered projects using Claude Code CLI.

- **Ralph Loop** — Task-by-task implementation. Picks up the next incomplete task from `tasks.md`, implements it, validates, commits, and exits. Repeats with fresh context until all tasks are done.
- **Lisa Loop** — Iterative cross-artifact analysis. Runs `/speckit.analyze` on `spec.md`, `plan.md`, and `tasks.md`, fixes all findings at the highest severity level, commits, and exits. Repeats until zero findings remain.
- **Homer Loop** — Iterative spec clarification. Runs `/speckit.clarify` on `spec.md`, `plan.md`, and `tasks.md`, resolves ambiguities and unanswered questions at the highest severity level, commits, and exits. Repeats until zero findings remain.

Both loops invoke `claude -p` with a fresh context per iteration, which avoids context window limits and keeps each run focused.

## Prerequisites

- A project already set up with Speckit (`.specify/` directory exists)
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) installed
- Existing Speckit commands in `.claude/commands/` (at minimum: `speckit.implement.md`, `speckit.analyze.md`, `speckit.clarify.md`)

## Setup

### Option A: Automated (recommended)

From the root of your target project, run the setup script:

```bash
bash <path-to-simpsons-loops>/setup.sh
```

This copies all files, makes scripts executable, appends `.gitignore` entries, and updates `.claude/settings.local.json` permissions. Requires `jq` for the permissions step (you'll get manual instructions if it's missing).

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

# Prompt templates → .specify/templates/
cp <path-to-simpsons-loops>/ralph-prompt.template.md   .specify/templates/ralph-prompt.template.md
cp <path-to-simpsons-loops>/lisa-prompt.template.md    .specify/templates/lisa-prompt.template.md
cp <path-to-simpsons-loops>/homer-prompt.template.md   .specify/templates/homer-prompt.template.md

# Claude Code commands → .claude/commands/
cp <path-to-simpsons-loops>/speckit.ralph.implement.md   .claude/commands/speckit.ralph.implement.md
cp <path-to-simpsons-loops>/speckit.lisa.analyze.md      .claude/commands/speckit.lisa.analyze.md
cp <path-to-simpsons-loops>/speckit.homer.clarify.md     .claude/commands/speckit.homer.clarify.md
```

#### 2. Make scripts executable

```bash
chmod +x .specify/scripts/bash/ralph-loop.sh
chmod +x .specify/scripts/bash/lisa-loop.sh
chmod +x .specify/scripts/bash/homer-loop.sh
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

*.specify/logs/*        # All log files
```

#### 4. Allow loop scripts in Claude Code permissions

Add the loop scripts to your `.claude/settings.local.json` allow list so Claude Code can run them without prompting:

```json
{
  "permissions": {
    "allow": [
      "Bash(.specify/scripts/bash/ralph-loop.sh*)",
      "Bash(.specify/scripts/bash/lisa-loop.sh*)",
      "Bash(.specify/scripts/bash/homer-loop.sh*)"
    ]
  }
}
```

</details>

## File mapping reference

| Source file                  | Destination                                     | Purpose                     |
| ---------------------------- | ----------------------------------------------- | --------------------------- |
| `ralph-loop.sh`              | `.specify/scripts/bash/ralph-loop.sh`           | Bash orchestrator for Ralph |
| `lisa-loop.sh`               | `.specify/scripts/bash/lisa-loop.sh`            | Bash orchestrator for Lisa  |
| `homer-loop.sh`              | `.specify/scripts/bash/homer-loop.sh`           | Bash orchestrator for Homer |
| `ralph-prompt.template.md`   | `.specify/templates/ralph-prompt.template.md`   | Prompt template for Ralph   |
| `lisa-prompt.template.md`    | `.specify/templates/lisa-prompt.template.md`    | Prompt template for Lisa    |
| `homer-prompt.template.md`   | `.specify/templates/homer-prompt.template.md`   | Prompt template for Homer   |
| `speckit.ralph.implement.md` | `.claude/commands/speckit.ralph.implement.md`   | Claude Code slash command   |
| `speckit.lisa.analyze.md`    | `.claude/commands/speckit.lisa.analyze.md`      | Claude Code slash command   |
| `speckit.homer.clarify.md`   | `.claude/commands/speckit.homer.clarify.md`     | Claude Code slash command   |

## Usage

### Ralph Loop (implementation)

Once you have a `tasks.md` generated by `/speckit.tasks`, run the Ralph command inside Claude Code:

```
/speckit.ralph.implement
```

This generates the prompt and prints a bash command to start the loop:

```bash
.specify/scripts/bash/ralph-loop.sh .specify/.ralph-prompt.md <MAX_ITERATIONS> <FEATURE_DIR>/tasks.md
```

Copy and run that command in your terminal. Ralph will iterate — one task per cycle — until all tasks in `tasks.md` are marked `[x]`.

### Lisa Loop (analysis)

Once you have `spec.md`, `plan.md`, and `tasks.md`, run the Lisa command inside Claude Code:

```
/speckit.lisa.analyze
```

This generates the prompt and prints a bash command:

```bash
.specify/scripts/bash/lisa-loop.sh .specify/.lisa-prompt.md 10
```

Copy and run that command in your terminal. Lisa will iterate — one severity level per cycle (CRITICAL > HIGH > MEDIUM > LOW) — until zero findings remain.

### Homer Loop (clarification)

Once you have `spec.md`, `plan.md`, and `tasks.md`, run the Homer command inside Claude Code:

```
/speckit.homer.clarify
```

This generates the prompt and prints a bash command:

```bash
.specify/scripts/bash/homer-loop.sh .specify/.homer-prompt.md 10
```

Copy and run that command in your terminal. Homer will iterate — one severity level per cycle (CRITICAL > HIGH > MEDIUM > LOW) — resolving ambiguities and unclear requirements until zero findings remain.

## How the loops work

### Fresh context per iteration

Both loops call `claude -p` as a subprocess for each iteration. This means every cycle starts with zero prior context, preventing hallucination drift and context window exhaustion.

### Completion detection

Each loop detects completion via promise tags in the Claude output:

- Ralph: `<promise>ALL_TASKS_COMPLETE</promise>`
- Lisa: `<promise>ALL_FINDINGS_RESOLVED</promise>`

### Stuck detection

If three consecutive iterations produce identical output, the loop aborts automatically to avoid infinite cycling.

### Logging

All iterations are logged to `.specify/logs/` with timestamps:

```
.specify/logs/ralph-20260218-130522.log
.specify/logs/lisa-20260218-220639.log
.specify/logs/homer-20260218-231045.log
```

## Customization

### Quality gates (Ralph)

The quality gate in `speckit.ralph.implement.md` ships as a **placeholder** that will intentionally fail. Before running Ralph, open the command file and replace the placeholder command in Step 3 with your project's actual quality gates (e.g., `npm run lint && npm run typecheck && npm test`). The command is substituted into the `{QUALITY_GATES}` slot in the prompt template at runtime.

### Max iterations

- Ralph defaults to `incomplete_tasks + 10`
- Lisa defaults to `10` (4 severity levels + buffer)
- Homer defaults to `10` (4 severity levels + buffer)

Override by editing the generated bash command before running it.

## References

- [Speckit Ralph Loop: Fresh Context AI Development](https://dominic-boettger.com/blog/speckit-ralph-loop-fresh-context-ai-development/)
