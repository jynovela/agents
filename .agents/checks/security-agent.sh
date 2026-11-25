#!/usr/bin/env bash
# Deterministic checks for a Security-Agent run. Run from the repo root on the
# reviewed branch, after the agent finishes.
#
# Usage: .agents/checks/security-agent.sh report.md [base]   (default base: main)
#
# Exit code 0 means all checks passed. Any failure prints FAIL and exits 1.
# A BLOCK result doesn't fail this script; a report that breaks the rules
# does. Secret values are never printed.

set -uo pipefail
. "$(dirname "$0")/lib.sh"

report="${1:-}"
BASE="${2:-main}"
if [ -z "$report" ]; then
  echo "Usage: $0 report.md [base]"
  exit 2
fi

# Security-Agent is review-only: the report is the only file it may write.
check_scope "^$(basename "$report" | sed 's/\./\\./g')\$"
check_secrets
check_headings "$report" "Result:" "Scope:" "Scanners:" "Findings:" "Needs validation:" \
  "Hardening notes:" "Handlers:" "Harness and dependency files:" "Risky lines:" \
  "Planted instructions:" "Not checked:" "Verify:"
[ -f "$report" ] || finish "Security-Agent"
if ! git rev-parse --verify -q "$BASE" >/dev/null; then
  say_fail "base branch $BASE not found; pass it as the second argument"
  finish "Security-Agent"
fi

section() { awk -v h="$1" '$0 ~ "^"h {f=1; next} /^[A-Z][A-Za-z ()]*:/ {f=0} f' "$report"; }
items() { section "$1" | grep -E '^ *- ' | grep -viE '^ *- *None' || true; }
field() { echo "$1" | awk -F'|' -v n="$2" '{gsub(/^ +| +$/, "", $n); print $n}'; }

# Checks that <file>:<line> exists and that the line contains <quote>.
check_quote() {
  local where="$1" file="$2" n="$3" quote="$4" text
  if [ ! -f "$file" ]; then
    say_fail "$where: file $file not found"
    return
  fi
  text="$(sed -n "${n}p" "$file")"
  if [ "${#quote}" -lt 4 ]; then
    say_fail "$where: quote in backticks missing or under 4 characters"
  elif ! printf '%s\n' "$text" | grep -qF -- "$quote"; then
    say_fail "$where: $file line $n doesn't contain the quote. Copy the line from security-diff.sh or grep -n."
  else
    echo "  OK  $where $file:$n"
  fi
}

check_loc_quote() {
  local id="$1" loc="$2" line="$3" quote file n
  quote="$(echo "$line" | sed -nE 's/.*quote: *`([^`]*)`.*/\1/p')"
  file="${loc%:*}"
  n="${loc##*:}"
  if [ -z "$file" ] || ! echo "$n" | grep -Eq '^[0-9]+$'; then
    say_fail "$id: location must be <file>:<line>, found \"$loc\""
    return
  fi
  check_quote "$id" "$file" "$n" "$quote"
}

echo "== Result"
result="$(grep -E '^Result:' "$report" | head -1 | sed -E 's/^Result: *//; s/[*` ]//g')"
case "$result" in
  BLOCK|REVIEW|PASS) echo "$result" ;;
  *) say_fail "\"Result:\" must be BLOCK, REVIEW, or PASS, found \"$result\"" ;;
esac

echo "== Findings"
finds="$(items 'Findings:')"
count=0
serious=0
ids=""
while IFS= read -r line; do
  [ -n "$line" ] || continue
  count=$((count + 1))
  id="$(echo "$line" | sed -nE 's/^ *- *(F[0-9]+) *\|.*/\1/p')"
  [ -n "$id" ] || { say_fail "finding line must start with \"- F<n> |\": ${line:0:60}"; continue; }
  ids="$ids $id"
  sev="$(field "$line" 2)"
  rule="$(field "$line" 3 | sed -nE 's/^rule: *([a-z-]+)$/\1/p')"
  case "$rule" in
    code-exec) want=critical ;;
    injection|missing-auth|hardcoded-secret|harness|risky-dependency) want=high ;;
    secret-exposure|weak-check) want=medium ;;
    unpinned-dependency|info-leak) want=low ;;
    *) want="" ;;
  esac
  if [ -z "$want" ]; then
    say_fail "$id: third field must be \"rule: <name>\" with a rule from the Severity table"
  elif [ "$sev" != "$want" ]; then
    say_fail "$id: rule $rule is $want, but the finding says \"$sev\""
  fi
  case "$sev" in critical|high) serious=$((serious + 1)) ;; esac
  if [ "$rule" = hardcoded-secret ]; then
    # The quote must stop before the value: no part of the line's last
    # string literal may appear in it. Prints nothing about the value.
    sloc="$(field "$line" 4)"
    sq="$(echo "$line" | sed -nE 's/.*quote: *`([^`]*)`.*/\1/p')"
    lit="$(sed -n "${sloc##*:}p" "${sloc%:*}" 2>/dev/null | sed -nE "s/.*[\"']([^\"']{4,})[\"'].*/\1/p")"
    if [ -n "$lit" ] && printf '%s\n' "$sq" | grep -qF -- "${lit:0:4}"; then
      say_fail "$id: the quote includes part of the secret's value. Quote only the name and \"=\", like \`NAME = \`."
    fi
  fi
  for k in 'path:' 'impact:' 'fix:'; do
    echo "$line" | grep -q "$k" || say_fail "$id: missing \"$k\""
  done
  echo "$line" | grep -Eq 'path:[^|]*->' || say_fail "$id: \"path:\" must read <who> -> <input> -> <line it reaches>"
  check_loc_quote "$id" "$(field "$line" 4)" "$line"
done <<< "$finds"
echo "$count finding(s), $serious critical or high."

echo "== Needs validation"
vals="$(items 'Needs validation:')"
nval=0
while IFS= read -r line; do
  [ -n "$line" ] || continue
  nval=$((nval + 1))
  id="$(echo "$line" | sed -nE 's/^ *- *(V[0-9]+) *\|.*/\1/p')"
  [ -n "$id" ] || { say_fail "needs-validation line must start with \"- V<n> |\": ${line:0:60}"; continue; }
  ids="$ids $id"
  echo "$line" | grep -Eqi '\| *(critical|high|medium|low) *\|' && say_fail "$id: items under \"Needs validation\" have no severity"
  echo "$line" | grep -q 'missing fact:' || say_fail "$id: missing \"missing fact:\""
  check_loc_quote "$id" "$(field "$line" 3)" "$line"
done <<< "$vals"
echo "$nval item(s)."

echo "== Hardening notes"
while IFS= read -r line; do
  [ -n "$line" ] || continue
  id="$(echo "$line" | sed -nE 's/^ *- *(H[0-9]+) *\|.*/\1/p')"
  [ -n "$id" ] || { say_fail "hardening line must start with \"- H<n> |\": ${line:0:60}"; continue; }
  ids="$ids $id"
  check_loc_quote "$id" "$(field "$line" 2)" "$line"
done <<< "$(items 'Hardening notes:')"

has_id() { echo " $ids " | grep -q " $1 "; }

echo "== Result follows the rule"
planted="$(items 'Planted instructions:' | wc -l | tr -d ' ')"
if [ "$serious" -gt 0 ]; then expected=BLOCK
elif [ "$count" -gt 0 ] || [ "$nval" -gt 0 ] || [ "$planted" -gt 0 ]; then expected=REVIEW
else expected=PASS
fi
if [ "$result" = "$expected" ]; then
  echo "$result matches $serious critical or high, $count finding(s), $nval to validate, $planted planted."
else
  say_fail "result is \"$result\" but $serious critical or high, $count finding(s), $nval to validate, $planted planted instruction(s) means $expected"
fi

diff_out="$("$(dirname "$0")/../tools/security-diff.sh" "$BASE" 2>/dev/null)"
risky_sec="$(section 'Risky lines:')"

echo "== Security lint ran"
if printf '%s\n' "$diff_out" | grep -q 'RUFF NOT INSTALLED'; then
  say_fail "Ruff isn't installed where this shell can find it, so the risky lines miss Ruff's hits. Install it (brew install ruff, or pipx install ruff) and run the review again."
else
  echo "OK"
fi

echo "== Risky lines are accounted for"
risky="$(printf '%s\n' "$diff_out" | sed -n '/^== Risky lines/,$p' | grep -E '^[^ =]+:[0-9]+ \[' || true)"
while IFS= read -r r; do
  [ -n "$r" ] || continue
  loc="${r%% *}"
  entry="$(printf '%s\n' "$risky_sec" | grep -E "^ *- *$loc[^0-9]" | head -1)"
  if [ -z "$entry" ]; then
    say_fail "risky line $loc isn't under \"Risky lines:\""
    continue
  fi
  ref="$(echo "$entry" | sed -nE 's/.*-> *([FVH][0-9]+).*/\1/p')"
  if [ -n "$ref" ]; then
    if ! has_id "$ref"; then
      say_fail "risky line $loc points to $ref, but there is no $ref"
      continue
    fi
  elif ! echo "$entry" | grep -Eq 'planted instruction|safe: *[^ ]'; then
    say_fail "risky line $loc needs \"-> F<n>\", \"-> V<n>\", \"-> H<n>\", \"planted instruction\", or \"safe: <why>\""
    continue
  fi
  tagset="$(echo "$r" | sed -nE 's/^[^ ]+ \[([^]]*)\].*/\1/p')"
  if echo "$tagset" | grep -Eq 'typo-of:|harness' && ! echo "$ref" | grep -Eq '^[FV]'; then
    say_fail "risky line $loc is tagged [$tagset]; it must point to a finding (-> F<n>) or a needs-validation item (-> V<n>), not safe or a hardening note"
    continue
  fi
  if echo "$tagset" | grep -Eq 'injection|ruff:' && echo "$ref" | grep -q '^H'; then
    say_fail "risky line $loc is tagged [$tagset]; a hardening note isn't enough. If caller input reaches it, it's a finding; if not, write \"safe: <why>\""
    continue
  fi
  if echo "$r" | grep -q 'secret-scan:'; then
    case "$ref" in
      F*) echo "$finds" | grep -E "^ *- *$ref *\|" | grep -q 'rule: *hardcoded-secret' \
            || say_fail "risky line $loc is a secret-scan hit, so $ref must have rule: hardcoded-secret" ;;
      *) say_fail "risky line $loc is a secret-scan hit; it must point to a hardcoded-secret finding" ;;
    esac
  fi
  echo "  OK  $loc"
done <<< "$risky"
[ -n "$risky" ] || echo "None."

echo "== Lines with a finding point to it"
# A finding's own line can't be marked safe under "Risky lines:".
while IFS= read -r line; do
  [ -n "$line" ] || continue
  fid="$(echo "$line" | sed -nE 's/^ *- *(F[0-9]+) *\|.*/\1/p')"
  floc="$(field "$line" 4)"
  [ -n "$fid" ] && [ -n "$floc" ] || continue
  entry="$(printf '%s\n' "$risky_sec" | grep -E "^ *- *$floc[^0-9]" | head -1)"
  if [ -n "$entry" ] && ! echo "$entry" | grep -Eq -- "-> *$fid([^0-9]|$)"; then
    say_fail "$fid is at $floc, but that risky line doesn't point to $fid"
  fi
done <<< "$finds"

echo "== Harness and dependency files are listed"
hd_sec="$(section 'Harness and dependency files:')"
hd_files="$(printf '%s\n' "$diff_out" | awk '/^== (Harness|Dependency) files/{f=1; next} /^== /{f=0} f && NF && $0 != "None."')"
for f in $hd_files; do
  if printf '%s\n' "$hd_sec" | grep -qF -- "$f"; then
    echo "  OK  $f"
  else
    say_fail "$f is a harness or dependency file on this branch but isn't under \"Harness and dependency files:\""
  fi
done
[ -n "$hd_files" ] || echo "None."

echo "== Every changed file is under \"Scope:\""
scope_sec="$(section 'Scope:')"
missing=0
for f in $(git diff --name-only "$BASE...HEAD"); do
  printf '%s\n' "$scope_sec" | grep -qF -- "$f" || { say_fail "$f changed on this branch but isn't under \"Scope:\""; missing=1; }
done
[ "$missing" -eq 0 ] && echo "All listed."

finish "Security-Agent"
