#!/usr/bin/env bash

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

count_usage_width() {
    local string="$1"
    local total=0
    local token
    local tail

    for token in "#{agent_usage}" "#{claude_usage}" "#{codex_usage}" "#{kimi_usage}"; do
        tail="$string"
        while [[ "$tail" == *"$token"* ]]; do
            case "$token" in
                "#{agent_usage}") total=$(( total + 42 )) ;;
                "#{claude_usage}") total=$(( total + 13 )) ;;
                "#{codex_usage}") total=$(( total + 14 )) ;;
                "#{kimi_usage}") total=$(( total + 14 )) ;;
            esac
            tail="${tail#*"$token"}"
        done
    done

    echo "$total"
}

do_interpolation() {
    local string="$1"
    # individual bars
    string="${string/\#\{claude_usage\}/#($CURRENT_DIR/scripts/agent_usage.sh claude)}"
    string="${string/\#\{codex_usage\}/#($CURRENT_DIR/scripts/agent_usage.sh codex)}"
    string="${string/\#\{kimi_usage\}/#($CURRENT_DIR/scripts/agent_usage.sh kimi)}"
    # combined (backwards compat)
    string="${string/\#\{agent_usage\}/#($CURRENT_DIR/scripts/agent_usage.sh)}"
    echo "$string"
}

ensure_status_length() {
    local option="$1"
    local original_value="$2"
    local extra_width
    local length_option="${option}-length"
    local current_length
    local min_length

    extra_width="$(count_usage_width "$original_value")"
    (( extra_width > 0 )) || return

    current_length="$(tmux show-option -gqv "$length_option" 2>/dev/null)"
    [[ "$current_length" =~ ^[0-9]+$ ]] || current_length=0

    # Leave room for the existing clock/text to the right of the usage bars.
    min_length=$(( extra_width + 16 ))
    (( current_length >= min_length )) && return

    tmux set-option -gq "$length_option" "$min_length"
}

update_tmux_option() {
    local option="$1"
    local value
    value="$(tmux show-option -gqv "$option")"
    local new_value
    new_value="$(do_interpolation "$value")"
    ensure_status_length "$option" "$value"
    tmux set-option -gq "$option" "$new_value"
}

main() {
    tmux set-option -g status-interval 20
    update_tmux_option "status-right"
    update_tmux_option "status-left"
}

main
