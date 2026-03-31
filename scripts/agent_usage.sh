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
    local width=10

    # clamp
    (( pct < 0 )) && pct=0
    (( pct > 100 )) && pct=100

    local filled=$(( pct * width / 100 ))
    local empty=$(( width - filled ))

    local bar=""
    for (( i=0; i<filled; i++ ));  do bar+="█"; done
    for (( i=0; i<empty;  i++ ));  do bar+="░"; done

    # color: green <50, yellow <80, red >=80
    local color
    if   (( pct >= 80 )); then color="red"
    elif (( pct >= 50 )); then color="yellow"
    else                       color="green"
    fi

    printf "#[fg=%s][%s] %d%%#[default]" "$color" "$bar" "$pct"
}

pct=$(get_percentage)
render_bar "$pct"
