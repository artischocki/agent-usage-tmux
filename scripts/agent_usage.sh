#!/usr/bin/env bash
# Usage: agent_usage.sh [claude|codex] [5h|weekly]
#        agent_usage.sh both [claude-window] [codex-window]
# Defaults to showing both bars when no argument is given.
#
# The second argument picks the rate-limit window; without it the tmux option
# @agent_usage_window_<agent> decides (see usage_menu.sh, which flips it on a
# click). Each bar is wrapped in a '#[range=user|au-<agent>]' so tmux can tell
# the key bindings which bar was clicked.
#
# Trailing arguments beyond the documented ones are ignored on purpose: the
# status line appends a nonce there, and a changed command string is what makes
# tmux start a fresh #() job instead of reusing the cached output.

AGENT="${1:-}"
WINDOW="${2:-}"

declare -A ICONS=(
    [claude]="✻"
    [codex]=">_"
)

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

declare -A DEFAULTS=(
    [claude]="python3 $SCRIPT_DIR/fetch_claude_usage.py"
    [codex]="python3 $SCRIPT_DIR/fetch_codex_usage.py"
)

declare -A DEFAULT_RESETS=(
    [claude]="python3 $SCRIPT_DIR/fetch_claude_usage.py --field reset_in"
    [codex]="python3 $SCRIPT_DIR/fetch_codex_usage.py --field reset_in"
)

# Both fetchers know two windows, they just spell them differently.
declare -A WINDOW_FLAGS=(
    [claude:5h]="5h"      [claude:weekly]="7d"
    [codex:5h]="primary"  [codex:weekly]="secondary"
)

# 5h unless the argument or the tmux option says otherwise.
get_window() {
    local agent="$1"
    local window="$2"

    if [[ -z "$window" ]]; then
        window="$(tmux show-option -gqv "@agent_usage_window_${agent}" 2>/dev/null)"
    fi

    case "$window" in
        weekly|week|7d|secondary) echo "weekly" ;;
        *)                        echo "5h" ;;
    esac
}

show_icons() {
    local value
    value="$(tmux show-option -gqv @agent_usage_show_icons 2>/dev/null)"
    if [[ -z "$value" ]]; then
        value="$(tmux show-option -gqv @agent_usage_disable_icons 2>/dev/null)"
        case "$value" in
            1|yes|true|on) return 1 ;;
        esac
        return 0
    fi

    case "$value" in
        0|no|false|off) return 1 ;;
    esac
    return 0
}

# The window flag only goes to the built-in fetchers - a command someone
# configured themselves is called exactly as they wrote it.
get_percentage() {
    local agent="$1"
    local window="$2"
    local cmd
    cmd="$(tmux show-option -gqv "@agent_usage_cmd_${agent}" 2>/dev/null)"
    if [[ -z "$cmd" ]]; then
        # fall back to legacy @agent_usage_cmd for claude
        [[ "$agent" == "claude" ]] && cmd="$(tmux show-option -gqv @agent_usage_cmd 2>/dev/null)"
    fi
    if [[ -z "$cmd" ]]; then
        cmd="${DEFAULTS[$agent]} --window ${WINDOW_FLAGS[${agent}:${window}]}"
    fi
    eval "$cmd" 2>/dev/null || echo "0"
}

get_reset_in() {
    local agent="$1"
    local window="$2"
    local cmd
    cmd="$(tmux show-option -gqv "@agent_usage_reset_cmd_${agent}" 2>/dev/null)"
    if [[ -z "$cmd" ]]; then
        [[ "$agent" == "claude" ]] && cmd="$(tmux show-option -gqv @agent_usage_reset_cmd 2>/dev/null)"
    fi
    if [[ -z "$cmd" ]]; then
        cmd="${DEFAULT_RESETS[$agent]} --window ${WINDOW_FLAGS[${agent}:${window}]}"
    fi
    eval "$cmd" 2>/dev/null || echo "0"
}

# HH:MM as before; the weekly window resets days away, where '3d04h' beats
# a three-digit hour count.
format_reset() {
    local reset_in="$1"
    local days hours minutes

    [[ "$reset_in" =~ ^[0-9]+$ ]] || reset_in=0
    days=$(( reset_in / 86400 ))
    hours=$(( (reset_in % 86400) / 3600 ))
    minutes=$(( (reset_in % 3600) / 60 ))
    if (( days > 0 )); then
        printf "%dd%02dh" "$days" "$hours"
    else
        printf "%02d:%02d" "$hours" "$minutes"
    fi
}

render_bar() {
    local agent="$1"
    local pct="$2"
    local reset_label="$3"
    local window="${4:-5h}"
    local width=6
    local empty_bg="colour236"
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
        codex)  color="colour250" ;;  # soft light gray
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

    local icon_prefix=""
    if show_icons; then
        icon_prefix="${ICONS[$agent]} "
    fi

    # 'w' in front of the percentage: the bar is showing the weekly window.
    local window_tag=""
    [[ "$window" == "weekly" ]] && window_tag="w"

    printf "#[fg=%s,bold]%s%s%d%%#[default] #[fg=%s,bg=%s]%s%s#[fg=%s,bg=%s]%s#[default] #[fg=%s,bold]%s#[default]" \
        "$color" "$icon_prefix" "$window_tag" "$pct" "$color" "$empty_bg" "$bar_on" "$partial" "$empty_bg" "$empty_bg" "$bar_off" "$color" "$reset_label"
}

render_agent() {
    local agent="$1"
    local window
    local pct
    local reset_in
    local reset_label
    window=$(get_window "$agent" "${2:-}")
    pct=$(get_percentage "$agent" "$window")
    reset_in=$(get_reset_in "$agent" "$window")
    reset_label=$(format_reset "$reset_in")

    # Mouse range around the whole bar: a click in here reaches the bindings
    # in agent-usage.tmux with #{mouse_status_range} = 'au-<agent>'. Only
    # '#[norange]' ends it - the '#[default]' inside just resets the colours.
    # (No colon in the name: tmux's #{s/…/…/:…} splits its arguments on it.)
    printf "#[range=user|au-%s]" "$agent"
    render_bar "$agent" "$pct" "$reset_label" "$window"
    printf "#[norange]"
}

case "$AGENT" in
    claude|codex) render_agent "$AGENT" "$WINDOW" ;;
    *)
        # Both bars: second argument is claude's window, third codex's.
        render_agent "claude" "$WINDOW"
        printf " "
        render_agent "codex" "${3:-}"
        ;;
esac
