#!/usr/bin/env bash
# Deterministic checks for an Implementer-Agent run. Run from the repo root
# after the agent finishes, before anything is committed.
#
# Usage: .agents/skills/implementer-agent/check.sh report.md [base]
#   base: the main branch the ticket branch came from (default: main).
#
# It reruns the acceptance and unit tests twice: once on the committed code
# (HEAD, before the agent's change) in a temporary worktree, and once on the
# code as it is now. It needs the app's port free while it runs, and leaves
# the app running only if it was running before.
#
# Exit code 0 means all checks passed. Any failure prints FAIL and exits 1.
# Failing tests alone don't fail this script, as long as the report says so.

set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/../../shared/lib.sh"
helper="$here/tools/implementer-run.sh"

# <!-- TAILOR: files the agent must never change, as an extended regex. Other
# agents or a person own them. Keep in sync with "Fenced files" in
# .agents/skills/implementer-agent/SKILL.md. -->
FENCED='(^|/)(tests?|__tests__|e2e|spec|acceptance)/|(^|/)test_[^/]*\.py$|_test\.(py|go)$|\.(test|spec)\.[jt]sx?$'
FENCED="$FENCED"'|^openapi\.ya?ml$|^\.api/|^\.spectral\.ya?ml$'
FENCED="$FENCED"'|^\.github/|^\.gitlab-ci\.yml$|^\.githooks/|^dev/|^scripts/|^setup/|(^|/)(Makefile|Dockerfile)$'
FENCED="$FENCED"'|^seed\.sql$|(^|/)(ruff\.toml|\.ruff\.toml|pyproject\.toml|setup\.cfg|\.flake8|\.markdownlint[^/]*|\.eslintrc[^/]*|\.pre-commit-config\.yaml|\.gitleaks\.toml)$'
FENCED="$FENCED"'|(^|/)(requirements[^/]*\.txt|package(-lock)?\.json|poetry\.lock|go\.(mod|sum))$'
FENCED="$FENCED"'|^\.agents/|^\.claude/|^\.hermes|(^|/)(AGENTS|CLAUDE)\.md$|(^|/)\.env'
FENCED="$FENCED"'|\.md$|^docs/|(^|/)CHANGELOG'

# <!-- TAILOR: the health check from the Dev environment section, and the
# stop command, so the check can free the port and restore the app. -->
DEV_HEALTH='dev/health.sh'
DEV_STOP='dev/stop.sh'
DEV_START='dev/start.sh'

# Added code lines that make code behave differently under test. Code that
# knows it's being tested passes tests without doing the work.
TEST_AWARE='unittest|pytest|test_c[0-9]|test-token|PYTEST_CURRENT_TEST|sys\.modules'

LOG_DIR='logs/implementer'

report="${1:-}"
base="${2:-main}"
if [ -z "$report" ]; then
  echo "Usage: .agents/skills/implementer-agent/check.sh report.md [base]"
  exit 1
fi

# Lines of one report section: from the heading line to the next heading.
section() {
  awk -v h="$1" '
    index($0, h) == 1 { on = 1; next }
    on && /^[A-Z][A-Za-z ()]+:/ { exit }
    on { print }' "$report"
}
# The text after a one-line heading like "Branch: x".
value() { grep -m1 "^$1:" "$report" | sed "s/^$1:[[:space:]]*//" | sed 's/[[:space:]]*$//'; }
items() { section "$1" | grep -E '^- ' | grep -vE '^- None' || true; }

check_headings "$report" "### Implementer-Agent report" "Ticket:" "Branch:" \
  "Stopped:" "Criteria:" "Plan:" "Files changed:" "Unit tests:" \
  "Failing tests (not fixed):" "Needs approval:" "Handoffs:" \
  "Security flags:" "Runs:" "Verify:"
[ -f "$report" ] || finish implementer-agent

code="$(changed_files | grep -Ev "^$(echo "$report" | sed 's/[.[\*^$()+?{|]/\\&/g')\$|^$LOG_DIR/" || true)"

echo "== Branch"
branch="$(git branch --show-current 2>/dev/null)"
echo "On: ${branch:-detached HEAD}"
case "$branch" in
  "" ) say_fail "not on a branch. Work on the ticket's branch." ;;
  "$base"|main|master) say_fail "on $branch. Work on the ticket's branch, never on $branch." ;;
esac
[ "$(value Branch)" = "$branch" ] || say_fail "\"Branch:\" says \"$(value Branch)\", but the current branch is \"$branch\""

echo "== Stopped"
stopped="$(value Stopped)"
echo "${stopped:-<empty>}"
if [ -z "$stopped" ]; then
  say_fail "\"Stopped:\" is empty. Write None, or why you stopped."
elif [ "$stopped" != "None" ] && [ -n "$code" ]; then
  say_fail "the report says it stopped, but code changed:"
  echo "$code" | sed 's/^/  /'
fi

echo "== Fenced files"
fenced="$(echo "$code" | grep -E "$FENCED" || true)"
if [ -n "$fenced" ]; then
  say_fail "changed files the agent must never change (tests, spec, CI, build, config, deps, agent files, docs):"
  echo "$fenced" | sed 's/^/  /'
else
  echo "None changed."
fi
deleted="$(git diff --name-only --diff-filter=D HEAD)"
if [ -n "$deleted" ]; then
  say_fail "files deleted (deleting is Ask first):"
  echo "$deleted" | sed 's/^/  /'
fi

echo "== Plan covers every changed file"
plan="$(items "Plan:")"
hits=0
while IFS= read -r l; do
  [ -n "$l" ] || continue
  f="$(echo "$l" | sed -E 's/^- ([^ |]+).*/\1/')"
  echo "$l" | grep -Eq 'for: *C[0-9]' || { say_fail "Plan line for $f has no \"for: C<n>\""; hits=$((hits + 1)); }
  if echo "$f" | grep -Eq "$FENCED"; then
    say_fail "Plan lists $f, which is fenced. List the change under \"Needs approval\" instead."
    hits=$((hits + 1))
  fi
done <<< "$plan"
listed="$(items "Files changed:")"
for f in $code; do
  echo "$plan" | grep -qF -- "- $f |" || { say_fail "$f changed, but isn't in \"Plan:\" as \"- $f | for: C<n> | ...\""; hits=$((hits + 1)); }
  echo "$listed" | grep -qF -- "- $f |" || { say_fail "$f changed, but isn't under \"Files changed:\""; hits=$((hits + 1)); }
done
[ "$hits" -eq 0 ] && echo "OK."

echo "== Code that knows it's under test"
hits=0
for f in $code; do
  [ -f "$f" ] || continue
  echo "$f" | grep -Eq "$FENCED" && continue
  hit="$(added_lines "$f" | grep -E -- "$TEST_AWARE" | cut -d: -f1 | tr '\n' ' ' || true)"
  if [ -n "$hit" ]; then
    say_fail "$f adds code that checks for tests (diff lines: $hit). Make the feature work instead."
    hits=$((hits + 1))
  fi
done
[ "$hits" -eq 0 ] && echo "None."

check_secrets

echo "== Lint guard on the agent's changes"
out="$("$here/../../shared/lint-guard.sh" 2>&1)"
fails="$(echo "$out" | grep '^FAIL: ' | sed 's/^FAIL: //' || true)"
if [ -n "$fails" ]; then
  while IFS= read -r l; do say_fail "$l"; done <<< "$fails"
elif echo "$out" | tail -1 | grep -q '^lint-guard checks: '; then
  echo "Passed."
else
  say_fail "lint-guard didn't finish. Its last line: $(echo "$out" | tail -1)"
fi

# Fails if a helper run in folder $2 didn't finish or the app didn't start.
check_run() {
  if ! echo "$1" | tail -1 | grep -q '^RUN_DONE$'; then
    say_fail "implementer-run.sh raw didn't finish in $2. Its last line: $(echo "$1" | tail -1)"
  fi
  if echo "$1" | grep -q '^START_FAILED'; then
    say_fail "the app did not start in $2"
  fi
}
result_of() { echo "$1" | grep -E "^ACCEPT_RESULT (PASS|FAIL) $2\$" | awk '{print $2}'; }

was_up=0
if [ -n "$DEV_HEALTH" ] && eval "$DEV_HEALTH" >/dev/null 2>&1; then was_up=1; fi
[ -n "$DEV_STOP" ] && eval "$DEV_STOP" >/dev/null 2>&1
if [ -n "$DEV_HEALTH" ] && eval "$DEV_HEALTH" >/dev/null 2>&1; then
  say_fail "something else is still serving the app's port after $DEV_STOP. Stop it and rerun."
fi

echo "== Tests on the committed code (HEAD), before the change"
before=""
wt="$(mktemp -d)"
if git worktree add -q --detach "$wt" HEAD >/dev/null 2>&1; then
  before="$(cd "$wt" && "$helper" raw 2>&1)"
  check_run "$before" "$wt"
  (cd "$wt" && [ -n "$DEV_STOP" ] && eval "$DEV_STOP" >/dev/null 2>&1)
  git worktree remove --force "$wt" >/dev/null 2>&1
else
  say_fail "could not check out HEAD in a temporary worktree"
fi
rm -rf "$wt"
echo "$before" | grep -E '^(ACCEPT_RESULT|UNIT_SUMMARY)' | sed 's/^/  /'

echo "== Tests on the code now"
after="$("$helper" raw 2>&1)"
check_run "$after" "the repo"
echo "$after" | grep -E '^(ACCEPT_RESULT|UNIT_SUMMARY)' | sed 's/^/  /'
if [ "$was_up" -eq 1 ]; then
  [ -n "$DEV_START" ] && eval "$DEV_START" >/dev/null 2>&1
else
  [ -n "$DEV_STOP" ] && eval "$DEV_STOP" >/dev/null 2>&1
fi
now_hash="$("$helper" hash)"

echo "== Report claims against the real runs"
claims="$(items "Criteria:")"
[ -n "$claims" ] || say_fail "\"Criteria:\" lists no criteria"
failing_before=0
cited=""
while IFS= read -r line; do
  [ -n "$line" ] || continue
  id="$(echo "$line" | sed -nE 's/^- (C[0-9]+):.*/\1/p')"
  t="$(echo "$line" | sed -nE 's/.*test: *([A-Za-z0-9_]+).*/\1/p')"
  b="$(echo "$line" | sed -nE 's/.*before: *(PASS|FAIL).*/\1/p')"
  a="$(echo "$line" | sed -nE 's/.*after: *(PASS|FAIL|not run).*/\1/p')"
  ev="$(echo "$line" | sed -nE 's/.*evidence: *([^ :`]+):([0-9]+) *`(.*)`.*/\1|\2|\3/p')"
  if [ "$stopped" != "None" ] && [ -z "$t" ]; then
    echo "  OK  ${id:-?} has no test (stopped)"
    continue
  fi
  if [ -z "$id" ] || [ -z "$t" ] || [ -z "$b" ]; then
    say_fail "criterion line needs \"- C<n>: ... | test: <name> | before: PASS|FAIL | after: ...\": ${line:0:70}"
    continue
  fi
  cited="$cited $t"
  hb="$(result_of "$before" "$t")"
  if [ -z "$hb" ]; then
    say_fail "$id cites $t, but no acceptance test with that name ran on HEAD. Tests must exist before you start."
    continue
  fi
  if [ "$b" != "$hb" ]; then
    say_fail "$id says $t was $b before, but on HEAD it is $hb"
  elif [ "$hb" = PASS ] && ! echo "$line" | grep -qi "already met"; then
    say_fail "$t passes on HEAD, before any change. Write \"already met\" on $id, or stop: the test doesn't test the ticket."
  fi
  [ "$hb" = FAIL ] && failing_before=$((failing_before + 1))
  if [ "$stopped" != "None" ]; then
    echo "  OK  $id $t before $b (stopped)"
    continue
  fi
  ha="$(result_of "$after" "$t")"
  if [ "$a" != "$ha" ]; then
    say_fail "$id says $t is ${a:-missing} after the change, but it is ${ha:-not run}"
    continue
  fi
  if [ -z "$ev" ]; then
    say_fail "$id has no evidence. Write \"evidence: $LOG_DIR/run-<N>.log:<line> \`<text of that line>\`\""
    continue
  fi
  log="${ev%%|*}"; rest="${ev#*|}"; n="${rest%%|*}"; quote="${rest#*|}"
  case "$log" in "$LOG_DIR"/run-*.log) ;; *) say_fail "$id evidence must come from $LOG_DIR/run-<N>.log, not $log"; continue ;; esac
  if [ ! -f "$log" ]; then
    say_fail "$id cites $log, which doesn't exist"
    continue
  fi
  if [ "$(sed -n 2p "$log" | sed 's/^CODE_HASH //')" != "$now_hash" ]; then
    say_fail "$id cites $log, but that run was on older code. Run the tests again after your last edit and cite the new log."
    continue
  fi
  text="$(sed -n "${n}p" "$log")"
  if ! echo "$text" | grep -qF -- "$quote"; then
    say_fail "$id quote isn't on $log line $n. That line is: ${text:0:80}"
  elif ! echo "$text" | grep -qw -- "$t"; then
    say_fail "$id cites $log line $n, which isn't the result line of $t"
  elif [ "$ha" = PASS ] && ! echo "$text" | grep -Eq 'ok *$'; then
    say_fail "$id says PASS, but $log line $n doesn't end in \"ok\""
  elif [ "$ha" = FAIL ] && ! echo "$text" | grep -Eq 'FAIL|ERROR'; then
    say_fail "$id says FAIL, but $log line $n doesn't say FAIL or ERROR"
  else
    echo "  OK  $id $t before $b, after $a"
  fi
done <<< "$claims"

echo "== Regressions not named in the report"
hits=0
for l in $(echo "$after" | grep '^ACCEPT_RESULT FAIL ' | awk '{print $3}'); do
  echo " $cited " | grep -q " $l " && continue
  if [ "$(result_of "$before" "$l")" = PASS ]; then
    grep -w -- "$l" "$report" | grep -qi regression \
      || { say_fail "acceptance test $l passed on HEAD and fails now. Name it with \"Regression:\" in the report."; hits=$((hits + 1)); }
  fi
done
for l in $(echo "$after" | sed -n 's/^UNIT_FAIL //p'); do
  echo "$before" | grep -qx "UNIT_FAIL $l" && continue
  grep -w -- "$l" "$report" | grep -qi regression \
    || { say_fail "unit test $l passed on HEAD and fails now. Name it with \"Regression:\" in the report."; hits=$((hits + 1)); }
done
[ "$hits" -eq 0 ] && echo "None."

echo "== Unit tests"
unit_now="$(echo "$after" | sed -n 's/^UNIT_SUMMARY //p')"
unit_line="$(section "Unit tests:" | grep -E '^- after:' | head -1)"
if [ "$stopped" = "None" ] && ! echo "$unit_line" | grep -qF -- "$unit_now"; then
  say_fail "\"Unit tests:\" needs \"- after: $unit_now\", from your last run"
else
  echo "OK: $unit_now"
fi

echo "== Retry cap"
runs="$(ls "$LOG_DIR"/run-*.log 2>/dev/null | wc -l | tr -d ' ')"
max=$((2 + 3 * failing_before))
echo "$runs test run(s); at most $max allowed for $failing_before failing test(s)"
[ "$runs" -le "$max" ] || say_fail "more than 3 fix attempts per failing test. Stop sooner and report what still fails."
[ "$(value Runs)" = "$runs" ] || { [ "$stopped" != "None" ] && value Runs | grep -q '^Not run'; } || say_fail "\"Runs:\" says \"$(value Runs)\", but $LOG_DIR has $runs run log(s)"

echo "== Handoffs"
if [ "$stopped" != "None" ]; then
  echo "Skipped: the run stopped before any change."
  finish implementer-agent
fi
out="$("$helper" handoffs 2>&1)"
if ! echo "$out" | tail -1 | grep -q '^HANDOFFS_DONE$'; then
  say_fail "implementer-run.sh handoffs didn't finish. Its last line: $(echo "$out" | tail -1)"
fi
handoffs="$(section "Handoffs:")"
for agent in Lint-Agent API-Agent Docs-Agent Security-Agent Review-Agent; do
  want="$(echo "$out" | sed -nE "s/^HANDOFF $agent: (not needed|needed).*/\1/p" | head -1)"
  got="$(echo "$handoffs" | sed -nE "s/^- $agent: (not needed|needed).*/\1/p" | head -1)"
  if [ -z "$got" ]; then
    say_fail "\"Handoffs:\" has no \"- $agent: needed | ...\" or \"- $agent: not needed | ...\" line"
  elif [ -n "$want" ] && [ "$got" != "$want" ]; then
    say_fail "\"Handoffs:\" says $agent is $got, but implementer-run.sh handoffs says $want"
  else
    echo "  OK  $agent: $got"
  fi
done

finish implementer-agent
