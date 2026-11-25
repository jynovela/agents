#!/usr/bin/env bash
# Catches the shortcuts that turn a red build green without fixing it, and
# production deploys added to build files:
#   1. a check made to pass no matter what (continue-on-error, || true, set +e)
#   2. a CI step, or a test, lint, or scan command in a build script, removed
#   3. a production deploy command added to a build file
#
# Usage: .agents/shared/build-guard.sh [base]
#   No argument: checks uncommitted changes against HEAD. Agents run it this
#   way.
#   base: checks everything on this branch since it left base (for example
#   origin/main). Use it in CI.
#
# Exit code 0 means no shortcut found. Any failure prints FAIL and exits 1.
# Only a human approves a weakened check.

set -uo pipefail
. "$(dirname "$0")/lib.sh"

# <!-- TAILOR: build files: CI, build and deploy scripts, and build config. -->
BUILD='^\.github/workflows/|^dev/|^scripts/|(^|/)(Makefile|Dockerfile|docker-compose\.ya?ml|compose\.ya?ml|vercel\.json|netlify\.toml|package\.json|pyproject\.toml|Procfile)$'

# Lines that make a failing command count as passing.
WEAKEN='continue-on-error:[[:space:]]*true|\|\|[[:space:]]*(true|:|exit[[:space:]]+0)([[:space:]]|;|$)|^[[:space:]]*set[[:space:]]+\+e|if:[[:space:]]*(false|\$\{\{[[:space:]]*false)|--passWithNoTests|--exit-zero|-k[[:space:]]+["'"'"']?not[[:space:]]'

# Commands in build scripts that check something. Removing one counts as
# removing a step.
CHECKS='test|lint|ruff|eslint|check|scan|audit|guard|verify|spec'

# One allowed exception: the lint guard step in CI is report-only on purpose
# (see setup/lint.md). A continue-on-error within 3 lines after a line that
# runs lint-guard.sh is fine.
ALLOW_NEAR='lint-guard\.sh'

# <!-- TAILOR: production deploy commands for your stack. -->
PROD='--prod([[:space:]]|$)|vercel[[:space:]]+promote|vercel[[:space:]]+rollback|netlify[[:space:]].*--prod|deploy(\.sh)?[[:space:]]+prod(uction)?([[:space:]]|$)|supabase[[:space:]].*--project-ref[[:space:]]+\$?\{?PROD|environment:[[:space:]]*production'

base="${1:-}"
if [ -n "$base" ]; then
  if ! git rev-parse --verify -q "$base" >/dev/null; then
    echo "FAIL: base \"$base\" is not a branch or commit here."
    exit 1
  fi
  from="$(git merge-base "$base" HEAD)"
else
  from="HEAD"
fi

build_changed() {
  { git diff --name-only "$from"; git ls-files --others --exclude-standard; } \
    | sort -u | grep -E "$BUILD" || true
}

# Added lines of one file as "<line number in the file>:<text>".
build_added_lines() {
  if git cat-file -e "$from:$1" 2>/dev/null; then
    git diff -U0 "$from" -- "$1" | awk '
      /^@@/ { split($3, a, ","); n = substr(a[1], 2) + 0; next }
      /^\+\+\+/ { next }
      /^\+/ { print n ":" substr($0, 2); n++ }'
  else
    grep -n '' "$1" || true
  fi
}

# Removed lines of one file, as text.
build_removed_lines() {
  git cat-file -e "$from:$1" 2>/dev/null || return 0
  git diff -U0 "$from" -- "$1" | grep -E '^-[^-]' | sed 's/^-//' || true
}

# Lines added in the file now, as text, to tell a moved line from a removed one.
build_added_text() {
  build_added_lines "$1" | sed 's/^[0-9]*://'
}

# True when ALLOW_NEAR appears on line $2 of file $1 or the 3 lines before it.
allowed_near() {
  local start=$(($2 - 3))
  [ "$start" -lt 1 ] && start=1
  sed -n "${start},${2}p" "$1" | grep -Eq "$ALLOW_NEAR"
}

changed="$(build_changed)"
echo "== Build files changed (since ${base:-HEAD})"
if [ -z "$changed" ]; then
  echo "None."
  finish build-guard
fi
echo "$changed"

echo "== Checks made to always pass"
hits=0
for f in $changed; do
  [ -f "$f" ] || continue
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    n="${line%%:*}"
    text="${line#*:}"
    echo "$text" | grep -Eq '^[[:space:]]*#' && continue
    if echo "$text" | grep -Eq -- "$WEAKEN"; then
      if echo "$text" | grep -q 'continue-on-error' && allowed_near "$f" "$n"; then
        continue
      fi
      say_fail "$f:$n makes a failing step pass. Fix the cause, or ask a human to approve it."
      hits=$((hits + 1))
    fi
  done <<< "$(build_added_lines "$f")"
done
[ "$hits" -eq 0 ] && echo "None added."

echo "== Steps or commands removed"
hits=0
for f in $changed; do
  if [ ! -f "$f" ]; then
    say_fail "$f was deleted. Deleting a build file needs a human."
    hits=$((hits + 1))
    continue
  fi
  added="$(build_added_text "$f")"
  while IFS= read -r text; do
    [ -n "$text" ] || continue
    # A step in CI is a "run:" line. In a script, a line that runs a check.
    case "$f" in
      .github/workflows/*) echo "$text" | grep -Eq '^[[:space:]]*-?[[:space:]]*run:' || continue ;;
      *)
        echo "$text" | grep -Eq '^[[:space:]]*(#|$)' && continue
        word="$(echo "$text" | grep -Eio -- "$CHECKS" | head -1)"
        [ -n "$word" ] || continue
        # Still runs the same kind of check on another line: a change, not a removal.
        echo "$added" | grep -v '^[[:space:]]*#' | grep -Fiq -- "$word" && continue
        ;;
    esac
    # Same command still there, maybe moved or reindented: not a removal.
    trimmed="$(echo "$text" | sed 's/^[[:space:]]*//')"
    if echo "$added" | sed 's/^[[:space:]]*//' | grep -qxF -- "$trimmed"; then
      continue
    fi
    say_fail "$f: removed or changed \"$(echo "$trimmed" | cut -c1-60)\". Removing a step needs a human. If you changed it, list the old and new line in your report."
    hits=$((hits + 1))
  done <<< "$(build_removed_lines "$f")"
done
[ "$hits" -eq 0 ] && echo "None removed."

echo "== Production deploy commands added"
hits=0
for f in $changed; do
  [ -f "$f" ] || continue
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    text="${line#*:}"
    case "$text" in *'Never put'*|*'never add'*|*'Never add'*) continue ;; esac
    if echo "$text" | grep -Eiq -- "$PROD"; then
      say_fail "$f:${line%%:*} adds a production deploy command. Only a person deploys to production."
      hits=$((hits + 1))
    fi
  done <<< "$(build_added_lines "$f")"
done
[ "$hits" -eq 0 ] && echo "None added."

finish build-guard
