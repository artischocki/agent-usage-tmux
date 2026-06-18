# agent-usage-tmux

Tmux status bar plugin for showing Claude, Codex, and Kimi usage as compact progress bars.

![Plugin preview](docs/preview.png)

## Install

Add the plugin with TPM:

```tmux
set -g @plugin 'artischocki/agent-usage-tmux'
set -g status-right "#{claude_usage} | #{codex_usage} | #{kimi_usage} "
```

Then reload tmux or install plugins with TPM.

## What It Shows

- Remaining usage percentage
- Time until reset
- Separate bars for Claude, Codex, and Kimi

Current format:

```text
✻ 42% ████▍      03:02
>_ 88% █████▎    00:44
K2 60% ███▌      04:10
```

## Configuration

By default, the plugin fetches usage from:

- `scripts/fetch_claude_usage.py`
- `scripts/fetch_codex_usage.py`
- `scripts/fetch_kimi_usage.py`

Optional tmux overrides:

```tmux
set -g @agent_usage_cmd_claude "python3 /path/to/custom_claude_percent.py"
set -g @agent_usage_cmd_codex "python3 /path/to/custom_codex_percent.py"
set -g @agent_usage_cmd_kimi "python3 /path/to/custom_kimi_percent.py"

set -g @agent_usage_reset_cmd_claude "python3 /path/to/custom_claude_reset.py"
set -g @agent_usage_reset_cmd_codex "python3 /path/to/custom_codex_reset.py"
set -g @agent_usage_reset_cmd_kimi "python3 /path/to/custom_kimi_reset.py"
```

Hide the leading icons:

```tmux
set -g @agent_usage_show_icons off
```

That changes the display to:

```text
42% ████▍      03:02
88% █████▎    00:44
60% ███▌      04:10
```

## Development

Useful local commands:

```bash
python3 scripts/fetch_claude_usage.py
python3 scripts/fetch_claude_usage.py --field reset_in
python3 scripts/fetch_codex_usage.py
python3 scripts/fetch_codex_usage.py --field reset_in
python3 scripts/fetch_kimi_usage.py
python3 scripts/fetch_kimi_usage.py --field reset_in
```
