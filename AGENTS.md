# Agents

## Instructions for all agents

When working in this repo, document any major concepts you introduce or discover in this file under the relevant section.

---

## Frontend

**Branch:** `frontend` (worktree at `.claude/worktrees/frontend`)
**Scope:** tmux status bar rendering - visual output only, no data fetching.

### What it owns

- `agent-usage.tmux` - plugin entrypoint. Replaces `#{claude_usage}`, `#{codex_usage}`, and `#{agent_usage}` in `status-right`/`status-left` with `#(scripts/agent_usage.sh <agent>)` calls.
- `agent-usage.tmux` also raises `status-right-length` / `status-left-length` when a usage placeholder is present, so adjacent text like the clock does not get clipped.
- `scripts/agent_usage.sh` - renders the progress bar. Accepts `claude`, `codex`, or no argument (renders both side by side).

### How the bar works

- tqdm-style: `✻ 42% ████▍      03:02` - `█` for filled, spaces for empty, with a dim background on the unfilled portion
- Sub-character precision using `▏▎▍▌▋▊▉` (1/8-cell steps via awk float math)
- Claude: orange (`colour214`), icon `✻`
- Codex: soft light gray (`colour250`), icon `>_`

### Data source interface

The script reads a tmux option per agent:
- `@agent_usage_cmd_claude` - shell command that prints 0-100
- `@agent_usage_cmd_codex` - shell command that prints 0-100
- `@agent_usage_reset_cmd_claude` - shell command that prints seconds until reset
- `@agent_usage_reset_cmd_codex` - shell command that prints seconds until reset
- `@agent_usage_show_icons` - `on|off`, controls whether the combined multi-agent bar shows the leading agent icons
- Falls back to `@agent_usage_cmd` (legacy) for claude if the above is unset
- Falls back to `@agent_usage_reset_cmd` (legacy) for claude if the above is unset
- Falls back to `@agent_usage_disable_icons` (legacy inverse toggle) if `@agent_usage_show_icons` is unset

The frontend does **not** implement data fetching. Leave `scripts/fetch_*.py` and `scripts/claude_usage.sh` to the backend agent.

### Local dev

The TPM plugin dir is symlinked to the repo root:
```
~/.config/tmux/plugins/agent-usage-tmux -> ~/code/agent-usage-tmux
```
Changes are live after: `tmux source ~/.config/tmux/tmux.conf`

## Backend

The backend consists of two Python scripts that fetch rate-limit utilisation from their respective APIs and print a single integer (0-100) representing **remaining** usage to stdout. These are consumed by the tmux bar script (`scripts/claude_usage.sh`).

### `scripts/fetch_claude_usage.py`

**Auth:** Reads the Claude Code OAuth token from `~/.claude/.credentials.json` (`claudeAiOauth.accessToken`). This file is written by `claude` on login and uses the `oauth-2025-04-20` beta header.

**How usage is fetched:** There is no dedicated usage endpoint. Instead, the script makes a minimal POST to `api.anthropic.com/v1/messages` (1 token, cheapest model: `claude-haiku-4-5-20251001`) and reads the rate-limit headers from the HTTP response:

- `anthropic-ratelimit-unified-5h-utilization` - fraction used of the 5-hour rolling window
- `anthropic-ratelimit-unified-7d-utilization` - fraction used of the 7-day rolling window
- `anthropic-ratelimit-unified-representative-claim` - which window is currently the binding constraint (`five_hour` or `seven_day`)

In `auto` mode (default), the script uses the representative claim to pick the right window. The fraction is subtracted from 1 and multiplied by 100 to get remaining percentage.

**Options:** `--window 5h|7d|auto`, `--field percent|reset_at|reset_in`, `--raw` (print all rate-limit headers), `--timeout`, `--credentials-file`

### `scripts/fetch_codex_usage.py`

**Auth:** Reads `~/.codex/auth.json` (`tokens.access_token` + `tokens.account_id`). The account ID is sent as a `ChatGPT-Account-Id` header alongside the Bearer token.

**How usage is fetched:** Hits a dedicated endpoint - `https://chatgpt.com/backend-api/wham/usage` - which returns a JSON body with `rate_limit.primary_window.used_percent` (5-hour window) and `rate_limit.secondary_window.used_percent` (7-day window). The `used_percent` value is subtracted from 100 to get remaining percentage.

**Options:** `--window primary|secondary`, `--field percent|reset_at|reset_in`, `--raw` (print full JSON), `--timeout`, `--proxy-url`, `--auth-file`

### Tmux integration

`scripts/claude_usage.sh` calls `fetch_claude_usage.py` by default. The data source can be overridden by setting `@claude_usage_cmd` in `tmux.conf`:

```
set -g @claude_usage_cmd "python3 /path/to/scripts/fetch_codex_usage.py"
```

The plugin entrypoint is `agent-usage.tmux`, which replaces the `#{claude_usage}` placeholder in `status-right`/`status-left` with a call to `claude_usage.sh`.
