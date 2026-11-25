#!/usr/bin/env bash
# Gates API spec changes: fails on any change to the spec that isn't purely
# additive, unless a person approved it in .api/approved.md.
#
# Usage: .agents/checks/spec-diff.sh [base]   (default base: main)
#   Compares each spec file as it was where this branch left base with the
#   spec in the working tree. Run it from the repo root.
#
# Each change prints on one line as:
#   ADDITIVE        <METHOD> <path> <change-id>: <what changed>
#   APPROVED        <METHOD> <path> <change-id>: <what changed>
#   NEEDS APPROVAL  <METHOD> <path> <change-id>: <what changed>
# Any NEEDS APPROVAL line fails the run.
#
# A change is additive only if it adds something optional: a new endpoint,
# response field, optional parameter, or response code. Everything else needs
# approval, including changes oasdiff itself calls "info", such as removing an
# optional response field or changing a default. Clients rely on those too.
#
# To approve a change, a person adds a line to .api/approved.md and commits it:
#   - GET /items response-optional-property-removed (ITEM-14)
# The line is "- <METHOD> <path> <change-id>", then anything. Use * for a
# method or path oasdiff doesn't give. Agents never edit that file.
#
# Needs oasdiff (https://github.com/oasdiff/oasdiff) and python3. Without
# oasdiff the run fails: a gate that silently skips looks like a clean one.
# See setup/api.md.

set -uo pipefail

# <!-- TAILOR: your spec files, space-separated, relative to the repo root. -->
SPECS="${API_SPECS:-openapi.yaml}"
APPROVALS=".api/approved.md"

base="${1:-main}"
fail=0

if ! git rev-parse --verify -q "$base" >/dev/null; then
  echo "FAIL: base \"$base\" is not a branch or commit here."
  exit 1
fi
from="$(git merge-base "$base" HEAD)"

checked=0
for spec in $SPECS; do
  echo "== $spec (against $base)"
  if [ ! -f "$spec" ]; then
    if git cat-file -e "$from:$spec" 2>/dev/null; then
      echo "NEEDS APPROVAL  * * spec-file-removed: $spec existed on $base and is gone"
      fail=1
    else
      echo "No spec file at $spec. Nothing to compare."
    fi
    continue
  fi
  if ! git cat-file -e "$from:$spec" 2>/dev/null; then
    echo "New spec file. Nothing to compare."
    continue
  fi
  if ! command -v oasdiff >/dev/null 2>&1; then
    echo "FAIL: oasdiff isn't installed, so spec changes can't be checked."
    echo "      Install it (brew install oasdiff), then run this again. See setup/api.md."
    exit 1
  fi
  checked=1

  tmp="$(mktemp -d)"
  git show "$from:$spec" > "$tmp/base.${spec##*.}"
  if ! oasdiff changelog "$tmp/base.${spec##*.}" "$spec" --format json > "$tmp/changes.json" 2> "$tmp/err.txt"; then
    echo "FAIL: oasdiff couldn't compare the specs:"
    sed 's/^/  /' "$tmp/err.txt"
    rm -rf "$tmp"
    fail=1
    continue
  fi

  python3 -I - "$tmp/changes.json" "$APPROVALS" <<'PY' || fail=1
import json
import sys

changes_file, approvals_file = sys.argv[1], sys.argv[2]

# Info-level changes that only add something optional. Every other change,
# whatever its oasdiff level, needs approval.
ADDITIVE_IDS = {
    "new-optional-request-parameter",
    "new-optional-request-property",
    "new-optional-request-default-parameter-to-existing-path",
    "request-body-added-optional",
    "request-body-became-optional",
    "request-parameter-became-optional",
    "request-property-became-optional",
}

approved = set()
try:
    with open(approvals_file) as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) >= 4 and parts[0] == "-":
                approved.add((parts[1].upper(), parts[2], parts[3]))
except FileNotFoundError:
    pass

with open(changes_file) as f:
    text = f.read().strip()
changes = json.loads(text) if text else []

if not changes:
    print("No interface changes.")
needs = 0
for c in changes:
    cid = c.get("id", "")
    method = (c.get("operation") or "*").upper()
    path = c.get("path") or "*"
    what = c.get("text", "").replace("`", "'")
    if c.get("level", 0) == 1 and (cid.endswith("-added") or cid in ADDITIVE_IDS):
        label = "ADDITIVE"
    elif (method, path, cid) in approved or ("*", path, cid) in approved or ("*", "*", cid) in approved:
        label = "APPROVED"
    else:
        label = "NEEDS APPROVAL"
        needs += 1
    print(f"{label:<15} {method} {path} {cid}: {what}")

if needs:
    print(f"FAIL: {needs} change(s) need a person's approval in {approvals_file}.")
    print("      Agents: report them under Needs approval. Don't edit that file.")
    sys.exit(1)
PY
  rm -rf "$tmp"
done

if [ "$fail" -ne 0 ]; then
  echo "== spec-diff: FAILED"
  exit 1
fi
if [ "$checked" -eq 0 ]; then
  echo "== spec-diff: passed (no spec to compare)"
else
  echo "== spec-diff: passed"
fi
