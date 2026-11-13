#!/usr/bin/env bash
# Deterministic checks for a Docs-Agent run. Run from the repo root after the
# agent finishes, before anything is committed.
#
# Usage: .agents/checks/docs-agent.sh [report-file]
#   report-file: optional file holding the agent's report, to check its headings.
#
# Exit code 0 means all checks passed. Any failure prints FAIL and exits 1.

set -uo pipefail
. "$(dirname "$0")/lib.sh"

# TAILOR: files the Docs-Agent may change (extended regex on repo-relative paths).
ALLOWED='^(docs/.*|README\.md|CHANGELOG\.md)$'

check_scope "$ALLOWED"
check_secrets

echo "== Markdown tables"
# Rows starting with "||" stop rendering as a table, and markdownlint can't
# see it because the lines are no longer parsed as a table.
bad_tables=0
for f in $(changed_files); do
  case "$f" in *.md) ;; *) continue ;; esac
  [ -f "$f" ] || continue
  bad="$(grep -n '^[[:space:]]*||' "$f" | cut -d: -f1 | tr '\n' ' ' || true)"
  if [ -n "$bad" ]; then
    say_fail "broken table rows starting with \"||\" in $f, lines: $bad"
    bad_tables=1
  fi
done
[ "$bad_tables" -eq 0 ] && echo "No broken table rows."

echo "== API spec files"
specs="$(git ls-files '*openapi*' '*swagger*' '*.graphql' '*.proto')"
if [ -n "$specs" ]; then
  echo "$specs"
  echo "The agent must compare these with the code and list drift in its report."
else
  echo "No spec file."
fi

if [ "${1:-}" != "" ]; then
  check_headings "$1" "Changed:" "Spec drift (not fixed):" "Security flags:" "Needs approval:" "Verify:"
fi

finish "Docs-Agent"
