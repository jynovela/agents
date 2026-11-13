#!/usr/bin/env bash
# Stops the inventory service started by dev/start.sh.
set -uo pipefail
cd "$(dirname "$0")/.."
if [ -f .dev.pid ]; then
  kill "$(cat .dev.pid)" 2>/dev/null || true
  rm -f .dev.pid
  echo "Stopped."
else
  echo "Not running."
fi
