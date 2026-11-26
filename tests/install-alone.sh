#!/usr/bin/env bash
# Proves every agent and skill installs and runs on its own, and that this
# repo's AGENTS.md lists exactly what install.sh would write.
# Usage: tests/install-alone.sh
# It works in a temporary folder and changes nothing in this repo.

set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0
say_fail() { echo "FAIL: $*"; fail=1; }

new_project() {
  mkdir -p "$1"
  git -C "$1" init -q -b main
  echo "# Sample" > "$1/README.md"
  git -C "$1" add -A
  git -C "$1" -c user.name=test -c user.email=test@example.invalid commit -q -m "start"
}

block_of() {
  sed -n '/^<!-- agents:start -->$/,/^<!-- agents:end -->$/p' "$1"
}

for dir in "$root"/agents/*/ "$root"/skills/*/; do
  name="$(basename "$dir")"
  project="$tmp/$name"
  new_project "$project"

  if ! out="$("$root/install.sh" "$project" "$name" 2>&1)"; then
    say_fail "$name: install.sh failed:"
    echo "$out" | sed 's/^/  /'
    continue
  fi

  installed="$(ls "$project/.agents/skills" | tr '\n' ' ')"
  [ "$installed" = "$name " ] || say_fail "$name: expected only $name in .agents/skills, found: $installed"

  doctor="$("$project/.agents/shared/doctor.sh" 2>&1)" || say_fail "$name: doctor.sh failed:"
  echo "$doctor" | grep '^FAIL' | sed 's/^/  /'

  rows="$(grep -c '^| .*`\.agents/skills/' "$project/AGENTS.md")"
  [ "$rows" = "1" ] || say_fail "$name: AGENTS.md should list 1 agent or skill, lists $rows"

  # The check may fail, since no agent ran. It must not break on a missing
  # file or command: that would mean it depends on something not installed.
  if [ -f "$project/.agents/skills/$name/check.sh" ]; then
    check="$(cd "$project" && .agents/skills/"$name"/check.sh 2>&1 || true)"
    broken="$(echo "$check" | grep -E 'No such file or directory|command not found|unbound variable|syntax error' || true)"
    if [ -n "$broken" ]; then
      say_fail "$name: check.sh depends on something that isn't installed:"
      echo "$broken" | sed 's/^/  /'
    fi
  fi

  before="$(cat "$project/AGENTS.md")"
  "$root/install.sh" "$project" "$name" >/dev/null 2>&1
  [ "$before" = "$(cat "$project/AGENTS.md")" ] || say_fail "$name: installing twice changed AGENTS.md"

  echo "ok: $name"
done

new_project "$tmp/all"
"$root/install.sh" "$tmp/all" all >/dev/null 2>&1 || say_fail "install.sh all failed"
if [ "$(block_of "$tmp/all/AGENTS.md")" != "$(block_of "$root/AGENTS.md")" ]; then
  say_fail "the tables in this repo's AGENTS.md don't match the agent.yaml files. What install.sh writes:"
  block_of "$tmp/all/AGENTS.md" | diff - <(block_of "$root/AGENTS.md") | sed 's/^/  /'
fi
# Every file an installed agent points at must come with the install.
lint="$(cd "$tmp/all" && .agents/shared/context-lint.sh 2>&1)" || {
  say_fail "context-lint fails in a fresh install of everything:"
  echo "$lint" | grep '^FAIL' | sed 's/^/  /'
}
echo "ok: all"

if [ "$fail" -ne 0 ]; then
  echo "RESULT: FAIL"
  exit 1
fi
echo "RESULT: PASS"
