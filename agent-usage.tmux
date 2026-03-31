#!/usr/bin/env bash

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

do_interpolation() {
    local string="$1"
    # individual bars
    string="${string/\#\{claude_usage\}/#($CURRENT_DIR/scripts/agent_usage.sh claude)}"
    string="${string/\#\{codex_usage\}/#($CURRENT_DIR/scripts/agent_usage.sh codex)}"
    # combined (backwards compat)
    string="${string/\#\{agent_usage\}/#($CURRENT_DIR/scripts/agent_usage.sh)}"
    echo "$string"
}

update_tmux_option() {
    local option="$1"
    local value
    value="$(tmux show-option -gqv "$option")"
    local new_value
    new_value="$(do_interpolation "$value")"
    tmux set-option -gq "$option" "$new_value"
}

main() {
    update_tmux_option "status-right"
    update_tmux_option "status-left"
}

main
