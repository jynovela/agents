#!/usr/bin/env bash
# Prints a branch's change for an API review, in a form that is easy to cite.
#
# Sections:
#   Changed files     every file the branch changed
#   Spec files        the spec files and whether the branch changed them
#   Interface lines   added and removed lines that may change the public
#                     interface, tagged with what kind. The report must
#                     account for each one.
#
# Locations: "server.py:47" is line 47 as the file is now (an added line).
# "server.py:-31" is line 31 on the base branch, which the branch removed;
# read it with: git show <base>:server.py | sed -n 31p
#
# Usage: .agents/skills/api-agent/tools/api-diff.sh [base]   (default base: main)
# Compares <base>...HEAD, the same range a pull request shows.
# Written for bash 3.2 (the macOS default): no case statements inside $( ).

set -uo pipefail
base="${1:-main}"

# <!-- TAILOR: your spec files (same as SPECS in .agents/shared/spec-diff.sh). -->
SPECS="${API_SPECS:-openapi.yaml}"

# <!-- TAILOR: patterns for your stack. Each tag names a kind of interface. -->
ROUTE='\.path ==|path\.startswith\(|def do_(GET|POST|PUT|PATCH|DELETE)|\.route\(|@(app|router|bp)\.(get|post|put|patch|delete)\(|(app|router)\.(get|post|put|patch|delete)\(|path\(|re_path\('
PARAM='query\.get\(|parse_qs\(|request\.args|request\.form|request\.json|req\.(query|body|params)|Query\(|Path\(|Body\(|[?&][a-z_]+=\{'
HEADER='send_header\(|headers\[|headers=|\.headers\.get\(|request\.headers|Header\(|setHeader\(|res\.set\('
RESPONSE='send_json\(|jsonify\(|JSONResponse\(|res\.(json|send)\(|return \{|\{"[A-Za-z_]+": |send_response\('
CLI='add_argument\(|add_parser\(|@click\.(option|argument|command|group)|\.option\(|\.command\('
ENV='os\.environ|getenv\(|process\.env'

# <!-- TAILOR: paths that never hold the public interface. -->
SKIP='(^|/)(tests?|acceptance|docs|\.agents|\.claude|\.tickets|\.notes|\.briefs)/|\.md$'

# Project settings. A value set in .agents/local/api-agent.sh replaces the one
# in this script. install.sh never changes that file.
if [ -f .agents/local/api-agent.sh ]; then . .agents/local/api-agent.sh; fi

if ! git rev-parse --verify -q "$base" >/dev/null; then
  echo "Base branch \"$base\" not found. Pass the right one, like: .agents/skills/api-agent/tools/api-diff.sh develop" >&2
  exit 1
fi

files="$(git diff --name-only "$base...HEAD")"
echo "== Changed files ($base...HEAD)"
if [ -n "$files" ]; then echo "$files"; else echo "None."; fi

echo
echo "== Spec files"
for s in $SPECS; do
  if [ ! -f "$s" ]; then
    echo "$s: not found"
  elif echo "$files" | grep -qx "$s"; then
    echo "$s: changed on this branch"
  else
    echo "$s: unchanged on this branch"
  fi
done

lines="$(git --no-pager diff -U0 --no-color "$base...HEAD" | awk '
  /^\+\+\+ / { file = substr($0, 7); next }
  /^--- /    { next }
  /^@@ /     { split($2, o, ","); old = substr(o[1], 2) + 0
               split($3, a, ","); new = substr(a[1], 2) + 0; next }
  /^\+/      { print file ":" new "\t" substr($0, 2); new++; next }
  /^-/       { print file ":-" old "\t" substr($0, 2); old++; next }
')"

echo
echo "== Interface lines"
out="$(printf '%s\n' "$lines" | while IFS="$(printf '\t')" read -r loc text; do
  [ -n "$loc" ] || continue
  file="${loc%:*}"
  echo "$file" | grep -Eq "$SKIP" && continue
  for s in $SPECS; do [ "$file" = "$s" ] && continue 2; done
  # Skip comments.
  echo "$text" | grep -Eq '^[[:space:]]*(#|//|\*)' && continue
  tags=""
  echo "$text" | grep -Eq "$ROUTE" && tags="$tags,route"
  echo "$text" | grep -Eq "$PARAM" && tags="$tags,param"
  echo "$text" | grep -Eq "$HEADER" && tags="$tags,header"
  echo "$text" | grep -Eq "$RESPONSE" && tags="$tags,response"
  echo "$text" | grep -Eq "$CLI" && tags="$tags,cli"
  echo "$text" | grep -Eq "$ENV" && tags="$tags,env"
  [ -n "$tags" ] || continue
  kind=added
  echo "$loc" | grep -q ':-' && kind=removed
  echo "$loc [$kind${tags}]: $(echo "$text" | sed -E 's/^[[:space:]]+//; s/[A-Za-z0-9_+\/=-]{24,}/<long value hidden>/g')"
done)"
if [ -n "$out" ]; then echo "$out"; else echo "None."; fi
