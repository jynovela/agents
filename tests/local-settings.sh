#!/usr/bin/env bash
# Proves a project's settings in .agents/local/ are read by the scripts and
# survive an update with install.sh.
# Usage: tests/local-settings.sh
# It works in a temporary folder and changes nothing in this repo.

set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0
say_fail() { echo "FAIL: $*"; fail=1; }
ok() { echo "ok: $*"; }

# Every script with a setting to tailor must read the project's file.
for script in "$root"/agents/*/check.sh "$root"/agents/*/tools/*.sh "$root"/skills/*/check.sh "$root"/shared/*.sh; do
  grep -q 'TAILOR' "$script" || continue
  grep -q '^if \[ -f \.agents/local/[a-z-]*\.sh \]; then \. \.agents/local/[a-z-]*\.sh; fi$' "$script" \
    || say_fail "${script#"$root"/} has TAILOR values but doesn't read .agents/local/."
done
[ "$fail" -eq 0 ] && ok "every script with TAILOR values reads .agents/local/"

project="$tmp/project"
mkdir -p "$project/guide"
git -C "$project" init -q -b main
echo "# Sample" > "$project/README.md"
echo "# Guide" > "$project/guide/start.md"
"$root/install.sh" "$project" docs-agent > /dev/null 2>&1 || say_fail "install.sh failed."
git -C "$project" add -A
git -C "$project" -c user.name=test -c user.email=test@example.invalid commit -q -m "start"

cd "$project" || exit 1
echo "More." >> guide/start.md

out="$(.agents/skills/docs-agent/check.sh 2>&1)"
echo "$out" | grep -q 'outside the allowed paths' \
  && ok "default setting: a change in guide/ is outside the Docs-Agent's paths" \
  || say_fail "the default ALLOWED should not cover guide/."

# The project commits its settings, as it does the rest of .agents/.
echo 'ALLOWED='"'"'^(guide/.*|README\.md)$'"'" > .agents/local/docs-agent.sh
settings="$(cat .agents/local/docs-agent.sh)"
git add .agents/local
git -c user.name=test -c user.email=test@example.invalid commit -q -m "settings"

out="$(.agents/skills/docs-agent/check.sh 2>&1)"
echo "$out" | grep -q 'outside the allowed paths' \
  && say_fail "the check ignored .agents/local/docs-agent.sh." \
  || ok "project setting: the same change is now inside the paths"

out="$("$root/install.sh" "$project" docs-agent 2>&1)" || say_fail "the update with install.sh failed."
[ "$(cat .agents/local/docs-agent.sh 2>/dev/null)" = "$settings" ] \
  && ok "the update kept .agents/local/docs-agent.sh" \
  || say_fail "the update changed or removed .agents/local/docs-agent.sh."
echo "$out" | grep -q 'Settings in .agents/local/ were kept' \
  || say_fail "the update didn't say that settings were kept."
echo "$out" | grep -q '^Project settings: .agents/local/docs-agent.sh$' \
  || say_fail "doctor.sh didn't list the settings file."

out="$(.agents/skills/docs-agent/check.sh 2>&1)"
echo "$out" | grep -q 'outside the allowed paths' \
  && say_fail "after the update the check ignored the project setting." \
  || ok "after the update the check still uses the project setting"

# The settings decide what agents may change, so agents must not edit them.
echo 'ALLOWED=.' > .agents/local/docs-agent.sh
out="$(.agents/shared/lint-guard.sh 2>&1)"
echo "$out" | grep -q 'FAIL' && echo "$out" | grep -q '\.agents/local/docs-agent\.sh' \
  && ok "lint-guard stops a change to a settings file" \
  || say_fail "lint-guard let a change to .agents/local/ through."

echo "not shell (" > .agents/local/docs-agent.sh
out="$(.agents/shared/doctor.sh 2>&1)"
echo "$out" | grep -q 'FAIL: .agents/local/docs-agent.sh has a syntax error' \
  && ok "doctor.sh reports a broken settings file" \
  || say_fail "doctor.sh missed a broken settings file."

if [ "$fail" -ne 0 ]; then
  echo "RESULT: FAIL"
  exit 1
fi
echo "RESULT: PASS"
