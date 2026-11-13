#!/usr/bin/env bash
# Exits 0 when the service answers GET /health.
python3 -c 'import urllib.request; urllib.request.urlopen("http://localhost:8000/health", timeout=2)'
