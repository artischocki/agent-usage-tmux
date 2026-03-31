#!/usr/bin/env bash

# Returns a usage percentage (0-100).
# Set @agent_usage_cmd in tmux.conf to a command that outputs the percentage.
# Example: set -g @agent_usage_cmd "cat ~/.claude/usage_percent"
get_percentage() {
    local cmd
    cmd="$(tmux show-option -gqv @agent_usage_cmd 2>/dev/null)"
    if [[ -n "$cmd" ]]; then
        eval "$cmd" 2>/dev/null
    else
        echo "0"
    fi
}

render_bar() {
    local pct="$1"
    local width=15

    (( pct < 0 )) && pct=0
    (( pct > 100 )) && pct=100

    local filled=$(( pct * width / 100 ))
    local empty=$(( width - filled ))

    local color
    if   (( pct >= 80 )); then color="colour160"
    elif (( pct >= 50 )); then color="colour214"
    else                       color="colour71"
    fi

    local bar_on="" bar_off=""
    for (( i=0; i<filled; i++ )); do bar_on+="█"; done
    for (( i=0; i<empty;  i++ )); do bar_off+=" "; done

    # tqdm style:  42%|████████       |
    printf "#[fg=%s,bold]%3d%%#[nobold,fg=colour240]|#[fg=%s]%s#[fg=colour240]%s|#[default]" \
        "$color" "$pct" "$color" "$bar_on" "$bar_off"
}

pct=$(get_percentage)
render_bar "$pct"
