#!/usr/bin/env bash
# Deterministic checks for a user-flows skill run. Run from the repo root after
# the agent finishes.
#
# Usage: .agents/checks/user-flows.sh report.md
#
# Exit code 0 means all checks passed. Any failure prints FAIL and exits 1.
# Secret values are never printed.

set -uo pipefail
. "$(dirname "$0")/lib.sh"

report="${1:-}"
if [ -z "$report" ]; then
  echo "Usage: $0 report.md"
  exit 2
fi

# <!-- TAILOR: match "Flows come from" in AGENTS.md. -->
FLOWS="${FLOWS_DIR:-.flows}"
MAX_STEPS=12

esc() { printf '%s' "$1" | sed 's/[.[\*^$/]/\\&/g'; }

# The skill may only add flow files and write its report.
check_scope "^$(esc "$FLOWS")/[^/]+\.md\$|^$(esc "$(basename "$report")")\$"
check_secrets
check_headings "$report" "Inputs:" "Goals:" "Flows written:" "Skipped:" "Assumptions:" \
  "Open questions:" "Security flags:" "Verify:"
[ -f "$report" ] || finish "user-flows"

section() { awk -v h="$1" '$0 ~ "^"h {f=1; next} /^[A-Z][A-Za-z ()]*:/ {f=0} f' "$report"; }

echo "== Existing flows are unchanged"
edited="$(git diff --name-only HEAD -- "$FLOWS" || true)"
for f in $edited; do say_fail "$f existed and changed. Never edit an existing flow; list the change under \"Open questions\"."; done
[ -z "$edited" ] && echo "None changed."

echo "== New flows"
new="$(git ls-files --others --exclude-standard -- "$FLOWS" | grep -E '\.md$' || true)"
[ -n "$new" ] || say_fail "no new flow files in $FLOWS/"
written="$(section 'Flows written:')"
for f in $new; do
  # Header lines.
  for k in Actor Goal Entry Exit; do
    v="$(grep -E "^$k:" "$f" | head -1 | sed -E "s/^$k: *//")"
    [ -n "$v" ] || say_fail "$f: \"$k:\" is missing or empty"
  done
  head -1 "$f" | grep -q '^# Flow: .' || say_fail "$f: first line must be \"# Flow: <name>\""
  for h in Steps Decisions Sources "Open questions"; do
    grep -qx "## $h" "$f" || say_fail "$f is missing the heading \"## $h\""
  done

  # Steps numbered F1..Fn, in order, at most MAX_STEPS.
  steps="$(awk '/^## Steps/ {f=1; next} /^## / {f=0} f' "$f" | grep -oE '^- F[0-9]+:' | sed -E 's/^- (F[0-9]+):/\1/')"
  n=0
  for s in $steps; do
    n=$((n + 1))
    [ "$s" = "F$n" ] || { say_fail "$f: steps must be numbered F1, F2, ... in order; found $s where F$n belongs"; break; }
  done
  [ "$n" -gt 0 ] || say_fail "$f has no steps written as \"- F<n>:\" under \"## Steps\""
  [ "$n" -le "$MAX_STEPS" ] || say_fail "$f has $n steps, over $MAX_STEPS. It holds more than one goal: split it."

  # Decisions: two branches each, after a real step.
  dec="$(awk '/^## Decisions/ {f=1; next} /^## / {f=0} f' "$f" | grep -E '^- ' | grep -viE '^- *None *$' || true)"
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    after="$(printf '%s\n' "$d" | sed -nE 's/^- D[0-9]+ after (F[0-9]+):.*/\1/p')"
    if [ -z "$after" ]; then
      say_fail "$f: decision must start with \"- D<n> after F<n>:\": ${d:0:50}"
      continue
    fi
    printf '%s\n' "$steps" | grep -qx "$after" || say_fail "$f: decision comes after $after, which isn't a step"
    printf '%s\n' "$d" | grep -qE '^- D[0-9]+ after F[0-9]+: *if .*; *otherwise' \
      || say_fail "$f: decision needs both branches, \"if ...; otherwise, ...\": ${d:0:50}"
  done <<< "$dec"

  # Sources: every step and the exit, each a real file:line or (assumption).
  src="$(awk '/^## Sources/ {f=1; next} /^## / {f=0} f' "$f")"
  for s in $steps Exit; do
    line="$(printf '%s\n' "$src" | grep -E "^- $s:" | head -1 | sed -E "s/^- $s: *//")"
    if [ -z "$line" ]; then
      say_fail "$f: no source for $s under \"## Sources\""
    elif ! printf '%s\n' "$line" | grep -q '(assumption)'; then
      path="$(printf '%s\n' "$line" | sed -nE 's/^`?([^`: ]+):[0-9]+.*/\1/p')"
      if [ -z "$path" ]; then
        say_fail "$f: source for $s must be \"<file>:<line>\" or \"(assumption)\""
      elif [ ! -f "$path" ]; then
        say_fail "$f: source for $s points to $path, which doesn't exist"
      fi
    fi
  done

  printf '%s\n' "$written" | grep -qF "$f" || say_fail "$f isn't listed under \"Flows written:\""
  echo "  OK  $f ($n steps)"
done

echo "== Assumptions are reported"
for f in $new; do
  if grep -q '(assumption)' "$f" && ! section 'Assumptions:' | grep -qF "$f"; then
    say_fail "$f marks assumptions, but \"Assumptions:\" doesn't list them"
  fi
done
echo "Done."

finish "user-flows"
