#!/usr/bin/env bash
# Creates one Hermes profile per agent, each with its own SOUL.md.
#
# Usage: hermes/profiles.sh <name> [<name>...]
#        hermes/profiles.sh all
#   name: a folder under agents/, like docs-agent.
#
# For each name it runs:
#   hermes profile create <name> --clone --description "<what the agent does>"
#   and copies agents/<name>/hermes/SOUL.md to ~/.hermes/profiles/<name>/SOUL.md
#
# --clone copies the model, provider, and keys from your current Hermes
# profile, so the new profile works at once. A profile that already exists
# is kept: only its SOUL.md is replaced. Set HERMES_HOME if your Hermes
# folder isn't ~/.hermes. See HERMES.md.

set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
home="${HERMES_HOME:-$HOME/.hermes}"

if [ "$#" -lt 1 ]; then
  echo "Usage: hermes/profiles.sh <name> [<name>...]   or   hermes/profiles.sh all" >&2
  exit 2
fi
if ! command -v hermes >/dev/null 2>&1; then
  echo "The hermes command isn't on your PATH. Install Hermes first." >&2
  exit 2
fi

if [ "$1" = "all" ]; then
  set --
  for d in "$here"/agents/*/; do
    [ -f "$d/hermes/SOUL.md" ] && set -- "$@" "$(basename "$d")"
  done
fi

for name in "$@"; do
  soul="$here/agents/$name/hermes/SOUL.md"
  if [ ! -f "$soul" ]; then
    echo "No agent named \"$name\" with a hermes/SOUL.md in $here/agents. Nothing was changed for it." >&2
    exit 2
  fi
done

for name in "$@"; do
  profile="$home/profiles/$name"
  if [ -d "$profile" ]; then
    echo "Profile $name exists. Keeping its settings."
  else
    purpose="$(sed -n 's/^purpose: *//p' "$here/agents/$name/agent.yaml" | sed 's/^"\(.*\)"$/\1/' | head -n 1)"
    hermes profile create "$name" --clone --description "$purpose"
  fi
  if [ ! -d "$profile" ]; then
    echo "Hermes didn't create $profile. Stopping." >&2
    exit 1
  fi
  cp "$here/agents/$name/hermes/SOUL.md" "$profile/SOUL.md"
  echo "SOUL.md written to $profile/SOUL.md"
done
