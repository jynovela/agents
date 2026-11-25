#!/usr/bin/env bash
# Copies agents from this repo into a project.
#
# Usage: ./install.sh <project-dir> <agent> [<agent>...]
#   project-dir: the root of the project to install into. It must exist.
#   agent:       a folder name under agents/, like docs-agent.
#
# For each agent it writes, inside the project:
#   .agents/skills/<agent>/     SKILL.md, check.sh, and tools/ when there are any
#   .agents/shared/lib.sh       helpers every check script uses
#   .claude/agents/<agent>.md   the Claude Code wrapper
# Running it again replaces those files with this repo's version. It changes
# nothing else: it doesn't write AGENTS.md, and it never commits.

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"

if [ "$#" -lt 2 ]; then
  echo "Usage: ./install.sh <project-dir> <agent> [<agent>...]" >&2
  echo "Agents you can install:" >&2
  for d in "$here"/agents/*/; do echo "  $(basename "$d")" >&2; done
  exit 2
fi

target="$1"
shift

if [ ! -d "$target" ]; then
  echo "Project folder $target doesn't exist." >&2
  exit 2
fi
target="$(cd "$target" && pwd)"

for agent in "$@"; do
  if [ ! -f "$here/agents/$agent/SKILL.md" ]; then
    echo "No agent named \"$agent\" in $here/agents. Nothing was installed for it." >&2
    exit 2
  fi
done

mkdir -p "$target/.agents/shared" "$target/.agents/skills" "$target/.claude/agents"
rm -f "$target/.agents/shared/lib.sh"
cp "$here/shared/lib.sh" "$target/.agents/shared/lib.sh"

for agent in "$@"; do
  src="$here/agents/$agent"
  dest="$target/.agents/skills/$agent"
  rm -rf "$dest"
  mkdir -p "$dest"
  cp "$src/SKILL.md" "$dest/SKILL.md"
  if [ -f "$src/check.sh" ]; then
    cp "$src/check.sh" "$dest/check.sh"
    chmod +x "$dest/check.sh"
  fi
  if [ -d "$src/tools" ]; then
    cp -R "$src/tools" "$dest/tools"
  fi
  if [ -f "$src/claude.md" ]; then
    rm -f "$target/.claude/agents/$agent.md"
    cp "$src/claude.md" "$target/.claude/agents/$agent.md"
  fi
  echo "Installed $agent into $dest"
done
