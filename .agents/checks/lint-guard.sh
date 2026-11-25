#!/usr/bin/env bash
# Catches the shortcuts agents take to make lint pass, which a linter can't see:
#   1. a new suppression comment (noqa, type: ignore, gitleaks:allow, ...)
#   2. a change to a lint, spec lint, or secret scanner config file, the API
#      approvals file, or the git hooks
#   3. a new leftover file such as app_old.py, auth_v2.py, or notes.bak
#   4. "--no-verify" added to a script or doc
#
# Usage: .agents/checks/lint-guard.sh [base]
#   No argument: checks uncommitted and staged changes against HEAD. Agents
#   run it this way, and so does the pre-commit hook.
#   base: checks everything on this branch since it left base (for example
#   main), committed or not. Use it in CI or before a review.
#
# Exit code 0 means no shortcut found. Any failure prints FAIL and exits 1.
# Only a human may approve a suppression or a config change. A human who
# approves one commits with "git commit --no-verify". Agents never do.

set -uo pipefail
. "$(dirname "$0")/lib.sh"

# <!-- TAILOR: comments that switch a check off, as an extended regex. -->
SUPPRESS='(#[[:space:]]*noqa|#[[:space:]]*type:[[:space:]]*ignore|#[[:space:]]*nosec|#[[:space:]]*pragma:[[:space:]]*no[[:space:]]*cover|pylint:[[:space:]]*disable|#[[:space:]]*fmt:[[:space:]]*(off|skip)|#[[:space:]]*ruff:[[:space:]]*noqa|eslint-disable|@ts-ignore|@ts-expect-error|@ts-nocheck|biome-ignore|//[[:space:]]*nolint|rubocop:disable|@SuppressWarnings|markdownlint-disable|gitleaks:allow|<!--[[:space:]]*vale[[:space:]]+off)'

# <!-- TAILOR: lint config files and hooks agents must not change. -->
CONFIG='(^|/)(ruff\.toml|\.ruff\.toml|\.flake8|\.pylintrc|pylintrc|mypy\.ini|\.eslintrc(\..*)?|eslint\.config\.[a-z]+|\.prettierrc(\..*)?|biome\.jsonc?|\.markdownlint[^/]*|\.vale\.ini|\.editorconfig|\.pre-commit-config\.yaml|\.golangci\.ya?ml|\.rubocop\.yml|\.gitleaks\.toml|\.gitleaksignore|\.spectral\.ya?ml)$|^\.api/approved\.md$|^\.githooks/|^\.agents/checks/|^\.github/workflows/'

# Files that hold lint settings among other things. Only changed lines that
# look like lint settings count.
MIXED='(^|/)(pyproject\.toml|setup\.cfg|tox\.ini|package\.json|tsconfig[^/]*\.json)$'
MIXED_LINES='ruff|flake8|pylint|mypy|eslint|prettier|lint|noqa|strict|ignore|select|exclude|per-file'

# Names agents leave behind while debugging.
RESIDUE='(_(old|new|v[0-9]+|backup|bak|copy|fixed|final|temp|tmp|wip|orig|working|simple|enhanced)\.[A-Za-z0-9]+$|\.(bak|orig|tmp|swp)$|[ _-]copy( [0-9]+)?\.[A-Za-z0-9]+$)'

base="${1:-}"
if [ -n "$base" ]; then
  if ! git rev-parse --verify -q "$base" >/dev/null; then
    echo "FAIL: base \"$base\" is not a branch or commit here."
    exit 1
  fi
  from="$(git merge-base "$base" HEAD)"
elif git rev-parse --verify -q HEAD >/dev/null; then
  from="HEAD"
else
  # No commits yet: compare with the empty tree, so every file counts as added.
  from="$(git hash-object -t tree /dev/null)"
fi

# Changed files: tracked changes since $from, plus untracked files.
guard_changed() {
  { git diff --name-only "$from"; git ls-files --others --exclude-standard; } | sort -u
}

# Added files only: new since $from, plus untracked files.
guard_added() {
  { git diff --name-only --diff-filter=A "$from"; git ls-files --others --exclude-standard; } | sort -u
}

# Added lines of one file as "<line number in the file>:<text>".
guard_added_lines() {
  if git ls-files --error-unmatch "$1" >/dev/null 2>&1 && git cat-file -e "$from:$1" 2>/dev/null; then
    git diff -U0 "$from" -- "$1" | awk '
      /^@@/ { split($3, a, ","); n = substr(a[1], 2) + 0; next }
      /^\+\+\+/ { next }
      /^\+/ { print n ":" substr($0, 2); n++ }'
  else
    grep -n '' "$1" || true
  fi
}

# Changed lines (added or removed) of one file, without their line numbers.
guard_changed_lines() {
  git diff -U0 "$from" -- "$1" | grep -E '^[+-][^+-]' || true
}

changed="$(guard_changed)"
echo "== Changed files (since ${base:-HEAD})"
if [ -z "$changed" ]; then
  echo "No changes."
else
  echo "$changed"
fi

echo "== Suppression comments in added lines"
hits=0
for f in $changed; do
  [ -f "$f" ] || continue
  case "$f" in .agents/checks/lint-guard.sh) continue ;; esac
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    if echo "${line#*:}" | grep -Eiq "$SUPPRESS"; then
      say_fail "$f:${line%%:*} adds a suppression comment. Fix the code instead, or ask a human to approve it."
      hits=$((hits + 1))
    fi
  done <<< "$(guard_added_lines "$f")"
done
[ "$hits" -eq 0 ] && echo "None added."

echo "== Lint config and hook files"
hits=0
for f in $changed; do
  if echo "$f" | grep -Eq "$CONFIG"; then
    say_fail "$f changed. Only a human changes lint config, API approvals, hooks, or checks."
    hits=$((hits + 1))
  elif echo "$f" | grep -Eq "$MIXED"; then
    if guard_changed_lines "$f" | grep -Eiq "$MIXED_LINES"; then
      say_fail "$f has changed lines that look like lint settings. Only a human changes them."
      hits=$((hits + 1))
    fi
  fi
done
[ "$hits" -eq 0 ] && echo "None changed."

echo "== Leftover files"
hits=0
for f in $(guard_added); do
  if basename "$f" | grep -Eiq "$RESIDUE"; then
    say_fail "$f looks like a leftover copy. Delete it, or rename it to say what it holds."
    hits=$((hits + 1))
  fi
done
[ "$hits" -eq 0 ] && echo "None added."

echo "== Skipped hooks"
hits=0
for f in $changed; do
  [ -f "$f" ] || continue
  case "$f" in .agents/checks/lint-guard.sh) continue ;; esac
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    if echo "${line#*:}" | grep -q -- '--no-verify'; then
      say_fail "$f:${line%%:*} adds --no-verify. Don't skip hooks."
      hits=$((hits + 1))
    fi
  done <<< "$(guard_added_lines "$f")"
done
[ "$hits" -eq 0 ] && echo "None added."

finish lint-guard
