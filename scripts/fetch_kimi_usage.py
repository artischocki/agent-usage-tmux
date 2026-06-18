#!/usr/bin/env python3
"""
Fetch Kimi Code rate-limit usage from the Kimi Code API.

Auth is read from ~/.kimi-code/credentials/kimi-code.json (access_token).
The remaining percentage for the primary 300-minute window is written to
stdout as a plain integer (0-100).
"""

import argparse
from datetime import datetime
import json
from pathlib import Path
import time
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


DEFAULT_CREDENTIALS_PATH = Path.home() / ".kimi-code" / "credentials" / "kimi-code.json"
DEFAULT_URL = "https://api.kimi.com/coding/v1/usages"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Fetch Kimi Code rate-limit remaining percentage."
    )
    parser.add_argument(
        "--credentials-file",
        default=str(DEFAULT_CREDENTIALS_PATH),
        help=f"Path to Kimi Code credentials JSON (default: {DEFAULT_CREDENTIALS_PATH})",
    )
    parser.add_argument(
        "--url",
        default=DEFAULT_URL,
        help=f"Kimi Code usages endpoint (default: {DEFAULT_URL})",
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
        help="Print raw JSON response instead of a single percentage.",
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
        choices=["primary", "weekly"],
        default="primary",
        help="Which quota window to report (default: primary / 300-minute)",
    )
    return parser.parse_args()


def load_credentials(credentials_path: Path) -> str:
    try:
        payload = json.loads(credentials_path.read_text())
    except FileNotFoundError:
        raise SystemExit(f"credentials file not found: {credentials_path}")
    except json.JSONDecodeError as exc:
        raise SystemExit(f"failed to parse credentials file {credentials_path}: {exc}")

    access_token = payload.get("access_token")
    if not access_token:
        raise SystemExit(f"missing access_token in {credentials_path}")
    return access_token


def fetch_usage(url: str, access_token: str, timeout: float) -> dict:
    request = Request(
        url,
        headers={
            "Authorization": f"Bearer {access_token}",
            "Accept": "application/json",
            "User-Agent": "agent-usage-tmux/1.0",
        },
        method="GET",
    )

    try:
        with urlopen(request, timeout=timeout) as response:
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


def parse_reset_time(value: object) -> int:
    if not isinstance(value, str):
        raise SystemExit(f"could not parse resetTime value: {value!r}")

    try:
        return int(datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp())
    except ValueError:
        raise SystemExit(f"could not parse resetTime value: {value!r}")


def parse_number(value: object, field: str) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        raise SystemExit(f"could not parse {field}: {value!r}")


def parse_primary_window(payload: dict) -> tuple[int, int]:
    limits = payload.get("limits")
    if not isinstance(limits, list) or not limits:
        raise SystemExit("limits[0] not found in response")

    detail = (limits[0] or {}).get("detail") or {}
    limit = parse_number(detail.get("limit"), "limits[0].detail.limit")
    used = parse_number(detail.get("used"), "limits[0].detail.used")
    reset_at = parse_reset_time(detail.get("resetTime"))

    if limit <= 0:
        raise SystemExit(f"invalid limits[0].detail.limit: {limit!r}")

    pct = max(0, min(100, round(100 - (used / limit * 100))))
    return pct, reset_at


def parse_weekly_window(payload: dict) -> tuple[int, int]:
    usage = payload.get("usage") or {}
    limit = parse_number(usage.get("limit"), "usage.limit")
    remaining = parse_number(usage.get("remaining"), "usage.remaining")
    reset_at = parse_reset_time(usage.get("resetTime"))

    if limit <= 0:
        raise SystemExit(f"invalid usage.limit: {limit!r}")

    pct = max(0, min(100, round(remaining / limit * 100)))
    return pct, reset_at


def parse_utilisation(payload: dict, window: str) -> tuple[int, int, int]:
    if window == "weekly":
        pct, reset_at = parse_weekly_window(payload)
    else:
        pct, reset_at = parse_primary_window(payload)

    reset_in = max(0, reset_at - int(time.time()))
    return pct, reset_at, reset_in


def main() -> None:
    args = parse_args()
    credentials_path = Path(args.credentials_file).expanduser()

    access_token = load_credentials(credentials_path)
    payload = fetch_usage(args.url, access_token, args.timeout)

    if args.raw:
        json.dump(payload, __import__("sys").stdout, indent=2)
        print()
        return

    pct, reset_at, reset_in = parse_utilisation(payload, args.window)

    if args.field == "percent":
        print(pct)
    elif args.field == "reset_at":
        print(reset_at)
    else:
        print(reset_in)


if __name__ == "__main__":
    main()
