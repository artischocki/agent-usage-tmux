# agent-usage-tmux

Tmux status bar plugin for showing Claude and Codex usage as compact progress bars.

![Plugin preview](docs/preview.png)

## Install

Add the plugin with TPM:

```tmux
set -g @plugin 'artischocki/agent-usage-tmux'
set -g status-right "#{claude_usage} | #{codex_usage} "
```

Then reload tmux or install plugins with TPM.

## What It Shows

- Remaining usage percentage
- Time until reset
- Separate bars for Claude and Codex

Current format:

```text
✻ 42% ████▍      03:02
>_ 88% █████▎    00:44
```

## Clicking a bar

Every bar is a mouse range, so tmux can tell which one was hit. Needs
`set -g mouse on`.

- **Left click** flips that bar between the 5-hour window and the weekly one.
  While the weekly window is up, a `w` sits in front of the percentage and the
  reset is written as days:

  ```text
  ✻ 42% ████▍      03:02      5-hour window
  ✻ w80% ████▊     2d06h      weekly window
  ```

- **Right click** opens a context menu for that bar:

  | Entry | Key | Does |
  |-------|-----|------|
  | Detailed stats | `s` | popup with every window at once: free/used, bar, reset time, status, raw headers |
  | 5-hour window  | `5` | show that window in the status line |
  | Weekly window  | `w` | show that window in the status line |
  | Refresh now    | `r` | refetch instead of waiting for the next `status-interval` |

Clicks next to a bar keep doing whatever they did before: the bindings remember
the previous `MouseDown1Status` / `MouseDown3Status` command and fall back to
it, so the window list still works and other status-line plugins that bind the
same keys survive.

Which window a bar shows lives in `@agent_usage_window_claude` /
`@agent_usage_window_codex` (`5h` or `weekly`) and can be preset:

```tmux
set -g @agent_usage_window_claude weekly
```

Custom `@agent_usage_cmd_*` commands are called exactly as written - the window
flag only goes to the built-in fetchers.

## Configuration

By default, the plugin fetches usage from:

- `scripts/fetch_claude_usage.py`
- `scripts/fetch_codex_usage.py`

Optional tmux overrides:

```tmux
set -g @agent_usage_cmd_claude "python3 /path/to/custom_claude_percent.py"
set -g @agent_usage_cmd_codex "python3 /path/to/custom_codex_percent.py"

set -g @agent_usage_reset_cmd_claude "python3 /path/to/custom_claude_reset.py"
set -g @agent_usage_reset_cmd_codex "python3 /path/to/custom_codex_reset.py"
```

Hide the leading icons:

```tmux
set -g @agent_usage_show_icons off
```

That changes the display to:

```text
42% ████▍      03:02
88% █████▎    00:44
```

## Development

Useful local commands:

```bash
python3 scripts/fetch_claude_usage.py
python3 scripts/fetch_claude_usage.py --field reset_in
python3 scripts/fetch_codex_usage.py
python3 scripts/fetch_codex_usage.py --field reset_in

python3 scripts/usage_stats.py claude    # the page behind "Detailed stats"
scripts/agent_usage.sh claude weekly     # one bar, weekly window
scripts/usage_menu.sh toggle claude      # what a left click does
```
