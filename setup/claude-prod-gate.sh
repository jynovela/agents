#!/usr/bin/env bash
# Claude Code PreToolUse hook: blocks shell commands that deploy to production
# or weaken a check, before they run. Exit code 2 blocks the command and shows
# the message to Claude.
# Copy to .claude/hooks/prod-gate.sh and register it in .claude/settings.json.
# See .agents/setup/build.md.
#
# This is a second layer. A determined or confused agent can find a command
# this list misses. The first layer is that the agent's machine has no
# production credentials.
set -uo pipefail

cmd="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("tool_input", {}).get("command", ""))')"

# <!-- TAILOR: production deploy and data commands for your stack. -->
PROD='--prod([[:space:]]|$)|vercel[[:space:]]+(promote|rollback)|netlify[[:space:]].*--prod|deploy(\.sh)?[[:space:]]+prod(uction)?([[:space:]]|$)|supabase[[:space:]]+link|supabase[[:space:]]+db[[:space:]]+(push|reset)[[:space:]].*--linked|git[[:space:]]+push[[:space:]].*[[:space:]](main|master|production)([[:space:]]|$)|git[[:space:]]+push[[:space:]].*--force'

if echo "$cmd" | grep -Eiq -- "$PROD"; then
  {
    echo "Blocked by the production gate: this command can change production."
    echo "Agents deploy only with dev/deploy.sh to local or staging."
    echo "Production changes need a person: they merge to the production branch."
    echo "Say in your report what you wanted to run and why."
  } >&2
  exit 2
fi
exit 0
