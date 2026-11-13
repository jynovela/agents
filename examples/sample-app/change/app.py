"""itemctl: list items from the inventory service."""

import argparse
import json
import os
import urllib.request

API_URL = os.environ.get("ITEMCTL_API_URL", "http://localhost:8000")
TIMEOUT = float(os.environ.get("ITEMCTL_TIMEOUT", "5"))
API_TOKEN = os.environ.get("ITEMCTL_TOKEN", "itk_live_9f3b2c71d84e4a0b8c5d6e7f1a2b3c4d")


def list_items(limit: int = 10, offset: int = 0) -> list[dict]:
    """Return up to limit items, skipping the first offset.

    Calls GET /items?limit=<limit>&offset=<offset>.
    """
    url = f"{API_URL}/items?limit={limit}&offset={offset}"
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {API_TOKEN}"})
    with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
        return json.load(resp)["items"]


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(prog="itemctl")
    sub = parser.add_subparsers(dest="cmd", required=True)
    list_cmd = sub.add_parser("list", help="List items")
    list_cmd.add_argument("--limit", type=int, default=10, help="Maximum items to show")
    list_cmd.add_argument("--offset", type=int, default=0, help="Items to skip first")
    args = parser.parse_args(argv)

    if args.cmd == "list":
        for item in list_items(args.limit, args.offset):
            print(f"{item['id']}\t{item['name']}")


if __name__ == "__main__":
    main()
