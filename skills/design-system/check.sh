#!/usr/bin/env bash
# Deterministic checks for a design-system skill run. Run from the repo root
# after the agent finishes.
#
# Usage: .agents/skills/design-system/check.sh agent-report.md
#
# Exit code 0 means all checks passed. Any failure prints FAIL and exits 1.
# Secret values are never printed.

set -uo pipefail
. "$(dirname "$0")/../../shared/lib.sh"

report="${1:-}"
if [ -z "$report" ]; then
  echo "Usage: $0 agent-report.md"
  exit 2
fi

# <!-- TAILOR: match "Design writes to" in AGENTS.md. -->
SYSTEM="${DESIGN_DIR:-design}/system.md"
MIN_CONTRAST=4.5
COMPONENTS="Button|Text input|Select|Checkbox|Radio|Field error|List item|Card|Navigation|Dialog|Alert|Empty state|Loading"

esc() { printf '%s' "$1" | sed 's/[.[\*^$/]/\\&/g'; }

# The skill may change only the system file and its report.
check_scope "^$(esc "$SYSTEM")\$|^$(esc "$(basename "$report")")\$"
check_secrets
check_headings "$report" "Inputs:" "Existing UI:" "Decisions:" "Open questions:" \
  "Security flags:" "Verify:"
[ -f "$report" ] || finish "design-system"

section() { awk -v h="$1" '$0 ~ "^"h {f=1; next} /^[A-Z][A-Za-z ()]*:/ {f=0} f' "$report"; }
part() { awk -v h="## $1" '$0 == h {f=1; next} /^## / {f=0} f' "$SYSTEM"; }

echo "== System file"
if [ ! -f "$SYSTEM" ]; then
  say_fail "$SYSTEM not found"
  finish "design-system"
fi
head -1 "$SYSTEM" | grep -q '^# Design system: .' || say_fail "$SYSTEM: first line must be \"# Design system: <product>\""
for k in Product Audience Platforms; do
  grep -qE "^$k: *[^ ]" "$SYSTEM" || say_fail "$SYSTEM: \"$k:\" is missing or empty"
done
for h in Principles Layout Type Color Components Forms "Voice and copy" Accessibility Sources "Open questions"; do
  if ! grep -qx "## $h" "$SYSTEM"; then
    say_fail "$SYSTEM is missing the heading \"## $h\""
  elif [ -z "$(part "$h" | grep -E '[^ ]')" ]; then
    say_fail "$SYSTEM: \"## $h\" is empty"
  fi
done
grep -q 'TODO\|TBD' "$SYSTEM" && say_fail "$SYSTEM has TODO or TBD. Write a value with (proposed) or an open question instead."
echo "Done."

echo "== Components"
comp="$(part Components)"
IFS='|' read -r -a names <<< "$COMPONENTS"
for c in "${names[@]}"; do
  printf '%s\n' "$comp" | grep -qiE "^\| *$c *\|" || say_fail "Components table has no row for \"$c\""
done
printf '%s\n' "$comp" | grep -qE '^Components page: *[^ ]' || say_fail "\"## Components\" needs a line \"Components page: <path>\""
echo "Done."

echo "== Contrast"
pairs="$(part Color | grep -E '^- Contrast:' || true)"
[ "$(printf '%s\n' "$pairs" | grep -c .)" -ge 2 ] || say_fail "\"## Color\" needs at least 2 \"- Contrast: <name>: #rrggbb on #rrggbb\" lines"
while IFS= read -r p; do
  [ -n "$p" ] || continue
  fg="$(printf '%s\n' "$p" | sed -nE 's/.*(#[0-9A-Fa-f]{6}) on (#[0-9A-Fa-f]{6}).*/\1/p')"
  bg="$(printf '%s\n' "$p" | sed -nE 's/.*(#[0-9A-Fa-f]{6}) on (#[0-9A-Fa-f]{6}).*/\2/p')"
  if [ -z "$fg" ] || [ -z "$bg" ]; then
    say_fail "contrast line must end in \"#rrggbb on #rrggbb\": ${p:0:60}"
    continue
  fi
  ratio="$(awk -v a="$fg" -v b="$bg" '
    function h(x) { return index("0123456789abcdef", tolower(x)) - 1 }
    function ch(s, i,  v) { v = (h(substr(s, i, 1)) * 16 + h(substr(s, i + 1, 1))) / 255
      return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ^ 2.4 }
    function lum(s) { return 0.2126 * ch(s, 2) + 0.7152 * ch(s, 4) + 0.0722 * ch(s, 6) }
    BEGIN { x = lum(a); y = lum(b); if (x < y) { t = x; x = y; y = t }
      printf "%.2f", (x + 0.05) / (y + 0.05) }')"
  said="$(printf '%s\n' "$p" | grep -oE '[0-9]+(\.[0-9]+)? *: *1' | head -1 | sed -E 's/ *: *1//')"
  if [ -n "$said" ] && awk -v a="$said" -v b="$ratio" 'BEGIN { d = a - b; exit !(d > 0.1 || d < -0.1) }'; then
    say_fail "contrast line says $said:1, but $fg on $bg measures $ratio:1. Don't write ratios; the check measures them."
  fi
  if awk -v r="$ratio" -v m="$MIN_CONTRAST" 'BEGIN { exit !(r < m) }'; then
    say_fail "contrast $ratio:1 is under $MIN_CONTRAST:1 for $fg on $bg (${p:0:40})"
  else
    echo "  OK  $ratio:1  $fg on $bg"
  fi
done <<< "$pairs"

echo "== Every color has a contrast line"
for c in $(part Color | grep -E '^\|' | awk -F'|' '{print $3}' | grep -oE '#[0-9A-Fa-f]{6}' | tr 'a-f' 'A-F' | sort -u); do
  printf '%s\n' "$pairs" | tr 'a-f' 'A-F' | grep -qF "$c" \
    || say_fail "$c is in the color table but in no \"Contrast:\" line. Pair it with its background, or replace it with a color that passes."
done
echo "Done."

echo "== Body text size"
body="$(part Type | grep -iE '^- *Body:' | head -1)"
size="$(printf '%s\n' "$body" | sed -nE 's/^- *Body: *([0-9]+) *px.*/\1/ip')"
if [ -z "$size" ]; then
  say_fail "\"## Type\" needs a line \"- Body: <n> px ...\""
elif [ "$size" -lt 16 ]; then
  say_fail "body text is $size px; it must be at least 16 px"
fi
echo "Done."

echo "== Existing UI lines are real"
while IFS= read -r line; do
  [ -n "$line" ] || continue
  loc="$(printf '%s\n' "$line" | sed -nE 's/^ *- *`?([^`: ]+):([0-9]+).*/\1 \2/p')"
  [ -n "$loc" ] || { printf '%s\n' "$line" | grep -qiE '^ *- *None' || say_fail "existing UI line must be \"- <file>:<line>: <what>\": ${line:0:50}"; continue; }
  set -- $loc
  if [ ! -f "$1" ]; then
    say_fail "existing UI points to $1, which doesn't exist"
  elif [ "$2" -gt "$(wc -l < "$1")" ]; then
    say_fail "existing UI points to $1 line $2, past the end of the file"
  fi
done <<< "$(section 'Existing UI:' | grep -E '^ *- ' || true)"
echo "Done."

echo "== Report file paths are real"
while IFS= read -r line; do
  f="$(printf '%s\n' "$line" | sed -nE 's/^ *- *`?([^` ]+)`?.*/\1/p')"
  [ -n "$f" ] && [ ! -f "$f" ] && say_fail "\"Inputs:\" lists $f, which doesn't exist. Write the path from the repo root."
done <<< "$(section 'Inputs:' | grep -E '^ *- ' || true)"
while IFS= read -r line; do
  f="$(printf '%s\n' "$line" | sed -nE 's/^ *- *`?([^` ]+)`? line [0-9]+.*/\1/p')"
  [ -n "$f" ] && [ ! -f "$f" ] && say_fail "\"Security flags:\" points to $f, which doesn't exist. Write the path from the repo root."
done <<< "$(section 'Security flags:' | grep -E '^ *- ' || true)"
echo "Done."

finish "design-system"
