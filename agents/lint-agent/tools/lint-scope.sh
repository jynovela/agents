#!/usr/bin/env bash
# Prints the files Lint-Agent may change, one per line: the lintable files
# this branch changed since it left base, or the tracked lintable files under
# the paths you name. Deleted files are left out.
#
# Usage: .agents/skills/lint-agent/tools/lint-scope.sh [base | path...]   (default: main)
#   base: a branch or commit, like main. Scope is what this branch changed.
#   path: one or more files or folders, like src/billing. Use it to clean up
#         old lint errors in code the branch didn't change.
#
# Use it inside the lint commands, like:
#   ruff check --fix $(.agents/skills/lint-agent/tools/lint-scope.sh main)

set -uo pipefail

# <!-- TAILOR: the file types your linter checks, as an extended regex. -->
PATTERN='\.py$'

# Project settings. A value set in .agents/local/lint-agent.sh replaces the one
# in this script. install.sh never changes that file.
if [ -f .agents/local/lint-agent.sh ]; then . .agents/local/lint-agent.sh; fi

if [ "$#" -eq 0 ]; then
  set -- main
fi

if [ "$#" -eq 1 ] && [ ! -e "$1" ] && git rev-parse --verify -q "$1" >/dev/null; then
  files="$(git diff --name-only --diff-filter=ACMR "$1...HEAD")"
elif [ -e "$1" ]; then
  files="$(git ls-files -- "$@")"
else
  echo "NO_FILES_IN_SCOPE"
  echo "\"$1\" is neither a branch nor a path here. Pass the base branch, like main, or a folder." >&2
  exit 1
fi

scope="$(echo "$files" | grep -E "$PATTERN" | while IFS= read -r f; do
  [ -f "$f" ] && echo "$f"
done)"

# An empty list would make "ruff check --fix" run on the whole repo, so print
# a path that doesn't exist instead. The linter then fails and fixes nothing.
if [ -z "$scope" ]; then
  echo "NO_FILES_IN_SCOPE"
  echo "No lintable files in scope." >&2
  exit 1
fi
echo "$scope"
