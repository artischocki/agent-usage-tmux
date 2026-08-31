#!/usr/bin/env bash

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

count_usage_width() {
    local string="$1"
    local total=0
    local token
    local tail

    for token in "#{agent_usage}" "#{claude_usage}" "#{codex_usage}"; do
        tail="$string"
        while [[ "$tail" == *"$token"* ]]; do
            # one column more than the bar needs, for the 'w' of the weekly window
            case "$token" in
                "#{agent_usage}") total=$(( total + 30 )) ;;
                "#{claude_usage}") total=$(( total + 14 )) ;;
                "#{codex_usage}") total=$(( total + 15 )) ;;
            esac
            tail="${tail#*"$token"}"
        done
    done

    echo "$total"
}

# The window options travel in the job's command string on purpose: tmux keys
# its #() jobs by that string, so flipping a bar to weekly starts a new job
# immediately instead of leaving the old window up until the next tick.
do_interpolation() {
    local string="$1"
    local claude_window="#{@agent_usage_window_claude}"
    local codex_window="#{@agent_usage_window_codex}"
    local nonce="#{@agent_usage_nonce}"   # bumped by the menu's 'Refresh now'
    # individual bars
    string="${string/\#\{claude_usage\}/#($CURRENT_DIR/scripts/agent_usage.sh claude $claude_window $nonce)}"
    string="${string/\#\{codex_usage\}/#($CURRENT_DIR/scripts/agent_usage.sh codex $codex_window $nonce)}"
    # combined (backwards compat)
    string="${string/\#\{agent_usage\}/#($CURRENT_DIR/scripts/agent_usage.sh both $claude_window $codex_window $nonce)}"
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

# Every placeholder above has to expand to something: an empty option would
# shift the remaining arguments of agent_usage.sh one to the left.
ensure_option() {
    local option="$1"
    local default="$2"
    [[ -n "$(tmux show-option -gqv "$option" 2>/dev/null)" ]] && return
    tmux set-option -gq "$option" "$default"
}

# --- mouse -----------------------------------------------------------------
#
# agent_usage.sh wraps each bar in '#[range=user|au-<agent>]'. A click inside
# such a range triggers the 'Status' mouse key and reports the range name in
# #{mouse_status_range}, so one binding can serve both bars and hand the agent
# on to usage_menu.sh. Clicks anywhere else must keep doing what they did
# before, hence the fall-back branch.

ON_BAR='#{m:au-*,#{mouse_status_range}}'

# What the key did before we touched it, remembered in an option so that
# re-sourcing the config does not nest our own binding inside itself.
saved_binding() {
    local key="$1"
    local option="$2"
    local fallback="$3"
    local saved current

    saved="$(tmux show-option -gqv "$option" 2>/dev/null)"
    if [[ -z "$saved" ]]; then
        current="$(tmux list-keys -T root "$key" 2>/dev/null | head -1 |
                   sed -E "s/^bind-key +-T +root +${key} +//")"
        [[ "$current" == *usage_menu.sh* ]] && current=""
        saved="${current:-$fallback}"
        tmux set-option -gq "$option" "$saved"
    fi
    printf '%s' "$saved"
}

bind_mouse() {
    local menu="$CURRENT_DIR/scripts/usage_menu.sh"
    local popup="display-popup -w 80% -h 80% -E"
    local left right context

    left="$(saved_binding MouseDown1Status @agent_usage_saved_mouse1 'select-window -t =')"
    right="$(saved_binding MouseDown3Status @agent_usage_saved_mouse3 'select-window -t =')"

    # -O keeps the menu up when the mouse button is released again; without it
    # the click that opens it would close it right away.
    context="display-menu -O -T '#[align=centre] #{s/^au-//:#{mouse_status_range}} usage ' -x M -y S \
        'Detailed stats' s \"$popup '$menu stats #{mouse_status_range}'\" \
        '' \
        '5-hour window'  5 \"run-shell -b '$menu window #{mouse_status_range} 5h'\" \
        'Weekly window'  w \"run-shell -b '$menu window #{mouse_status_range} weekly'\" \
        'Refresh now'    r \"run-shell -b '$menu refresh'\""

    tmux bind-key -n MouseDown1Status if-shell -F "$ON_BAR" \
        "run-shell -b '$menu toggle #{mouse_status_range}'" "$left"

    tmux bind-key -n MouseDown3Status if-shell -F "$ON_BAR" "$context" "$right"
}

main() {
    tmux set-option -g status-interval 20
    ensure_option @agent_usage_window_claude "5h"
    ensure_option @agent_usage_window_codex "5h"
    ensure_option @agent_usage_nonce "0"
    update_tmux_option "status-right"
    update_tmux_option "status-left"
    bind_mouse
}

main
