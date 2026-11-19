#!/usr/bin/env bash
# Claude Code PostToolUse hook: formats and lints each file right after Claude
# edits it, and sends what's left back to Claude so it fixes it in the same turn.
# Copy to .claude/hooks/lint-file.sh and register it in .claude/settings.json.
# See setup/lint.md.
set -uo pipefail

# The hook gets the tool call as JSON on stdin. Pull out the edited file.
file="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("tool_input", {}).get("file_path", ""))')"

# <!-- TAILOR: the file types and linter for your stack. -->
case "$file" in
  *.py) ;;
  *) exit 0 ;;
esac
[ -f "$file" ] || exit 0

ruff format --quiet "$file"
# Don't autofix unused imports or variables: Claude often adds an import one
# edit before the code that uses it.
ruff check --fix --unfixable F401,F841 --quiet "$file" >/dev/null 2>&1

if ! out="$(ruff check --output-format concise "$file" 2>&1)"; then
  # Exit code 2 shows stderr to Claude.
  {
    echo "Lint errors remain in $file. Fix the code; don't add noqa or change the lint config:"
    echo "$out"
  } >&2
  exit 2
fi
exit 0
