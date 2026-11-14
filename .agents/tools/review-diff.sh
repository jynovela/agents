#!/usr/bin/env bash
# Prints a branch's change in a form that is easy to cite: every changed file,
# then every added line as "<file>:<line>: <text>", with the line number in
# the file as it is now. Removed lines show as "<file>: (removed) <text>".
# Long values that could be secrets show as <long value hidden>; quote the
# part of the line before them.
#
# Last, it lists "risky lines": added lines that often change what users or
# other systems see (env vars, flags, headers, imports). The report must
# account for each one under "Risky lines:".
#
# Usage: .agents/tools/review-diff.sh [base]   (default base: main)
# Compares <base>...HEAD, the same range a pull request shows.

set -uo pipefail
base="${1:-main}"

# TAILOR: added lines that often mean a change users or callers notice.
RISKY='environ|getenv|process\.env|add_argument|addOption|\.option\(|[Hh]eaders?[ =:\[(]|Authorization|^import |^from [A-Za-z_.]+ import|require\('
hide() { sed -E 's/[A-Za-z0-9_+\/=-]{24,}/<long value hidden>/g'; }

if ! git rev-parse --verify -q "$base" >/dev/null; then
  echo "Base branch \"$base\" not found. Pass the right one, like: .agents/tools/review-diff.sh develop" >&2
  exit 1
fi

echo "== Changed files ($base...HEAD)"
git --no-pager diff --stat "$base...HEAD"
echo
echo "== Added and removed lines"
lines="$(git --no-pager diff -U0 --no-color "$base...HEAD" | awk '
  /^\+\+\+ / { file = substr($0, 7); next }
  /^--- /    { next }
  /^@@ /     {
    split($3, a, ",")
    line = substr(a[1], 2) + 0
    next
  }
  /^\+/ { print file ":" line ": " substr($0, 2); line++; next }
  /^-/  { print file ": (removed) " substr($0, 2); next }
')"
echo "$lines" | hide
echo
echo "== Risky lines"
risky="$(echo "$lines" | grep -E '^[^:]+:[0-9]+: ' | grep -E "^[^:]+:[0-9]+: .*($RISKY)" | grep -vE '^[^:]+:[0-9]+: *#' || true)"
if [ -n "$risky" ]; then
  echo "$risky" | hide
else
  echo "None."
fi
