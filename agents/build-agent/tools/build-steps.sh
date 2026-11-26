#!/usr/bin/env bash
# Runs the build steps one by one and says which pass, so Build-Agent doesn't
# have to read long logs by hand. Every step runs, even after one fails.
#
# Usage:
#   .agents/skills/build-agent/tools/build-steps.sh run      Run every step. Prints one STEP line
#                                         each, and for a failing step, the
#                                         log lines that look like the error.
#   .agents/skills/build-agent/tools/build-steps.sh ci       Print each step command that no CI
#                                         workflow runs, as CI_MISSING lines.
#
# Logs go to logs/build/<n>.log. Exit code 0 means every step passed. The
# last line is STEPS_DONE <n> or CI_CHECK_DONE; without it, the helper broke.

set -uo pipefail
. "$(dirname "$0")/../../../shared/lib.sh"

# <!-- TAILOR: the build steps, in the order CI runs them, one per line as
# "Name|command". Use the commands from AGENTS.md. -->
STEPS='Lint code|ruff check . && ruff format --check .
Unit tests|python3 -m unittest discover -s tests -t .
Build|dev/build.sh
Start app|dev/start.sh && dev/health.sh'

# <!-- TAILOR: the health check and stop commands. If the app wasn't running
# before the steps, it's stopped after them. Set both to "" if no step starts
# the app. -->
HEALTH='dev/health.sh'
STOP='dev/stop.sh'

# <!-- TAILOR: where CI workflows live. -->
CI_FILES='.github/workflows/*.yml .github/workflows/*.yaml'

# Project settings. A value set in .agents/local/build-agent.sh replaces the one
# in this script. install.sh never changes that file.
if [ -f .agents/local/build-agent.sh ]; then . .agents/local/build-agent.sh; fi

# Log lines worth showing for a failing step.
ERROR_LINES='error|fail|traceback|not found|no such|denied|cannot|refused|exception|would reformat|--> |^[^ :]+:[0-9]+:[0-9]+: '

mode="${1:-}"
case "$mode" in
  run|ci) ;;
  *)
    echo "Usage: .agents/skills/build-agent/tools/build-steps.sh run | ci" >&2
    exit 2
    ;;
esac

if [ "$mode" = run ]; then
  mkdir -p logs/build
  was_running=0
  [ -n "$HEALTH" ] && bash -c "$HEALTH" >/dev/null 2>&1 && was_running=1
  n=0
  status=0
  while IFS='|' read -r name cmd; do
    [ -n "$name" ] || continue
    n=$((n + 1))
    log="logs/build/$n.log"
    if bash -c "$cmd" < /dev/null > "$log" 2>&1; then
      echo "STEP $name: PASS"
    else
      code=$?
      status=1
      echo "STEP $name: FAIL (exit $code) log: $log"
      grep -n -iE "$ERROR_LINES" "$log" | tail -5 | while IFS= read -r l; do
        if secret_like "$l"; then
          echo "  $log:${l%%:*}: (line hidden: looks like a secret)"
        else
          echo "  $log:$l" | cut -c1-200
        fi
      done
    fi
  done <<< "$STEPS"
  if [ "$was_running" -eq 0 ] && [ -n "$STOP" ]; then
    bash -c "$STOP" >/dev/null 2>&1 || true
  fi
  # The check script needs this line to know the helper ran to the end.
  echo "STEPS_DONE $n"
  exit "$status"
fi

# ci mode: the run: lines of every workflow, one command per line.
ci_runs=""
for f in $CI_FILES; do
  [ -f "$f" ] || continue
  ci_runs="$ci_runs
$(sed -n 's/^[[:space:]]*-\{0,1\}[[:space:]]*run:[[:space:]]*//p' "$f")"
done
if [ -z "$(echo "$ci_runs" | tr -d '[:space:]')" ]; then
  echo "NO_CI_WORKFLOW"
  echo "CI_CHECK_DONE"
  exit 0
fi

missing=0
while IFS='|' read -r name cmd; do
  [ -n "$name" ] || continue
  # A step like "a && b" counts as run when CI runs a and b, together or apart.
  rest="$cmd"
  while [ -n "$rest" ]; do
    part="${rest%% && *}"
    if [ "$part" = "$rest" ]; then rest=""; else rest="${rest#* && }"; fi
    if ! echo "$ci_runs" | grep -qF -- "$part"; then
      echo "CI_MISSING $name: $part"
      missing=1
    fi
  done
done <<< "$STEPS"
if [ "$missing" -eq 0 ]; then
  echo "CI runs every step."
fi
# The check script needs this line to know the helper ran to the end.
echo "CI_CHECK_DONE"
exit 0
