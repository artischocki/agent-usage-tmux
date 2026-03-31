#!/usr/bin/env bash
# Usage: agent_usage.sh [claude|codex]
# Defaults to showing both bars when no argument is given.

AGENT="${1:-}"

declare -A ICONS=(
    [claude]="✦"
    [codex]=">_"
)

get_percentage() {
    local agent="$1"
    local cmd
    cmd="$(tmux show-option -gqv "@agent_usage_cmd_${agent}" 2>/dev/null)"
    if [[ -z "$cmd" ]]; then
        # fall back to legacy @agent_usage_cmd for claude
        [[ "$agent" == "claude" ]] && cmd="$(tmux show-option -gqv @agent_usage_cmd 2>/dev/null)"
    fi
    if [[ -n "$cmd" ]]; then
        eval "$cmd" 2>/dev/null
    else
        echo "0"
    fi
}

render_bar() {
    local agent="$1"
    local pct="$2"
    local width=10
    local sub_chars=('▏' '▎' '▍' '▌' '▋' '▊' '▉')

    (( pct < 0 )) && pct=0
    (( pct > 100 )) && pct=100

    read -r full partial_idx <<< "$(awk -v p="$pct" -v w="$width" 'BEGIN {
        filled = p * w / 100
        full   = int(filled)
        idx    = int((filled - full) * 8)
        print full, idx
    }')"

    local color
    case "$agent" in
        claude) color="colour214" ;;  # orange
        codex)  color="colour255" ;;  # white
        *)
            if   (( pct >= 80 )); then color="colour160"
            elif (( pct >= 50 )); then color="colour214"
            else                       color="colour71"
            fi ;;
    esac

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

    local icon="${ICONS[$agent]}"
    printf "#[fg=%s,bold]%s %3d%%#[nobold,fg=colour240]|#[fg=%s]%s%s#[fg=colour240]%s|#[default]" \
        "$color" "$icon" "$pct" "$color" "$bar_on" "$partial" "$bar_off"
}

render_agent() {
    local agent="$1"
    local pct
    pct=$(get_percentage "$agent")
    render_bar "$agent" "$pct"
}

case "$AGENT" in
    claude|codex) render_agent "$AGENT" ;;
    *)
        render_agent "claude"
        printf " "
        render_agent "codex"
        ;;
esac
