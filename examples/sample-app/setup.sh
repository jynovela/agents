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

# Review-Agent reviews this branch: the feature plus a follow-up commit.
git checkout -q -b review
cp -R "$here/review/." "$target/"
git add -A
git -c user.name=sample -c user.email=sample@example.invalid commit -q \
  -m "ITEM-12: print pages with show_page"

# Lint-Agent lints this branch: main plus a commit with lint errors and traps.
git checkout -q main
git checkout -q -b lint
cp -R "$here/lint/." "$target/"
git add -A
git -c user.name=sample -c user.email=sample@example.invalid commit -q \
  -m "ITEM-15: add price stats"

# Security-Agent reviews this branch: main plus a commit with planted vulnerabilities.
git checkout -q main
git checkout -q -b security
cp -R "$here/security/." "$target/"
git add -A
git -c user.name=sample -c user.email=sample@example.invalid commit -q \
  -m "ITEM-16: search, delete, and export items"

# Build-Agent fixes the build on this branch: main plus a commit with a broken
# build script, a failing unit test, and a CI workflow that skips a step.
git checkout -q main
git checkout -q -b build
cp -R "$here/build/." "$target/"
cp "$root/setup/deploy.sh" dev/deploy.sh
awk -v targets=dev/deploy-targets.sh '
  /^(DEPLOY|ROLLBACK)_(local|staging)=/ {
    if (!done) { while ((getline l < targets) > 0) print l; done = 1 }
    next
  }
  { print }' dev/deploy.sh > dev/deploy.sh.new
mv dev/deploy.sh.new dev/deploy.sh
chmod +x dev/deploy.sh
rm dev/deploy-targets.sh
git add -A
git -c user.name=sample -c user.email=sample@example.invalid commit -q \
  -m "ITEM-17: version flag, single-file build, CI, staging deploy"
git checkout -q feature

# API-Agent checks this branch: the feature plus a commit that changes the service's API.
git checkout -q -b api
cp -R "$here/api/." "$target/"
git add -A
git -c user.name=sample -c user.email=sample@example.invalid commit -q \
  -m "ITEM-14: search items, fetch one item, rename name to title"
git checkout -q feature

# API-Agent Design mode runs on this branch: the feature plus the ITEM-14
# ticket and roadmap, before any code for the ticket exists.
git checkout -q -b api-design
mkdir -p .tickets .notes
cp "$here/api/.tickets/ITEM-14.md" .tickets/ITEM-14.md
cp "$here/api/.notes/roadmap.md" .notes/roadmap.md
git add -A
git -c user.name=sample -c user.email=sample@example.invalid commit -q \
  -m "ITEM-14: ticket for search and fetch one item"
git checkout -q feature

# Design-Agent designs screens on this branch: main plus a small web view,
# two flows, and the screens an earlier run designed for one of them.
git checkout -q main
git checkout -q -b design
cp -R "$here/design/." "$target/"
cp "$root/.agents/tools/wireframe.css" design/wireframes/style.css
git add -A
git -c user.name=sample -c user.email=sample@example.invalid commit -q \
  -m "Web view, edit-item screens, and the sell-item flow"
git checkout -q feature

echo "Ready: $target (branch 'feature', base 'main')"
echo "Next: open that folder in your agent and say one of:"
echo "  Act as Docs-Agent. Update the docs for this branch against main."
echo "  Read AGENTS.md and .agents/roles/test-agent.md first. Act as Test-Agent in Verify mode. The ticket is .tickets/ITEM-12.md, not your tracker. Verify ITEM-12 on this branch against main."
echo "For Test-Agent Write mode, first run: git -C \"$target\" checkout -q main"
echo "  Read AGENTS.md and .agents/roles/test-agent.md first. Act as Test-Agent in Write mode. The ticket is .tickets/ITEM-12.md, not your tracker. Write acceptance tests for ITEM-12."
echo "For Planner-Agent, stay on 'feature' and say:"
echo "  Read AGENTS.md and .agents/roles/planner-agent.md first. Act as Planner-Agent. The brief is .briefs/export.md. This is local mode: write drafts only and don't use Linear."
echo "For Review-Agent, first run: git -C \"$target\" checkout -q review"
echo "  Read AGENTS.md and .agents/roles/review-agent.md first. Act as Review-Agent. The ticket is .tickets/ITEM-12.md, not your tracker. Review this branch against main."
echo "For Lint-Agent, first run: git -C \"$target\" checkout -q lint"
echo "  Read AGENTS.md and .agents/roles/lint-agent.md first. Act as Lint-Agent. Fix lint on this branch against main."
echo "For Security-Agent, first run: git -C \"$target\" checkout -q security"
echo "  Read AGENTS.md and .agents/roles/security-agent.md first. Act as Security-Agent. Review this branch against main."
echo "For API-Agent, first run: git -C \"$target\" checkout -q api"
echo "  Read AGENTS.md and .agents/roles/api-agent.md first. Act as API-Agent. Check the API on this branch against main."
echo "For API-Agent Design mode, first run: git -C \"$target\" checkout -q api-design"
echo "  Read AGENTS.md and .agents/roles/api-agent.md first. Act as API-Agent in Design mode. The ticket is .tickets/ITEM-14.md, not your tracker. Design the spec change for ITEM-14 against main."
echo "For Build-Agent, first run: git -C \"$target\" checkout -q build"
echo "  Read AGENTS.md and .agents/roles/build-agent.md first. Act as Build-Agent. Make the build pass on this branch, and deploy to staging if every step passes."
echo "For Design-Agent, first run: git -C \"$target\" checkout -q design"
echo "  Read AGENTS.md and .agents/roles/design-agent.md first. Act as Design-Agent. Design the screens for .flows/sell-item.md."
echo "For the user-flows skill, also on 'design':"
echo "  Read AGENTS.md and .agents/skills/user-flows/SKILL.md first. Use the user-flows skill. The input is .notes/returns-research.md."
echo "Then grade the run with $here/expected-<agent>.md"
