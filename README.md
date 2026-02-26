# 🍩 Simpsons Loops for Speckit + Claude Code

Automated iteration loops and pipeline orchestration for [Speckit](https://github.com/speckit)-powered projects using Claude Code CLI.

Each loop invokes `claude -p --dangerously-skip-permissions` with a fresh context per iteration, preventing hallucination drift and context window exhaustion.

| Loop | What it does |
| --- | --- |
| 🍩 **Homer** | Iterative spec clarification. Runs `/speckit.clarify` on `spec.md`, resolves the highest-severity ambiguity, commits, and repeats until zero findings remain. |
| 🎷 **Lisa** | Iterative cross-artifact analysis. Runs `/speckit.analyze` on `spec.md`, `plan.md`, and `tasks.md`, fixes the highest-severity finding, commits, and repeats until zero findings remain. |
| 🖍️ **Ralph** | Task-by-task implementation. Picks the next incomplete task from `tasks.md`, implements it, validates, commits, and repeats until all tasks are done. |
| 🏭 **Pipeline** | End-to-end orchestrator: homer → plan → tasks → lisa → ralph. Auto-detects where to start based on existing artifacts. |

> **Warning: `--dangerously-skip-permissions`**
> Claude will execute tool calls (file writes, shell commands, etc.) without asking for confirmation. Review the prompt templates and understand what each loop does before running them.

## 💡 Recommended workflow

Before kicking off the pipeline or any loop, refine your specs manually. Run `/speckit.specify` to draft the initial spec, then use `/speckit.clarify` interactively to resolve ambiguities. The more precise your spec is before automation takes over, the better the results — automation amplifies whatever it's given.

You can also run each loop individually and review between stages instead of running the full pipeline. Run Homer first, review the clarified spec, generate the plan and tasks manually, review those, run Lisa, review, then run Ralph. This staged approach lets you course-correct at every step.

## 🔑 API key vs. Claude subscription

If `ANTHROPIC_API_KEY` is set, every iteration will consume API credits from that key. To use your **Claude subscription** (Pro/Max) instead:

```bash
unset ANTHROPIC_API_KEY
```

## ✅ Prerequisites

- A project already set up with Speckit (`.specify/` directory exists)
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) installed
- Existing Speckit commands in `.claude/commands/` (at minimum: `speckit.implement.md`, `speckit.analyze.md`, `speckit.clarify.md`, `speckit.plan.md`, `speckit.tasks.md`)

## 🛠️ Setup

### 🤖 Option A: Automated (recommended)

From the root of your target project:

```bash
bash <path-to-simpsons-loops>/setup.sh
```

This copies all files (loop scripts, pipeline, prompt templates, and Claude Code commands), makes scripts executable, appends `.gitignore` entries, and updates `.claude/settings.local.json` permissions. Requires `jq` for the permissions step (you'll get manual instructions if it's missing).

### 📝 Option B: Manual

<details>
<summary>Click to expand manual steps</summary>

#### 1. Copy files into your project

From the root of your project:

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

Add to `.claude/settings.local.json`:

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

## 🚀 Usage

Each loop has a corresponding Claude Code slash command. The slash command does **not** run the script directly — it prints the bash command for you to copy-paste and run in your terminal.

### 🍩 Homer (clarification)

After running `/speckit.specify` to create `spec.md`, run the slash command — it prints the bash command to execute:

```
/speckit.homer.clarify
```

Then copy-paste and run the printed command:

```bash
.specify/scripts/bash/homer-loop.sh <FEATURE_DIR> 10
```

### 🎷 Lisa (analysis)

Once you have `spec.md`, `plan.md`, and `tasks.md`, run the slash command — it prints the bash command to execute:

```
/speckit.lisa.analyze
```

Then copy-paste and run the printed command:

```bash
.specify/scripts/bash/lisa-loop.sh <FEATURE_DIR> 10
```

### 🖍️ Ralph (implementation)

Once you have `tasks.md` from `/speckit.tasks`, run the slash command — it prints the bash command to execute:

```
/speckit.ralph.implement
```

Then copy-paste and run the printed command:

```bash
.specify/scripts/bash/ralph-loop.sh .specify/.ralph-prompt.md <MAX> <FEATURE_DIR>/tasks.md
```

### 🏭 Pipeline (end-to-end)

After creating a spec with `/speckit.specify`, run the slash command — it prints the bash command to execute:

```
/speckit.pipeline
```

Then copy-paste and run the printed command:

```bash
.specify/scripts/bash/pipeline.sh specs/a1b2-feat-user-auth
```

**Options:**

| Flag               | Description                                              | Default      |
| ------------------ | -------------------------------------------------------- | ------------ |
| `--from <step>`    | Resume from a specific step (homer/plan/tasks/lisa/ralph) | auto-detect |
| `--homer-max <n>`  | Max homer loop iterations                                | 10           |
| `--lisa-max <n>`   | Max lisa loop iterations                                 | 10           |
| `--ralph-max <n>`  | Max ralph loop iterations                                | 20           |
| `--model <model>`  | Claude model to use                                      | opus         |
| `--dry-run`        | Show what would run without executing                    | —            |

**Smart auto-detection:** If `--from` is not specified, the pipeline inspects existing artifacts and starts from the right step:

- `tasks.md` with some tasks completed → **ralph**
- `tasks.md` with no tasks started → **lisa**
- `plan.md` exists → **tasks**
- `spec.md` exists → **homer**

**Resuming after interruption:** All work is committed after each iteration, so you can safely Ctrl+C and resume:

```bash
.specify/scripts/bash/pipeline.sh --from ralph specs/a1b2-feat-user-auth
```

## ⚙️ How the loops work

**Completion detection** — Each loop looks for promise tags in the output:

- Homer / Lisa: `<promise>ALL_FINDINGS_RESOLVED</promise>`
- Ralph: `<promise>ALL_TASKS_COMPLETE</promise>`

**Stuck detection** — If three consecutive iterations produce identical output, the loop aborts to avoid infinite cycling.

**Logging** — All iterations are logged to `.specify/logs/` with timestamps (e.g. `ralph-20260218-130522.log`).

## 🎨 Customization

### Quality gates (Ralph)

The quality gate in `speckit.ralph.implement.md` ships as a **placeholder** that will intentionally fail. Before running Ralph standalone, replace the placeholder in Step 3 with your project's actual quality gates (e.g., `npm run lint && npm run typecheck && npm test`).

When running via the pipeline, set the `QUALITY_GATES` environment variable:

```bash
QUALITY_GATES="npm run lint && npm run typecheck && npm test" .specify/scripts/bash/pipeline.sh
```

### Max iterations

| Loop  | Standalone default          | Pipeline default |
| ----- | --------------------------- | ---------------- |
| Homer | 10                          | 10               |
| Lisa  | 10                          | 10               |
| Ralph | incomplete tasks + 10       | 20               |

Override with `--homer-max`, `--lisa-max`, `--ralph-max` flags (pipeline) or by editing the generated bash command (standalone).

## 📚 References

- [Speckit Ralph Loop: Fresh Context AI Development](https://dominic-boettger.com/blog/speckit-ralph-loop-fresh-context-ai-development/)
