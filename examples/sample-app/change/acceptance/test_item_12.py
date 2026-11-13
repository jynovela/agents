"""Acceptance tests for ITEM-12. They run against the live service.

Start it first with dev/start.sh. Each test resets the database and log.
"""

import json
import os
import sqlite3
import subprocess
import unittest
import urllib.request

ENV = dict(os.environ, ITEMCTL_TOKEN="test-token")


def reset() -> None:
    subprocess.run(["dev/reset.sh"], check=True, capture_output=True)


def db_rows(sql: str) -> list[tuple]:
    db = sqlite3.connect("file:data/items.db?mode=ro", uri=True)
    try:
        return db.execute(sql).fetchall()
    finally:
        db.close()


def cli(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["python3", "app.py", *args], env=ENV, capture_output=True, text=True, timeout=10
    )


def log_text() -> str:
    with open("logs/server.log") as f:
        return f.read()


class Item12Test(unittest.TestCase):
    def setUp(self) -> None:
        reset()

    def test_c1_limit_and_offset_print_items_2_and_3(self):
        expected = "".join(
            f"{i}\t{n}\n" for i, n in db_rows("SELECT id, name FROM items WHERE id IN (2, 3) ORDER BY id")
        )
        result = cli("list", "--limit", "2", "--offset", "1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, expected)

    def test_c2_request_is_logged_with_limit_and_offset(self):
        cli("list", "--limit", "2", "--offset", "1")
        self.assertIn("GET /items limit=2 offset=1 returned=2", log_text())

    def test_c3_offset_past_end_prints_nothing(self):
        result = cli("list", "--offset", "100")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")

    def test_c4_items_endpoint_defaults_to_first_10(self):
        expected = [{"id": i, "name": n} for i, n in db_rows("SELECT id, name FROM items ORDER BY id LIMIT 10")]
        with urllib.request.urlopen("http://localhost:8000/items", timeout=5) as resp:
            body = json.load(resp)
        self.assertEqual(body["items"], expected)


if __name__ == "__main__":
    unittest.main()
