#!/usr/bin/env bash
# Builds a throwaway git repo for testing agents against the sample app.
# Usage: ./setup.sh [target-dir]   (default: /tmp/itemctl-test)
# The target sits outside this repo so tools do not also load this repo's AGENTS.md or CLAUDE.md.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
target="${1:-/tmp/itemctl-test}"

if [ -e "$target" ]; then
  echo "Target $target already exists. For a clean run, remove it with: rm -rf \"$target\"" >&2
  exit 1
fi

mkdir -p "$target"
cp -R "$here/base/." "$target/"

# Agent files come from the repo root, so the test always uses the current roles.
cp -R "$root/.agents" "$root/.claude" "$root/.markdownlint-cli2.yaml" "$target/"
cp "$root/CLAUDE.md" "$target/"
{
  cat "$target/AGENTS.header.md"
  echo
  sed -n '/^## Shared guardrails/,$p' "$root/AGENTS.md"
} > "$target/AGENTS.md"
rm "$target/AGENTS.header.md"

cd "$target"
git init -q -b main
git add -A
git -c user.name=sample -c user.email=sample@example.invalid commit -q -m "itemctl 1.0.0"

git checkout -q -b feature
cp -R "$here/change/." "$target/"
git add -A
git -c user.name=sample -c user.email=sample@example.invalid commit -q \
  -m "ITEM-12: rename --max to --limit, add --offset, timeout, and auth token"

echo "Ready: $target (branch 'feature', base 'main')"
echo "Next: open that folder in your agent and say one of:"
echo "  Act as Docs-Agent. Update the docs for this branch against main."
echo "  Read AGENTS.md and .agents/roles/test-agent.md first. Act as Test-Agent in Verify mode. The ticket is .tickets/ITEM-12.md, not your tracker. Verify ITEM-12 on this branch against main."
echo "For Test-Agent Write mode, first run: git -C \"$target\" checkout -q main"
echo "  Read AGENTS.md and .agents/roles/test-agent.md first. Act as Test-Agent in Write mode. The ticket is .tickets/ITEM-12.md, not your tracker. Write acceptance tests for ITEM-12."
echo "For Planner-Agent, stay on 'feature' and say:"
echo "  Read AGENTS.md and .agents/roles/planner-agent.md first. Act as Planner-Agent. The brief is .briefs/export.md. This is local mode: write drafts only and don't use Linear."
echo "Then grade the run with $here/expected-<agent>.md"
