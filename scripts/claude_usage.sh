#!/usr/bin/env bash

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DEFAULT_CMD="python3 ${CURRENT_DIR}/fetch_claude_usage.py"

# Returns a usage percentage (0-100).
# Override the data source by setting @claude_usage_cmd in tmux.conf.
# Default: fetch_claude_usage.py reads the Claude OAuth token and queries the
# Anthropic API, caching the result for 5 minutes.
# Example override: set -g @claude_usage_cmd "cat ~/.claude/usage_percent"
get_percentage() {
    local cmd
    cmd="$(tmux show-option -gqv @claude_usage_cmd 2>/dev/null)"
    if [[ -n "$cmd" ]]; then
        eval "$cmd" 2>/dev/null
    else
        eval "$DEFAULT_CMD" 2>/dev/null
    fi
}

render_bar() {
    local pct="$1"
    local width=15
    local sub_chars=('▏' '▎' '▍' '▌' '▋' '▊' '▉')  # 1/8 … 7/8

    (( pct < 0 )) && pct=0
    (( pct > 100 )) && pct=100

    # floating-point split: full cells + fractional remainder index (0-7)
    read -r full partial_idx <<< "$(awk -v p="$pct" -v w="$width" 'BEGIN {
        filled = p * w / 100
        full   = int(filled)
        idx    = int((filled - full) * 8)
        print full, idx
    }')"

    local color
    if   (( pct >= 80 )); then color="colour160"
    elif (( pct >= 50 )); then color="colour214"
    else                       color="colour71"
    fi

    local bar_on=""
    for (( i=0; i<full; i++ )); do bar_on+="█"; done

    local partial="" empty
    if (( partial_idx > 0 )); then
        partial="${sub_chars[$(( partial_idx - 1 ))]}"
        empty=$(( width - full - 1 ))
    else
        empty=$(( width - full ))
    fi

    local bar_off=""
    for (( i=0; i<empty; i++ )); do bar_off+=" "; done

    printf "#[fg=%s,bold]%3d%%#[nobold,fg=colour240]|#[fg=%s]%s%s#[fg=colour240]%s|#[default]" \
        "$color" "$pct" "$color" "$bar_on" "$partial" "$bar_off"
}

pct=$(get_percentage)
render_bar "$pct"
