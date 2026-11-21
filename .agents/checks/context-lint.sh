#!/usr/bin/env bash
# Lints the files that instruct agents: every AGENTS.md, CLAUDE.md, role files,
# and Claude Code wrappers. Agents treat these files as true, so a dead file
# reference or a leftover TODO turns into wrong behavior.
#
# Usage: .agents/checks/context-lint.sh
#
# Exit code 0 means all checks passed. Any failure prints FAIL and exits 1.

set -uo pipefail
. "$(dirname "$0")/lib.sh"

# <!-- TAILOR: line limits. Long files get skimmed, and small models drop rules. -->
MAX_AGENTS=250
MAX_ROLE=400

# <!-- TAILOR: folders whose file references must exist. A reference is a path
# in backticks, like `.agents/roles/docs-agent.md`. Paths elsewhere are often
# examples, so they aren't checked. A bare folder like `docs/` isn't checked
# either. Add your source folders, like src/. -->
REF_DIRS='^(\.agents|\.claude|docs|setup)/'

files="$( { git ls-files 'AGENTS.md' '*/AGENTS.md' 'CLAUDE.md' '*/CLAUDE.md' \
            '.agents/roles/*.md' '.claude/agents/*.md'; } | sort -u )"

echo "== Files checked"
if [ -z "$files" ]; then
  say_fail "no AGENTS.md, role, or wrapper files found. Run this from the repo root."
  finish context-lint
fi
echo "$files"

echo "== Length"
hits=0
for f in $files; do
  n="$(wc -l < "$f" | tr -d ' ')"
  case "$f" in
    AGENTS.md|*/AGENTS.md) max="$MAX_AGENTS" ;;
    *) max="$MAX_ROLE" ;;
  esac
  if [ "$n" -gt "$max" ]; then
    say_fail "$f has $n lines, over the limit of $max. Move detail to a role file or docs/."
    hits=$((hits + 1))
  fi
done
[ "$hits" -eq 0 ] && echo "All within limits."

echo "== File references"
hits=0
for f in $files; do
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    num="${line%%:*}"
    for ref in $(echo "${line#*:}" | grep -oE '`[^` ]+`' | tr -d '`'); do
      echo "$ref" | grep -Eq "$REF_DIRS" || continue
      case "$ref" in *'<'*|*'*'*|*'$'*|*'{'*|*/) continue ;; esac
      if [ ! -e "$ref" ]; then
        say_fail "$f:$num refers to $ref, which doesn't exist."
        hits=$((hits + 1))
      fi
    done
  done <<< "$(grep -nE '`[^` ]+`' "$f" || true)"
done
[ "$hits" -eq 0 ] && echo "All references exist."

echo "== Leftover markers"
hits=0
for f in $files; do
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    say_fail "$f:${line%%:*} has a leftover marker: finish or delete it."
    hits=$((hits + 1))
  done <<< "$(grep -nwE 'TODO|FIXME|TBD|XXX' "$f" || true)"
done
[ "$hits" -eq 0 ] && echo "None found."

echo "== Frontmatter"
hits=0
for f in $files; do
  case "$f" in .agents/roles/*|.claude/agents/*) ;; *) continue ;; esac
  head -1 "$f" | grep -qx -- '---' || { say_fail "$f has no frontmatter."; hits=$((hits + 1)); continue; }
  for key in name description; do
    if ! sed -n '2,/^---$/p' "$f" | grep -q "^$key: ."; then
      say_fail "$f frontmatter has no \"$key:\"."
      hits=$((hits + 1))
    fi
  done
done
[ "$hits" -eq 0 ] && echo "All role and wrapper files have name and description."

finish context-lint
