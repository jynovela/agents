#!/usr/bin/env bash
# Deterministic checks for a Lint-Agent run. Run from the repo root after the
# agent finishes, before anything is committed.
#
# Usage: .agents/skills/lint-agent/check.sh agent-report.md [base | path...]
#   agent-report.md: the agent's saved report.
#   base or path: the same scope the agent used (default: main). See
#   .agents/skills/lint-agent/tools/lint-scope.sh.
#
# Exit code 0 means all checks passed. Any failure prints FAIL and exits 1.

set -uo pipefail
here="$(dirname "$0")"
. "$here/../../shared/lib.sh"

# <!-- TAILOR: your lint, format check, and unit test commands. The scoped
# files are added after LINT and FORMAT_CHECK. Set UNIT to "" if there are
# no unit tests. -->
LINT='ruff check --output-format concise'
FORMAT_CHECK='ruff format --check'
UNIT='python3 -m unittest discover -s tests -t .'

# Project settings. A value set in .agents/local/lint-agent.sh replaces the one
# in this script. install.sh never changes that file.
if [ -f .agents/local/lint-agent.sh ]; then . .agents/local/lint-agent.sh; fi

# Rule codes the agent may fix by hand. Keep in sync with the table in
# .agents/skills/lint-agent/SKILL.md.
HAND_SAFE='ERA001|F841|E741|E501|B007'

report="${1:-}"
if [ -z "$report" ]; then
  echo "Usage: .agents/skills/lint-agent/check.sh agent-report.md [base | path...]"
  exit 1
fi
shift
[ "$#" -eq 0 ] && set -- main
mode=base
[ -e "$1" ] && mode=path

scope="$("$here/tools/lint-scope.sh" "$@" 2>/dev/null | grep -v '^NO_FILES_IN_SCOPE$' || true)"
echo "== Scope ($*)"
if [ -z "$scope" ]; then
  echo "No lintable files in scope."
else
  echo "$scope"
fi

# Lines of one report section: from the heading line to the next heading.
section() {
  awk -v h="$1" '
    index($0, h) == 1 { on = 1; next }
    on && /^[A-Z][A-Za-z ]+:/ { exit }
    on { print }' "$report"
}

check_headings "$report" "### Lint-Agent report" "Scope:" "Autofix:" \
  "Fixed by hand:" "Needs approval:" "Shortcuts on the branch:" \
  "Rule suggestions:" "Security flags:" "Unit tests:" "Verify:"
[ -f "$report" ] || finish lint-agent

allowed="^($(printf '%s\n' "$scope" "$report" | sed 's/[.[\*^$()+?{|]/\\&/g' | paste -sd '|' -))$"
check_scope "$allowed"

echo "== Deleted files"
deleted="$(git diff --name-only --diff-filter=D HEAD)"
if [ -n "$deleted" ]; then
  say_fail "files deleted (deleting is Ask first):"
  echo "$deleted" | sed 's/^/  /'
else
  echo "None."
fi

check_secrets

echo "== Lint guard on the agent's changes"
# The report may mention noqa or --no-verify in its text, so skip it.
guard="$("$here/../../shared/lint-guard.sh" 2>&1 | grep '^FAIL: ' | sed 's/^FAIL: //' | grep -v "^$report[: ]" || true)"
if [ -z "$guard" ]; then
  echo "Passed."
else
  while IFS= read -r l; do say_fail "$l"; done <<< "$guard"
fi

if [ -n "$scope" ]; then
  echo "== Formatting"
  # shellcheck disable=SC2086
  if $FORMAT_CHECK $scope >/dev/null 2>&1; then
    echo "All scoped files formatted."
  else
    say_fail "scoped files aren't formatted. Run the format command on them."
  fi

  echo "== Remaining lint errors are under \"Needs approval\""
  approval="$(section "Needs approval:")"
  # shellcheck disable=SC2086
  remaining="$($LINT $scope 2>/dev/null | grep -E '^[^ :]+:[0-9]+:[0-9]+: [A-Z]+[0-9]+' || true)"
  if [ -z "$remaining" ]; then
    echo "No lint errors left."
  else
    while IFS= read -r l; do
      loc="$(echo "$l" | cut -d: -f1,2)"
      code="$(echo "$l" | sed -E 's/^[^ ]+ ([A-Z]+[0-9]+).*/\1/')"
      if echo "$approval" | grep -F -- "$loc" | grep -qw -- "$code"; then
        echo "Listed: $loc $code"
      else
        say_fail "$loc $code is still a lint error but isn't under \"Needs approval\" as \"- $loc $code | ...\""
      fi
    done <<< "$remaining"
  fi
fi

echo "== Fixed by hand uses only hand-safe rules"
hits=0
while IFS= read -r l; do
  case "$l" in -\ None*|None*|'') continue ;; esac
  code="$(echo "$l" | grep -oE '[A-Z]+[0-9]{3,4}' | head -1)"
  if [ -z "$code" ]; then
    say_fail "\"Fixed by hand\" line has no rule code: $l"
    hits=$((hits + 1))
  elif ! echo "$code" | grep -Eqx "$HAND_SAFE"; then
    say_fail "$code isn't a hand-safe rule. Undo that fix and list it under \"Needs approval\": $l"
    hits=$((hits + 1))
  fi
done <<< "$(section "Fixed by hand:")"
[ "$hits" -eq 0 ] && echo "OK."

if [ "$mode" = base ]; then
  echo "== Branch shortcuts are under \"Shortcuts on the branch\""
  shortcuts="$(section "Shortcuts on the branch:")"
  # Only what was already committed. The agent's own changes are checked above.
  mine="$(changed_files)"
  found="$("$here/../../shared/lint-guard.sh" "$1" 2>/dev/null | grep '^FAIL' | sed -E 's/^FAIL: ([^ :]+).*/\1/' | sort -u \
    | grep -vxF -- "$mine" || true)"
  if [ -z "$found" ]; then
    echo "lint-guard found none."
  else
    while IFS= read -r f; do
      [ "$f" = "$report" ] && continue
      if echo "$shortcuts" | grep -qF -- "$f"; then
        echo "Listed: $f"
      else
        say_fail "lint-guard $1 flags $f, but it isn't under \"Shortcuts on the branch\""
      fi
    done <<< "$found"
  fi
fi

echo "== Unit tests"
if [ -z "$UNIT" ]; then
  echo "No unit test command set."
elif $UNIT >/dev/null 2>&1; then
  echo "Passed."
else
  say_fail "unit tests fail after the agent's changes. If they also fail on HEAD, the report must say so under \"Unit tests\"."
fi

finish lint-agent
