# AGENTS.md

Project: itemctl, a command-line tool that lists items from an inventory
service. `server.py` is a local copy of that service, for development.

Stack: Python 3.9 or later, standard library only. SQLite for the local service.

## Commands

- Lint docs: `npx markdownlint-cli2 "**/*.md"`
- API spec is: follows the code
- Lint API spec: `npx --yes @stoplight/spectral-cli@6 lint --fail-severity error openapi.yaml`
- Spec diff: `.agents/checks/spec-diff.sh main`
- Lint code: `ruff check . && ruff format --check .`
- Fix lint: `ruff check --fix . && ruff format .`
- Lint guard: `.agents/checks/lint-guard.sh`
- Scan secrets: `.agents/checks/secret-scan.sh`
- Audit dependencies: None
- Lint agent files: `.agents/checks/context-lint.sh`
- Build: `dev/build.sh`
- Build guard: `.agents/checks/build-guard.sh`
- Deploy (local or staging only): `dev/deploy.sh staging`
- Roll back a deploy: `dev/deploy.sh rollback staging`

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

Planner writes tickets to: local drafts in `.tickets/drafts/` only.

Planner reads code in: this repository.

## Design

Flows come from: `.flows/`, one file per flow.

Design writes to: `design/`

UI code lives in: `web/`
