#!/usr/bin/env bash
# Click actions for the usage bars in the tmux status line (see agent-usage.tmux).
#
#     usage_menu.sh toggle <agent>            5h window <-> weekly window
#     usage_menu.sh window <agent> <5h|weekly>
#     usage_menu.sh stats  <agent>            detailed page, meant for a popup
#     usage_menu.sh refresh                   drop the cached bar and refetch
#
# <agent> may be given as the raw range name tmux reports in
# #{mouse_status_range} ('au-claude', 'au-codex') - the prefix is stripped here
# so the key bindings can simply forward it.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

ACTION="${1:-stats}"
AGENT="${2:-claude}"
AGENT="${AGENT##*[-:]}"

case "$AGENT" in
    claude|codex) ;;
    *) AGENT="claude" ;;
esac

current_window() {
    case "$(tmux show-option -gqv "@agent_usage_window_${AGENT}" 2>/dev/null)" in
        weekly|week|7d|secondary) echo "weekly" ;;
        *) echo "5h" ;;
    esac
}

# The bar runs as a #() job and tmux caches such a job by its command string.
# agent-usage.tmux puts the window option into that string, so setting the
# option here gives the status line a *new* job that runs at once - otherwise
# the old window would stay up until the next status-interval tick.
set_window() {
    tmux set-option -g "@agent_usage_window_${AGENT}" "$1"
    tmux refresh-client -S
}

wait_for_key() {
    printf '\n\033[2m[press any key]\033[0m'
    { read -rsn1 </dev/tty; } 2>/dev/null
    printf '\n'
}

case "$ACTION" in
    toggle)
        if [[ "$(current_window)" == "weekly" ]]; then
            set_window "5h"
        else
            set_window "weekly"
        fi
        ;;
    window)
        set_window "${3:-5h}"
        ;;
    refresh)
        # Same idea as set_window: a new nonce means a new command string,
        # which is the only way to make tmux re-run the job before the next tick.
        tmux set-option -g @agent_usage_nonce "$(date +%s)"
        tmux refresh-client -S
        ;;
    stats)
        python3 "$SCRIPT_DIR/usage_stats.py" "$AGENT"
        wait_for_key
        ;;
    *)
        echo "unknown action: $ACTION" >&2
        echo "expected: toggle, window, stats, refresh" >&2
        ;;
esac
