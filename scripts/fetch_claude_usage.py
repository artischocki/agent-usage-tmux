#!/usr/bin/env python3
"""
Fetch Claude Code rate-limit utilisation from the Anthropic messages API.

Auth is read from ~/.claude/.credentials.json (claudeAiOauth.accessToken).
The utilisation percentage for the representative rate-limit window is
written to stdout as a plain integer (0-100).
"""

import argparse
import json
from pathlib import Path
import time
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


DEFAULT_CREDENTIALS_PATH = Path.home() / ".claude" / ".credentials.json"
DEFAULT_MESSAGES_URL = "https://api.anthropic.com/v1/messages"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Fetch Claude Code rate-limit utilisation percentage."
    )
    parser.add_argument(
        "--credentials-file",
        default=str(DEFAULT_CREDENTIALS_PATH),
        help=f"Path to Claude credentials JSON (default: {DEFAULT_CREDENTIALS_PATH})",
    )
    parser.add_argument(
        "--url",
        default=DEFAULT_MESSAGES_URL,
        help=f"Anthropic messages endpoint (default: {DEFAULT_MESSAGES_URL})",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=15.0,
        help="HTTP timeout in seconds (default: 15)",
    )
    parser.add_argument(
        "--raw",
        action="store_true",
        help="Print raw rate-limit header values instead of a single percentage.",
    )
    parser.add_argument(
        "--field",
        choices=["percent", "reset_at", "reset_in"],
        default="percent",
        help=(
            "Which value to print: remaining percentage, reset epoch time, "
            "or seconds until reset (default: percent)"
        ),
    )
    parser.add_argument(
        "--window",
        choices=["5h", "7d", "auto"],
        default="auto",
        help=(
            "Which rate-limit window to report: 5h, 7d, or auto (use the "
            "representative claim, default: auto)"
        ),
    )
    return parser.parse_args()


def load_credentials(credentials_path: Path) -> str:
    try:
        payload = json.loads(credentials_path.read_text())
    except FileNotFoundError:
        raise SystemExit(f"credentials file not found: {credentials_path}")
    except json.JSONDecodeError as exc:
        raise SystemExit(f"failed to parse credentials file {credentials_path}: {exc}")

    oauth = payload.get("claudeAiOauth") or {}
    access_token = oauth.get("accessToken")
    if not access_token:
        raise SystemExit(
            f"missing claudeAiOauth.accessToken in {credentials_path}"
        )
    return access_token


def fetch_rate_limit_headers(
    url: str,
    access_token: str,
    timeout: float,
) -> dict:
    """
    Make a minimal messages API call and return the rate-limit response headers.
    Uses claude-haiku (cheapest model) with a 1-token response to minimise cost.
    """
    body = json.dumps({
        "model": "claude-haiku-4-5-20251001",
        "max_tokens": 1,
        "messages": [{"role": "user", "content": "0"}],
    }).encode()

    request = Request(
        url,
        data=body,
        headers={
            "Authorization": f"Bearer {access_token}",
            "anthropic-beta": "oauth-2025-04-20",
            "anthropic-version": "2023-06-01",
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": "agent-usage-tmux/1.0",
        },
        method="POST",
    )

    try:
        with urlopen(request, timeout=timeout) as response:
            headers = {k.lower(): v for k, v in response.getheaders()}
    except HTTPError as exc:
        headers = {k.lower(): v for k, v in exc.headers.items()}
        if any(k.startswith("anthropic-ratelimit-unified") for k in headers):
            return headers
        body_text = exc.read().decode("utf-8", errors="replace")
        raise SystemExit(f"HTTP {exc.code}: {body_text}")
    except URLError as exc:
        raise SystemExit(f"request failed: {exc}")

    return headers


def select_window(headers: dict, window: str) -> str:
    representative = headers.get(
        "anthropic-ratelimit-unified-representative-claim",
        "five_hour",
    )

    if window == "auto":
        return "5h" if representative == "five_hour" else "7d"
    return window


def parse_utilisation(headers: dict, window: str) -> tuple[int, int, dict]:
    raw = {
        k: v
        for k, v in headers.items()
        if k.startswith("anthropic-ratelimit-unified")
    }

    window_key = select_window(headers, window)

    util_key = f"anthropic-ratelimit-unified-{window_key}-utilization"
    util_str = headers.get(util_key)
    reset_key = f"anthropic-ratelimit-unified-{window_key}-reset"
    reset_str = headers.get(reset_key)

    if util_str is None:
        raise SystemExit(
            f"rate-limit utilisation header '{util_key}' not found in response"
        )
    if reset_str is None:
        raise SystemExit(
            f"rate-limit reset header '{reset_key}' not found in response"
        )

    try:
        util_float = float(util_str)
    except ValueError:
        raise SystemExit(f"could not parse utilisation value: {util_str!r}")
    try:
        reset_at = int(reset_str)
    except ValueError:
        raise SystemExit(f"could not parse reset value: {reset_str!r}")

    pct = max(0, min(100, 100 - round(util_float * 100)))
    return pct, reset_at, raw


def main() -> None:
    args = parse_args()
    credentials_path = Path(args.credentials_file).expanduser()

    access_token = load_credentials(credentials_path)
    headers = fetch_rate_limit_headers(args.url, access_token, args.timeout)
    pct, reset_at, raw = parse_utilisation(headers, args.window)

    if args.raw:
        for k, v in sorted(raw.items()):
            print(f"{k}: {v}")
        return

    if args.field == "percent":
        print(pct)
    elif args.field == "reset_at":
        print(reset_at)
    else:
        print(max(0, reset_at - int(time.time())))


if __name__ == "__main__":
    main()
