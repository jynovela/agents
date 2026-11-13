# AGENTS.md

Project: itemctl, a command-line tool that lists items from an inventory service.

Stack: Python 3.10, standard library only.

## Commands

- Run tests: `python3 -m unittest discover -s tests -t .`
- Coverage: `python3 -m trace --count --summary --missing -C /tmp/itemctl-cov --module unittest discover -s tests -t . 2>&1 | grep -E '%.*app\.py'`
- Lint docs: `npx markdownlint-cli2 "**/*.md"`
- Lint API spec: `npx @stoplight/spectral-cli lint openapi.yaml`
