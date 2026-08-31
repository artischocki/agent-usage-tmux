#!/usr/bin/env python3
"""
Detailed rate-limit page behind the usage bars in the tmux status line.

Usage: usage_stats.py [claude|codex|all]

The fetchers next to this file stay the single place that knows how to
authenticate and where the numbers come from - this module only asks them once
and lays the answer out for a popup. One request per agent covers every window,
unlike the status bar, which asks for percentage and reset separately.
"""

import json
import sys
import time
from datetime import datetime
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))
sys.dont_write_bytecode = True  # no __pycache__ next to the plugin's scripts

import fetch_claude_usage as claude_fetch  # noqa: E402
import fetch_codex_usage as codex_fetch  # noqa: E402


BAR_WIDTH = 20
FULL_BLOCK = "█"
SUB_CHARS = ("▏", "▎", "▍", "▌", "▋", "▊", "▉")

RESET = "\033[0m"
BOLD = "\033[1m"
DIM = "\033[2m"
GREEN = "\033[38;5;71m"
ORANGE = "\033[38;5;214m"
RED = "\033[38;5;160m"
EMPTY_BG = "\033[48;5;236m"


def colour_for(free_pct: float) -> str:
    """Colour by what is left: little headroom is the interesting case."""
    if free_pct <= 20:
        return RED
    if free_pct <= 50:
        return ORANGE
    return GREEN


def bar(free_pct: float, width: int = BAR_WIDTH) -> str:
    """Same shape as the status-line bar: filled = quota still available."""
    free_pct = max(0.0, min(100.0, free_pct))
    filled = free_pct * width / 100.0
    full = int(filled)
    idx = int((filled - full) * 8)
    partial = SUB_CHARS[idx - 1] if idx > 0 else ""
    empty = " " * max(0, width - full - (1 if partial else 0))
    colour = colour_for(free_pct)
    return f"{colour}{EMPTY_BG}{FULL_BLOCK * full}{partial}{empty}{RESET}"


def fmt_delta(seconds: int) -> str:
    if seconds <= 0:
        return "now"
    days, rest = divmod(seconds, 86400)
    hours, rest = divmod(rest, 3600)
    minutes = rest // 60
    if days:
        return f"{days}d {hours}h"
    if hours:
        return f"{hours}h {minutes:02d}m"
    return f"{minutes}m"


def fmt_reset(reset_at) -> str:
    if not reset_at:
        return "-"
    when = datetime.fromtimestamp(int(reset_at))
    today = datetime.now().date()
    days_off = (when.date() - today).days
    if days_off == 0:
        stamp = f"today {when:%H:%M}"
    elif days_off == 1:
        stamp = f"tomorrow {when:%H:%M}"
    else:
        stamp = f"{when:%a %d.%m. %H:%M}"
    left = fmt_delta(int(reset_at) - int(time.time()))
    return f"{stamp}  {DIM}(in {left}){RESET}"


def window_row(label: str, free_pct: float, reset_at, note: str = "") -> str:
    colour = colour_for(free_pct)
    used = 100 - free_pct
    return (f"  {label:<12} {colour}{BOLD}{free_pct:3.0f}% free{RESET} "
            f"{bar(free_pct)} {DIM}{used:3.0f}% used{RESET}  "
            f"{fmt_reset(reset_at)}{note}")


def heading(text: str) -> str:
    return f"\n{BOLD}{text}{RESET}\n"


def shown_in_status(agent: str) -> str:
    """Which window the status bar itself is currently showing."""
    import subprocess
    try:
        value = subprocess.run(
            ["tmux", "show-option", "-gqv", f"@agent_usage_window_{agent}"],
            capture_output=True, text=True, timeout=5).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return "5h"
    return "weekly" if value in ("weekly", "week", "7d", "secondary") else "5h"


def api_message(raw: str) -> str:
    """Turn 'HTTP 401: {"error": {"message": "..."}}' into one readable line."""
    prefix, _, body = raw.partition(": ")
    try:
        detail = json.loads(body).get("error", {}).get("message")
    except (ValueError, AttributeError):
        detail = None
    return f"{prefix}: {detail}" if detail else raw.splitlines()[0]


def claude_page() -> None:
    print(heading("Claude Code"), end="")

    path = claude_fetch.DEFAULT_CREDENTIALS_PATH
    try:
        token = claude_fetch.load_credentials(path)
        headers = claude_fetch.fetch_rate_limit_headers(
            claude_fetch.DEFAULT_MESSAGES_URL, token, 15.0)
    except SystemExit as exc:
        print(f"  {RED}{exc}{RESET}\n")
        return

    def value(key, default=None):
        return headers.get(f"anthropic-ratelimit-unified-{key}", default)

    representative = value("representative-claim", "five_hour")
    live = shown_in_status("claude")
    marks = {
        "5h": "  <- representative" if representative == "five_hour" else "",
        "7d": "  <- representative" if representative != "five_hour" else "",
    }
    for key, label in (("5h", "5 hours"), ("7d", "7 days"), ("overage", "overage")):
        util = value(f"{key}-utilization")
        if util is None:
            continue
        free = max(0.0, min(100.0, 100 - float(util) * 100))
        note = marks.get(key, "")
        if (key == "7d") == (live == "weekly") and key in ("5h", "7d"):
            note += f"  {DIM}[in status line]{RESET}"
        print(window_row(label, free, value(f"{key}-reset"), note))

    states = ", ".join(
        f"{key}: {value(f'{key}-status', '?')}" for key in ("5h", "7d", "overage"))
    fallback = value("fallback-percentage")
    print(f"\n  {DIM}status{RESET}   {states}")
    if fallback is not None:
        print(f"  {DIM}fallback share{RESET}   {float(fallback) * 100:.0f}%")

    print(f"\n  {DIM}raw headers{RESET}")
    for key in sorted(headers):
        if key.startswith("anthropic-ratelimit-unified"):
            print(f"    {DIM}{key[28:]:<24} {headers[key]}{RESET}")
    print()


def codex_page() -> None:
    print(heading("Codex"), end="")

    try:
        token, account = codex_fetch.load_auth(codex_fetch.DEFAULT_AUTH_PATH)
        payload = codex_fetch.fetch_usage(
            codex_fetch.DEFAULT_URL, token, account, 15.0, "")
    except SystemExit as exc:
        message = api_message(str(exc))
        print(f"  {RED}{message}{RESET}")
        if "401" in message or "unauthorized" in message.lower():
            print(f"  {DIM}token expired - run 'codex login' to refresh "
                  f"{codex_fetch.DEFAULT_AUTH_PATH}{RESET}")
        print()
        return

    rate_limit = payload.get("rate_limit") or {}
    live = shown_in_status("codex")
    for key, label in (("primary_window", "5 hours"), ("secondary_window", "weekly")):
        data = rate_limit.get(key) or {}
        used = data.get("used_percent")
        if used is None:
            continue
        free = max(0.0, min(100.0, 100 - float(used)))
        note = ""
        if (key == "secondary_window") == (live == "weekly"):
            note = f"  {DIM}[in status line]{RESET}"
        print(window_row(label, free, data.get("reset_at"), note))

    print(f"\n  {DIM}raw rate_limit{RESET}")
    for line in json.dumps(rate_limit, indent=2).splitlines():
        print(f"    {DIM}{line}{RESET}")
    print()


def main() -> None:
    agent = sys.argv[1] if len(sys.argv) > 1 else "all"
    agent = agent.split(":")[-1]  # tolerate the raw range name, e.g. 'au:claude'

    if agent in ("claude", "all"):
        claude_page()
    if agent in ("codex", "all"):
        codex_page()
    if agent not in ("claude", "codex", "all"):
        raise SystemExit(f"unknown agent: {agent} (expected claude, codex or all)")


if __name__ == "__main__":
    main()
