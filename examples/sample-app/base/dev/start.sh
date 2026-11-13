#!/usr/bin/env bash
# Starts the inventory service in the background and waits until it's healthy.
set -euo pipefail
cd "$(dirname "$0")/.."
if dev/health.sh >/dev/null 2>&1; then
  echo "Already running on http://localhost:8000"
  exit 0
fi
[ -f data/items.db ] || dev/reset.sh
mkdir -p logs
nohup python3 server.py >> logs/server.out 2>&1 &
echo $! > .dev.pid
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if dev/health.sh >/dev/null 2>&1; then
    echo "Running on http://localhost:8000 (pid $(cat .dev.pid))"
    exit 0
  fi
  sleep 0.5
done
echo "Service did not become healthy. See logs/server.out" >&2
exit 1
