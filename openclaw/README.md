# OpenClaw Skills for Spec-Kit + Simpsons Loops

Agent skills for running autonomous Claude Code sessions with spec-driven development. These skills provide the lifecycle infrastructure for launching, monitoring, and cleaning up background Claude Code sessions in tmux.

## What's Included

### claude-runner/
Core lifecycle engine. Handles the mechanical parts of running Claude Code in background tmux sessions:
- **runner.sh** — Creates tmux session, generates launcher script, auto-dismisses trust prompts, outputs session metadata
- **watcher.md** — Monitoring template for cron-based health checks (idle detection, error scanning, auto-cleanup)
- **SKILL.md** — Full documentation of the lifecycle, session tracker, cleanup checklist, and learnings

### coding-agent/
Coding-specific consumer skill that builds on claude-runner:
- Pre-flight checks (Speckit CLI, Simpsons Loops, tmux)
- Spec-driven development workflow via Speckit + Simpsons Loops pipeline
- PR review patterns, parallel issue fixing with git worktrees
- Quality gates integration

## Dependencies

| Tool | Required | Purpose |
|---|---|---|
| [tmux](https://github.com/tmux/tmux) | Yes | PTY for Claude Code sessions + shared terminal access |
| [Claude CLI](https://docs.anthropic.com/en/docs/claude-code) | Yes | The `claude` command-line tool |
| [Speckit](https://github.com/github/spec-kit) (`specify` CLI) | For coding-agent | Spec-driven development framework |
| [Simpsons Loops](https://github.com/jnhuynh/spec-kit-simpsons-loops) | For coding-agent | Automated iteration loops (Homer, Lisa, Ralph, Pipeline) |
| bash 4+ | Yes | Shell scripts use `set -euo pipefail` and modern bash features |
| [OpenClaw](https://github.com/pj/openclaw) | For watchers | Cron scheduling for session monitoring |

## Installation

### Automated

```bash
bash openclaw/INSTALL.sh
```

### Manual

Copy the skill directories to your OpenClaw skills location:

```bash
cp -r openclaw/claude-runner/ ~/.openclaw/skills/claude-runner/
cp -r openclaw/coding-agent/ ~/.openclaw/skills/coding-agent/
chmod +x ~/.openclaw/skills/claude-runner/runner.sh
```

## Quick Start

```bash
# 1. Run pre-flight (ensure speckit, simpsons-loops, tmux are ready)
cd ~/Projects/myproject
specify init --here --ai claude
bash ~/Projects/spec-kit-simpsons-loops/setup.sh

# 2. Write a task prompt
cat > /tmp/task-myproject.txt << 'EOF'
Build a REST API for user management. Start with /speckit.specify to draft
the spec, then run /speckit.pipeline for the full development cycle.
EOF

# 3. Launch via runner.sh
eval $(~/.openclaw/skills/claude-runner/runner.sh \
  --prefix claude \
  --slug myproject \
  --workdir ~/Projects/myproject \
  --task-file /tmp/task-myproject.txt)

# 4. Drop in to watch
tmux attach -t $TMUX_NAME
# Ctrl+B D to detach safely
```

## How It Works

Every background Claude Code session follows three phases:

1. **Launch** — `runner.sh` creates a tmux session, generates a launcher script (two-script executor pattern to avoid shell metacharacter issues), auto-dismisses the directory trust prompt, and outputs session metadata as key=value pairs.

2. **Monitor** — A watcher cron (from `watcher.md` template) polls the session every 5 minutes. It uses dual-signal idle detection (log staleness + prompt visibility) to distinguish between "thinking" and "done." Errors trigger notifications; clean completion triggers auto-cleanup.

3. **Complete** — On completion, the watcher reads the persistent log, summarizes results, updates the session tracker, sends a notification, and cleans up all artifacts (tmux session, log file, temp files, watcher cron).

## Directory Structure

```
openclaw/
  claude-runner/
    SKILL.md       # Full lifecycle documentation
    runner.sh      # Mechanical launch script
    watcher.md     # Monitoring cron template
  coding-agent/
    SKILL.md       # Coding-specific workflows and pre-flight
  README.md        # This file
  INSTALL.sh       # Automated installer
```

## Customization

- **Notification target**: The watcher template uses `{{NOTIFY_TARGET}}` — substitute with your preferred notification channel (Telegram chat ID, Slack webhook, etc.)
- **Session tracker**: Defaults to `$HOME/.openclaw/workspace/CLAUDE-SESSIONS.md` — change via `{{TRACKER_FILE}}` in watcher setup
- **Watcher interval**: Default 300000ms (5 min) — adjust in the cron schedule

## License

Same license as the parent [spec-kit-simpsons-loops](https://github.com/jnhuynh/spec-kit-simpsons-loops) repository.
