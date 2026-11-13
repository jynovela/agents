"""Local inventory service for itemctl: GET /items and GET /health.

Reads items from data/items.db (SQLite) and logs each request to
logs/server.log.
"""

import json
import logging
import os
import sqlite3
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlparse

DB_PATH = os.environ.get("ITEMCTL_DB", "data/items.db")
PORT = int(os.environ.get("ITEMCTL_PORT", "8000"))

os.makedirs("logs", exist_ok=True)
logging.basicConfig(
    filename="logs/server.log",
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)
log = logging.getLogger("inventory")


def fetch_items(limit: int, offset: int) -> list[dict]:
    """Return up to limit items ordered by id, skipping the first offset."""
    with sqlite3.connect(DB_PATH) as db:
        rows = db.execute(
            "SELECT id, name FROM items ORDER BY id LIMIT ? OFFSET ?", (limit, offset)
        ).fetchall()
    return [{"id": r[0], "name": r[1]} for r in rows]


class Handler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:
        url = urlparse(self.path)
        if url.path == "/health":
            self.send_json(200, {"status": "ok"})
            return
        if url.path != "/items":
            self.send_json(404, {"error": "not found"})
            return
        query = parse_qs(url.query)
        try:
            limit = int(query.get("limit", ["10"])[0])
            offset = int(query.get("offset", ["0"])[0])
        except ValueError:
            log.warning("GET /items rejected: limit and offset must be integers")
            self.send_json(400, {"error": "limit and offset must be integers"})
            return
        items = fetch_items(limit, offset)
        log.info("GET /items limit=%d offset=%d returned=%d", limit, offset, len(items))
        self.send_json(200, {"items": items})

    def send_json(self, status: int, body: dict) -> None:
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *args) -> None:
        """Silence the default stderr access log; requests go to logs/server.log."""


if __name__ == "__main__":
    log.info("inventory service listening on port %d", PORT)
    HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
