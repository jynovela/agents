#!/usr/bin/env bash
# Runs one ticket through the agents in a fixed order. It never starts an
# agent itself. It tells the coordinator (you, Claude Code, or a Hermes
# orchestrator) which agent to run next, and after each agent it runs that
# agent's check, saves the report, commits the change, and decides what
# comes next.
#
# Usage, from the project root:
#   .agents/flow/ticket.sh start <ticket-id> [--api] [--base <branch>]
#       Start a ticket on a new branch ticket/<id>. --api adds the API design
#       step, for a ticket that adds or changes an endpoint, a CLI flag, or
#       an environment variable. Default base: main.
#   .agents/flow/ticket.sh done
#       The agent named by the last NEXT has finished and saved its report
#       to .runs/<id>/step.txt.
#   .agents/flow/ticket.sh next      Print the current NEXT again.
#   .agents/flow/ticket.sh status    Print where the ticket is.
#
# Every call ends with one of:
#   NEXT: <agent>     run this agent with the PROMPT printed under it, then call "done"
#   ASK: <reason>     stop and ask the person. Nothing else may run.
#   DONE: <summary>   the ticket is ready for the person to test
#
# State lives in .runs/<ticket-id>/ and is never committed. See
# .agents/flow/pipeline.md.

set -uo pipefail

MAX_TRIES=2      # times one agent may fail its own check in a row
MAX_RETURNS=2    # times the work may go back to Implementer-Agent

root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ASK: this folder is not a git repository."; exit 2; }
cd "$root"
skills=".agents/skills"

die() { echo "ASK: $*"; exit 2; }

# --- state: one "key=value" per line in .runs/<id>/state ---------------------
id=""
state=""
get() { sed -n "s/^$1=//p" "$state" | head -n 1; }
put() {
  grep -v "^$1=" "$state" > "$state.new" || true
  echo "$1=$2" >> "$state.new"
  mv "$state.new" "$state"
}
load() {
  [ -f .runs/current ] || die "no ticket is running. Start one with: .agents/flow/ticket.sh start <ticket-id>"
  id="$(cat .runs/current)"
  state=".runs/$id/state"
  [ -f "$state" ] || die "the state file $state is missing. Start the ticket again."
}

title_of() {
  local t
  t="$(sed -n 's/^title: *//p' "$skills/$1/agent.yaml" 2>/dev/null | head -n 1)"
  echo "${t:-$1}"
}

command_set() {
  local v
  v="$(grep -E "^(- )?$1( \([^)]*\))?:" AGENTS.md 2>/dev/null | head -n 1 | sed 's/^[^:]*: *//')"
  case "$v" in ""|None|None.) return 1 ;; esac
  return 0
}

# --- what to tell each agent --------------------------------------------------
prompt_for() {
  local step="$1" base returns note=""
  base="$(get base)"
  returns="$(get returns)"
  case "$step" in
    api-agent:design)
      echo "Ticket $id. Design mode. Write the ticket's interface changes into the API spec, before any code exists. The base branch is $base." ;;
    api-agent:check)
      echo "Ticket $id. Check mode. Check this branch's interface changes against the API spec. The base branch is $base." ;;
    test-agent:write)
      echo "Ticket $id. Write mode. Write the acceptance tests for the ticket's criteria. Each must fail, because the code doesn't exist yet. The base branch is $base." ;;
    implementer-agent)
      if [ "${returns:-0}" -gt 0 ]; then
        note=" This is return $returns: an earlier try was sent back. First read $(get return_file) and fix what it reports."
      fi
      echo "Ticket $id. Build the ticket: make its acceptance tests pass with the smallest code change. The base branch is $base.$note" ;;
    lint-agent)
      echo "Ticket $id. Fix lint on this branch's changed files against $base, without changing behavior." ;;
    test-agent:verify)
      echo "Ticket $id. Verify mode. Run the acceptance tests against the running app and report each criterion with evidence. The base branch is $base." ;;
    docs-agent)
      echo "Ticket $id. Update the docs for this branch against $base." ;;
    review-agent)
      echo "Ticket $id. Review this branch against the ticket. The base branch is $base." ;;
    security-agent)
      echo "Ticket $id. Review this branch's change for security problems. The base branch is $base." ;;
    build-agent:deploy)
      echo "Ticket $id. Run every build step, and if all pass, deploy this branch to staging. Never deploy to production." ;;
  esac
}

print_next() {
  local queue step agent mode out
  out=".runs/$id/step.txt"
  queue="$(get queue)"
  if [ -n "$(get ask)" ]; then
    echo "ASK: $(get ask)"
    echo "Reports and check output are in .runs/$id/."
    return
  fi
  if [ -z "$queue" ]; then
    echo "DONE: ticket $id is on branch $(get branch), ready for the person to test."
    echo "Reports: .runs/$id/"
    if [ -n "$(get flags)" ]; then
      echo "For the person to read first:"
      get flags | tr ';' '\n' | sed '/^$/d; s/^/  - /'
    fi
    echo "Nothing was pushed or merged. The person tests it, then merges and releases."
    return
  fi
  step="${queue%% *}"
  agent="${step%%:*}"
  mode=""
  case "$step" in *:*) mode="${step#*:}" ;; esac
  echo "NEXT: $agent"
  [ -n "$mode" ] && echo "MODE: $mode"
  echo "PROMPT: $(prompt_for "$step") In this run your report file is $out, not report.md: wherever your instructions say report.md, use $out, also in the command that runs your check script. Save it before you finish."
  if [ "$(get tries)" -gt 0 ]; then
    echo "RETRY: this agent's last try failed its check. Add this to the prompt: Your last try failed the check. Read $(get last_check), fix what it lists, and save $out again."
  fi
  echo "THEN: .agents/flow/ticket.sh done"
}

flag() {
  local old
  old="$(get flags)"
  put flags "$old$1;"
}

# --- start ---------------------------------------------------------------------
cmd="${1:-}"
[ "$#" -gt 0 ] && shift

if [ "$cmd" = "start" ]; then
  id=""
  api=0
  base="main"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --api) api=1 ;;
      --base) shift; base="${1:-main}" ;;
      -*) die "unknown option $1" ;;
      *) id="$1" ;;
    esac
    shift
  done
  [ -n "$id" ] || die "give a ticket id: .agents/flow/ticket.sh start <ticket-id>"
  case "$id" in *[!A-Za-z0-9._-]*) die "the ticket id may hold only letters, digits, dots, dashes, and underscores." ;; esac

  missing=""
  for a in test-agent implementer-agent docs-agent review-agent security-agent; do
    [ -f "$skills/$a/SKILL.md" ] || missing="$missing $a"
  done
  [ -z "$missing" ] || die "these agents are not installed:$missing. Run install.sh from the agents repo."
  if [ "$api" -eq 1 ] && [ ! -f "$skills/api-agent/SKILL.md" ]; then
    die "--api needs api-agent, which is not installed."
  fi
  git rev-parse --verify -q "$base" >/dev/null || die "the base branch $base doesn't exist."

  # Keep run files and reports out of git, without touching .gitignore.
  exclude="$(git rev-parse --git-path info/exclude)"
  mkdir -p "$(dirname "$exclude")"
  for line in ".runs/" "/report.md"; do
    grep -qxF "$line" "$exclude" 2>/dev/null || echo "$line" >> "$exclude"
  done

  if [ -n "$(git status --porcelain)" ]; then
    die "there are uncommitted changes. Commit or remove them first, so each agent's change can be told apart."
  fi

  branch="ticket/$(echo "$id" | tr 'A-Z' 'a-z')"
  if git rev-parse --verify -q "$branch" >/dev/null; then
    die "the branch $branch already exists. To go on with it, run: .agents/flow/ticket.sh next. To start over, delete the branch and .runs/$id first."
  fi
  git checkout -q -b "$branch" "$base" || die "couldn't create the branch $branch from $base."

  mkdir -p ".runs/$id"
  echo "$id" > .runs/current
  state=".runs/$id/state"
  : > "$state"
  queue="test-agent:write implementer-agent test-agent:verify docs-agent review-agent security-agent"
  [ "$api" -eq 1 ] && queue="api-agent:design $queue"
  if [ -f "$skills/build-agent/SKILL.md" ] && command_set "Deploy"; then
    queue="$queue build-agent:deploy"
  fi
  put base "$base"
  put branch "$branch"
  put queue "$queue"
  put tries 0
  put returns 0
  put count 0
  put flags ""
  put ask ""
  echo "Started ticket $id on branch $branch."
  print_next
  exit 0
fi

load

case "$cmd" in
  next) print_next; exit 0 ;;
  status)
    echo "Ticket: $id"
    echo "Branch: $(get branch)"
    echo "Steps left: $(get queue)"
    echo "Returns to Implementer-Agent: $(get returns) of $MAX_RETURNS"
    ls ".runs/$id" | grep -v '^state$' | sed 's/^/  /'
    exit 0 ;;
  done) ;;
  *) die "unknown command \"$cmd\". Use start, done, next, or status." ;;
esac

# --- done: check, save, decide, commit ----------------------------------------
[ -z "$(get ask)" ] || { print_next; exit 0; }
queue="$(get queue)"
[ -n "$queue" ] || { print_next; exit 0; }
step="${queue%% *}"
rest=""
case "$queue" in *" "*) rest="${queue#* }" ;; esac
agent="${step%%:*}"
mode=""
case "$step" in *:*) mode="${step#*:}" ;; esac
base="$(get base)"
title="$(title_of "$agent")"

[ "$(git rev-parse --abbrev-ref HEAD)" = "$(get branch)" ] ||
  die "the current branch is not $(get branch). Check it out, then run: .agents/flow/ticket.sh done"

count=$(( $(get count) + 1 ))
put count "$count"
label="$(printf '%02d' "$count")-$agent${mode:+-$mode}"
check_out=".runs/$id/$label.check.txt"
saved=".runs/$id/$label.md"

fail_try() {
  local tries
  tries=$(( $(get tries) + 1 ))
  put tries "$tries"
  put last_check "$check_out"
  if [ "$tries" -ge "$MAX_TRIES" ]; then
    put ask "$title failed its check $tries times in a row on ticket $id. Read $check_out."
  fi
  print_next
  exit 0
}

# Claude Code refuses to let a subagent write a file named like a report, so
# the report goes in a plainly named file under .runs/.
out=".runs/$id/step.txt"
if [ ! -f "$out" ]; then
  echo "FAIL: $title didn't save its report to $out." > "$check_out"
  fail_try
fi
cp "$out" "$saved"

case "$agent" in
  api-agent)         "$skills/$agent/check.sh" "$out" "$base" "$mode" > "$check_out" 2>&1 ;;
  test-agent)        BASE="$base" "$skills/$agent/check.sh" "$out" > "$check_out" 2>&1 ;;
  review-agent)      BASE="$base" "$skills/$agent/check.sh" "$out" > "$check_out" 2>&1 ;;
  docs-agent|build-agent) "$skills/$agent/check.sh" "$out" > "$check_out" 2>&1 ;;
  *)                 "$skills/$agent/check.sh" "$out" "$base" > "$check_out" 2>&1 ;;
esac
[ "$?" -eq 0 ] || fail_try

# The check passed. Commit what the agent changed, through the project's hooks.
if [ -n "$(git status --porcelain)" ]; then
  git add -A
  if ! git commit -q -m "$id: $title${mode:+ ($mode)}" >> "$check_out" 2>&1; then
    git reset -q
    echo "FAIL: the commit was refused, most likely by the pre-commit hook. Its output is above." >> "$check_out"
    fail_try
  fi
fi
rm -f "$out"
put tries 0

# Read the outcome from the saved report.
send_back=""
case "$step" in
  implementer-agent)
    stopped="$(sed -n 's/^Stopped: *//p' "$saved" | head -n 1)"
    case "$stopped" in ""|None|None.) ;; *) put ask "Implementer-Agent stopped on ticket $id: $stopped. Read $saved." ;; esac
    if grep -q '| after: FAIL' "$saved"; then
      put ask "Implementer-Agent couldn't make every acceptance test pass on ticket $id. Read \"Failing tests\" in $saved."
    fi
    add=""
    if grep -q '^- Lint-Agent: needed' "$saved" && [ -f "$skills/lint-agent/SKILL.md" ]; then
      add="$add lint-agent"
    fi
    if grep -q '^- API-Agent: needed' "$saved" && [ -f "$skills/api-agent/SKILL.md" ] && command_set "API spec is"; then
      add="$add api-agent:check"
    fi
    rest="$(echo "$add $rest" | sed 's/^ *//')"
    if sed -n '/^Needs approval:/,/^$/p' "$saved" | grep -q '^- ' &&
       ! sed -n '/^Needs approval:/,/^$/p' "$saved" | grep -qi '^- None'; then
      flag "Implementer-Agent listed changes that need approval: see $saved"
    fi ;;
  test-agent:verify)
    if grep -q '| result: FAIL' "$saved"; then
      send_back="Test-Agent's Verify run found failing criteria"
    fi ;;
  review-agent)
    verdict="$(sed -n 's/^Verdict: *//p' "$saved" | head -n 1)"
    case "$verdict" in
      REJECTED*) send_back="Review-Agent rejected the change" ;;
      APPROVED_WITH_COMMENTS*) flag "Review-Agent approved with comments: see $saved" ;;
      APPROVED*) ;;
      *) put ask "Review-Agent's report has no verdict the pipeline knows (\"$verdict\"). Read $saved." ;;
    esac ;;
  security-agent)
    result="$(sed -n 's/^Result: *//p' "$saved" | head -n 1)"
    case "$result" in
      BLOCK*) send_back="Security-Agent's result is BLOCK" ;;
      REVIEW*) flag "Security-Agent's result is REVIEW, so a person should read it: see $saved" ;;
      PASS*) ;;
      *) put ask "Security-Agent's report has no result the pipeline knows (\"$result\"). Read $saved." ;;
    esac ;;
esac

if [ -n "$send_back" ]; then
  returns=$(( $(get returns) + 1 ))
  put returns "$returns"
  put return_file "$saved"
  if [ "$returns" -gt "$MAX_RETURNS" ]; then
    put ask "$send_back, and the work has already gone back to Implementer-Agent $MAX_RETURNS times on ticket $id. Read $saved."
  else
    rest="implementer-agent test-agent:verify docs-agent review-agent security-agent"
    case " $(get queue) " in *" build-agent:deploy "*) rest="$rest build-agent:deploy" ;; esac
  fi
fi

put queue "$rest"
print_next
