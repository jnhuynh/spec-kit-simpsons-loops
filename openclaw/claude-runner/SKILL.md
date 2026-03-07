---
name: claude-runner
description: 'Core lifecycle engine for Claude Code tmux sessions. Provides runner.sh (mechanical launch), watcher.md (monitoring template), and the unified session tracker. Consumer skills (coding-agent, blog-drafter, marketing-drafter) call this instead of duplicating lifecycle machinery. NOT a standalone skill — always used through a consumer skill.'
metadata:
  { "openclaw": { "emoji": "🏗️", "requires": { "anyBins": ["claude", "tmux"] } } }
---

# Claude Runner — Core Lifecycle Engine

The shared infrastructure for all Claude Code tmux sessions. Extracts the mechanical lifecycle (launch, monitor, complete, cleanup) so consumer skills stay thin — just prompts and hooks.

**Consumer skills:** `coding-agent`, `blog-drafter`, `marketing-drafter`

When ACP runtime gets fixed, swap this core once — all consumers benefit.

---

## tmux Attach is Non-Negotiable

The ability to `tmux attach -t <session>` from any terminal and drop into a live Claude Code session is the single most valuable troubleshooting capability of this system. It must survive every refactor, every abstraction, and any future migration to ACP or other runtimes.

If a future change would remove or degrade tmux attach capability, that change is wrong. Find another way.

---

## runner.sh — Mechanical Launch

A bash script that handles everything from tmux session creation through trust prompt dismissal.

### Interface

```bash
~/.openclaw/skills/claude-runner/runner.sh \
  --prefix <prefix>         # tmux name prefix (e.g. "blog", "claude", "mktg")
  --slug <slug>             # session slug (e.g. "spec-is-the-product")
  --workdir <dir>           # cd here before running claude
  --task-file <path>        # path to a file containing the Claude Code task prompt
  [--on-success <script>]   # optional: bash <script> runs on clean exit (code 0); use for Phase 2 chaining
```

### What it does (in order)

1. Generates timestamp: `date +%Y%m%d-%H%M%S`
2. Composes names:
   - `TMUX_NAME=<prefix>-<slug>-<timestamp>`
   - `LOG=/tmp/claude-runner-<prefix>-<slug>-<timestamp>.log`
3. Writes a launcher script to `/tmp/claude-runner-launch-<prefix>-<slug>-<timestamp>.sh` using the two-script executor pattern (task content is read by the executor at runtime with `set -f` — never embedded in a shell `-c` string, so backticks, `$()`, and angle brackets in task content are all safe). If `--on-success` was provided, chains `bash <script>` when Claude exits with code 0.
4. `chmod +x` the launcher script
5. Creates tmux session: `tmux new-session -d -s $TMUX_NAME -x 220 -y 50000`
6. Sends launcher: `tmux send-keys -t $TMUX_NAME "bash <launcher-script>" Enter`
7. Auto-dismisses trust prompt: polls tmux pane for up to 30s, sends Enter when "Do you trust" appears, exits early if Claude Code UI detected
8. Outputs key=value pairs to stdout:
   ```
   TMUX_NAME='blog-spec-is-the-product-20260303-222220'
   LOG='/tmp/claude-runner-blog-spec-is-the-product-20260303-222220.log'
   TIMESTAMP='20260303-222220'
   LAUNCHER='/tmp/claude-runner-launch-blog-spec-is-the-product-20260303-222220.sh'
   ATTACH='tmux attach -t blog-spec-is-the-product-20260303-222220'
   WATCHER_NAME='watch-blog-spec-is-the-product-20260303-222220'
   ```
   `LAUNCHER` is the generated launcher script path. The executor script (`/tmp/claude-runner-exec-<TMUX_NAME>.sh`) is created and deleted inside the launcher — it is not output. `WATCHER_NAME` is the canonical cron job name for the watcher — use it for dedup checks before creating the watcher cron. `ATTACH` is the pre-formatted drop-in command — use it directly instead of constructing the tmux attach command manually.

### Error handling

- Exit 1 if `--workdir` doesn't exist
- Exit 1 if `--task-file` doesn't exist or is empty
- Exit 1 if `--on-success` is provided but the script doesn't exist
- Exit 1 if tmux is not installed
- Exit 1 if claude CLI is not found
- Exit 1 if tmux session with the same name already exists
- All errors go to stderr; only key=value output goes to stdout

### Examples

```bash
# Coding agent session
~/.openclaw/skills/claude-runner/runner.sh \
  --prefix claude \
  --slug my-app \
  --workdir ~/Projects/my-app \
  --task-file /tmp/task-my-app.txt

# Blog drafter session
~/.openclaw/skills/claude-runner/runner.sh \
  --prefix blog \
  --slug spec-is-the-product \
  --workdir ~/Projects/my-blog \
  --task-file /tmp/blog-task-spec.txt

# Marketing drafter session
~/.openclaw/skills/claude-runner/runner.sh \
  --prefix mktg \
  --slug launch-campaign \
  --workdir ~/Projects/my-blog \
  --task-file /tmp/mktg-task-launch.txt
```

---

## watcher.md — Monitoring Template

A markdown file at `~/.openclaw/skills/claude-runner/watcher.md` containing the watcher cron message with `{{PLACEHOLDER}}` variables. This is the single source of truth for watcher logic.

### Placeholders

| Placeholder | Description |
|---|---|
| `{{TMUX_NAME}}` | The tmux session name |
| `{{LOG}}` | Path to the persistent log file |
| `{{CRON_UUID}}` | The watcher's own cron job UUID (for self-removal) |
| `{{TRACKER_FILE}}` | Path to the session tracker file |
| `{{NOTIFY_TARGET}}` | Notification target (e.g. Telegram chat ID) |

### How to use

1. **Dedup check (MANDATORY):** Before creating a watcher, check if one already exists for this session:
   ```bash
   openclaw cron list 2>/dev/null | grep -q "$WATCHER_NAME" && echo "WATCHER_EXISTS" || echo "NO_WATCHER"
   ```
   If `WATCHER_EXISTS` — do NOT create another watcher. Log it and move on. This prevents the double-watcher bug where the orchestrating agent creates two watchers for the same session.

2. Read the template: `cat ~/.openclaw/skills/claude-runner/watcher.md`
3. Substitute placeholders with `sed`:
   ```bash
   sed -e 's|{{TMUX_NAME}}|claude-my-app-20260303-170000|g' \
       -e 's|{{LOG}}|/tmp/claude-runner-claude-my-app-20260303-170000.log|g' \
       -e 's|{{CRON_UUID}}|PLACEHOLDER|g' \
       -e 's|{{TRACKER_FILE}}|$HOME/.openclaw/workspace/CLAUDE-SESSIONS.md|g' \
       -e 's|{{NOTIFY_TARGET}}|YOUR_NOTIFY_TARGET|g' \
       ~/.openclaw/skills/claude-runner/watcher.md
   ```
4. Create the cron job via `openclaw cron add` using `$WATCHER_NAME` as the job name — returns `jobId`
5. Immediately update via `openclaw cron update` to replace the `CRON_UUID` placeholder with the actual job ID

### Cron parameters

```
cron action:add job:{
  "name": "$WATCHER_NAME",
  "schedule": { "kind": "every", "everyMs": 300000 },
  "payload": { "kind": "agentTurn", "model": "sonnet", "message": "<substituted watcher message>", "timeoutSeconds": 30 },
  "sessionTarget": "isolated",
  "enabled": true
}
```

**Use `$WATCHER_NAME` from runner.sh output** — this ensures the cron name matches the canonical format (`watch-<TMUX_NAME>`) and enables the dedup check.

Always use **sonnet** for watchers — simple observational work should never burn Opus tokens.

---

## The Full Lifecycle

Every background Claude Code session follows three phases: **launch -> monitor -> complete**.

| Phase | What happens | Who does it |
|---|---|---|
| Pre-flight | Consumer-specific checks (Speckit, humanizer, creds, etc.) | Consumer skill |
| Launch | `runner.sh` + schedule watcher cron + update tracker | Main agent (you) |
| Monitor | Check tmux session + log every 5 min, catch stuck/errors | Watcher cron (sonnet) |
| Complete | Read log, summarize, notify, clean up all | Watcher cron or main agent |
| Drop-in | `tmux attach` (human) or `capture-pane`/`send-keys` (agent) | Main agent or human |

### Consumer skill launch pattern

```
1. Run consumer-specific pre-flight
2. Write task prompt to temp file
3. Call runner.sh --prefix <prefix> --slug <slug> --workdir <dir> --task-file <path>
4. Capture output (eval or parse key=value pairs — includes WATCHER_NAME)
5. DEDUP CHECK: openclaw cron list | grep "$WATCHER_NAME" — if exists, skip steps 6-7
6. Create watcher from watcher.md template (substitute placeholders, use $WATCHER_NAME as cron name)
7. Schedule watcher via openclaw cron add, then update to embed real UUID
8. Update CLAUDE-SESSIONS.md with new row (include Watcher UUID)
9. Tell the user (TMUX_NAME, drop-in command, monitoring instructions)
```

### Completion (detected by watcher or system event)

1. Read the persistent log — `tail -200 $LOG`
2. Summarize — what changed, what was built, any errors
3. Update `CLAUDE-SESSIONS.md` — mark status
4. Notify — send the summary
5. Clean up — kill tmux session (if still exists) + remove log file + remove temp files (task file, launcher script, executor script) + remove watcher cron

### Cleanup checklist (mandatory after every session ends)

- [ ] `tmux kill-session -t <TMUX_NAME>` (safe: `tmux has-session -t <TMUX_NAME> 2>/dev/null && tmux kill-session -t <TMUX_NAME>`)
- [ ] `openclaw cron rm <WATCHER_UUID>`
- [ ] `rm -f $LOG`
- [ ] `rm -f /tmp/task-*<SLUG>*.txt` (task file written by consumer skill)
- [ ] `rm -f /tmp/claude-runner-launch-*<TMUX_NAME>*.sh` (launcher script written by runner.sh)
- [ ] `rm -f /tmp/claude-runner-exec-*<TMUX_NAME>*.sh` (executor script, if used)
- [ ] Remove any consumer-specific temp files (e.g. blog-drafter's Phase 2 script, temp HTML — see consumer skill docs)
- [ ] Update `CLAUDE-SESSIONS.md` — mark as done/failed/killed
- [ ] Notify — on failure include reason + suggested fix; on success include summary
- [ ] Confirm all are gone (no orphans)

---

## Session Tracker

**File:** `$HOME/.openclaw/workspace/CLAUDE-SESSIONS.md`

Unified tracker for all Claude Code sessions — coding, blog, marketing, everything.

### Format

```markdown
| Type | Session | Watcher | Workdir/Post | Task | Status | Started |
|---|---|---|---|---|---|---|
| <emoji> <type> | `<TMUX_NAME>` | `<WATCHER_UUID>` | <workdir or post file> | <brief task> | <status> | <datetime CST> |
```

The Watcher column stores the cron job UUID for the session's watcher. This enables reliable cleanup (no guessing which cron to remove) and duplicate detection (check if a watcher UUID already exists for a session before creating). Use `-` for completed/cleaned sessions where the watcher has been removed.

### Type prefixes

| Type | Emoji | Prefix |
|---|---|---|
| Coding agent | `coding` | `claude-` |
| Blog drafter | `blog` | `blog-` |
| Marketing drafter | `mktg` | `mktg-` |

### Status values

| Status | Meaning |
|---|---|
| `Running` | Session is active |
| `Done` | Completed successfully (with summary) |
| `Failed` | Completed with errors (with reason) |
| `Killed` | Manually terminated |

### Rules

- **On launch:** Add a row
- **On completion:** Update status to done/failed with a brief result summary
- **On kill:** Update status to killed
- **Cleanup:** Remove completed/failed/killed rows after 24h or when acknowledged

---

## Orphan Prevention (crash / OOM / unexpected death)

The watcher cron is the safety net. If the tmux session dies unexpectedly (crash, OOM kill, host restart), the watcher will detect the missing session on its next poll and execute the full cleanup checklist — including temp file removal. The watcher MUST NOT assume a missing session means clean completion; it checks log freshness first (see "Session not found" learning below).

**What the watcher does on unexpected death:**

1. Detect `tmux has-session` returns non-zero (session gone)
2. Check log file mtime — if modified within 60s, back off (might still be writing)
3. Read the log tail for errors or completion signals
4. Run the full cleanup checklist (temp files, cron self-removal, log deletion)
5. Update `CLAUDE-SESSIONS.md` with `Failed` status and reason
6. Notify with the failure context

**What the watcher cannot recover:** If the watcher cron itself is lost (e.g. OpenClaw restart clears cron state), orphaned tmux sessions and temp files will persist. Manual spot-checks (`tmux ls`) are the last line of defense.

---

## Drop-In Commands

### Human operator (direct terminal access)

```bash
# Live view — type directly to Claude Code
tmux attach -t <TMUX_NAME>

# Ctrl+B D to detach safely (session keeps running)
```

### Agent (non-invasive monitoring)

```bash
# Recent terminal state
tmux capture-pane -t <TMUX_NAME> -p -S -100

# Persistent log
tail -50 <LOG>

# Send input to Claude Code
tmux send-keys -t <TMUX_NAME> 'yes' Enter      # send a response
tmux send-keys -t <TMUX_NAME> '' Enter           # send Enter key only
tmux send-keys -t <TMUX_NAME> 'C-c'              # send Ctrl+C

# Kill session
tmux kill-session -t <TMUX_NAME>
openclaw cron rm <WATCHER_UUID> && rm -f <LOG>
```

### Conflict Protocol

- When the human operator is actively attached, the agent backs off from sending keys.
- The agent only auto-sends for known unambiguous prompts: directory trust Enter, well-known y/N confirmations.
- For anything ambiguous or requiring judgment, the agent notifies and waits.
- Human detaching (`Ctrl+B D`) signals that the agent can resume normal interaction.

---

## Persistent Artifacts (Critical Design Principle)

**Background processes are ephemeral. Artifacts must not be.**

tmux sessions can disappear at any time — clean exit, crash, timeout, OOM kill, host restart. If the only record of what happened lives in the tmux pane, it's gone when the session is gone.

**Rule:** Every background session MUST write durable artifacts to disk via `script -qf`. The log file is the source of truth — not `tmux capture-pane`, which only shows recent terminal state.

---

## After Launch — What to Tell the User

Send **one message** that includes ALL of:

1. What's running, the workdir, and a brief task summary
2. The TMUX_NAME for the session
3. Drop-in command (exact, copy-pasteable): `tmux attach -t <ACTUAL_TMUX_NAME>`
4. `Ctrl+B D` to safely detach without killing the session
5. Natural language queries to ask the agent:
   - "How's session `<name>` going?" -> progress summary
   - "Show me logs for `<name>`" -> recent output
   - "Tell session `<name>` to focus on X" -> relay input
   - "Kill session `<name>`" -> terminate + cleanup
6. Watcher cron is running; notification will fire on completion

Then **move on**. Don't sit and watch.

---

## Rules

1. **Always use tmux** — Claude Code needs a terminal; tmux provides the PTY and enables shared access.
2. **Always use detached tmux sessions** for real work — `tmux new-session -d` keeps it running in the background.
3. **Always schedule a watcher cron (with dedup check)** — every background session gets monitoring. Always check `openclaw cron list | grep "$WATCHER_NAME"` before creating. Never create a second watcher for the same session.
4. **Always chain `openclaw system event`** — runner.sh handles this in the launcher script.
5. **Always use `script -qf` for persistent logs** — log file is the source of truth.
6. **Clean up after completion** — kill tmux + remove watcher cron + delete log file.
7. **Orchestrate, don't hand-code** — if Claude Code fails/hangs, respawn or ask the user.
8. **Be patient** — don't kill sessions because they're "slow."
9. **`--dangerously-skip-permissions`** — required for Claude Code to run bash commands without prompting.
10. **Use `~/Projects/claude-tmp/` for temp work** — pre-trusted directory for sessions without their own project. Each session gets its own subdirectory.
11. **Parallel is OK** — run many sessions at once for batch work.
12. **NEVER start agents in `~/.openclaw/`** — it'll read soul docs and get weird ideas.
13. **NEVER checkout branches in your live OpenClaw project directory** — that's the LIVE instance.

---

## Learnings

- **PTY is essential:** Claude Code is an interactive terminal app. Without a PTY, output breaks or agent hangs.
- **Claude Code `-p` buffers everything** — no streaming, no drop-in. Always launch interactively (no `-p`).
- **`--dangerously-skip-permissions`** is required for background non-interactive bash access.
- **ACP runtime sessions are unreliable** (as of Mar 2026) — tmux-based sessions via this skill are the preferred path.
- **Two-layer completion detection** — chained `openclaw system event` (instant) + watcher cron (backup).
- **Watcher crons use sonnet** — simple observational work should always use sonnet.
- **Always clean up** — every session end must kill tmux + remove watcher cron + delete log file.
- **tmux pane output is ephemeral** — `tmux capture-pane` only shows recent terminal state. NEVER rely solely on it for completion detection. Always persist output to disk via `script`.
- **Auto-accept directory trust prompt** — runner.sh polls the tmux pane for up to 30s, sends Enter when the prompt appears. The old blind `sleep 1 && send Enter` was unreliable.
- **Temp files are part of cleanup** — task files (`/tmp/task-*`), launcher scripts (`/tmp/claude-runner-launch-*`), and executor scripts (`/tmp/claude-runner-exec-*`) must be removed alongside the log file. Consumer skills with additional temp files (e.g. blog-drafter's Phase 2 script, temp HTML) must document their own temp file cleanup in their SKILL.md.
- **"Session not found" does not mean automatic completion** — a missing tmux session could mean completion, crash, or cleanup. The watcher must check log file freshness (`stat --format=%Y`) before declaring completion. If the log was modified within 60 seconds, back off.
- **Watcher self-removal requires UUID, not name** — `openclaw cron rm` takes the job UUID. Embed the UUID in the watcher message at creation time via a two-step create -> update pattern.
- **Persistent artifacts pattern** — any background skill must write durable artifacts to disk. If it runs in the background, its output survives on disk.
- **tmux replaces exec pty:true** — Named tmux sessions give both human and agent simultaneous access. No process sessionId needed.
- **`script -qf` still runs inside tmux** — tmux is the outer shell; `script` captures everything inside.
- **`openclaw system event` still chains correctly** — the compound command inside `script` fires the event when claude exits.
- **`tmux has-session` replaces `process action:poll`** — exit code 0 = running, 1 = gone.
- **Watcher dedup is mandatory** — the orchestrating LLM can create duplicate watchers for the same session (observed: two `watch-claude-runner-fix-*` crons, one in error state, neither cleaning up). Root cause: no check before `openclaw cron add`. Fix: runner.sh now outputs `WATCHER_NAME` — always run `openclaw cron list | grep "$WATCHER_NAME"` before creating. If it exists, skip creation. The session tracker also records the watcher UUID for cleanup.
- **Idle detection requires two signals** — log staleness alone is NOT enough. Claude Code's thinking spinner uses ANSI escape sequences that do NOT append to the `script -qf` log. A stale log could mean active thinking. Idle requires BOTH: (1) log mtime >2 min stale, AND (2) the input prompt visible in `tmux capture-pane`. Idle + no errors = auto-kill. Idle + errors = notify human.
- **Conflict protocol** — agent only auto-sends for known unambiguous prompts. Anything ambiguous -> notify + wait for human.
- **Launcher script pattern** — write task to file, write launcher to script, tmux runs `bash $LAUNCHER`. Avoids all quoting issues. The launcher can be inspected and re-run manually.
- **`--on-success` for Phase 2 chaining** — consumer skills that need post-processing (e.g. blog-drafter Ghost upload) should pass `--on-success <phase2-script>` to runner.sh instead of writing a custom launcher. runner.sh chains `bash <script>` on clean exit. This keeps all launcher logic in one place and prevents consumers from accidentally reintroducing the inline-TASK bug.
- **Never write a custom launcher that does `TASK=$(cat file)` inline in `script -c`** — this was the original bug. When task content contains shell metacharacters (`$()`, backticks, `<`, `>`), they get interpreted by the shell parsing the `-c` string, causing parse errors or silent command execution. The executor pattern (runner.sh's default) avoids this entirely: task content is read inside the executor script with `set -f`, then passed as a quoted argument to `exec claude`. It never touches a shell `-c` string.
- **No backticks in task files** — when loaded via `TASK=$(cat $TASK_FILE)`, backticks are interpreted as command substitutions. Use markdown code fences or avoid them.
- **`script -c "..."` spawns a new zsh shell that glob-expands its argument** — passing task content inline in the `-c` string causes zsh to glob-expand characters like `<`, `>`, `*`, `?`. Fix: use the two-script pattern. Write an EXECUTOR script that reads the task file with `set -f` (noglob) and runs claude. Pass only the executor's *path* (no special chars) to `script -c`. Task content never appears as a literal string in any shell `-c` argument.
