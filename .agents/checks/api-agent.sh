#!/usr/bin/env bash
# Deterministic checks for an API-Agent run. Run from the repo root on the
# checked branch, after the agent finishes.
#
# Usage: .agents/checks/api-agent.sh report.md [base]   (default base: main)
#
# Exit code 0 means all checks passed. Any failure prints FAIL and exits 1.
# Secret values are never printed.

set -uo pipefail
. "$(dirname "$0")/lib.sh"

report="${1:-}"
BASE="${2:-main}"
if [ -z "$report" ]; then
  echo "Usage: $0 report.md [base]"
  exit 2
fi

# <!-- TAILOR: your spec files (same as SPECS in spec-diff.sh). -->
SPECS="${API_SPECS:-openapi.yaml}"

esc() { printf '%s' "$1" | sed 's/[.[\*^$/]/\\&/g'; }
allowed="^$(esc "$(basename "$report")")\$"
for s in $SPECS; do allowed="$allowed|^$(esc "$s")\$"; done

# API-Agent may change only the spec files and its report.
check_scope "$allowed"
check_secrets
check_headings "$report" "Mode:" "Spec files:" "Approvals:" "Spec changes made:" \
  "Needs approval:" "Interface lines:" "Spec diff:" "Style warnings:" \
  "Security flags:" "Verify:"
[ -f "$report" ] || finish "API-Agent"
if ! git rev-parse --verify -q "$BASE" >/dev/null; then
  say_fail "base branch $BASE not found; pass it as the second argument"
  finish "API-Agent"
fi

section() { awk -v h="$1" '$0 ~ "^"h {f=1; next} /^[A-Z][A-Za-z ()]*:/ {f=0} f' "$report"; }
items() { section "$1" | grep -E '^ *- ' | grep -viE '^ *- *None' || true; }

spec_changed=""
for s in $SPECS; do
  [ -n "$(git status --porcelain -- "$s")" ] && spec_changed="$spec_changed $s"
done

echo "== Mode"
mode="$(grep -E '^- API spec is:' AGENTS.md 2>/dev/null | head -1 | sed -E 's/^- API spec is: *//')"
echo "AGENTS.md says: ${mode:-not set}"
if echo "$mode" | grep -qi 'contract'; then
  [ -n "$spec_changed" ] && say_fail "API spec is \"the contract\", but the spec changed:$spec_changed. Undo it with git restore and list each difference as rule: contract."
fi

echo "== Spec diff"
diff_cmd="$(dirname "$0")/spec-diff.sh"
if "$diff_cmd" "$BASE" >/dev/null 2>&1; then
  echo "spec-diff.sh passed."
else
  "$diff_cmd" "$BASE" | grep -E '^(FAIL|NEEDS APPROVAL)' | sed 's/^/  /'
  say_fail "spec-diff.sh fails. Undo each breaking spec edit and list it under \"Needs approval\"."
fi

echo "== Needs approval items"
aids=""
while IFS= read -r line; do
  [ -n "$line" ] || continue
  id="$(echo "$line" | sed -nE 's/^ *- *(A[0-9]+) *\|.*/\1/p')"
  [ -n "$id" ] || { say_fail "needs-approval line must start with \"- A<n> |\": ${line:0:60}"; continue; }
  aids="$aids $id"
  echo "$line" | grep -Eq '\| *rule: *(breaking|contract) *\|' || say_fail "$id: second field must be \"rule: breaking\" or \"rule: contract\""
  for k in 'change:' 'breaking because:' 'proposed spec edit:' 'approve with:'; do
    echo "$line" | grep -q "$k" || say_fail "$id: missing \"$k\""
  done
  appr="$(echo "$line" | sed -nE 's/.*approve with: *`([^`]*)`.*/\1/p')"
  if [ -n "$appr" ] && [ "$appr" != "n/a" ]; then
    echo "$appr" | grep -Eq '^- [A-Z*]+ [^ ]+ [a-z0-9-]+' \
      || say_fail "$id: \"approve with\" must be \`- <METHOD> <path> <change-id>\` or \`n/a\`"
  fi
  echo "  OK  $id"
done <<< "$(items 'Needs approval:')"

has_aid() { echo " $aids " | grep -q " $1 "; }

echo "== Interface lines are accounted for"
iface_sec="$(section 'Interface lines:')"
locs="$("$(dirname "$0")/../tools/api-diff.sh" "$BASE" 2>/dev/null | sed -n '/^== Interface lines/,$p' | sed -nE 's/^([^ =]+:-?[0-9]+) \[.*/\1/p')"
updated=0
while IFS= read -r loc; do
  [ -n "$loc" ] || continue
  entry="$(printf '%s\n' "$iface_sec" | grep -F -- "- $loc:" | head -1)"
  if [ -z "$entry" ]; then
    say_fail "interface line $loc is missing under \"Interface lines:\""
    continue
  fi
  outcome="$(printf '%s\n' "$entry" | sed -E "s/^ *- *$(esc "$loc"): *//")"
  case "$outcome" in
    "already in spec"*|"no spec: additive"*) ;;
    "spec updated"*) updated=$((updated + 1)) ;;
    "not interface:"*)
      [ "${#outcome}" -gt 16 ] || say_fail "$loc: \"not interface:\" needs a reason" ;;
    "-> A"*)
      aid="$(echo "$outcome" | sed -nE 's/^-> (A[0-9]+).*/\1/p')"
      has_aid "$aid" || say_fail "$loc points to $aid, which isn't under \"Needs approval\"" ;;
    *) say_fail "$loc: outcome must be already in spec, spec updated..., no spec: additive, not interface: <why>, or -> A<n>; found \"${outcome:0:40}\"" ;;
  esac
done <<< "$locs"
[ -n "$locs" ] && echo "$(printf '%s\n' "$locs" | wc -l | tr -d ' ') interface line(s) checked."

echo "== Spec edits match the report"
changes="$(items 'Spec changes made:' | wc -l | tr -d ' ')"
if [ "$updated" -gt 0 ] && [ -z "$spec_changed" ]; then
  say_fail "$updated interface line(s) say \"spec updated\", but no spec file changed"
fi
if [ -n "$spec_changed" ] && [ "$changes" -eq 0 ]; then
  say_fail "the spec changed ($spec_changed ), but \"Spec changes made:\" lists nothing"
fi
echo "spec changed:${spec_changed:- no}; $changes change(s) listed; $updated line(s) say spec updated."

finish "API-Agent"
