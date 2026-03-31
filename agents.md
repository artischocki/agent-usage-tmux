# Agents

## Frontend

**Branch:** `frontend` (worktree at `.claude/worktrees/frontend`)
**Scope:** tmux status bar rendering — visual output only, no data fetching.

### What it owns

- `claude-usage.tmux` — plugin entrypoint. Replaces `#{claude_usage}`, `#{codex_usage}`, and `#{agent_usage}` in `status-right`/`status-left` with `#(scripts/agent_usage.sh <agent>)` calls.
- `scripts/agent_usage.sh` — renders the progress bar. Accepts `claude`, `codex`, or no argument (renders both side by side).

### How the bar works

- tqdm-style: `✻ 42%|████▍     |` — `█` for filled, spaces for empty, `|` as borders
- Sub-character precision using `▏▎▍▌▋▊▉` (1/8-cell steps via awk float math)
- Claude: orange (`colour214`), icon `✻`
- Codex: white (`colour255`), icon `>_`

### Data source interface

The script reads a tmux option per agent:
- `@agent_usage_cmd_claude` — shell command that prints 0–100
- `@agent_usage_cmd_codex` — shell command that prints 0–100
- Falls back to `@agent_usage_cmd` (legacy) for claude if the above is unset

The frontend does **not** implement data fetching. Leave `scripts/fetch_*.py` and `scripts/claude_usage.sh` to the backend agent.

### Local dev

The TPM plugin dir is symlinked to the repo root:
```
~/.config/tmux/plugins/agent-usage-tmux -> ~/code/agent-usage-tmux
```
Changes are live after: `tmux source ~/.config/tmux/tmux.conf`
