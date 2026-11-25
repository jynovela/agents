"""Acceptance tests for ITEM-18. They run against the live service.

Start it first with dev/start.sh. Each test resets the database and log.
"""

import json
import sqlite3
import subprocess
import unittest
import urllib.error
import urllib.request

BASE_URL = "http://localhost:8000"


def reset() -> None:
    subprocess.run(["dev/reset.sh"], check=True, capture_output=True)


def db_rows(sql: str) -> list[tuple]:
    db = sqlite3.connect("file:data/items.db?mode=ro", uri=True)
    try:
        return db.execute(sql).fetchall()
    finally:
        db.close()


def cli(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["python3", "app.py", *args], capture_output=True, text=True, timeout=10)


def get(path: str) -> tuple[int, dict]:
    try:
        with urllib.request.urlopen(BASE_URL + path, timeout=5) as resp:
            return resp.status, json.load(resp)
    except urllib.error.HTTPError as err:
        return err.code, json.load(err)


def log_text() -> str:
    with open("logs/server.log") as f:
        return f.read()


class Item18Test(unittest.TestCase):
    def setUp(self) -> None:
        reset()

    def test_c1_show_prints_item_3(self):
        (row,) = db_rows("SELECT id, name FROM items WHERE id = 3")
        result = cli("show", "3")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, f"{row[0]}\t{row[1]}\n")

    def test_c2_show_missing_item_prints_error(self):
        result = cli("show", "999")
        self.assertEqual(result.stdout, "")
        self.assertEqual(result.stderr, "item 999 not found\n")
        self.assertEqual(result.returncode, 1)

    def test_c3_get_item_returns_it(self):
        (row,) = db_rows("SELECT id, name FROM items WHERE id = 3")
        status, body = get("/items/3")
        self.assertEqual(status, 200)
        self.assertEqual(body, {"id": row[0], "name": row[1]})

    def test_c4_show_logs_the_lookup(self):
        cli("show", "3")
        cli("show", "999")
        log = log_text()
        self.assertIn("GET /items/3 found=1", log)
        self.assertIn("GET /items/999 found=0", log)

    def test_c5_missing_item_returns_404(self):
        status, body = get("/items/999")
        self.assertEqual(status, 404)
        self.assertEqual(body, {"error": "not found"})


if __name__ == "__main__":
    unittest.main()
