#!/usr/bin/env bash
# Tests flow/ticket.sh with stand-in agents: each "agent" is this script
# writing a report and a file. Every check script is a stub that passes
# unless FAIL_CHECK names its agent.
# Usage: tests/flow.sh

set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0
say_fail() { echo "FAIL: $*"; fail=1; }

new_project() {
  local p="$1" a
  mkdir -p "$p/.agents/flow"
  git -C "$p" init -q -b main
  cp "$root/flow/ticket.sh" "$p/.agents/flow/"
  for a in api-agent test-agent implementer-agent lint-agent docs-agent review-agent security-agent; do
    mkdir -p "$p/.agents/skills/$a"
    echo "# $a" > "$p/.agents/skills/$a/SKILL.md"
    echo "title: $a" > "$p/.agents/skills/$a/agent.yaml"
    cat > "$p/.agents/skills/$a/check.sh" <<STUB
#!/usr/bin/env bash
echo "stub check for $a, args: \$*"
[ "\${FAIL_CHECK:-}" = "$a" ] && { echo "FAIL: stub"; exit 1; }
exit 0
STUB
    chmod +x "$p/.agents/skills/$a/check.sh"
  done
  printf -- '- API spec is: follows the code\n- Deploy (local or staging only): None\n' > "$p/AGENTS.md"
  git -C "$p" add -A
  git -C "$p" -c user.name=t -c user.email=t@example.invalid commit -q -m start
  git -C "$p" config user.name t
  git -C "$p" config user.email t@example.invalid
}

t() { (cd "$proj" && .agents/flow/ticket.sh "$@" 2>&1); }

# Plays one agent: writes a file (unless told not to) and a report, then "done".
agent() {
  local report="$1" change="${2:-yes}"
  if [ "$change" = "yes" ]; then
    echo "$RANDOM" >> "$proj/work.txt"
  fi
  printf '%s\n' "$report" > "$proj/agent-report.md"
  t done
}

expect() {
  local what="$1" want="$2" got="$3"
  echo "$got" | grep -qF "$want" || { say_fail "$what: expected \"$want\", got:"; echo "$got" | sed 's/^/    /'; }
}

IMPL_OK='Stopped: None
- C1: x | test: t | before: FAIL | after: PASS | evidence: e
Needs approval:
- None

Handoffs:
- Lint-Agent: needed | lint fails
- API-Agent: not needed | none'

# 1. The whole order, with Lint-Agent called by the Implementer's handoff.
proj="$tmp/happy"; new_project "$proj"
out="$(t start ITEM-1 --api)";                    expect "start" "NEXT: api-agent" "$out"; expect "start" "MODE: design" "$out"
out="$(agent 'Mode: design')";                    expect "after api design" "NEXT: test-agent" "$out"
out="$(agent 'Mode: Write')";                     expect "after write" "NEXT: implementer-agent" "$out"
out="$(agent "$IMPL_OK")";                        expect "after implement" "NEXT: lint-agent" "$out"
out="$(agent 'lint')";                            expect "after lint" "NEXT: docs-agent" "$out"
out="$(agent 'docs')";                            expect "after docs" "MODE: verify" "$out"
out="$(agent '- C1 | result: PASS | e' no)";      expect "after verify" "NEXT: review-agent" "$out"
out="$(agent 'Verdict: APPROVED_WITH_COMMENTS' no)"; expect "after review" "NEXT: security-agent" "$out"
out="$(agent 'Result: REVIEW' no)";               expect "end" "DONE: ticket ITEM-1" "$out"
expect "end flags" "Review-Agent approved with comments" "$out"
expect "end flags" "Security-Agent's result is REVIEW" "$out"
[ "$(git -C "$proj" rev-parse --abbrev-ref HEAD)" = "ticket/item-1" ] || say_fail "happy: not on branch ticket/item-1"
[ "$(git -C "$proj" log --oneline main..HEAD | wc -l | tr -d ' ')" = "5" ] || say_fail "happy: expected 5 commits, one per agent that changed files"
[ -z "$(git -C "$proj" status --porcelain)" ] || say_fail "happy: the tree isn't clean at the end"
git -C "$proj" log --format=%s main..HEAD | grep -q '^ITEM-1: test-agent (write)$' || say_fail "happy: commit message for the write step is missing"
[ -f "$proj/.runs/ITEM-1/03-implementer-agent.md" ] || say_fail "happy: the Implementer's report wasn't saved"
echo "ok: full order"

# 2. A failing Verify sends the work back, with the report named. Past the limit, it asks.
proj="$tmp/back"; new_project "$proj"
t start ITEM-2 >/dev/null
agent 'Mode: Write' >/dev/null
agent "$(echo "$IMPL_OK" | sed 's/Lint-Agent: needed/Lint-Agent: not needed/')" >/dev/null
agent 'docs' >/dev/null
mkdir -p "$proj/logs/implementer"; echo old > "$proj/logs/implementer/run-1.log"
out="$(agent '- C1 | result: FAIL | e' no)"
expect "verify fail" "NEXT: implementer-agent" "$out"; expect "verify fail" "This is return 1" "$out"; expect "verify fail" ".runs/ITEM-2/04-test-agent-verify.md" "$out"
[ ! -e "$proj/logs/implementer/run-1.log" ] || say_fail "send-back: earlier implementer logs were not moved"
ls "$proj"/.runs/ITEM-2/implementer-logs-*/run-1.log >/dev/null 2>&1 || say_fail "send-back: earlier implementer logs were not kept in .runs/ITEM-2/"
agent 'Stopped: None' >/dev/null
agent 'docs' >/dev/null
agent '- C1 | result: PASS | e' no >/dev/null
out="$(agent 'Verdict: REJECTED' no)";            expect "review reject" "This is return 2" "$out"
agent 'Stopped: None' >/dev/null
agent 'docs' >/dev/null
agent '- C1 | result: PASS | e' no >/dev/null
agent 'Verdict: APPROVED' no >/dev/null
out="$(agent 'Result: BLOCK' no)";                expect "third return" "ASK: Security-Agent's result is BLOCK" "$out"
out="$(t done)";                                  expect "ask holds" "ASK:" "$out"
echo "ok: send back and limit"

# 3. A failed check retries the same agent once, then asks. Nothing is committed.
proj="$tmp/check"; new_project "$proj"
t start ITEM-3 >/dev/null
out="$(FAIL_CHECK=test-agent agent 'Mode: Write')"; expect "check fail 1" "NEXT: test-agent" "$out"; expect "check fail 1" "RETRY:" "$out"
[ "$(git -C "$proj" log --oneline main..HEAD | wc -l | tr -d ' ')" = "0" ] || say_fail "check: a failed check must not commit"
out="$(FAIL_CHECK=test-agent agent 'Mode: Write')"; expect "check fail 2" "ASK: test-agent failed its check 2 times" "$out"
echo "ok: failed check"

# 4. No report, an Implementer that stopped, and a dirty start.
proj="$tmp/misc"; new_project "$proj"
echo x > "$proj/stray.txt"
out="$(t start ITEM-4)";                          expect "dirty start" "ASK: there are uncommitted changes" "$out"
rm "$proj/stray.txt"
t start ITEM-4 >/dev/null
out="$(t done)";                                  expect "no report" "RETRY:" "$out"
agent 'Mode: Write' >/dev/null
out="$(agent 'Stopped: the tests need a database this machine lacks')"
expect "stopped" "ASK: Implementer-Agent stopped" "$out"
out="$(t status)";                                expect "status" "Ticket: ITEM-4" "$out"
echo "ok: no report, stopped, dirty start"

if [ "$fail" -ne 0 ]; then
  echo "RESULT: FAIL"
  exit 1
fi
echo "RESULT: PASS"
