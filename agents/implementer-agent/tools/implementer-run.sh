#!/usr/bin/env bash
# Helper for Implementer-Agent. Runs the tests the same way every time, keeps
# a numbered log of each run as evidence, and works out the handoffs from the
# code change, so a small model doesn't do this by hand.
#
# Usage: .agents/skills/implementer-agent/tools/implementer-run.sh <command>
#   tests     Restart the app, run the acceptance and unit tests, and save the
#             output to logs/implementer/run-<N>.log. Prints the log with line
#             numbers. Cite its lines as evidence.
#   files     Print each file the agent changed, with lines added and removed.
#   handoffs  Print what the change hands to Lint, API, Docs, Security, and
#             Review, with the lines that make each one needed.
#   raw       Like tests, but prints only the result lines and saves no log.
#             The check script uses it.
#   stop      Stop the app and wait until it no longer answers.
#   hash      Print a fingerprint of the current code change. Each log holds
#             the fingerprint of the code it ran.
#
# Written for bash 3.2 (macOS) as well as newer bash.

set -uo pipefail

# <!-- TAILOR: test and dev commands from the Dev environment section of
# AGENTS.md. ACCEPT_CMD must print one line per test, like Python's
# "unittest -v" does. -->
ACCEPT_CMD='python3 -m unittest discover -v -s acceptance -t .'
UNIT_CMD='python3 -m unittest discover -s tests -t .'
DEV_START='dev/start.sh'
DEV_STOP='dev/stop.sh'
DEV_HEALTH='dev/health.sh'

# <!-- TAILOR: extended regexes for the test runner's output. RAN_PATTERN's
# first group is the name of a test that ran; FAIL_PATTERN's second group is
# a failing test's name. -->
RAN_PATTERN='^(test[A-Za-z0-9_]*) \('
FAIL_PATTERN='^(FAIL|ERROR): ([A-Za-z0-9_]+)'

# <!-- TAILOR: the lint command for a list of files, and which files it lints.
# Leave LINT_CMD empty if the project has no linter. -->
LINT_CMD='ruff check --output-format concise'
LINT_FORMAT_CMD='ruff format --check'
LINT_FILES='\.py$'

# <!-- TAILOR: changed lines that make each handoff needed. Matched against
# added and removed lines of the agent's change, ignoring case. -->
API_PATTERN='add_argument\(|add_parser\(|environ|getenv\(|process\.env|url\.path|do_(GET|POST|PUT|PATCH|DELETE)|@(app|router|bp)\.(get|post|put|patch|delete|route)'
DOCS_PATTERN="$API_PATTERN|help=|print\\(|sys\\.stderr|sys\\.exit\\(|exit\\("
SECURITY_PATTERN='subprocess|os\.system|shell=|eval\(|exec\(|pickle|yaml\.load|execute\(|open\(|urlopen|requests\.|authorization|token|passw|secret|api_key|hmac|sql'

# Where logs go, and files that are never part of the code change.
LOG_DIR='logs/implementer'
NOT_CODE="^report\\.md\$|^$LOG_DIR/"

# Files the agent changed: tracked changes against HEAD plus untracked files,
# without the report and logs.
code_files() {
  { git diff --name-only HEAD; git ls-files --others --exclude-standard; } \
    | sort -u | grep -Ev "$NOT_CODE" || true
}

code_hash() {
  local f files
  files="$(code_files)"
  {
    [ -n "$files" ] && git diff HEAD -- $files 2>/dev/null
    for f in $files; do
      git ls-files --error-unmatch "$f" >/dev/null 2>&1 && continue
      [ -f "$f" ] || continue
      echo "NEW FILE $f"
      cat "$f"
    done
  } | git hash-object --stdin
}

# Changed lines of the agent's change as "<file>:<line>\t<+ or -><text>".
# Added lines use the line number in the file now; removed lines use
# "-<line>" from the file at HEAD.
changed_lines() {
  local f
  for f in $(code_files); do
    [ -f "$f" ] || [ -n "$(git ls-files -- "$f")" ] || continue
    if git ls-files --error-unmatch "$f" >/dev/null 2>&1; then
      git diff -U0 --no-color HEAD -- "$f" | awk -v f="$f" '
        /^(\+\+\+|---) / { next }
        /^@@/ {
          split($2, o, ","); old = substr(o[1], 2) + 0
          split($3, n, ","); new = substr(n[1], 2) + 0
          next
        }
        /^\+/ { print f ":" new "\t+" substr($0, 2); new++; next }
        /^-/  { print f ":-" old "\t-" substr($0, 2); old++; next }'
    elif [ -f "$f" ]; then
      awk -v f="$f" '{ print f ":" NR "\t+" $0 }' "$f"
    fi
  done
}

# Stops the app and waits up to 10 seconds until the health check fails, so
# the next start loads the new code instead of finding the old app running.
stop_app() {
  local i
  [ -n "$DEV_STOP" ] || return 0
  eval "$DEV_STOP" >/dev/null 2>&1
  [ -n "$DEV_HEALTH" ] || return 0
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    eval "$DEV_HEALTH" >/dev/null 2>&1 || return 0
    sleep 0.5
  done
  echo "STOP_FAILED: the app still answers after $DEV_STOP"
}

# Restarts the app, runs both test suites, and prints the raw output followed
# by result lines. The last line is RUN_DONE when it finished.
run_all() {
  local acc_out unit_out t unit_failing acc_failing
  stop_app
  if [ -n "$DEV_START" ]; then
    if ! eval "$DEV_START" >/dev/null 2>&1; then
      echo "START_FAILED: $DEV_START"
    fi
  fi
  echo "== Acceptance tests: $ACCEPT_CMD"
  acc_out="$(eval "$ACCEPT_CMD" 2>&1)"
  echo "$acc_out"
  echo "== Unit tests: $UNIT_CMD"
  unit_out="$(eval "$UNIT_CMD" 2>&1)"
  echo "$unit_out"
  echo "== Results"
  acc_failing="$(echo "$acc_out" | grep -Eo "$FAIL_PATTERN" | sed -E "s/$FAIL_PATTERN/\2/" | sort -u)"
  for t in $(echo "$acc_out" | grep -Eo "$RAN_PATTERN" | sed -E "s/$RAN_PATTERN/\1/" | sort -u); do
    if echo "$acc_failing" | grep -qx "$t"; then
      echo "ACCEPT_RESULT FAIL $t"
    else
      echo "ACCEPT_RESULT PASS $t"
    fi
  done
  echo "UNIT_SUMMARY $(echo "$unit_out" | grep -E '^(OK|FAILED)' | tail -1)"
  unit_failing="$(echo "$unit_out" | grep -Eo "$FAIL_PATTERN" | sed -E "s/$FAIL_PATTERN/\2/" | sort -u)"
  for t in $unit_failing; do echo "UNIT_FAIL $t"; done
  echo "RUN_DONE"
}

cmd_tests() {
  local n log
  mkdir -p "$LOG_DIR"
  n=1
  while [ -e "$LOG_DIR/run-$n.log" ]; do n=$((n + 1)); done
  log="$LOG_DIR/run-$n.log"
  {
    echo "RUN $n"
    echo "CODE_HASH $(code_hash)"
    run_all
  } > "$log" 2>&1
  grep -n '' "$log"
  echo
  echo "Saved: $log"
  echo "Cite evidence as $log:<line number> with the text of that line."
}

cmd_files() {
  local f stat
  for f in $(code_files); do
    if git ls-files --error-unmatch "$f" >/dev/null 2>&1; then
      stat="$(git diff --numstat HEAD -- "$f" | awk '{ print "+" $1 " -" $2 }')"
    else
      stat="+$(wc -l < "$f" | tr -d ' ') -0 (new file)"
    fi
    echo "FILE $f | $stat"
  done
  echo "FILES_DONE"
}

# Prints "HANDOFF <agent>: needed | <why>" or "not needed", then the lines
# behind it.
handoff() {
  local agent="$1" pattern="$2" what="$3" hits
  hits="$(echo "$lines" | grep -Ei -- "$(printf '\t')[+-].*($pattern)" || true)"
  if [ -n "$hits" ]; then
    echo "HANDOFF $agent: needed | $(echo "$hits" | wc -l | tr -d ' ') changed line(s) with $what"
    echo "$hits" | sed "s/^/  LINE /" | tr "\t" " " | cut -c1-120
  else
    echo "HANDOFF $agent: not needed | no changed lines with $what"
  fi
}

cmd_handoffs() {
  local files out n tool
  lines="$(changed_lines)"
  files="$(code_files | grep -E "$LINT_FILES" || true)"
  files="$(for f in $files; do [ -f "$f" ] && echo "$f"; done)"
  if [ -z "$LINT_CMD" ]; then
    echo "HANDOFF Lint-Agent: not needed | no lint command"
  elif [ -z "$files" ]; then
    echo "HANDOFF Lint-Agent: not needed | no lintable files changed"
  else
    tool="${LINT_CMD%% *}"
    if ! command -v "$tool" >/dev/null 2>&1; then
      echo "HANDOFF Lint-Agent: needed | lint not run, $tool is not installed"
    else
      out="$(eval "$LINT_CMD" $files 2>&1 | grep -E '^[^ ]+:[0-9]+:' || true)"
      if [ -n "$LINT_FORMAT_CMD" ]; then
        out="$out$(printf '\n')$(eval "$LINT_FORMAT_CMD" $files 2>&1 | grep -i '^would reformat' || true)"
      fi
      out="$(echo "$out" | grep -v '^$' || true)"
      if [ -n "$out" ]; then
        n="$(echo "$out" | wc -l | tr -d ' ')"
        echo "HANDOFF Lint-Agent: needed | $n lint problem(s) in changed files"
        echo "$out" | sed 's/^/  LINT /'
      else
        echo "HANDOFF Lint-Agent: not needed | lint passes on changed files"
      fi
    fi
  fi
  handoff "API-Agent" "$API_PATTERN" "flags, endpoints, or env vars"
  handoff "Docs-Agent" "$DOCS_PATTERN" "user-visible flags, endpoints, output, or exit codes"
  handoff "Security-Agent" "$SECURITY_PATTERN" "input handling, files, network, SQL, or credentials"
  echo "HANDOFF Review-Agent: needed | every change gets a review"
  echo "HANDOFFS_DONE"
}

case "${1:-}" in
  tests) cmd_tests ;;
  stop) stop_app ;;
  raw) run_all | grep -E '^(STOP_FAILED|START_FAILED|ACCEPT_RESULT|UNIT_SUMMARY|UNIT_FAIL|RUN_DONE)' ;;
  files) cmd_files ;;
  handoffs) cmd_handoffs ;;
  hash) code_hash ;;
  *)
    echo "Usage: .agents/skills/implementer-agent/tools/implementer-run.sh tests|files|handoffs|raw|hash" >&2
    exit 2
    ;;
esac
