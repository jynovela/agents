"""itemctl: list items from the inventory service."""

import argparse
import json
import os
import urllib.request

API_URL = os.environ.get("ITEMCTL_API_URL", "http://localhost:8000")


def list_items(max_items: int = 10) -> list[dict]:
    """Return up to max_items items by calling GET /items?limit=<max_items>."""
    url = f"{API_URL}/items?limit={max_items}"
    with urllib.request.urlopen(url) as resp:
        return json.load(resp)["items"]


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(prog="itemctl")
    sub = parser.add_subparsers(dest="cmd", required=True)
    list_cmd = sub.add_parser("list", help="List items")
    list_cmd.add_argument("--max", type=int, default=10, help="Maximum items to show")
    args = parser.parse_args(argv)

    if args.cmd == "list":
        for item in list_items(args.max):
            print(f"{item['id']}\t{item['name']}")


if __name__ == "__main__":
    main()
