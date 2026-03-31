#!/usr/bin/env python3
"""
Fetch Codex rate-limit utilisation from the ChatGPT backend API.

Auth is read from ~/.codex/auth.json (tokens.access_token + tokens.account_id).
The utilisation percentage for the primary (5h) rate-limit window is
written to stdout as a plain integer (0-100).
"""

import argparse
import json
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import ProxyHandler, Request, build_opener, urlopen


DEFAULT_AUTH_PATH = Path.home() / ".codex" / "auth.json"
DEFAULT_URL = "https://chatgpt.com/backend-api/wham/usage"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Fetch Codex rate-limit utilisation percentage."
    )
    parser.add_argument(
        "--auth-file",
        default=str(DEFAULT_AUTH_PATH),
        help=f"Path to Codex auth.json (default: {DEFAULT_AUTH_PATH})",
    )
    parser.add_argument(
        "--url",
        default=DEFAULT_URL,
        help=f"Usage endpoint to query (default: {DEFAULT_URL})",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=15.0,
        help="HTTP timeout in seconds (default: 15)",
    )
    parser.add_argument(
        "--proxy-url",
        default="",
        help="Optional proxy URL for HTTP(S) requests.",
    )
    parser.add_argument(
        "--raw",
        action="store_true",
        help="Print raw JSON response instead of a single percentage.",
    )
    parser.add_argument(
        "--window",
        choices=["primary", "secondary"],
        default="primary",
        help="Which rate-limit window to report (default: primary / 5h)",
    )
    return parser.parse_args()


def load_auth(auth_path: Path) -> tuple[str, str]:
    try:
        payload = json.loads(auth_path.read_text())
    except FileNotFoundError:
        raise SystemExit(f"auth file not found: {auth_path}")
    except json.JSONDecodeError as exc:
        raise SystemExit(f"failed to parse auth file {auth_path}: {exc}")

    tokens = payload.get("tokens") or {}
    access_token = tokens.get("access_token")
    account_id = tokens.get("account_id")

    if not access_token:
        raise SystemExit(f"missing tokens.access_token in {auth_path}")
    if not account_id:
        raise SystemExit(f"missing tokens.account_id in {auth_path}")

    return access_token, account_id


def fetch_usage(
    url: str,
    access_token: str,
    account_id: str,
    timeout: float,
    proxy_url: str,
) -> dict:
    request = Request(
        url,
        headers={
            "Authorization": f"Bearer {access_token}",
            "ChatGPT-Account-Id": account_id,
            "User-Agent": "claude-usage-tmux/1.0",
            "Accept": "application/json",
        },
        method="GET",
    )

    try:
        opener = build_opener(ProxyHandler({"http": proxy_url, "https": proxy_url})) if proxy_url else None
        open_fn = opener.open if opener else urlopen
        with open_fn(request, timeout=timeout) as response:
            body = response.read().decode("utf-8")
    except HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise SystemExit(f"HTTP {exc.code}: {body}")
    except URLError as exc:
        raise SystemExit(f"request failed: {exc}")

    try:
        return json.loads(body)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"failed to parse response JSON: {exc}")


def parse_utilisation(payload: dict, window: str) -> int:
    rate_limit = payload.get("rate_limit") or {}
    window_data = rate_limit.get(f"{window}_window") or {}
    used_percent = window_data.get("used_percent")

    if used_percent is None:
        raise SystemExit(
            f"used_percent not found in rate_limit.{window}_window"
        )

    try:
        pct = max(0, min(100, round(float(used_percent))))
    except (TypeError, ValueError):
        raise SystemExit(f"could not parse used_percent value: {used_percent!r}")

    return pct


def main() -> None:
    args = parse_args()
    auth_path = Path(args.auth_file).expanduser()

    access_token, account_id = load_auth(auth_path)
    payload = fetch_usage(args.url, access_token, account_id, args.timeout, args.proxy_url)

    if args.raw:
        json.dump(payload, __import__("sys").stdout, indent=2)
        print()
        return

    pct = parse_utilisation(payload, args.window)
    print(pct)


if __name__ == "__main__":
    main()
