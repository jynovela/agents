#!/usr/bin/env bash
# Deterministic checks for a Test-Agent run. Run from the repo root after the
# agent finishes, before anything is committed.
#
# Usage: .agents/checks/test-agent.sh [report-file]
#   report-file: the agent's report. When given, the script also checks its
#   headings, and compares every "test: ... | result: ..." line under
#   "Criteria:" with the results of its own acceptance test run.
# Set BASE to compare against a branch other than main, e.g. BASE=develop.
#
# Exit code 0 means all checks passed. Any failure prints FAIL and exits 1.
# Failing tests alone don't fail this script: a failing test is a valid result,
# as long as the report names it and reports it truthfully.

set -uo pipefail
. "$(dirname "$0")/lib.sh"

# TAILOR: files the Test-Agent may change (extended regex on repo-relative paths).
ALLOWED='^report\.md$|^(.*/)?(tests?|__tests__|e2e|spec|acceptance)/.*$|^(.*/)?test_[^/]*\.py$|^(.*/)?[^/]*_test\.(py|go)$|^(.*/)?[^/]*\.(test|spec)\.[jt]sx?$'

# TAILOR: acceptance test files (extended regex). Mocks aren't allowed in them.
ACCEPT_PATH='^(.*/)?(acceptance|e2e)/.*$'

# TAILOR: test commands from the Dev environment section of AGENTS.md. Leave
# ACCEPT_CMD or the DEV_ commands empty if the project has none.
UNIT_CMD='python3 -m unittest discover -s tests -t .'
ACCEPT_CMD='python3 -m unittest discover -v -s acceptance -t .'
DEV_START='dev/start.sh'
DEV_STOP='dev/stop.sh'
DEV_HEALTH='dev/health.sh'

# TAILOR: extended regexes for the test runner's output. FAIL_PATTERN's second
# group is a failing test's name; RAN_PATTERN's first group is the name of any
# test that ran (needs verbose output).
FAIL_PATTERN='^(FAIL|ERROR): ([A-Za-z0-9_]+)'
RAN_PATTERN='^(test[A-Za-z0-9_]*) \('

BASE="${BASE:-main}"

# Patterns avoid \b and backreferences so they work with macOS grep too.
SKIP_PATTERN='unittest\.skip|@skip(If|Unless)?([^A-Za-z]|$)|expectedFailure|pytest\.mark\.(skip|xfail)|pytest\.(skip|xfail)\(|(^|[^A-Za-z_.])(xit|xdescribe|xtest|fit|fdescribe)\(|\.(skip|only|todo)\(|@Disabled|@Ignore|t\.Skip(Now|f)?\('
TRIVIAL_PATTERN='assertTrue\((True|1)\)|assert (True|1)( |#|$)|expect\(true\)\.toBe\(true\)|except( Exception)?: *pass|catch *\([^)]*\) *\{ *\}'
MOCK_PATTERN='mock\.patch|patch\(|patch\.object|MagicMock|Mock\(|monkeypatch|jest\.mock|vi\.mock|jest\.spyOn|vi\.spyOn|sinon\.'

failing_in() { echo "$1" | grep -Eo "$FAIL_PATTERN" | sed -E "s/$FAIL_PATTERN/\2/" | sort -u; }

check_scope "$ALLOWED"

changed="$(changed_files)"
tests_changed="$(echo "$changed" | grep -E "$ALLOWED" | grep -v '^report\.md$' || true)"

echo "== Deleted test files"
deleted="$(git diff --name-only --diff-filter=D HEAD | grep -E "$ALLOWED" || true)"
if [ -n "$deleted" ]; then
  say_fail "test files deleted or renamed (needs human approval):"
  echo "$deleted" | sed 's/^/  /'
else
  echo "None."
fi

echo "== Changed lines in existing test files"
# Existing test files are add-only. Any removed or edited line needs approval.
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

echo "== Skip markers, trivial asserts, and mocks in added lines"
found=0
mocks=0
for f in $tests_changed; do
  [ -f "$f" ] || continue
  added="$(added_lines "$f")"
  hit="$(echo "$added" | grep -E -- "$SKIP_PATTERN" | cut -d: -f1 | tr '\n' ' ' || true)"
  [ -n "$hit" ] && say_fail "skip or disable marker added in $f, diff lines: $hit" && found=1
  hit="$(echo "$added" | grep -E -- "$TRIVIAL_PATTERN" | cut -d: -f1 | tr '\n' ' ' || true)"
  [ -n "$hit" ] && say_fail "assert that can't fail, or swallowed error, added in $f, diff lines: $hit" && found=1
  n="$(echo "$added" | grep -cE -- "$MOCK_PATTERN" || true)"
  if [ "$n" -gt 0 ]; then
    if echo "$f" | grep -Eq "$ACCEPT_PATH"; then
      say_fail "mocks in acceptance test $f: acceptance tests must use the real app"
      found=1
    else
      echo "  $f: $n line(s) with mocks (must be listed under \"Mocks:\")"
      mocks=$((mocks + n))
    fi
  fi
done
[ "$found" -eq 0 ] && echo "No skip markers, trivial asserts, or mocks in acceptance tests."

check_secrets

echo "== Unit tests: $UNIT_CMD"
unit_out="$(eval "$UNIT_CMD" 2>&1)"
unit_status=$?
echo "$unit_out" | tail -n 3 | sed 's/^/  | /'
unit_failing="$(failing_in "$unit_out")"
if [ "$unit_status" -ne 0 ] && [ -z "$unit_failing" ]; then
  say_fail "unit tests failed but no failing test names were found; read the output above"
fi

echo "== Regressions against $BASE"
# Runs the unit tests on $BASE in a temporary worktree. A test that passes
# there and fails here is a regression: old behavior broke.
regressions=""
if [ -n "$unit_failing" ] && git rev-parse --verify -q "$BASE" >/dev/null; then
  wt="$(mktemp -d)"
  if git worktree add -q --detach "$wt" "$BASE" >/dev/null 2>&1; then
    base_failing="$(failing_in "$(cd "$wt" && eval "$UNIT_CMD" 2>&1)")"
    for t in $unit_failing; do
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
    echo "Pass on $BASE, fail now (mark each \"Regression:\" in the report):"
    for t in $regressions; do echo "  $t"; done
  else
    echo "None."
  fi
else
  echo "None to check."
fi

echo "== Acceptance tests: ${ACCEPT_CMD:-none}"
acc_ran=""
acc_failing=""
if [ -z "$ACCEPT_CMD" ]; then
  echo "No acceptance test command. The report must say the criteria are untested."
else
  started=0
  if [ -n "$DEV_HEALTH" ] && ! eval "$DEV_HEALTH" >/dev/null 2>&1; then
    if eval "$DEV_START" >/dev/null 2>&1; then started=1; else say_fail "could not start the app with: $DEV_START"; fi
  fi
  acc_out="$(eval "$ACCEPT_CMD" 2>&1)"
  echo "$acc_out" | tail -n 3 | sed 's/^/  | /'
  acc_ran="$(echo "$acc_out" | grep -Eo "$RAN_PATTERN" | sed -E "s/$RAN_PATTERN/\1/" | sort -u)"
  acc_failing="$(failing_in "$acc_out")"
  for t in $acc_ran; do
    if echo "$acc_failing" | grep -qx "$t"; then echo "  FAIL  $t"; else echo "  PASS  $t"; fi
  done
  [ "$started" -eq 1 ] && eval "$DEV_STOP" >/dev/null 2>&1
fi

if [ "${1:-}" != "" ]; then
  report="$1"
  check_headings "$report" "Mode:" "Criteria:" "Added:" "Mocks:" "Failing tests (not fixed):" "Security flags:" "Needs approval:" "Verify:"
  if [ -f "$report" ]; then
    section() { awk -v h="$1" '$0 ~ "^"h {f=1; next} /^[A-Z][A-Za-z ()]*:/ {f=0} f' "$report"; }
    mode="$(grep -E '^Mode:' "$report" | head -1 | sed 's/^Mode: *//')"
    case "$mode" in Write|Verify) ;; *) say_fail "\"Mode:\" must be Write or Verify, found \"$mode\"" ;; esac

    echo "== Report claims against the real run"
    claims="$(section 'Criteria:' | grep -E '^ *- ' | grep -viE '^ *- *None' || true)"
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      t="$(echo "$line" | sed -nE 's/.*test: *([A-Za-z0-9_]+).*/\1/p')"
      r="$(echo "$line" | sed -nE 's/.*result: *(PASS|FAIL).*/\1/p')"
      if [ -z "$t" ] || [ -z "$r" ]; then
        say_fail "criterion line lacks \"test: <name>\" or \"result: PASS|FAIL\": ${line:0:60}"
        continue
      fi
      if ! echo "$acc_ran" | grep -qx "$t"; then
        say_fail "report cites $t, but no acceptance test with that name ran"
        continue
      fi
      actual=PASS
      echo "$acc_failing" | grep -qx "$t" && actual=FAIL
      if [ "$r" != "$actual" ]; then
        say_fail "report says $t is $r, but it is $actual"
      elif [ "$mode" = "Write" ] && [ "$r" = "PASS" ] && ! echo "$line" | grep -qi "already met"; then
        say_fail "Write mode: $t passes before the feature exists; mark it \"already met\" or fix the test"
      else
        echo "  OK  $t $r"
      fi
    done <<< "$claims"
    for t in $acc_ran; do
      echo "$claims" | grep -qw "$t" || say_fail "acceptance test $t ran but isn't under \"Criteria:\""
    done

    for t in $unit_failing $acc_failing; do
      grep -qw "$t" "$report" || say_fail "failing test $t is not named in the report"
    done
    for t in $regressions; do
      grep -w "$t" "$report" | grep -qi "regression" || say_fail "regression $t is not marked \"Regression:\" in the report"
    done
    if [ "$mocks" -gt 0 ]; then
      listed="$(section 'Mocks:' | grep -E '^ *- ' | grep -viE '^ *- *None' || true)"
      [ -n "$listed" ] || say_fail "new tests use mocks but \"Mocks:\" lists none"
    fi
  fi
fi

finish "Test-Agent"
