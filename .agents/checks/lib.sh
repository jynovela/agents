#!/usr/bin/env bash
# Shared helpers for the role check scripts. Source it; don't run it.
#   . "$(dirname "$0")/lib.sh"
#
# Every check reads uncommitted changes against HEAD. Secret values are never
# printed: only file names.

fail=0
say_fail() { echo "FAIL: $*"; fail=1; }

# Changed and untracked files, one per line.
changed_files() {
  { git diff --name-only HEAD; git ls-files --others --exclude-standard; } | sort -u
}

# Added lines of one file as "<n>:+<text>". A new untracked file counts as all
# added.
added_lines() {
  if git ls-files --error-unmatch "$1" >/dev/null 2>&1; then
    git diff -U0 HEAD -- "$1" | grep -n '^+[^+]' || true
  else
    grep -n '' "$1" | sed 's/^\([0-9]*\):/\1:+/' || true
  fi
}

# Fails on changed files that don't match the extended regex in $1.
check_scope() {
  local allowed="$1" changed outside
  changed="$(changed_files)"
  echo "== Changed files"
  if [ -z "$changed" ]; then
    echo "No uncommitted changes. If the agent committed, that breaks its rules."
    return
  fi
  echo "$changed"
  outside="$(echo "$changed" | grep -Ev "$allowed" || true)"
  if [ -n "$outside" ]; then
    say_fail "changed files outside the allowed paths:"
    echo "$outside" | sed 's/^/  /'
  fi
}

# Long tokens that mix letters and digits, or known key prefixes, in added
# lines of every changed file. Runs gitleaks too when it's installed.
check_secrets() {
  local f line text hits=0
  echo "== Secret scan on added lines"
  for f in $(changed_files); do
    [ -f "$f" ] || continue
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      text="${line#*:}"
      if echo "$text" | grep -Eq -- '(-----BEGIN [A-Z ]*PRIVATE KEY|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{30,}|sk-[A-Za-z0-9]{20,}|xox[abpr]-)' \
        || echo "$text" | grep -Eo '[A-Za-z0-9_+/=-]{24,}' | grep -v '^-*$' | grep -Eq '[0-9]' ; then
        say_fail "possible secret added in $f (value not shown)"
        hits=$((hits + 1))
        break
      fi
    done <<< "$(added_lines "$f")"
  done
  if command -v gitleaks >/dev/null 2>&1; then
    for f in $(changed_files); do
      [ -f "$f" ] || continue
      gitleaks dir --no-banner --redact "$f" >/dev/null 2>&1 || say_fail "gitleaks found a secret in $f"
    done
  else
    echo "gitleaks not installed; ran the built-in pattern check only."
  fi
  [ "$hits" -eq 0 ] && echo "No secret-like values found in added lines."
}

# Fails when the report file $1 lacks any of the remaining arguments.
check_headings() {
  local report="$1" h
  shift
  echo "== Report headings"
  if [ ! -f "$report" ]; then
    say_fail "report file $report not found"
    return
  fi
  for h in "$@"; do
    grep -qF "$h" "$report" || say_fail "report is missing the heading \"$h\""
  done
}

# Prints the final result and exits. $1 is the role name.
finish() {
  echo
  if [ "$fail" -ne 0 ]; then
    echo "$1 checks: FAILED"
    exit 1
  fi
  echo "$1 checks: passed"
  exit 0
}
