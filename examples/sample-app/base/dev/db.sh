#!/usr/bin/env bash
# Runs one read-only SQL query against data/items.db and prints the rows.
# Usage: dev/db.sh "SELECT id, name FROM items ORDER BY id"
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - "$1" <<'PY'
import sqlite3, sys
db = sqlite3.connect("file:data/items.db?mode=ro", uri=True)
for row in db.execute(sys.argv[1]):
    print("\t".join(str(v) for v in row))
PY
