#!/usr/bin/env bash
# Recreates data/items.db from seed.sql and clears the log.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p data logs
python3 -c 'import sqlite3, sys; db = sqlite3.connect("data/items.db"); db.executescript(open("seed.sql").read()); db.commit()'
: > logs/server.log
echo "Database reset to seed.sql; log cleared."
