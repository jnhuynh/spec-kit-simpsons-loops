---
name: coding-agent
description: 'Delegate coding tasks to Claude Code via tmux sessions with spec-driven development (Speckit + Simpsons Loops). Use when: (1) building/creating new features or apps, (2) reviewing PRs (spawn in temp dir), (3) refactoring large codebases, (4) iterative coding that needs file exploration. NOT for: simple one-liner fixes (just edit), reading code (use read tool), or any work in the OpenClaw workspace (never spawn agents here). Requires tmux and claude CLI.'
metadata:
  {
    "openclaw": { "emoji": "🧩", "requires": { "anyBins": ["claude", "tmux"] } },
  }
---

# Coding Agent (Claude Code + Spec-Driven Development)

Claude Code is the only supported coding agent. All sessions use **spec-driven development** powered by [Speckit](https://github.com/github/spec-kit) and [Simpsons Loops](https://github.com/jnhuynh/spec-kit-simpsons-loops).

> **For session lifecycle (launch, monitoring, completion, cleanup), see the `claude-runner` skill.** This file covers coding-agent-specific pre-flight, workflows, and patterns only.

---

## Pre-Flight: Ensure Tooling Is Ready

**Before launching any coding session**, run these checks. Every time, every project — no exceptions.

### 1. Ensure Speckit (`specify` CLI) is installed

```bash
which specify || brew install specify-cli
```

### 2. Pull latest Simpsons Loops

The simpsons-loops repo lives at `~/Projects/spec-kit-simpsons-loops`. **Always pull latest before any session** — it gets updated frequently.

```bash
# Clone if missing, pull if exists
if [ -d ~/Projects/spec-kit-simpsons-loops ]; then
  cd ~/Projects/spec-kit-simpsons-loops && git pull --ff-only
else
  git clone https://github.com/jnhuynh/spec-kit-simpsons-loops.git ~/Projects/spec-kit-simpsons-loops
fi
```

### 3. Initialize Speckit + Simpsons Loops on the project

**Always run both steps** — regardless of whether the project already has `.specify/` or `.claude/` dirs. `specify init` is safe to re-run (won't clobber existing config). Simpsons Loops `setup.sh` is also idempotent.

```bash
cd <PROJECT_DIR>
specify init --here --ai claude
bash ~/Projects/spec-kit-simpsons-loops/setup.sh
```

### 4. Ensure tmux is installed

```bash
which tmux || brew install tmux
```

### Pre-Flight Sequence (copy-paste ready)

```bash
# 1. Speckit CLI
which specify || brew install specify-cli

# 2. Simpsons Loops (clone or pull)
if [ -d ~/Projects/spec-kit-simpsons-loops ]; then
  cd ~/Projects/spec-kit-simpsons-loops && git pull --ff-only
else
  git clone https://github.com/jnhuynh/spec-kit-simpsons-loops.git ~/Projects/spec-kit-simpsons-loops
fi

# 3. Init speckit + simpsons on the project (always — safe to re-run)
cd <PROJECT_DIR>
specify init --here --ai claude
bash ~/Projects/spec-kit-simpsons-loops/setup.sh

# 4. tmux
which tmux || brew install tmux
```

---

## Quick Start: Launch a Coding Session

```bash
# 1. Run pre-flight (full sequence above)

# 2. Write task prompt to file
cat > /tmp/task-myproject.txt << 'EOF'
We are building FEATURE_DESCRIPTION. Start with /speckit.specify to draft
the spec, then run /speckit.pipeline to take it through the full development cycle.
EOF

# 3. Launch via runner.sh
eval $(~/.openclaw/skills/claude-runner/runner.sh \
  --prefix claude \
  --slug myproject \
  --workdir ~/Projects/myproject \
  --task-file /tmp/task-myproject.txt)

# 4. Dedup check + create watcher from template, update CLAUDE-SESSIONS.md
#    (see claude-runner skill for watcher dedup + setup + session tracker format)
# $ATTACH is the pre-formatted attach command — use it directly, never construct manually
```

---

## Spec-Driven Development Workflow

Speckit + Simpsons Loops provide a structured pipeline for feature development. The key slash commands (available inside Claude Code after setup.sh runs):

| Command | Description |
|---|---|
| `/speckit.specify` | Draft the initial spec — describe *what* and *why* |
| `/speckit.constitution` | Create project governing principles |
| `/speckit.clarify` | Interactive ambiguity resolution |
| `/speckit.plan` | Create implementation plan with tech stack |
| `/speckit.tasks` | Generate actionable task list from the plan |
| `/speckit.implement` | Execute all tasks |

### Simpsons Loops (automated iteration)

| Loop | Command | What it does |
|---|---|---|
| Homer | `/speckit.homer.clarify` | Iterative spec clarification — resolves ambiguities until none remain |
| Lisa | `/speckit.lisa.analyze` | Cross-artifact analysis — fixes inconsistencies across spec/plan/tasks |
| Ralph | `/speckit.ralph.implement` | Task-by-task implementation with quality gates |
| Pipeline | `/speckit.pipeline` | End-to-end: homer -> plan -> tasks -> lisa -> ralph |

### Typical Feature Build

```bash
# Pre-flight (always — run full sequence from Pre-Flight section)
cd ~/Projects/myproject
specify init --here --ai claude
bash ~/Projects/spec-kit-simpsons-loops/setup.sh

# Write task prompt
cat > /tmp/task-myproject.txt << 'EOF'
We are building FEATURE_DESCRIPTION. Start with /speckit.specify to draft
the spec, then run /speckit.pipeline to take it through the full development cycle.
EOF

# Launch via runner.sh
eval $(~/.openclaw/skills/claude-runner/runner.sh \
  --prefix claude \
  --slug myproject \
  --workdir ~/Projects/myproject \
  --task-file /tmp/task-myproject.txt)

# $TMUX_NAME, $LOG, $TIMESTAMP, $LAUNCHER, $WATCHER_NAME, $ATTACH are now set
# Use $ATTACH as the drop-in attach command — NEVER construct it manually from $TMUX_NAME
# Dedup check + schedule watcher + update tracker (see claude-runner skill)
```

### Quality Gates

The pipeline supports quality gates for Ralph (implementation loop). Set via environment variable:

```bash
QUALITY_GATES="npm run lint && npm run typecheck && npm test" .specify/scripts/bash/pipeline.sh
```

Or edit the placeholder in `.claude/commands/speckit.ralph.implement.md` with the project's actual test/lint commands.

### Pipeline Flags (bash scripts)

| Flag | Description | Default |
|---|---|---|
| `--from <step>` | Resume from step (homer/plan/tasks/lisa/ralph) | auto-detect |
| `--homer-max <n>` | Max homer iterations | 10 |
| `--lisa-max <n>` | Max lisa iterations | 10 |
| `--ralph-max <n>` | Max ralph iterations | 20 |
| `--quality-gates <cmd>` | Quality gates command | placeholder |
| `--model <model>` | Claude model | opus |
| `--dry-run` | Show what would run | -- |

### Resuming After Interruption

All loops commit after each iteration. Safe to stop and resume — the pipeline auto-detects where to pick up based on existing artifacts.

---

## Reviewing PRs

**CRITICAL: Never review PRs in your live OpenClaw project folder!** Clone to temp folder or use git worktree.

```bash
REVIEW_DIR=$(mktemp -d)
git clone https://github.com/user/repo.git $REVIEW_DIR
cd $REVIEW_DIR && gh pr checkout 130

cat > /tmp/task-review.txt << 'EOF'
Review this PR against the main branch. Check for bugs, style issues, and test coverage.
EOF

eval $(~/.openclaw/skills/claude-runner/runner.sh \
  --prefix claude \
  --slug review \
  --workdir $REVIEW_DIR \
  --task-file /tmp/task-review.txt)

# Clean up after: tmux kill-session -t $TMUX_NAME; trash $REVIEW_DIR
```

---

## Parallel Issue Fixing with git worktrees

```bash
# 1. Create worktrees
git worktree add -b fix/issue-78 /tmp/issue-78 main
git worktree add -b fix/issue-99 /tmp/issue-99 main

# 2. Run pre-flight on each worktree
for d in /tmp/issue-78 /tmp/issue-99; do
  cd "$d"
  specify init --here --ai claude
  bash ~/Projects/spec-kit-simpsons-loops/setup.sh
done

# 3. Write task files
echo "Fix issue #78: DESCRIPTION." > /tmp/task-issue78.txt
echo "Fix issue #99: DESCRIPTION." > /tmp/task-issue99.txt

# 4. Launch via runner.sh
eval $(~/.openclaw/skills/claude-runner/runner.sh \
  --prefix claude --slug issue-78 --workdir /tmp/issue-78 --task-file /tmp/task-issue78.txt)
TMUX78=$TMUX_NAME

eval $(~/.openclaw/skills/claude-runner/runner.sh \
  --prefix claude --slug issue-99 --workdir /tmp/issue-99 --task-file /tmp/task-issue99.txt)
TMUX99=$TMUX_NAME

# 5. Create PRs after fixes
cd /tmp/issue-78 && git push -u origin fix/issue-78
gh pr create --repo user/repo --head fix/issue-78 --title "fix: ..." --body "..."

# 6. Cleanup
git worktree remove /tmp/issue-78
git worktree remove /tmp/issue-99
```

---

## Rules

1. **Always run pre-flight** — check specify, pull simpsons-loops, run setup.sh. Every session. No shortcuts.
2. **Use `~/Projects/claude-tmp/` for temp work** — Claude Code prompts for directory trust on new/unknown directories even with `--dangerously-skip-permissions`. This directory is pre-trusted. Each session gets its own subdirectory. Always `mkdir -p` it before launching.
3. **Parallel is OK** — run many sessions at once for batch work.
4. **NEVER start agents in `~/.openclaw/`** — it'll read your soul docs and get weird ideas.
5. **NEVER checkout branches in your live OpenClaw project directory** — that's the LIVE instance.
6. **Docker cleanup in task prompts** — if the task is likely to involve Docker (database containers, integration tests, docker-compose stacks), include explicit cleanup instructions in the task prompt: `"Before finishing, stop and remove any Docker containers you started: docker stop <id> && docker rm <id>, or docker compose down."` Claude Code won't clean up what it doesn't know it owns.

For lifecycle rules (tmux, watchers, cleanup, logging), see the `claude-runner` skill.

---

## Learnings

- **Simpsons Loops commits after each iteration** — safe to interrupt and resume.
- **`specify init` and `setup.sh` are idempotent** — safe to run on every session, even if the project is already initialized. Always run both unconditionally.
- **When to skip Speckit/Simpsons:** Speckit + Simpsons Loops are for code projects only — features, apps, refactors, anything with tests and implementation cycles. For data transformation, file processing, organizational tasks, or any non-code work, skip the pre-flight and launch with a direct task prompt. But always apply full lifecycle management regardless.
- **No angle brackets or backticks in task file content** — angle brackets (`<like this>`) and backticks are interpreted by the shell (zsh glob expansion or command substitution) when task content is passed through `script -c`. Use `UPPERCASE_PLACEHOLDERS` or `__DOUBLE_UNDERSCORE__` sentinels instead. See `claude-runner` for the two-script fix that prevents this.
- **Docker cleanup must be in the task prompt** — Claude Code sessions can start Docker containers (test databases, integration suites, docker-compose stacks) but have no lifecycle awareness beyond their own session. If the task might involve Docker, the prompt must explicitly instruct cleanup. The watcher can't see inside Docker — only Claude Code knows what it started.

For lifecycle learnings (tmux, idle detection, watcher patterns, persistent artifacts), see the `claude-runner` skill.
