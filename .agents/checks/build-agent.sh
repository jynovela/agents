#!/usr/bin/env bash
# Deterministic checks for a Build-Agent run. Run from the repo root after the
# agent finishes, before anything is committed.
#
# Usage: .agents/checks/build-agent.sh report.md
#
# Exit code 0 means all checks passed. Any failure prints FAIL and exits 1.

set -uo pipefail
here="$(dirname "$0")"
. "$here/lib.sh"

# <!-- TAILOR: the build files the agent may edit, as an extended regex. Keep
# in sync with "Scope" in .agents/roles/build-agent.md. -->
EDITABLE='^dev/[^/]+\.sh$|^Makefile$|^Dockerfile$'
NOT_EDITABLE='^dev/deploy\.sh$'

# <!-- TAILOR: the deploy targets dev/deploy.sh allows. -->
ALLOWED='local staging'

report="${1:-}"
if [ -z "$report" ]; then
  echo "Usage: .agents/checks/build-agent.sh report.md"
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

echo "== Build guard on the agent's changes"
guard="$("$here/build-guard.sh" 2>&1 | grep '^FAIL: ' | sed 's/^FAIL: //' || true)"
if [ -z "$guard" ]; then
  echo "Passed."
else
  while IFS= read -r l; do say_fail "$l"; done <<< "$guard"
fi

echo "== Lint guard on the agent's changes"
guard="$("$here/lint-guard.sh" 2>&1 | grep '^FAIL: ' | sed 's/^FAIL: //' | grep -v "^$report[: ]" || true)"
if [ -z "$guard" ]; then
  echo "Passed."
else
  while IFS= read -r l; do say_fail "$l"; done <<< "$guard"
fi

echo "== Steps, rerun by this check"
steps="$("$here/../tools/build-steps.sh" run 2>/dev/null | grep '^STEP ' || true)"
echo "$steps"
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
    if ! echo "$failing" | grep -F -- "- $name |" | grep -q 'owner:'; then
      say_fail "$name fails, but \"Failing steps\" has no \"- $name | ... | owner: ...\" line"
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
gaps="$("$here/../tools/build-steps.sh" ci 2>/dev/null | grep '^CI_MISSING ' || true)"
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
