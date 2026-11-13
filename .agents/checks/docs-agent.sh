#!/usr/bin/env bash
# Deterministic checks for a Docs-Agent run. Run from the repo root after the
# agent finishes, before anything is committed.
#
# Usage: .agents/checks/docs-agent.sh [report-file]
#   report-file: optional file holding the agent's report, to check its headings.
#
# Exit code 0 means all checks passed. Any failure prints FAIL and exits 1.

set -uo pipefail

# TAILOR: files the Docs-Agent may change (extended regex on repo-relative paths).
ALLOWED='^(docs/.*|README\.md|CHANGELOG\.md)$'

fail=0
say_fail() { echo "FAIL: $*"; fail=1; }

changed="$( { git diff --name-only HEAD; git ls-files --others --exclude-standard; } | sort -u)"

echo "== Changed files"
if [ -z "$changed" ]; then
  echo "No uncommitted changes. If the agent committed, that breaks its rules."
else
  echo "$changed"
  outside="$(echo "$changed" | grep -Ev "$ALLOWED" || true)"
  if [ -n "$outside" ]; then
    say_fail "changed files outside the allowed docs paths:"
    echo "$outside" | sed 's/^/  /'
  fi
fi

echo "== Secret scan on added lines"
# Long tokens that mix letters and digits, or known key prefixes. Values are
# never printed: only file and line numbers.
hits=0
for f in $changed; do
  [ -f "$f" ] || continue
  if git ls-files --error-unmatch "$f" >/dev/null 2>&1; then
    added="$(git diff -U0 HEAD -- "$f" | grep -n '^+[^+]' || true)"
  else
    added="$(grep -n '' "$f" | sed 's/^\([0-9]*\):/\1:+/' || true)"
  fi
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    text="${line#*:}"
    if echo "$text" | grep -Eq -- '(-----BEGIN [A-Z ]*PRIVATE KEY|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{30,}|sk-[A-Za-z0-9]{20,}|xox[abpr]-)' \
      || echo "$text" | grep -Eo '[A-Za-z0-9_+/=-]{24,}' | grep -v '^-*$' | grep -Eq '[0-9]' ; then
      say_fail "possible secret added in $f (value not shown)"
      hits=$((hits + 1))
      break
    fi
  done <<< "$added"
done
if command -v gitleaks >/dev/null 2>&1 && [ -n "$changed" ]; then
  for f in $changed; do
    [ -f "$f" ] || continue
    gitleaks dir --no-banner --redact "$f" >/dev/null 2>&1 || say_fail "gitleaks found a secret in $f"
  done
else
  echo "gitleaks not installed; ran the built-in pattern check only."
fi
[ "$hits" -eq 0 ] && echo "No secret-like values found in added lines."

echo "== Markdown tables"
# Rows starting with "||" stop rendering as a table, and markdownlint can't
# see it because the lines are no longer parsed as a table.
for f in $changed; do
  case "$f" in *.md) ;; *) continue ;; esac
  [ -f "$f" ] || continue
  bad="$(grep -n '^[[:space:]]*||' "$f" | cut -d: -f1 | tr '\n' ' ' || true)"
  [ -n "$bad" ] && say_fail "broken table rows starting with \"||\" in $f, lines: $bad"
done
[ "$fail" -eq 0 ] && echo "No broken table rows."

echo "== API spec files"
specs="$(git ls-files '*openapi*' '*swagger*' '*.graphql' '*.proto')"
if [ -n "$specs" ]; then
  echo "$specs"
  echo "The agent must compare these with the code and list drift in its report."
else
  echo "No spec file."
fi

if [ "${1:-}" != "" ]; then
  echo "== Report headings"
  for h in "Changed:" "Spec drift (not fixed):" "Security flags:" "Needs approval:" "Verify:"; do
    grep -qF "$h" "$1" || say_fail "report is missing the heading \"$h\""
  done
fi

echo
if [ "$fail" -ne 0 ]; then
  echo "Docs-Agent checks: FAILED"
  exit 1
fi
echo "Docs-Agent checks: passed"
