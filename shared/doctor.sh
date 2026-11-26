#!/usr/bin/env bash
# Checks the agents installed in this project. Run it from anywhere:
#   .agents/shared/doctor.sh            list what is installed and what each one still needs
#   .agents/shared/doctor.sh --strict   also exit 1 when any agent is not ready
#
# FAIL means the install itself is broken: run install.sh again.
# NOT READY means an agent needs a line in AGENTS.md or a tool on this
# machine before it can do its job. The other agents still work.
#
# It reads AGENTS.md and each .agents/skills/<name>/agent.yaml. It changes nothing.

set -uo pipefail

strict=0
[ "${1:-}" = "--strict" ] && strict=1

root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"

fail=0
not_ready=0
say_fail() { echo "FAIL: $*"; fail=1; }

field() {
  sed -n "s/^$2: *//p" "$1" | sed 's/^"\(.*\)"$/\1/' | head -n 1
}

# Prints the value AGENTS.md gives a label, like "Lint docs". A label matches
# a line that starts with it, with or without "- " in front, up to the colon.
# Text in brackets before the colon is allowed.
value_of() {
  grep -E "^(- )?$1( \([^)]*\))?:" AGENTS.md | head -n 1 | sed 's/^[^:]*: *//'
}

if [ ! -f AGENTS.md ]; then
  say_fail "AGENTS.md is missing from $root."
else
  grep -q '^## Shared guardrails' AGENTS.md || say_fail "AGENTS.md has no \"Shared guardrails\" section. Every agent reads it."
fi
[ -f .agents/shared/lib.sh ] || say_fail ".agents/shared/lib.sh is missing."
command -v git >/dev/null 2>&1 || say_fail "git is not installed. Every check script uses it."

found=0
for manifest in .agents/skills/*/agent.yaml; do
  [ -f "$manifest" ] || continue
  found=1
  dir="$(dirname "$manifest")"
  name="$(basename "$dir")"
  kind="$(field "$manifest" kind)"
  title="$(field "$manifest" title)"
  problems=""

  [ -f "$dir/SKILL.md" ] || say_fail "$name: $dir/SKILL.md is missing."
  for script in "$dir/check.sh" "$dir"/tools/*.sh; do
    [ -f "$script" ] || continue
    [ -x "$script" ] || say_fail "$name: $script can't be run (chmod +x)."
    bash -n "$script" 2>/dev/null || say_fail "$name: $script has a syntax error."
  done
  if [ "$kind" = "agent" ]; then
    [ -f ".claude/agents/$name.md" ] || say_fail "$name: .claude/agents/$name.md is missing, so Claude Code can't start it."
  else
    [ -f ".claude/skills/$name/SKILL.md" ] || say_fail "$name: the link .claude/skills/$name is missing or broken, so Claude Code can't find it."
  fi
  if [ -f AGENTS.md ] && ! grep -qF "\`.agents/skills/$name/SKILL.md\`" AGENTS.md; then
    say_fail "$name: AGENTS.md doesn't list it. Run install.sh again."
  fi

  old_ifs="$IFS"
  IFS=','
  for label in $(field "$manifest" needs_commands); do
    label="$(echo "$label" | sed 's/^ *//; s/ *$//')"
    [ -n "$label" ] || continue
    value=""
    [ -f AGENTS.md ] && value="$(value_of "$label")"
    case "$value" in
      ""|None|None.) problems="$problems
  - AGENTS.md: set \"$label\"" ;;
    esac
  done
  for tool in $(field "$manifest" needs_tools); do
    tool="$(echo "$tool" | sed 's/^ *//; s/ *$//')"
    [ -n "$tool" ] || continue
    command -v "$tool" >/dev/null 2>&1 || problems="$problems
  - install $tool on this machine"
  done
  IFS="$old_ifs"

  if [ -z "$problems" ]; then
    echo "READY: $title"
  else
    not_ready=1
    echo "NOT READY: $title$problems"
    guide="$(field "$manifest" setup)"
    [ -n "$guide" ] && echo "  See $guide."
  fi
done

[ "$found" -eq 1 ] || say_fail "Nothing is installed in .agents/skills/. Run install.sh."

if [ "$fail" -ne 0 ]; then
  echo "RESULT: FAIL"
  exit 1
fi
if [ "$not_ready" -ne 0 ]; then
  echo "RESULT: OK, but some agents are not ready. Fix the lines above, then run this again."
  [ "$strict" -eq 1 ] && exit 1
  exit 0
fi
echo "RESULT: OK"
