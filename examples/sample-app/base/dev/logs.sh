#!/usr/bin/env bash
# Prints the last lines of the service log. Usage: dev/logs.sh [lines]
cd "$(dirname "$0")/.."
tail -n "${1:-20}" logs/server.log
