# AGENTS.md

Project: itemctl, a command-line tool that lists items from an inventory
service. `server.py` is a local copy of that service, for development.

Stack: Python 3.10, standard library only. SQLite for the local service.

## Commands

- Lint docs: `npx markdownlint-cli2 "**/*.md"`
- Lint API spec: `npx @stoplight/spectral-cli lint openapi.yaml`

## Dev environment

- Start the app (returns once it's healthy): `dev/start.sh`
- Stop the app: `dev/stop.sh`
- Health check: `dev/health.sh`
- Base URL: `http://localhost:8000`
- Reset test data: `dev/reset.sh`
- Read-only database query: `dev/db.sh "SELECT id, name FROM items ORDER BY id"`
- Tail logs: `dev/logs.sh 20`
- Trigger a job: None
- Unit tests: `python3 -m unittest discover -s tests -t .`
- Acceptance tests (need the app running): `python3 -m unittest discover -s acceptance -t .`

## Tickets

Acceptance criteria come from: files in `.tickets/`, named by ticket ID.
