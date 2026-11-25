#!/usr/bin/env bash
# Deterministic checks for a Build-Agent run. Run from the repo root after the
# agent finishes, before anything is committed.
#
# Usage: .agents/skills/build-agent/check.sh report.md
#
# Exit code 0 means all checks passed. Any failure prints FAIL and exits 1.

set -uo pipefail
here="$(dirname "$0")"
. "$here/../../shared/lib.sh"

# <!-- TAILOR: the build files the agent may edit, as an extended regex. Keep
# in sync with "Scope" in .agents/skills/build-agent/SKILL.md. -->
EDITABLE='^dev/[^/]+\.sh$|^Makefile$|^Dockerfile$'
NOT_EDITABLE='^dev/deploy\.sh$'

# <!-- TAILOR: the deploy targets dev/deploy.sh allows. -->
ALLOWED='local staging'

# <!-- TAILOR: steps whose owner is always the same, as "Step name|Owner",
# one per line. Keep in sync with step 2 of the role's procedure. -->
STEP_OWNERS='Lint code|Lint-Agent'

report="${1:-}"
if [ -z "$report" ]; then
  echo "Usage: .agents/skills/build-agent/check.sh report.md"
  exit 1
fi

# Lines of one report section: from the heading line to the next heading.
section() {
  awk -v h="$1" '
    index($0, h) == 1 { on = 1; next }
    on && /^[A-Z][A-Za-z ]+:/ { exit }
    on { print }' "$report"
}

check_headings "$report" "### Build-Agent report" "Steps before:" \
  "Failing steps:" "Fixed:" "Needs approval:" "Security flags:" \
  "Steps after:" "Deploy:" "Verify:"
[ -f "$report" ] || finish build-agent

rep="$(echo "$report" | sed 's/[.[\*^$()+?{|]/\\&/g')"
check_scope "$EDITABLE|^$rep\$"
if changed_files | grep -Eq "$NOT_EDITABLE"; then
  say_fail "dev/deploy.sh changed. Only a person changes the deploy script."
fi

echo "== Deleted files"
deleted="$(git diff --name-only --diff-filter=D HEAD)"
if [ -n "$deleted" ]; then
  say_fail "files deleted (deleting is Ask first):"
  echo "$deleted" | sed 's/^/  /'
else
  echo "None."
fi

check_secrets

# Runs a guard and fails on each FAIL line it prints. A guard that crashes
# prints no FAIL line, so it also fails unless its last line says it finished.
run_guard() {
  local name="$1" out last fails
  shift
  out="$("$@" 2>&1)"
  last="$(echo "$out" | tail -1)"
  fails="$(echo "$out" | grep '^FAIL: ' | sed 's/^FAIL: //' | grep -v "^$report[: ]" || true)"
  if [ -n "$fails" ]; then
    while IFS= read -r l; do say_fail "$l"; done <<< "$fails"
  elif echo "$last" | grep -q "^$name checks: "; then
    echo "Passed."
  else
    say_fail "$name didn't finish. Its last line: $last"
  fi
}

echo "== Build guard on the agent's changes"
run_guard build-guard "$here/../../shared/build-guard.sh"

echo "== Lint guard on the agent's changes"
run_guard lint-guard "$here/../../shared/lint-guard.sh"

echo "== Steps, rerun by this check"
out="$("$here/tools/build-steps.sh" run 2>&1)"
code=$?
steps="$(echo "$out" | grep '^STEP ' || true)"
echo "$steps"
done_n="$(echo "$out" | sed -n 's/^STEPS_DONE \([0-9][0-9]*\)$/\1/p')"
got_n="$(echo "$steps" | grep -c '^STEP ' || true)"
if [ "$code" -gt 1 ] || [ -z "$done_n" ] || [ "$done_n" -eq 0 ] || [ "$got_n" -ne "$done_n" ]; then
  say_fail "build-steps.sh run didn't finish (exit $code). Its last line: $(echo "$out" | tail -1)"
fi
after="$(section "Steps after:")"
failing="$(section "Failing steps:")"
red=""
while IFS= read -r l; do
  [ -n "$l" ] || continue
  name="$(echo "$l" | sed -E 's/^STEP (.*): (PASS|FAIL).*/\1/')"
  state="$(echo "$l" | sed -E 's/^STEP .*: (PASS|FAIL).*/\1/')"
  claimed="$(echo "$after" | grep -F -- "- $name:" | head -1 | grep -oE 'PASS|FAIL' | head -1)"
  if [ -z "$claimed" ]; then
    say_fail "\"Steps after\" has no line \"- $name: $state\""
  elif [ "$claimed" != "$state" ]; then
    say_fail "\"Steps after\" says $name: $claimed, but it's $state now"
  fi
  if [ "$state" = FAIL ]; then
    red="$red $name,"
    line="$(echo "$failing" | grep -F -- "- $name |" | head -1)"
    if ! echo "$line" | grep -q 'owner:'; then
      say_fail "$name fails, but \"Failing steps\" has no \"- $name | ... | owner: ...\" line"
    fi
    want="$(echo "$STEP_OWNERS" | grep -F -- "$name|" | head -1 | cut -d'|' -f2)"
    if [ -n "$want" ] && ! echo "$line" | grep -qF -- "owner: $want"; then
      say_fail "$name always belongs to $want. Write \"owner: $want\" on its \"Failing steps\" line."
    fi
  fi
done <<< "$steps"

echo "== Fixes made their step pass"
hits=0
fixed="$(section "Fixed:")"
mine="$(changed_files | grep -vxF -- "$report" || true)"
while IFS= read -r l; do
  case "$l" in -\ None*|None*|'') continue ;; esac
  step="$(echo "$l" | sed -n 's/.*fixes:[[:space:]]*//p' | sed 's/[[:space:]]*$//')"
  if [ -z "$step" ]; then
    say_fail "\"Fixed\" line has no \"fixes: <step>\": $l"
    hits=$((hits + 1))
  elif echo "$red" | grep -qF -- " $step,"; then
    say_fail "\"Fixed\" says it fixes $step, but $step still fails. Undo the fix and list it under \"Needs approval\"."
    hits=$((hits + 1))
  fi
done <<< "$fixed"
for f in $mine; do
  if ! echo "$fixed" | grep -qF -- "$f"; then
    say_fail "$f changed, but isn't under \"Fixed\""
    hits=$((hits + 1))
  fi
done
[ "$hits" -eq 0 ] && echo "OK."

echo "== CI gaps are under \"Needs approval\""
approval="$(section "Needs approval:")"
out="$("$here/tools/build-steps.sh" ci 2>&1)"
if ! echo "$out" | tail -1 | grep -q '^CI_CHECK_DONE$'; then
  say_fail "build-steps.sh ci didn't finish. Its last line: $(echo "$out" | tail -1)"
fi
gaps="$(echo "$out" | grep '^CI_MISSING ' || true)"
if [ -z "$gaps" ]; then
  echo "None."
else
  while IFS= read -r l; do
    name="$(echo "$l" | sed -E 's/^CI_MISSING ([^:]*):.*/\1/')"
    if echo "$approval" | grep -qF -- "CI_MISSING $name"; then
      echo "Listed: $name"
    else
      say_fail "CI doesn't run the \"$name\" step, but \"Needs approval\" has no line with \"why: CI_MISSING $name\""
    fi
  done <<< "$gaps"
fi

echo "== Deploys"
deploy="$(section "Deploy:")"
if [ -f logs/deploy.log ]; then
  cat logs/deploy.log
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    target="$(echo "$l" | awk '{print $NF}')"
    case "$l" in
      *REFUSED*) say_fail "a deploy to a target that isn't allowed was tried: $l" ;;
      *) case " $ALLOWED " in
           *" $target "*) ;;
           *) say_fail "deploy log has a target that isn't allowed: $l" ;;
         esac ;;
    esac
  done <<< "$(awk '{ $1 = ""; print }' logs/deploy.log | sed 's/ (.*)$//')"
  if grep -q 'START deploy staging' logs/deploy.log && [ -n "$red" ]; then
    say_fail "deployed to staging while steps fail:$red"
  fi
  if grep -q 'OK deploy staging' logs/deploy.log && ! echo "$deploy" | grep -q 'staging: deployed'; then
    say_fail "staging was deployed, but \"Deploy\" doesn't say \"- staging: deployed\""
  fi
else
  echo "No deploys."
  if echo "$deploy" | grep -q 'staging: deployed'; then
    say_fail "\"Deploy\" says staging was deployed, but logs/deploy.log has no deploy"
  fi
fi

finish build-agent
