#!/usr/bin/env bash
# Copies agents and skills from this repo into a project.
#
# Usage: ./install.sh <project-dir> <name> [<name>...]
#        ./install.sh <project-dir> all
#   project-dir: the root of the project to install into. It must exist.
#   name:        a folder under agents/ or skills/, like docs-agent or user-flows.
#
# It writes, inside the project:
#   .agents/skills/<name>/      SKILL.md, check.sh, and tools/ when there are any
#   .agents/shared/             lib.sh and the checks every agent shares
#   .claude/agents/<name>.md    the Claude Code wrapper, for an agent
#   .claude/skills/<name>       a link to .agents/skills/<name>, for a skill
# Running it again replaces those files with this repo's version. It changes
# nothing else: it doesn't write AGENTS.md, and it never commits.

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"

list_names() {
  local d
  for d in "$here"/agents/*/ "$here"/skills/*/; do
    [ -f "$d/SKILL.md" ] && basename "$d"
  done
}

if [ "$#" -lt 2 ]; then
  echo "Usage: ./install.sh <project-dir> <name> [<name>...]   or   ./install.sh <project-dir> all" >&2
  echo "Names you can install:" >&2
  list_names | sed 's/^/  /' >&2
  exit 2
fi

target="$1"
shift

if [ ! -d "$target" ]; then
  echo "Project folder $target doesn't exist." >&2
  exit 2
fi
target="$(cd "$target" && pwd)"

if [ "$1" = "all" ]; then
  set -- $(list_names)
fi

# Prints the source folder of one name, or nothing when there is none.
source_of() {
  if [ -f "$here/agents/$1/SKILL.md" ]; then
    echo "$here/agents/$1"
  elif [ -f "$here/skills/$1/SKILL.md" ]; then
    echo "$here/skills/$1"
  fi
}

for name in "$@"; do
  if [ -z "$(source_of "$name")" ]; then
    echo "Nothing named \"$name\" in $here/agents or $here/skills. Nothing was installed." >&2
    exit 2
  fi
done

mkdir -p "$target/.agents/skills" "$target/.claude/agents" "$target/.claude/skills"
rm -rf "$target/.agents/shared"
mkdir -p "$target/.agents/shared"
cp "$here"/shared/*.sh "$target/.agents/shared/"
chmod +x "$target"/.agents/shared/*.sh

for name in "$@"; do
  src="$(source_of "$name")"
  dest="$target/.agents/skills/$name"
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
    rm -f "$target/.claude/agents/$name.md"
    cp "$src/claude.md" "$target/.claude/agents/$name.md"
  else
    rm -rf "$target/.claude/skills/$name"
    ln -s "../../.agents/skills/$name" "$target/.claude/skills/$name"
  fi
  echo "Installed $name into $dest"
done
