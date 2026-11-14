#!/usr/bin/env bash
# Deterministic checks for a Review-Agent run. Run from the repo root on the
# reviewed branch, after the agent finishes.
#
# Usage: .agents/checks/review-agent.sh report.md
# Set BASE to compare against a branch other than main, e.g. BASE=develop.
#
# Exit code 0 means all checks passed. Any failure prints FAIL and exits 1.
# A REJECTED verdict doesn't fail this script; a report that breaks the rules
# does.

set -uo pipefail
. "$(dirname "$0")/lib.sh"

# TAILOR: the branch reviews compare against.
BASE="${BASE:-main}"
MAX_FINDINGS=8

report="${1:-}"
if [ -z "$report" ]; then
  echo "Usage: $0 report.md"
  exit 2
fi

# Review-Agent is review-only: the report is the only file it may write.
check_scope "^$(basename "$report" | sed 's/\./\\./g')\$"
check_secrets
check_headings "$report" "Verdict:" "Criteria:" "Changes:" "Findings:" "Security flags:" "Not checked:" "Verify:"
[ -f "$report" ] || finish "Review-Agent"

section() { awk -v h="$1" '$0 ~ "^"h {f=1; next} /^[A-Z][A-Za-z ()]*:/ {f=0} f' "$report"; }
items() { section "$1" | grep -E '^ *- ' | grep -viE '^ *- *None' || true; }

# Checks that <file>:<line> exists and that the line contains <quote>.
check_quote() {
  local where="$1" file="$2" n="$3" quote="$4" text
  if [ ! -f "$file" ]; then
    say_fail "$where: file $file not found"
    return
  fi
  text="$(sed -n "${n}p" "$file")"
  if [ "${#quote}" -lt 5 ]; then
    say_fail "$where: quote in backticks missing or under 5 characters; quote enough of the line to identify it"
  elif ! printf '%s\n' "$text" | grep -qF -- "$quote"; then
    say_fail "$where: $file line $n doesn't contain the quote. Get the line from review-diff.sh or grep -n."
  else
    echo "  OK  $where $file:$n"
  fi
}

echo "== Verdict"
verdict="$(grep -E '^Verdict:' "$report" | head -1 | sed -E 's/^Verdict: *//; s/[*` ]//g')"
case "$verdict" in
  APPROVED|APPROVED_WITH_COMMENTS|REJECTED) echo "$verdict" ;;
  *) say_fail "\"Verdict:\" must be APPROVED, APPROVED_WITH_COMMENTS, or REJECTED, found \"$verdict\"" ;;
esac

echo "== Criteria"
not_met=0
crit="$(items 'Criteria:')"
[ -n "$crit" ] || say_fail "no criteria listed under \"Criteria:\""
while IFS= read -r line; do
  [ -n "$line" ] || continue
  id="$(echo "$line" | sed -nE 's/^ *- *(C[0-9]+).*/\1/p')"
  status="$(echo "$line" | sed -nE 's/.*status: *(NOT MET|MET|UNCLEAR).*/\1/p')"
  if [ -z "$id" ] || [ -z "$status" ]; then
    say_fail "criterion line lacks \"C<n>:\" or \"status: MET|NOT MET|UNCLEAR\": ${line:0:60}"
    continue
  fi
  [ "$status" = "NOT MET" ] && not_met=$((not_met + 1))
  [ "$status" = "UNCLEAR" ] && { echo "  UNCLEAR  $id"; continue; }
  file="$(echo "$line" | sed -nE 's/.*evidence: *([^ :`]+):([0-9]+).*/\1/p')"
  n="$(echo "$line" | sed -nE 's/.*evidence: *([^ :`]+):([0-9]+).*/\2/p')"
  quote="$(echo "$line" | sed -nE 's/.*evidence: *[^ :`]+:[0-9]+[^`]*`([^`]*)`.*/\1/p')"
  if [ -z "$file" ] || [ -z "$n" ]; then
    say_fail "$id is $status but has no \"evidence: <file>:<line> \`<quote>\`\""
    continue
  fi
  check_quote "$id" "$file" "$n" "$quote"
done <<< "$crit"

echo "== Findings"
blockers=0
count=0
finds="$(items 'Findings:')"
while IFS= read -r line; do
  [ -n "$line" ] || continue
  count=$((count + 1))
  id="$(echo "$line" | sed -nE 's/^ *- *(F[0-9]+).*/\1/p')"
  sev="$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/, "", $2); print $2}')"
  loc="$(echo "$line" | awk -F'|' '{gsub(/^ +| +$/, "", $3); print $3}')"
  quote="$(echo "$line" | sed -nE 's/.*quote: *`([^`]*)`.*/\1/p')"
  [ -n "$id" ] || id="finding $count"
  case "$sev" in
    Blocker) blockers=$((blockers + 1)) ;;
    "Should fix"|Nit) ;;
    *) say_fail "$id: severity must be Blocker, Should fix, or Nit, found \"$sev\""; continue ;;
  esac
  echo "$line" | grep -q 'problem:' || say_fail "$id: missing \"problem:\""
  echo "$line" | grep -q 'fix:' || say_fail "$id: missing \"fix:\""
  file="${loc%:*}"
  n="${loc##*:}"
  if [ -z "$file" ] || ! echo "$n" | grep -Eq '^[0-9]+$'; then
    say_fail "$id: location must be <file>:<line>, found \"$loc\""
    continue
  fi
  check_quote "$id" "$file" "$n" "$quote"
done <<< "$finds"
echo "$count finding(s), $blockers Blocker(s)"
[ "$count" -le "$MAX_FINDINGS" ] || say_fail "$count findings; keep at most $MAX_FINDINGS, most severe first"
if [ "$not_met" -gt 0 ] && [ "$blockers" -eq 0 ]; then
  say_fail "$not_met criterion(s) NOT MET but no Blocker finding"
fi

echo "== Verdict follows the rule"
flags="$(items 'Security flags:' | wc -l | tr -d ' ')"
if [ "$blockers" -gt 0 ]; then expected=REJECTED
elif [ "$count" -gt 0 ] || [ "$flags" -gt 0 ]; then expected=APPROVED_WITH_COMMENTS
else expected=APPROVED
fi
if [ "$verdict" = "$expected" ]; then
  echo "$verdict matches $blockers Blocker(s), $count finding(s), $flags security flag(s)."
else
  say_fail "verdict is \"$verdict\" but $blockers Blocker(s), $count finding(s), $flags security flag(s) means $expected"
fi

echo "== Every changed file is under \"Changes:\""
if git rev-parse --verify -q "$BASE" >/dev/null; then
  changes="$(section 'Changes:')"
  missing=0
  for f in $(git diff --name-only "$BASE...HEAD"); do
    if ! printf '%s\n' "$changes" | grep -qF -- "$f"; then
      say_fail "$f changed on this branch but isn't under \"Changes:\""
      missing=1
    fi
  done
  [ "$missing" -eq 0 ] && echo "All listed."
  lines="$(git diff --numstat "$BASE...HEAD" | awk '{a += $1 + $2} END {print a + 0}')"
  echo "$lines line(s) changed against $BASE."
  [ "$lines" -gt 400 ] && echo "  Over 400: the report should have a Should fix finding to split it."
else
  say_fail "base branch $BASE not found; set BASE"
fi

finish "Review-Agent"
