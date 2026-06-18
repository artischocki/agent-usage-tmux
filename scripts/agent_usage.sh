#!/usr/bin/env bash
# Usage: agent_usage.sh [claude|codex|kimi]
# Defaults to showing all bars when no argument is given.

AGENT="${1:-}"

declare -A ICONS=(
    [claude]="✻"
    [codex]=">_"
    [kimi]="K2"
)

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

declare -A DEFAULTS=(
    [claude]="python3 $SCRIPT_DIR/fetch_claude_usage.py"
    [codex]="python3 $SCRIPT_DIR/fetch_codex_usage.py"
    [kimi]="python3 $SCRIPT_DIR/fetch_kimi_usage.py"
)

declare -A DEFAULT_RESETS=(
    [claude]="python3 $SCRIPT_DIR/fetch_claude_usage.py --field reset_in"
    [codex]="python3 $SCRIPT_DIR/fetch_codex_usage.py --field reset_in"
    [kimi]="python3 $SCRIPT_DIR/fetch_kimi_usage.py --field reset_in"
)

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

get_percentage() {
    local agent="$1"
    local cmd
    cmd="$(tmux show-option -gqv "@agent_usage_cmd_${agent}" 2>/dev/null)"
    if [[ -z "$cmd" ]]; then
        # fall back to legacy @agent_usage_cmd for claude
        [[ "$agent" == "claude" ]] && cmd="$(tmux show-option -gqv @agent_usage_cmd 2>/dev/null)"
    fi
    if [[ -z "$cmd" ]]; then
        cmd="${DEFAULTS[$agent]}"
    fi
    eval "$cmd" 2>/dev/null || echo "0"
}

get_reset_in() {
    local agent="$1"
    local cmd
    cmd="$(tmux show-option -gqv "@agent_usage_reset_cmd_${agent}" 2>/dev/null)"
    if [[ -z "$cmd" ]]; then
        [[ "$agent" == "claude" ]] && cmd="$(tmux show-option -gqv @agent_usage_reset_cmd 2>/dev/null)"
    fi
    if [[ -z "$cmd" ]]; then
        cmd="${DEFAULT_RESETS[$agent]}"
    fi
    eval "$cmd" 2>/dev/null || echo "0"
}

format_reset() {
    local reset_in="$1"
    local hours minutes

    [[ "$reset_in" =~ ^[0-9]+$ ]] || reset_in=0
    hours=$(( reset_in / 3600 ))
    minutes=$(( (reset_in % 3600) / 60 ))
    printf "%02d:%02d" "$hours" "$minutes"
}

render_bar() {
    local agent="$1"
    local pct="$2"
    local reset_label="$3"
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
        kimi)   color="colour81"  ;;  # cyan
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

    printf "#[fg=%s,bold]%s%d%%#[default] #[fg=%s,bg=%s]%s%s#[fg=%s,bg=%s]%s#[default] #[fg=%s,bold]%s#[default]" \
        "$color" "$icon_prefix" "$pct" "$color" "$empty_bg" "$bar_on" "$partial" "$empty_bg" "$empty_bg" "$bar_off" "$color" "$reset_label"
}

render_agent() {
    local agent="$1"
    local pct
    local reset_in
    local reset_label
    pct=$(get_percentage "$agent")
    reset_in=$(get_reset_in "$agent")
    reset_label=$(format_reset "$reset_in")
    render_bar "$agent" "$pct" "$reset_label"
}

case "$AGENT" in
    claude|codex|kimi) render_agent "$AGENT" ;;
    *)
        render_agent "claude"
        printf " "
        render_agent "codex"
        printf " "
        render_agent "kimi"
        ;;
esac
