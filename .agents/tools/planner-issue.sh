#!/usr/bin/env bash
# Prints the Linear title, description, and blocked-by IDs for one Planner
# draft, with every DRAFT-<n> replaced by the Linear ID already recorded under
# "Created:" in the report. Copy its output into save_issue as is.
#
# Usage: .agents/tools/planner-issue.sh <draft-number> [report-file]
#   Example: .agents/tools/planner-issue.sh 3 report.md
#
# Fails, and prints nothing to copy, if the draft names another draft that
# has no Linear ID under "Created:" yet. Create that one first.
# Written for bash 3.2 and BSD tools, so it runs on a stock Mac.

set -uo pipefail

DRAFTS_DIR='.tickets/drafts'
n="${1:-}"
report="${2:-report.md}"

case "$n" in
  ''|*[!0-9]*) echo "Usage: $0 <draft-number> [report-file]" >&2; exit 2 ;;
esac
draft="$DRAFTS_DIR/DRAFT-$n.md"
[ -f "$draft" ] || { echo "ERROR: $draft not found" >&2; exit 1; }
[ -f "$report" ] || { echo "ERROR: $report not found" >&2; exit 1; }

created="$(awk 'index($0, "Created:") == 1 {f=1; next} /^[A-Z][A-Za-z ()]*:/ {f=0} f' "$report")"
id_of() {
  echo "$created" | sed -nE "s/.*DRAFT-$1 -> (exists: )?([A-Z][A-Z0-9]*-[0-9]+).*/\\2/p" | head -1
}

title="$(head -1 "$draft" | sed -E "s/^# DRAFT-$n: *//")"
body="$(tail -n +2 "$draft" | sed '/./,$!d')"

missing=""
for k in $(echo "$body" | grep -Eo 'DRAFT-[0-9]+' | sed 's/DRAFT-//' | sort -nu); do
  id="$(id_of "$k")"
  if [ -z "$id" ]; then
    missing="$missing DRAFT-$k"
    continue
  fi
  body="$(echo "$body" | sed -E "s/DRAFT-$k([^0-9]|$)/$id\\1/g")"
done
if [ -n "$missing" ]; then
  echo "ERROR: no Linear ID under \"Created:\" in $report for:$missing" >&2
  echo "Create those first and add \"- DRAFT-<n> -> <ID> <url>\" lines, then rerun." >&2
  exit 1
fi

blocked=""
for k in $(awk '$0 == "## Depends on" {f=1; next} /^#/ {f=0} f' "$draft" | grep -Eo 'DRAFT-[0-9]+' | sed 's/DRAFT-//' | sort -nu); do
  blocked="$blocked $(id_of "$k")"
done

echo "TITLE: $title"
echo "BLOCKED BY:${blocked:- None}"
echo "DESCRIPTION:"
echo "$body"
