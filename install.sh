#!/usr/bin/env bash
# Copies agents and skills from this repo into a project.
#
# Usage: ./install.sh <project-dir> <name> [<name>...]
#        ./install.sh <project-dir> all
#   project-dir: the root of the project to install into. It must exist.
#   name:        a folder under agents/ or skills/, like docs-agent or user-flows.
#
# It writes, inside the project:
#   .agents/skills/<name>/      SKILL.md, agent.yaml, check.sh, and tools/ when there are any
#   .agents/shared/             lib.sh, doctor.sh, and the checks every agent shares
#   .agents/setup/              the setup guides and the files they tell you to copy
#   .claude/agents/<name>.md    the Claude Code wrapper, for an agent
#   .claude/skills/<name>       a link to .agents/skills/<name>, for a skill
#   AGENTS.md                   created from this repo's AGENTS.md when the project has
#                               none. In an existing one, only the part between the
#                               agents:start and agents:end comments is rewritten: the
#                               tables of what is installed.
#   CLAUDE.md, .markdownlint-cli2.yaml   created only when the project has none
# Running it again replaces the files under .agents/ and .claude/ with this
# repo's version. It never commits. When it finishes it runs
# .agents/shared/doctor.sh, which lists what each agent still needs.

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
if [ "$target" = "$here" ]; then
  echo "Can't install into the agents repo itself. Give the folder of the project that will use the agents." >&2
  exit 2
fi

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

rm -rf "$target/.agents/setup"
cp -R "$here/setup" "$target/.agents/setup"

for name in "$@"; do
  src="$(source_of "$name")"
  dest="$target/.agents/skills/$name"
  rm -rf "$dest"
  mkdir -p "$dest"
  cp "$src/SKILL.md" "$dest/SKILL.md"
  cp "$src/agent.yaml" "$dest/agent.yaml"
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

# One field of an installed manifest, without the quotes around it.
field() {
  sed -n "s/^$2: *//p" "$1" | sed 's/^"\(.*\)"$/\1/' | head -n 1
}

# The table rows for every installed manifest of one kind (agent or skill).
rows() {
  local f name
  for f in "$target"/.agents/skills/*/agent.yaml; do
    [ -f "$f" ] || continue
    [ "$(field "$f" kind)" = "$1" ] || continue
    name="$(basename "$(dirname "$f")")"
    echo "| $(field "$f" title) | \`.agents/skills/$name/SKILL.md\` | $(field "$f" purpose) |"
  done
}

# The part of AGENTS.md this script owns: the tables of what is installed.
block() {
  local agent_rows skill_rows
  agent_rows="$(rows agent)"
  skill_rows="$(rows skill)"
  echo "<!-- agents:start -->"
  echo "<!-- install.sh writes everything from here to agents:end. Don't edit it by hand. -->"
  if [ -n "$agent_rows" ]; then
    echo
    echo "## Agent roles"
    echo
    echo "When asked to act as one of these agents, read its role file first and follow it."
    echo
    echo "| Agent | Role file | Purpose |"
    echo "| ----- | --------- | ------- |"
    echo "$agent_rows"
  fi
  if [ -n "$skill_rows" ]; then
    echo
    echo "## Skills"
    echo
    echo "Skills are procedures any agent, or you, can run. When asked to use one,"
    echo "read its file first and follow it."
    echo
    echo "| Skill | File | Purpose |"
    echo "| ----- | ---- | ------- |"
    echo "$skill_rows"
  fi
  echo
  echo "<!-- agents:end -->"
}

agents_md="$target/AGENTS.md"
if [ ! -f "$agents_md" ]; then
  sed '/^<!-- agents:start -->$/,$d' "$here/AGENTS.md" > "$agents_md"
  block >> "$agents_md"
  echo "Created AGENTS.md. Fill in every TAILOR comment in it."
elif grep -q '^<!-- agents:start -->$' "$agents_md" && grep -q '^<!-- agents:end -->$' "$agents_md"; then
  {
    sed '/^<!-- agents:start -->$/,$d' "$agents_md"
    block
    sed '1,/^<!-- agents:end -->$/d' "$agents_md"
  } > "$agents_md.new"
  mv "$agents_md.new" "$agents_md"
  echo "Updated the agent tables in AGENTS.md."
else
  [ -z "$(tail -n 1 "$agents_md")" ] || echo >> "$agents_md"
  block >> "$agents_md"
  echo "Added the agent tables to the end of AGENTS.md."
fi

if [ ! -f "$target/CLAUDE.md" ]; then
  cp "$here/CLAUDE.md" "$target/CLAUDE.md"
  echo "Created CLAUDE.md."
fi
if [ ! -f "$target/.markdownlint-cli2.yaml" ]; then
  cp "$here/.markdownlint-cli2.yaml" "$target/.markdownlint-cli2.yaml"
  echo "Created .markdownlint-cli2.yaml."
fi

echo
"$target/.agents/shared/doctor.sh" || true
