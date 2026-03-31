# Agents

## Instructions for all agents

When working in this repo, document any major concepts you introduce or discover in this file under the relevant section.

---

## Backend

The backend consists of two Python scripts that fetch rate-limit utilisation from their respective APIs and print a single integer (0–100) representing **remaining** usage to stdout. These are consumed by the tmux bar script (`scripts/claude_usage.sh`).

### `scripts/fetch_claude_usage.py`

**Auth:** Reads the Claude Code OAuth token from `~/.claude/.credentials.json` (`claudeAiOauth.accessToken`). This file is written by `claude` on login and uses the `oauth-2025-04-20` beta header.

**How usage is fetched:** There is no dedicated usage endpoint. Instead, the script makes a minimal POST to `api.anthropic.com/v1/messages` (1 token, cheapest model: `claude-haiku-4-5-20251001`) and reads the rate-limit headers from the HTTP response:

- `anthropic-ratelimit-unified-5h-utilization` — fraction used of the 5-hour rolling window
- `anthropic-ratelimit-unified-7d-utilization` — fraction used of the 7-day rolling window
- `anthropic-ratelimit-unified-representative-claim` — which window is currently the binding constraint (`five_hour` or `seven_day`)

In `auto` mode (default), the script uses the representative claim to pick the right window. The fraction is subtracted from 1 and multiplied by 100 to get remaining percentage.

**Options:** `--window 5h|7d|auto`, `--raw` (print all rate-limit headers), `--timeout`, `--credentials-file`

### `scripts/fetch_codex_usage.py`

**Auth:** Reads `~/.codex/auth.json` (`tokens.access_token` + `tokens.account_id`). The account ID is sent as a `ChatGPT-Account-Id` header alongside the Bearer token.

**How usage is fetched:** Hits a dedicated endpoint — `https://chatgpt.com/backend-api/wham/usage` — which returns a JSON body with `rate_limit.primary_window.used_percent` (5-hour window) and `rate_limit.secondary_window.used_percent` (7-day window). The `used_percent` value is subtracted from 100 to get remaining percentage.

**Options:** `--window primary|secondary`, `--raw` (print full JSON), `--timeout`, `--proxy-url`, `--auth-file`

### Tmux integration

`scripts/claude_usage.sh` calls `fetch_claude_usage.py` by default. The data source can be overridden by setting `@claude_usage_cmd` in `tmux.conf`:

```
set -g @claude_usage_cmd "python3 /path/to/scripts/fetch_codex_usage.py"
```

The plugin entrypoint is `claude-usage.tmux`, which replaces the `#{claude_usage}` placeholder in `status-right`/`status-left` with a call to `claude_usage.sh`.
