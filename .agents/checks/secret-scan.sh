#!/usr/bin/env bash
# Scans for secrets with gitleaks and prints where they are, never what they
# are: each finding is "<file>:<line> <rule>". The value is never printed.
#
# Usage: .agents/checks/secret-scan.sh [--staged | base]
#   --staged: scans only staged changes. The pre-commit hook runs it this way.
#   No argument: scans uncommitted changes against HEAD (staged, unstaged, and
#   new untracked files). Agents run it this way before they finish.
#   base: also scans every commit on this branch since it left base (for
#   example main). A secret that was added and then deleted still counts,
#   because it's still in the history. Use it in CI or before a review.
#
# Exit code 0 means no secret found. A finding, or gitleaks missing, prints
# FAIL and exits 1. See setup/security.md.

set -uo pipefail
. "$(dirname "$0")/lib.sh"

if ! command -v gitleaks >/dev/null 2>&1; then
  echo "FAIL: gitleaks is not installed, so nothing was scanned. Install it: see setup/security.md."
  exit 1
fi

cd "$(git rev-parse --show-toplevel)" || exit 1

# gitleaks looks for its config next to what it scans, which misses the repo
# config when it scans one file. Pass it explicitly.
cfg=()
[ -f .gitleaks.toml ] && cfg=(--config .gitleaks.toml)

base="${1:-}"
staged_only=0
if [ "$base" = "--staged" ]; then
  staged_only=1
  base=""
fi
if [ -n "$base" ] && ! git rev-parse --verify -q "$base" >/dev/null; then
  echo "FAIL: base \"$base\" is not a branch or commit here."
  exit 1
fi

tmpl="$(mktemp)"
out="$(mktemp)"
trap 'rm -f "$tmpl" "$out"' EXIT
# One line per finding: file, line, and rule. The secret itself is left out.
printf '{{ range . }}{{ .File }}:{{ .StartLine }} {{ .RuleID }}\n{{ end }}' > "$tmpl"

leaks() {
  gitleaks "$@" ${cfg[@]+"${cfg[@]}"} --redact --no-banner --log-level error \
    --report-format template --report-template "$tmpl" --report-path - >> "$out" 2>/dev/null
  # Exit code 1 means leaks found. Anything else above 1 is an error.
  local rc=$?
  if [ "$rc" -gt 1 ]; then
    say_fail "gitleaks $1 exited with code $rc, so this part wasn't scanned."
  fi
}

if [ "$staged_only" -eq 1 ]; then
  echo "== Secret scan (staged changes)"
else
  echo "== Secret scan (since ${base:-HEAD})"
fi
leaks git --pre-commit --staged .
untracked=""
if [ "$staged_only" -eq 0 ]; then
  leaks git --pre-commit .
  untracked="$(git ls-files --others --exclude-standard)"
fi
if [ -n "$untracked" ]; then
  while IFS= read -r f; do
    [ -f "$f" ] && leaks dir "$f"
  done <<< "$untracked"
fi
if [ -n "$base" ]; then
  leaks git --log-opts="$base..HEAD" .
fi

found="$(grep -v '^[[:space:]]*$' "$out" | sort -u)"
if [ -n "$found" ]; then
  while IFS= read -r line; do
    say_fail "$line (value not shown)"
  done <<< "$found"
  echo "Don't copy, move, or print these values. Report each file and line to a human."
else
  echo "No secrets found."
fi

finish secret-scan
