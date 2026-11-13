#!/usr/bin/env bash
# Deterministic checks for a Test-Agent run. Run from the repo root after the
# agent finishes, before anything is committed.
#
# Usage: .agents/checks/test-agent.sh [report-file]
#   report-file: optional file holding the agent's report. When given, the
#   script also checks its headings, that every failing test is named in it,
#   and that it lists the mocks the new tests use.
# Set BASE to compare against a branch other than main, e.g. BASE=develop.
#
# Exit code 0 means all checks passed. Any failure prints FAIL and exits 1.
# Failing tests alone don't fail this script: a failing test that exposes a bug
# is a valid result, as long as the report names it.

set -uo pipefail
. "$(dirname "$0")/lib.sh"

# TAILOR: files the Test-Agent may change (extended regex on repo-relative paths).
ALLOWED='^(.*/)?(tests?|__tests__|e2e|spec)/.*$|^(.*/)?test_[^/]*\.py$|^(.*/)?[^/]*_test\.(py|go)$|^(.*/)?[^/]*\.(test|spec)\.[jt]sx?$'

# TAILOR: the project's test command, and an extended regex that pulls the
# name of each failing test out of its output (first capture group).
TEST_CMD='python3 -m unittest discover -s tests -t .'
FAIL_PATTERN='^(FAIL|ERROR): ([A-Za-z0-9_]+)'

# Mock calls in added lines; each new test file that uses them needs a "Mocks:" entry.
MOCK_PATTERN='mock\.patch|patch\(|patch\.object|MagicMock|Mock\(|monkeypatch|jest\.mock|vi\.mock|jest\.spyOn|vi\.spyOn|sinon\.'

BASE="${BASE:-main}"

# Patterns avoid \b and backreferences so they work with macOS grep too.
# Markers that skip, disable, or focus tests, across common frameworks.
SKIP_PATTERN='unittest\.skip|@skip(If|Unless)?([^A-Za-z]|$)|expectedFailure|pytest\.mark\.(skip|xfail)|pytest\.(skip|xfail)\(|(^|[^A-Za-z_.])(xit|xdescribe|xtest|fit|fdescribe)\(|\.(skip|only|todo)\(|@Disabled|@Ignore|t\.Skip(Now|f)?\('

# Asserts that can never fail, and swallowed errors.
TRIVIAL_PATTERN='assertTrue\((True|1)\)|assert (True|1)( |#|$)|expect\(true\)\.toBe\(true\)|except( Exception)?: *pass|catch *\([^)]*\) *\{ *\}'

check_scope "$ALLOWED"

changed="$(changed_files)"
tests_changed="$(echo "$changed" | grep -E "$ALLOWED" || true)"

echo "== Deleted test files"
deleted="$(git diff --name-only --diff-filter=D HEAD | grep -E "$ALLOWED" || true)"
if [ -n "$deleted" ]; then
  say_fail "test files deleted or renamed (needs human approval):"
  echo "$deleted" | sed 's/^/  /'
else
  echo "None."
fi

echo "== Changed lines in existing test files"
# Existing test files are add-only. Any removed or edited line, including an
# assertion or an import, needs human approval.
edits=0
for f in $tests_changed; do
  git ls-files --error-unmatch "$f" >/dev/null 2>&1 || continue
  [ -f "$f" ] || continue
  removed="$(git diff -U0 HEAD -- "$f" | grep -c '^-[^-]' || true)"
  if [ "$removed" -gt 0 ]; then
    say_fail "$f: $removed existing line(s) changed or removed (needs human approval)"
    edits=1
  fi
done
[ "$edits" -eq 0 ] && echo "None. Existing tests only had lines added."

echo "== Skip, disable, and focus markers"
marks=0
for f in $changed; do
  [ -f "$f" ] || continue
  hit="$(added_lines "$f" | grep -E -- "$SKIP_PATTERN" | cut -d: -f1 | tr '\n' ' ' || true)"
  if [ -n "$hit" ]; then
    say_fail "skip or disable marker added in $f, diff lines: $hit"
    marks=1
  fi
done
[ "$marks" -eq 0 ] && echo "None added."

echo "== Trivial asserts and swallowed errors"
trivial=0
for f in $changed; do
  [ -f "$f" ] || continue
  hit="$(added_lines "$f" | grep -E -- "$TRIVIAL_PATTERN" | cut -d: -f1 | tr '\n' ' ' || true)"
  if [ -n "$hit" ]; then
    say_fail "assert that can't fail, or swallowed error, added in $f, diff lines: $hit"
    trivial=1
  fi
done
[ "$trivial" -eq 0 ] && echo "None added."

check_secrets

echo "== Test run: $TEST_CMD"
out="$(eval "$TEST_CMD" 2>&1)"
status=$?
echo "$out" | tail -n 5 | sed "s/^/  | /"
failing="$(echo "$out" | grep -Eo "$FAIL_PATTERN" | sed -E "s/$FAIL_PATTERN/\2/" | sort -u)"
if [ "$status" -eq 0 ]; then
  echo "All tests pass."
elif [ -z "$failing" ]; then
  say_fail "the test command failed but no failing test names were found; read the output above"
else
  echo "Failing tests (each must be in the report under \"Failing tests (not fixed):\"):"
  echo "$failing" | sed 's/^/  /'
fi

echo "== Regressions against $BASE"
# Runs the same test command on $BASE in a temporary worktree. A test that
# passes there and fails here is a regression: old behavior broke.
regressions=""
if [ -n "$failing" ] && git rev-parse --verify -q "$BASE" >/dev/null; then
  wt="$(mktemp -d)"
  if git worktree add -q --detach "$wt" "$BASE" >/dev/null 2>&1; then
    base_out="$(cd "$wt" && eval "$TEST_CMD" 2>&1)"
    base_failing="$(echo "$base_out" | grep -Eo "$FAIL_PATTERN" | sed -E "s/$FAIL_PATTERN/\2/" | sort -u)"
    for t in $failing; do
      echo "$base_failing" | grep -qx "$t" && continue
      grep -rqw "$t" "$wt" 2>/dev/null || continue
      regressions="$regressions $t"
    done
    git worktree remove --force "$wt" >/dev/null 2>&1
  else
    echo "Could not check out $BASE; skipped."
  fi
  rm -rf "$wt"
  if [ -n "$regressions" ]; then
    echo "Pass on $BASE, fail now (report each as a regression):"
    for t in $regressions; do echo "  $t"; done
  else
    echo "None. Every failing test is new or already failed on $BASE."
  fi
elif [ -z "$failing" ]; then
  echo "None. No failing tests."
else
  echo "No branch $BASE; skipped. Set BASE to the base branch."
fi

echo "== Mocks in added lines"
mocks=0
for f in $tests_changed; do
  [ -f "$f" ] || continue
  n="$(added_lines "$f" | grep -cE -- "$MOCK_PATTERN" || true)"
  [ "$n" -gt 0 ] && echo "  $f: $n line(s) with mocks" && mocks=$((mocks + n))
done
[ "$mocks" -eq 0 ] && echo "None."

if [ "${1:-}" != "" ]; then
  check_headings "$1" "Baseline:" "Added:" "Mocks:" "Failing tests (not fixed):" "Coverage:" "Security flags:" "Needs approval:" "Verify:"
  if [ -f "$1" ]; then
    for t in $failing; do
      grep -qF "$t" "$1" || say_fail "failing test $t is not named in the report"
    done
    for t in $regressions; do
      grep -F "$t" "$1" | grep -qi "regression" || say_fail "regression $t is not marked as a regression in the report"
    done
    if [ "$mocks" -gt 0 ]; then
      listed="$(awk '/^Mocks:/{f=1; next} /^[A-Z][A-Za-z ()]*:/{f=0} f' "$1" | grep -E '^ *- ' | grep -viE '^ *- *None' || true)"
      [ -n "$listed" ] || say_fail "new tests use mocks but the report's \"Mocks:\" section lists none"
    fi
  fi
fi

finish "Test-Agent"
